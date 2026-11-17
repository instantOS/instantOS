#!/usr/bin/env python3
"""Upload and verify an ISO pair in the GitLab Package Registry."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

PACKAGE = "instantos-iso"
BUILD = re.compile(r"build-([0-9]+)-([0-9]+)")
MAX_FILE_SIZE = 5 * 1024**3


def build_order(version):
    match = BUILD.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid build identifier: {version}")
    return tuple(map(int, match.groups()))


class GitLab:
    def __init__(self, project_id, token):
        if not project_id.isdecimal() or not token or any(c in token for c in "\r\n"):
            raise ValueError("Set GITLAB_PROJECT_ID and GITLAB_TOKEN")
        self.base = f"https://gitlab.com/api/v4/projects/{project_id}"
        self.token = token

    def request(self, method, path, data=None, missing_ok=False):
        payload = None if data is None else json.dumps(data).encode()
        request = Request(
            self.base + path,
            data=payload,
            method=method,
            headers={"PRIVATE-TOKEN": self.token, "Content-Type": "application/json"},
        )
        try:
            with urlopen(request, timeout=60) as response:
                body = response.read()
                return json.loads(body) if body else None
        except HTTPError as error:
            if missing_ok and error.code == 404:
                return None
            raise RuntimeError(f"GitLab {method} {path}: HTTP {error.code}") from None

    def pages(self, path):
        result = []
        for page in range(1, 1001):
            separator = "&" if "?" in path else "?"
            items = self.request("GET", f"{path}{separator}per_page=100&page={page}")
            result.extend(items)
            if len(items) < 100:
                return result
        raise RuntimeError("GitLab pagination exceeded 1000 pages")

    def upload(self, version, path):
        # Feed the credential through stdin, keeping it out of process arguments.
        escaped = self.token.replace("\\", "\\\\").replace('"', '\\"')
        result = subprocess.run(
            [
                "curl",
                "--config",
                "-",
                "--fail",
                "--silent",
                "--show-error",
                "--connect-timeout",
                "30",
                "--max-time",
                "7200",
                "--upload-file",
                str(path),
                f"{self.base}/packages/generic/{PACKAGE}/{version}/{quote(path.name)}",
            ],
            input=f'header = "PRIVATE-TOKEN: {escaped}"\n',
            text=True,
            stdout=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode:
            raise RuntimeError(f"Upload failed: {path.name} (curl {result.returncode})")

    def public_head(self, url, size):
        # No credentials: verify that users can download without signing in.
        with urlopen(Request(url, method="HEAD"), timeout=60) as response:
            if response.status != 200 or response.headers.get("Content-Length") != str(
                size
            ):
                raise RuntimeError(f"Public download unavailable: {url}")


def file_info(path):
    if not path.is_file() or not re.fullmatch(r"[A-Za-z0-9_.-]+\.iso", path.name):
        raise ValueError(f"Expected an ISO with a simple filename: {path}")
    size = path.stat().st_size
    if not 0 < size <= MAX_FILE_SIZE:
        raise ValueError(
            f"{path.name}: {size} bytes exceeds GitLab's 5 GiB limit or is empty"
        )
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return {"name": path.name, "size": size, "sha256": digest.hexdigest()}


def release_notes(manifest):
    lines = [
        f"# instantOS {manifest['version']}",
        "",
        (
            f"Built from [instantOS commit `{manifest['commit']}`]"
            f"(https://github.com/instantOS/instantOS/commit/{manifest['commit']})."
        ),
        "",
        "ISO downloads are hosted on GitLab. Previous builds are kept available.",
        "",
    ]
    for key, label in (("live", "Live ISO"), ("offline", "Offline ISO")):
        item = manifest[key]
        lines += [f"- [{label}]({item['url']}) ([SHA256]({item['sha256Url']}))"]
    lines += [
        "",
        f"[Build metadata]({manifest['live']['url'].rsplit('/', 1)[0]}/build.json)",
        "",
        "SHA256 checksums:",
        "",
        "```text",
    ]
    lines += [
        f"{manifest[key]['sha256']}  {manifest[key]['name']}"
        for key in ("live", "offline")
    ]
    return "\n".join(lines + ["```", ""])


def publish(
    api, live, offline, build, version, commit, epoch, notes_path, metadata_path
):
    build_order(build)
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or not re.fullmatch(
        r"\d{4}\.\d{2}\.\d{2}", version
    ):
        raise ValueError("Expected an ISO version date and full source commit")
    # Check BOTH sizes before uploading either file.
    infos = {"live": file_info(live), "offline": file_info(offline)}
    if live.name == offline.name or not offline.name.endswith("-offline.iso"):
        raise ValueError("Expected distinct live and offline ISO filenames")
    project = api.request("GET", "")
    if project["visibility"] != "public":
        raise ValueError("GitLab project must be public")

    base = f"{api.base}/packages/generic/{PACKAGE}/{build}"
    manifest = {
        "build": build,
        "version": version,
        "commit": commit,
        "projectUrl": project["web_url"],
        "builtAt": datetime.fromtimestamp(epoch, UTC).isoformat(),
    }
    expected = {}
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        files = []
        for key, iso in (("live", live), ("offline", offline)):
            item = infos[key]
            item.update(url=f"{base}/{iso.name}", sha256Url=f"{base}/{iso.name}.sha256")
            manifest[key] = item
            checksum = temp / (iso.name + ".sha256")
            checksum.write_text(f"{item['sha256']}  {iso.name}\n")
            files.extend((iso, checksum))
        metadata = temp / "build.json"
        metadata.write_text(json.dumps(manifest, indent=2) + "\n")
        files.append(metadata)
        for path in files:
            if path.suffix == ".iso":
                expected[path.name] = (
                    infos["offline" if path == offline else "live"]["size"],
                    infos["offline" if path == offline else "live"]["sha256"],
                )
            else:
                contents = path.read_bytes()
                expected[path.name] = (
                    len(contents),
                    hashlib.sha256(contents).hexdigest(),
                )

        packages = api.pages(
            "/packages?"
            + urlencode(
                {
                    "package_type": "generic",
                    "package_name": PACKAGE,
                    "package_version": build,
                }
            )
        )
        existing = [
            p for p in packages if p["name"] == PACKAGE and p["version"] == build
        ]
        if len(existing) > 1:
            raise RuntimeError(
                "Multiple packages for this build; use a new build attempt"
            )
        stored = (
            api.pages(f"/packages/{existing[0]['id']}/package_files")
            if existing
            else []
        )
        actual = {f["file_name"]: (f["size"], f["file_sha256"]) for f in stored}
        if len(actual) != len(stored) or any(
            name not in expected or info != expected[name]
            for name, info in actual.items()
        ):
            raise RuntimeError(
                "Existing package files conflict with this build; use a new build attempt"
            )
        # Resume matching uploads without replacing files or requiring delete access.
        for path in files:
            if path.name in actual:
                continue
            print(f"Uploading {path.name}", flush=True)
            api.upload(build, path)

        # Validate GitLab's stored sizes and hashes before promoting the release.
        for attempt in range(8):
            current = api.pages(
                "/packages?"
                + urlencode(
                    {
                        "package_type": "generic",
                        "package_name": PACKAGE,
                        "package_version": build,
                    }
                )
            )
            current = [
                p for p in current if p["name"] == PACKAGE and p["version"] == build
            ]
            stored = (
                api.pages(f"/packages/{current[0]['id']}/package_files")
                if len(current) == 1
                else []
            )
            actual = {f["file_name"]: (f["size"], f["file_sha256"]) for f in stored}
            if actual == expected and len(stored) == len(expected):
                break
            if attempt == 7:
                raise RuntimeError(
                    "GitLab package is incomplete or its sizes/checksums do not match"
                )
            time.sleep(2)
        for path in files:
            api.public_head(f"{base}/{quote(path.name)}", expected[path.name][0])

        # Only expose metadata for GitHub publication after verification succeeds.
        notes_path.write_text(release_notes(manifest))
        metadata_path.write_text(metadata.read_text())

    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("live", type=Path)
    parser.add_argument("offline", type=Path)
    parser.add_argument("build")
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--epoch", required=True, type=int)
    parser.add_argument("--notes", type=Path, default=Path("release-notes.md"))
    parser.add_argument("--metadata", type=Path, default=Path("build.json"))
    args = parser.parse_args()
    api = GitLab(
        os.environ.get("GITLAB_PROJECT_ID", ""), os.environ.get("GITLAB_TOKEN", "")
    )
    published = publish(
        api,
        args.live,
        args.offline,
        args.build,
        args.version,
        args.commit,
        args.epoch,
        args.notes,
        args.metadata,
    )
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"published={str(published).lower()}\n")


if __name__ == "__main__":
    main()
