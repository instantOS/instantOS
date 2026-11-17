"""Verify announcement ordering and recovery without publishing real releases."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "github_publisher", Path(__file__).parents[1] / "publish-github.py"
)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.metadata = Path(self.temp.name) / "build.json"
        self.notes = Path(self.temp.name) / "notes.md"
        self.metadata.write_text(
            json.dumps(
                {
                    "build": "build-12-2",
                    "version": "2026.11.17",
                    "commit": "a" * 40,
                }
            )
        )
        self.notes.write_text("Verified GitLab download links")
        self.calls = []
        self.releases = []

    def gh(self, *args):
        self.calls.append(args)
        if args[:2] == ("release", "list"):
            return json.dumps(self.releases)
        return ""

    def publish(self):
        with patch.object(publisher, "gh", side_effect=self.gh):
            return publisher.publish("instantOS/instantOS", self.metadata, self.notes)

    def test_new_release_attaches_manifest_before_publishing(self):
        self.assertTrue(self.publish())
        create, edit = self.calls[1:]
        self.assertEqual(create[:3], ("release", "create", "v2026.11.17-12-2"))
        self.assertIn(str(self.metadata), create)
        self.assertIn("--draft", create)
        self.assertIn("--draft=false", edit)
        self.assertIn("--latest", edit)

    def test_retry_recovers_existing_draft(self):
        self.releases = [
            {"tagName": "v2026.11.17-12-2", "isDraft": True, "isPrerelease": False}
        ]
        self.assertTrue(self.publish())
        self.assertEqual(self.calls[1][:2], ("release", "upload"))
        self.assertEqual(self.calls[2][:2], ("release", "edit"))

    def test_older_runs_and_attempts_cannot_replace_newer_releases(self):
        for tag in ("v2026.11.17-13-1", "v2026.11.17-12-3", "v2026.11.17-13"):
            with self.subTest(tag=tag):
                self.calls = []
                self.releases = [
                    {"tagName": tag, "isDraft": False, "isPrerelease": False}
                ]
                self.assertFalse(self.publish())
                self.assertEqual(len(self.calls), 1)

    def test_newer_drafts_do_not_block_completed_builds(self):
        self.releases = [
            {"tagName": "v2026.11.17-13-1", "isDraft": True, "isPrerelease": False}
        ]
        self.assertTrue(self.publish())

    def test_manifest_upload_failure_leaves_draft_unpublished(self):
        def fail_upload(*args):
            if args[:2] == ("release", "create"):
                raise RuntimeError("upload failed")
            return self.gh(*args)

        with (
            patch.object(publisher, "gh", side_effect=fail_upload),
            self.assertRaisesRegex(RuntimeError, "upload failed"),
        ):
            publisher.publish("instantOS/instantOS", self.metadata, self.notes)
        self.assertFalse(any(c[:2] == ("release", "edit") for c in self.calls))


if __name__ == "__main__":
    unittest.main()
