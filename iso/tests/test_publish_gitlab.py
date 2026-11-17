"""Verify release promotion and resumable uploads without credentials or large files."""

import hashlib
import importlib.util
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
        self.releases = []
        self.contents = {}
        self.uploads = []
        self.fail_upload = None
        self.fail_public = False
        self.fail_release = False
        self.corrupt_upload = False
        self.next_id = 1

    def request(self, method, path, data=None, **kwargs):
        if method == "GET" and path == "":
            return {
                "visibility": "public",
                "default_branch": "main",
                "web_url": "https://gitlab.com/instantos/instantos-releases",
            }
        if method == "POST" and path == "/releases":
            if self.fail_release:
                raise RuntimeError("release creation failed")
            self.releases.append(data)
            return data
        raise AssertionError((method, path, data))

    def pages(self, path):
        if path == "/releases":
            return list(self.releases)
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
            )

    def test_complete_release_links_checksums_and_all_builds_preserved(self):
        for number in range(1, 12):
            self.assertTrue(self.publish(number))
        self.assertEqual(
            {p["version"] for p in self.api.packages},
            {f"build-{number}-1" for number in range(1, 12)},
        )
        self.assertEqual(
            {r["tag_name"] for r in self.api.releases},
            {f"build-{number}-1" for number in range(1, 12)},
        )
        links = self.api.releases[-1]["assets"]["links"]
        self.assertEqual(
            {l["direct_asset_path"] for l in links},
            {
                "/live/instantos.iso",
                "/live/instantos.iso.sha256",
                "/offline/instantos.iso",
                "/offline/instantos.iso.sha256",
                "/build.json",
            },
        )
        self.assertIn(hashlib.sha256(b"live ISO").hexdigest(), self.notes.read_text())
        self.assertIn("GitLab releases", self.notes.read_text())

    def test_failed_second_iso_resumes_without_reuploading_verified_files(self):
        self.publish(1)
        self.publish(2)
        self.api.fail_upload = self.offline.name
        with self.assertRaisesRegex(RuntimeError, "upload failure"):
            self.publish(3)
        self.assertEqual(
            {r["tag_name"] for r in self.api.releases}, {"build-1-1", "build-2-1"}
        )
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
        self.assertEqual(self.api.releases, [])

    def test_private_download_blocks_release(self):
        self.api.fail_public = True
        with self.assertRaisesRegex(RuntimeError, "anonymous"):
            self.publish(1)
        self.assertEqual(self.api.releases, [])

    def test_failed_release_creation_reuses_verified_package(self):
        self.publish(1)
        self.publish(2)
        self.api.fail_release = True
        with self.assertRaisesRegex(RuntimeError, "release creation"):
            self.publish(3)
        self.assertEqual(
            {r["tag_name"] for r in self.api.releases}, {"build-1-1", "build-2-1"}
        )
        self.assertTrue(
            {"build-1-1", "build-2-1"}.issubset(
                {p["version"] for p in self.api.packages}
            )
        )
        self.api.fail_release = False
        uploads = list(self.api.uploads)
        self.publish(3)
        self.assertEqual(self.api.uploads, uploads)
        self.assertEqual(
            {p["version"] for p in self.api.packages},
            {"build-1-1", "build-2-1", "build-3-1"},
        )

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
        self.assertEqual(self.api.releases, [])
        self.assertTrue(self.publish(1, 2))

    def test_duplicate_or_unexpected_package_files_block_resume(self):
        for duplicate in (True, False):
            with self.subTest(duplicate=duplicate):
                self.api = FakeGitLab()
                self.api.fail_release = True
                with self.assertRaisesRegex(RuntimeError, "release creation"):
                    self.publish(1)
                extra = dict(self.api.contents[1][0])
                if not duplicate:
                    extra["file_name"] = "unexpected.iso"
                self.api.contents[1].append(extra)
                self.api.fail_release = False
                with self.assertRaisesRegex(RuntimeError, "conflict.*new build attempt"):
                    self.publish(1)
                self.assertEqual(self.api.releases, [])

    def test_older_runs_cannot_replace_newer_builds_and_retries_are_idempotent(self):
        self.publish(10)
        self.assertFalse(self.publish(9))
        self.assertTrue(self.publish(10))
        self.assertEqual(len(self.api.packages), 1)
        self.assertEqual(len(self.api.releases), 1)
        self.publish(10, 2)
        self.assertEqual(len(self.api.releases), 2)

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
