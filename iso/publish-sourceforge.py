#!/usr/bin/env python3
"""Publish offline ISOs via SFTP; latest plus three archives use four ISO slots."""

import base64
import errno
import hashlib
import io
import os
import re
import stat
import sys
from pathlib import Path

import paramiko

ROOT = "/home/frs/project/instantos/offline"
ISO_NAME = "instantos-offline-latest.iso"
BUILD_PATTERN = re.compile(r"build-([0-9]+)-([0-9]+)")
# https://sourceforge.net/p/forge/documentation/SSH%20Key%20Fingerprints/
HOST_FINGERPRINTS = {
    "QAAxYkf0iI/tc9oGa0xSsVOAzJBZstcO8HqGKfjpxcY",
    "209BDmH3jsRyO9UeGPPgLWPSegKmYCBIya0nR/AWWCY",
    "xB2rnn0NUjZ/E0IXQp4gyPqc7U7gjcw7G26RhkDyk90",
}


class SourceForgeHostKey(paramiko.MissingHostKeyPolicy):
    def missing_host_key(self, client, hostname, key):
        fingerprint = base64.b64encode(hashlib.sha256(key.asbytes()).digest())
        if fingerprint.decode().rstrip("=") not in HOST_FINGERPRINTS:
            raise paramiko.SSHException("SourceForge host key fingerprint mismatch")


def exists(sftp, path):
    try:
        sftp.stat(path)
        return True
    except OSError as error:
        if error.errno != errno.ENOENT:
            raise
        return False


def remove_build(sftp, path):
    # Refuse to recursively delete unexpected content or follow symlinks.
    files = sftp.listdir_attr(path)
    allowed = {ISO_NAME, ISO_NAME + ".sha256", "build.txt"}
    if any(f.filename not in allowed or not stat.S_ISREG(f.st_mode) for f in files):
        raise RuntimeError(f"Unexpected content in managed directory: {path}")
    for file in files:
        sftp.remove(f"{path}/{file.filename}")
    sftp.rmdir(path)


def publish(sftp, iso, build):
    if not BUILD_PATTERN.fullmatch(build):
        raise ValueError("Invalid build identifier")
    if not exists(sftp, ROOT):
        sftp.mkdir(ROOT)
        sftp.chmod(ROOT, 0o755)
    latest = ROOT + "/latest"
    pending = ROOT + "/pending"
    # Discard an interrupted upload before counting slots.
    if exists(sftp, pending):
        remove_build(sftp, pending)
    previous = None
    if exists(sftp, latest):
        with sftp.open(latest + "/build.txt", "r") as metadata:
            previous = metadata.read().decode().strip()
        if not BUILD_PATTERN.fullmatch(previous):
            raise RuntimeError("Invalid latest build metadata; refusing cleanup")
        if tuple(map(int, BUILD_PATTERN.fullmatch(build).groups())) <= tuple(
            map(int, BUILD_PATTERN.fullmatch(previous).groups())
        ):
            print("This build is already published or older than latest; skipping")
            return

    archives = [
        entry.filename
        for entry in sftp.listdir_attr(ROOT)
        if BUILD_PATTERN.fullmatch(entry.filename) and stat.S_ISDIR(entry.st_mode)
    ]
    archives.sort(
        key=lambda name: tuple(map(int, BUILD_PATTERN.fullmatch(name).groups()))
    )
    # Three existing ISOs + one incoming ISO, including during upload.
    keep = 2 if previous else 3
    for archive in archives[: max(0, len(archives) - keep)]:
        print(f"Removing old offline ISO: {archive}")
        remove_build(sftp, ROOT + "/" + archive)

    digest = hashlib.sha256()
    with iso.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    sftp.mkdir(pending)
    sftp.chmod(pending, 0o755)
    print(f"Uploading {iso.name} ({iso.stat().st_size} bytes)", flush=True)
    sftp.put(str(iso), pending + "/" + ISO_NAME, confirm=True)
    for name, content in {
        ISO_NAME + ".sha256": f"{digest.hexdigest()}  {ISO_NAME}\n",
        "build.txt": build + "\n",
    }.items():
        with sftp.open(pending + "/" + name, "w") as target:
            target.write(content)
    for name in (ISO_NAME, ISO_NAME + ".sha256", "build.txt"):
        sftp.chmod(pending + "/" + name, 0o644)
    if previous:
        sftp.rename(latest, ROOT + "/" + previous)
    # Directory rename publishes ISO and checksum together. If promotion fails,
    # restore the previous latest so the stable path remains available.
    try:
        sftp.rename(pending, latest)
    except Exception:
        if previous:
            sftp.rename(ROOT + "/" + previous, latest)
        raise
    print(
        "Published https://sourceforge.net/projects/instantos/files/offline/latest/"
        + ISO_NAME
        + "/download"
    )


def main():
    username = os.environ.get("SOURCEFORGE_USERNAME", "")
    private_key = os.environ.get("SOURCEFORGE_SSH_KEY", "")
    if not username or not private_key:
        sys.exit("Set SOURCEFORGE_USERNAME and SOURCEFORGE_SSH_KEY before publishing")
    iso = Path(sys.argv[1])
    if not iso.is_file() or not iso.name.endswith("-offline.iso"):
        sys.exit("Expected an existing offline ISO")
    key = None
    for key_type in (paramiko.Ed25519Key, paramiko.ECDSAKey, paramiko.RSAKey):
        try:
            key = key_type.from_private_key(io.StringIO(private_key))
            break
        except paramiko.SSHException:
            continue
    if key is None:
        sys.exit("SOURCEFORGE_SSH_KEY must contain an unencrypted SSH private key")
    with paramiko.SSHClient() as client:
        client.set_missing_host_key_policy(SourceForgeHostKey())
        client.connect(
            "frs.sourceforge.net",
            username=username,
            pkey=key,
            allow_agent=False,
            look_for_keys=False,
            timeout=60,
            auth_timeout=60,
            banner_timeout=60,
        )
        client.get_transport().set_keepalive(30)
        with client.open_sftp() as sftp:
            publish(sftp, iso, sys.argv[2])


if __name__ == "__main__":
    main()
