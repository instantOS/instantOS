"""Verify release promotion and resumable uploads without credentials or large files."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "gitlab_publisher", Path(__file__).parents[1] / "publish-gitlab.py"
)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class FakeGitLab:
    base = "https://gitlab.com/api/v4/projects/89059216"

    def __init__(self):
        self.packages = []
        self.contents = {}
        self.uploads = []
        self.fail_upload = None
        self.fail_public = False
        self.corrupt_upload = False
        self.next_id = 1

    def request(self, method, path, data=None, **kwargs):
        if method == "GET" and path == "":
            return {
                "visibility": "public",
                "default_branch": "main",
                "web_url": "https://gitlab.com/instantos/instantos-releases",
            }
        raise AssertionError((method, path, data))

    def pages(self, path):
        if path.startswith("/packages?"):
            return list(self.packages)
        if path.endswith("/package_files"):
            package_id = int(path.split("/")[2])
            return self.contents[package_id]
        raise AssertionError(path)

    def upload(self, version, path):
        if self.fail_upload == path.name:
            raise RuntimeError("simulated upload failure")
        self.uploads.append((version, path.name))
        package = next(
            (
                p
                for p in self.packages
                if p["name"] == publisher.PACKAGE and p["version"] == version
            ),
            None,
        )
        if not package:
            package = {
                "name": publisher.PACKAGE,
                "version": version,
                "id": self.next_id,
            }
            self.next_id += 1
            self.packages.append(package)
            self.contents[package["id"]] = []
        body = path.read_bytes()
        self.contents[package["id"]].append(
            {
                "file_name": path.name,
                "size": len(body),
                "file_sha256": "bad"
                if self.corrupt_upload
                else hashlib.sha256(body).hexdigest(),
            }
        )

    def public_head(self, url, size):
        if self.fail_public:
            raise RuntimeError("anonymous download denied")


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.live = root / "instantos-2026.11.17-x86_64.iso"
        self.offline = root / "instantos-2026.11.17-offline.iso"
        self.live.write_bytes(b"live ISO")
        self.offline.write_bytes(b"offline ISO")
        self.notes = root / "notes.md"
        self.metadata = root / "build.json"
        self.api = FakeGitLab()

    def publish(self, number, attempt=1):
        with patch.object(publisher.time, "sleep"):
            return publisher.publish(
                self.api,
                self.live,
                self.offline,
                f"build-{number}-{attempt}",
                "2026.11.17",
                "a" * 40,
                1794916800,
                self.notes,
                self.metadata,
            )

    def test_complete_release_links_checksums_and_all_builds_preserved(self):
        for number in range(1, 12):
            self.assertTrue(self.publish(number))
        self.assertEqual(
            {p["version"] for p in self.api.packages},
            {f"build-{number}-1" for number in range(1, 12)},
        )
        manifest = json.loads(self.metadata.read_text())
        self.assertEqual(manifest["build"], "build-11-1")
        for key in ("live", "offline"):
            self.assertIn(manifest[key]["url"], self.notes.read_text())
            self.assertIn(manifest[key]["sha256Url"], self.notes.read_text())
        self.assertIn("Build metadata", self.notes.read_text())
        self.assertIn(hashlib.sha256(b"live ISO").hexdigest(), self.notes.read_text())

    def test_failed_second_iso_resumes_without_reuploading_verified_files(self):
        self.publish(1)
        self.publish(2)
        self.api.fail_upload = self.offline.name
        with self.assertRaisesRegex(RuntimeError, "upload failure"):
            self.publish(3)
        self.api.fail_upload = None
        self.publish(3)
        self.assertEqual(
            {p["version"] for p in self.api.packages},
            {"build-1-1", "build-2-1", "build-3-1"},
        )
        self.assertEqual(self.api.uploads.count(("build-3-1", self.live.name)), 1)
        self.assertEqual(len(self.api.contents[3]), 5)

    def test_checksum_mismatch_blocks_release(self):
        self.api.corrupt_upload = True
        with self.assertRaisesRegex(RuntimeError, "checksums"):
            self.publish(1)
        self.assertFalse(self.metadata.exists())

    def test_private_download_blocks_release(self):
        self.api.fail_public = True
        with self.assertRaisesRegex(RuntimeError, "anonymous"):
            self.publish(1)
        self.assertFalse(self.metadata.exists())

    def test_retry_after_announcement_failure_reuses_verified_package(self):
        self.publish(1)
        uploads = list(self.api.uploads)
        self.metadata.unlink()
        self.notes.unlink()
        self.assertTrue(self.publish(1))
        self.assertEqual(self.api.uploads, uploads)
        self.assertTrue(self.metadata.exists())
        self.assertTrue(self.notes.exists())

    def test_conflicting_incomplete_package_requires_new_attempt(self):
        self.api.fail_upload = self.offline.name
        with self.assertRaisesRegex(RuntimeError, "upload failure"):
            self.publish(1)
        self.api.fail_upload = None
        self.live.write_bytes(b"changed ISO")
        uploads = list(self.api.uploads)
        with self.assertRaisesRegex(RuntimeError, "conflict.*new build attempt"):
            self.publish(1)
        self.assertEqual(self.api.uploads, uploads)
        self.assertFalse(self.metadata.exists())
        self.assertTrue(self.publish(1, 2))

    def test_duplicate_or_unexpected_package_files_block_resume(self):
        for duplicate in (True, False):
            with self.subTest(duplicate=duplicate):
                self.api = FakeGitLab()
                self.publish(1)
                self.metadata.unlink()
                extra = dict(self.api.contents[1][0])
                if not duplicate:
                    extra["file_name"] = "unexpected.iso"
                self.api.contents[1].append(extra)
                with self.assertRaisesRegex(
                    RuntimeError, "conflict.*new build attempt"
                ):
                    self.publish(1)
                self.assertFalse(self.metadata.exists())

    def test_size_limit_is_checked_before_any_upload(self):
        with (
            patch.object(publisher, "MAX_FILE_SIZE", 8),
            self.assertRaisesRegex(ValueError, "5 GiB"),
        ):
            self.publish(1)
        self.assertEqual(self.api.packages, [])

    def test_unrelated_packages_are_never_deleted(self):
        self.api.packages.extend(
            [
                {"name": "other", "version": "build-1-1", "id": 100},
                {"name": publisher.PACKAGE, "version": "manual", "id": 101},
            ]
        )
        for number in range(1, 5):
            self.publish(number)
        self.assertTrue({100, 101}.issubset({p["id"] for p in self.api.packages}))


if __name__ == "__main__":
    unittest.main()
