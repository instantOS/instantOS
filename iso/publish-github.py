#!/usr/bin/env python3
"""Announce verified GitLab package downloads through GitHub Releases."""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

TAG = re.compile(r"v\d{4}\.\d{2}\.\d{2}-(\d+)(?:-(\d+))?")


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True)


def publish(repo, metadata_path, notes_path):
    manifest = json.loads(metadata_path.read_text())
    match = re.fullmatch(r"build-(\d+)-(\d+)", manifest["build"])
    if not match or not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}", manifest["version"]):
        raise ValueError("Invalid build metadata")
    order = tuple(map(int, match.groups()))
    tag = f"v{manifest['version']}-{order[0]}-{order[1]}"
    releases = json.loads(
        gh(
            "release",
            "list",
            "--repo",
            repo,
            "--limit",
            "1000",
            "--json",
            "tagName,isDraft,isPrerelease",
        )
    )
    for release in releases:
        previous = TAG.fullmatch(release["tagName"])
        if (
            previous
            and not release["isDraft"]
            and not release["isPrerelease"]
            and (int(previous[1]), int(previous[2] or 1)) > order
        ):
            print("A newer GitHub release is already published; skipping announcement")
            return False

    title = f"instantOS Release {manifest['version']}"
    existing = next((r for r in releases if r["tagName"] == tag), None)
    if existing:
        gh("release", "upload", tag, str(metadata_path), "--clobber", "--repo", repo)
    else:
        # Attach the manifest before making the release visible to latest consumers.
        gh(
            "release",
            "create",
            tag,
            str(metadata_path),
            "--draft",
            "--target",
            manifest["commit"],
            "--title",
            title,
            "--notes-file",
            str(notes_path),
            "--repo",
            repo,
        )
    gh(
        "release",
        "edit",
        tag,
        "--draft=false",
        "--latest",
        "--title",
        title,
        "--notes-file",
        str(notes_path),
        "--repo",
        repo,
    )
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo", default=os.environ.get("GITHUB_REPOSITORY"), required=False
    )
    parser.add_argument("--metadata", type=Path, default=Path("build.json"))
    parser.add_argument("--notes", type=Path, default=Path("release-notes.md"))
    args = parser.parse_args()
    if not args.repo:
        parser.error("Set GITHUB_REPOSITORY or --repo")
    publish(args.repo, args.metadata, args.notes)


if __name__ == "__main__":
    main()
