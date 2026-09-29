"""Exercise retention and interrupted transfers without SourceForge credentials."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location(
    "publisher", Path(__file__).parents[1] / "publish-sourceforge.py"
)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class LocalSFTP:
    def __init__(self, root):
        self.root = root
        self.fail_upload = False
        self.fail_promotion = False
        self.max_isos = 0

    def path(self, remote):
        return self.root / remote.removeprefix(publisher.ROOT).lstrip("/")

    def stat(self, path):
        return self.path(path).stat()

    def mkdir(self, path):
        self.path(path).mkdir()

    def chmod(self, path, mode):
        self.path(path).chmod(mode)

    def listdir_attr(self, path):
        return [
            SimpleNamespace(filename=p.name, st_mode=p.lstat().st_mode)
            for p in self.path(path).iterdir()
        ]

    def open(self, path, mode):
        return (
            self.path(path).open(mode + "b")
            if mode == "r"
            else self.path(path).open(mode)
        )

    def remove(self, path):
        self.path(path).unlink()

    def rmdir(self, path):
        self.path(path).rmdir()

    def rename(self, source, target):
        if self.fail_promotion and source.endswith("/pending"):
            raise OSError("simulated promotion failure")
        self.path(source).rename(self.path(target))

    def put(self, source, target, confirm):
        self.path(target).write_bytes(Path(source).read_bytes())
        self.max_isos = max(self.max_isos, len(list(self.root.rglob("*.iso"))))
        if self.fail_upload:
            raise OSError("simulated upload failure")


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.iso = root / "instantos-test-offline.iso"
        self.iso.write_bytes(b"test ISO")
        self.sftp = LocalSFTP(root / "remote")

    def publish(self, number, attempt=1):
        publisher.publish(self.sftp, self.iso, f"build-{number}-{attempt}")

    def latest(self):
        return (self.sftp.root / "latest/build.txt").read_text().strip()

    def test_retention_checksum_and_numeric_order(self):
        for number in range(1, 12):
            self.publish(number)
        self.assertEqual(self.latest(), "build-11-1")
        self.assertEqual(
            {p.name for p in self.sftp.root.iterdir()},
            {"latest", "build-8-1", "build-9-1", "build-10-1"},
        )
        self.assertEqual(self.sftp.max_isos, 4)
        checksum = (
            self.sftp.root / "latest" / (publisher.ISO_NAME + ".sha256")
        ).read_text()
        self.assertEqual(
            checksum,
            publisher.hashlib.sha256(b"test ISO").hexdigest()
            + "  "
            + publisher.ISO_NAME
            + "\n",
        )
        self.publish(9)
        self.publish(11)
        self.assertEqual(self.latest(), "build-11-1")
        self.publish(11, 2)
        self.assertEqual(self.latest(), "build-11-2")

    def test_failed_upload_and_retry(self):
        for number in range(1, 5):
            self.publish(number)
        self.sftp.fail_upload = True
        with self.assertRaises(OSError):
            self.publish(5)
        self.assertEqual(self.latest(), "build-4-1")
        self.sftp.fail_upload = False
        self.publish(5)
        self.assertEqual(self.latest(), "build-5-1")
        self.assertLessEqual(self.sftp.max_isos, 4)

    def test_promotion_failure_restores_latest(self):
        self.publish(1)
        self.sftp.fail_promotion = True
        with self.assertRaises(OSError):
            self.publish(2)
        self.assertEqual(self.latest(), "build-1-1")
        self.sftp.fail_promotion = False
        self.publish(2)
        self.assertEqual(self.latest(), "build-2-1")

    def test_unexpected_files_are_preserved(self):
        self.publish(1)
        pending = self.sftp.root / "pending"
        pending.mkdir()
        (pending / "unrelated.txt").write_text("preserve")
        with self.assertRaises(RuntimeError):
            self.publish(2)
        self.assertTrue((pending / "unrelated.txt").exists())
        self.assertEqual(self.latest(), "build-1-1")

    def test_interruption_between_directory_renames(self):
        self.publish(1)
        (self.sftp.root / "latest").rename(self.sftp.root / "build-1-1")
        self.publish(2)
        self.assertEqual(self.latest(), "build-2-1")
        self.assertTrue((self.sftp.root / "build-1-1").is_dir())


if __name__ == "__main__":
    unittest.main()
