"""Exercise key bootstrap and offline signature verification without root or network."""

import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures/signing"
PACKAGE = "instantos-keyring-1_20260825-1-any.pkg.tar.zst"
MASTER = "E5C4740F883910B29694D6BE10DA645A82CF5206"


def run(*args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


@unittest.skipUnless(all(shutil.which(c) for c in ("gpg", "pacman-conf")), "requires GnuPG and pacman-conf")
class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.keydir = self.root / "target-keyring"
        self.keydir.mkdir(mode=0o700)
        self.conf = self.root / "pacman.conf"
        self.conf.write_text(f"[options]\nGPGDir = {self.keydir}\n")
        self.log = self.root / "commands"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", BOOTSTRAP_LOG=str(self.log))
        self.wrapper("whoami", "printf 'root\\n'")
        self.wrapper("id", "printf '%s\\n' \"${TEST_UID:-0}\"")
        self.wrapper("sudo", 'exec "$@"')
        self.wrapper("curl", 'echo network >> "$BOOTSTRAP_LOG"; exit 99')
        self.wrapper("wget", 'echo network >> "$BOOTSTRAP_LOG"; exit 99')
        # Emulate pacman-key's GPG operations in a disposable directory. The
        # production script itself is unchanged and uses the real public key.
        self.wrapper("pacman-key", r'''
set -eu
printf '%s\n' "$*" >> "$BOOTSTRAP_LOG"
[ "$1" = --gpgdir ]; dir=$2; shift 2
mkdir -p "$dir"; chmod 700 "$dir"
case "$1" in
 --init)
   if ! gpg --homedir "$dir" --batch --list-secret-keys fixture@example.invalid >/dev/null 2>&1; then
     gpg --homedir "$dir" --batch --pinentry-mode loopback --passphrase '' \
       --quick-generate-key fixture@example.invalid ed25519 cert 0
   fi ;;
 --add) gpg --homedir "$dir" --batch --import "$2" ;;
 --lsign-key) gpg --homedir "$dir" --batch --yes --quick-lsign-key "$2" ;;
 --updatedb) gpg --homedir "$dir" --batch --check-trustdb ;;
 *) exit 98 ;;
esac
''')

    def wrapper(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def bootstrap(self, script=None):
        return run("bash", str(script or REPO / "repo.sh"), "--bootstrap-key", str(self.conf), env=self.env)

    def test_custom_keyring_is_trusted_offline_and_bootstrap_is_repeatable(self):
        before = self.conf.read_bytes()
        for _ in range(2):
            result = self.bootstrap()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        operations = self.log.read_text().splitlines()
        self.assertEqual(len(operations), 8)
        self.assertTrue(all(line.startswith(f"--gpgdir {self.keydir} ") for line in operations))
        self.assertEqual(self.conf.read_bytes(), before)
        keys = run("gpg", "--homedir", str(self.keydir), "--batch", "--with-colons", "--list-keys", MASTER)
        self.assertIn("pub:f:", keys.stdout)
        self.assertIn(MASTER, keys.stdout)

    def test_sudo_path_uses_the_same_configuration(self):
        self.env["TEST_UID"] = "1000"
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"--gpgdir {self.keydir}", self.log.read_text())

    def test_wrong_pin_is_rejected_before_keyring_changes(self):
        script = self.root / "wrong-pin.sh"
        script.write_text((REPO / "repo.sh").read_text().replace(MASTER, "0" * 40))
        result = self.bootstrap(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)
        self.assertFalse(self.log.exists())
        self.assertEqual(list(self.keydir.iterdir()), [])

    def test_embedded_snapshot_matches_vendored_public_key(self):
        source = (REPO / "repo.sh").read_text()
        embedded = source.split("<<'INSTANTOS_PUBLIC_KEY'\n", 1)[1].split("\nINSTANTOS_PUBLIC_KEY", 1)[0]
        self.assertEqual(embedded.strip(), (REPO / "signing/instantos-signing-key.asc").read_text().strip())


@unittest.skipUnless(all(shutil.which(c) for c in ("gpg", "gpgv", "mksquashfs", "unsquashfs", "bsdtar")), "requires squashfs and GnuPG tools")
class ImageVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / "image"
        self.image.mkdir()
        self.bundle = self.root / "contents"
        self.bundle.mkdir()
        self.sha = "a" * 40
        self.write("opt/instantos/.setup-done", "status=complete\n" + "".join(f"{name}_commit={self.sha}\n" for name in ("dotfiles", "instanttools", "liveutils")))
        self.write("usr/share/instantos/build-sources.env", "".join(f"{name.upper()}_COMMIT={self.sha}\n" for name in ("dotfiles", "instanttools", "liveutils")) + "DOTFILES_BRANCH=main\n")
        dots = "home/instantos/.local/share/instant/dots/dotfiles"
        for path in ("opt/instantos/rootinstall", "usr/local/bin/ibuild", "usr/share/instantos/offline-image", "usr/share/instantos/build-inputs/dotfiles/.git/config"):
            self.write(path, "fixture\n")
        self.write("home/instantos/.zshrc", "fixture\n")
        self.write(f"{dots}/dots/.zshrc", "fixture\n")
        self.write(f"{dots}/.git/config", "https://github.com/instantOS/dotfiles\n")
        self.write(f"{dots}/.git/HEAD", "ref: refs/heads/main\n")
        self.write(f"{dots}/.git/refs/heads/main", self.sha + "\n")
        self.write("home/instantos/.config/instant/dots.toml", "https://github.com/instantOS/dotfiles\n")
        self.write("etc/greetd/config.toml", 'user = "instantos"\ninstantwm --backend drm\n')
        self.write("usr/local/share/instanttools/version", self.sha[:10] + "\n")
        self.write("etc/pacman.d/mirrorlist", 'Server = file:///run/archiso/bootmnt/offline-repo/$repo/os/$arch\n')
        service = "etc/systemd/system/pacman-init.service"
        self.write(service, (REPO / "iso/releng/airootfs" / service).read_text())
        enabled = self.image / "etc/systemd/system/multi-user.target.wants/pacman-init.service"
        enabled.parent.mkdir(parents=True)
        enabled.symlink_to("../pacman-init.service")
        for path in ("usr/share/pacman/keyrings/instantos.gpg", "usr/share/pacman/keyrings/instantos-trusted", "usr/share/pacman/keyrings/instantos-revoked", "usr/bin/instantos-keyring-wkd-sync"):
            data = subprocess.check_output(["bsdtar", "-xOf", str(FIXTURES / PACKAGE), path])
            self.write(path, data)
        for repo in ("core", "extra", "multilib", "instant"):
            self.bundle_write(f"offline-repo/{repo}/os/x86_64/{repo}.db", b"fixture")
        self.bundle_write("offline-repo/regions/regions.html", b"fixture")
        self.bundle_write("offline-repo/regions/mirrorlists/de.txt", b"fixture")
        self.bundle_write("offline-repo/packages.list", b"instantos-keyring\n")
        self.archive = self.bundle / "offline-repo/instant/os/x86_64" / PACKAGE
        shutil.copyfile(FIXTURES / PACKAGE, self.archive)
        shutil.copyfile(FIXTURES / (PACKAGE + ".sig"), str(self.archive) + ".sig")

    def write(self, path, data):
        file = self.image / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data.encode() if isinstance(data, str) else data)

    def bundle_write(self, path, data):
        file = self.bundle / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data)

    def verify(self):
        squash = self.bundle / "arch/x86_64/airootfs.sfs"
        squash.parent.mkdir(parents=True, exist_ok=True)
        result = run("mksquashfs", str(self.image), str(squash), "-noappend", "-processors", "1", "-quiet")
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.root / "fixture.iso"
        # bsdtar accepts a tar container as well as ISO9660; use a tiny fixture
        # with the same paths to exercise the production verifier end to end.
        with tarfile.open(archive, "w") as output:
            for file in sorted(self.bundle.rglob("*")):
                output.add(file, arcname=str(file.relative_to(self.bundle)), recursive=False)
        return run("bash", str(REPO / "iso/verify.sh"), str(archive), "--offline")

    def test_valid_signed_bundle(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_instant_signature_is_rejected(self):
        Path(str(self.archive) + ".sig").unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without a signature", result.stderr)

    def test_corrupted_instant_package_is_rejected(self):
        with self.archive.open("ab") as output:
            output.write(b"tampered")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid instantOS package signature", result.stderr)

    def test_missing_keyring_is_rejected(self):
        (self.image / "usr/share/pacman/keyrings/instantos.gpg").unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing expected file", result.stderr)

    def test_disabled_initializer_is_rejected(self):
        (self.image / "etc/systemd/system/multi-user.target.wants/pacman-init.service").unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("initialization is not enabled", result.stderr)


if __name__ == "__main__":
    unittest.main()
