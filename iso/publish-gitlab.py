#!/usr/bin/env python3
"""Publish a complete ISO pair to GitLab, retaining two successful builds."""

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
        (
            "ISO downloads are hosted on GitLab. This rolling release retains the latest two builds; "
            "older download links may expire."
        ),
        "",
    ]
    for key, label in (("live", "Live ISO"), ("offline", "Offline ISO")):
        item = manifest[key]
        lines += [f"- [{label}]({item['url']}) ([SHA256]({item['sha256Url']}))"]
    lines += [
        "",
        f"[GitLab releases]({manifest['projectUrl']}/-/releases)",
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


def publish(api, live, offline, build, version, commit, epoch, notes_path):
    order = build_order(build)
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or not re.fullmatch(
        r"\d{4}\.\d{2}\.\d{2}", version
    ):
        raise ValueError("Expected an ISO version date and full source commit")
    # Check BOTH sizes before uploading either file.
    infos = {"live": file_info(live), "offline": file_info(offline)}
    if live.name == offline.name or not offline.name.endswith("-offline.iso"):
        raise ValueError("Expected distinct live and offline ISO filenames")
    project = api.request("GET", "")
    if project["visibility"] != "public" or not project.get("default_branch"):
        raise ValueError(
            "GitLab project must be public and initialized with a default branch"
        )
    releases = api.pages("/releases")
    managed = [r for r in releases if BUILD.fullmatch(r["tag_name"])]
    if any(build_order(r["tag_name"]) > order for r in managed):
        print("A newer build is already published; skipping this build")
        return False

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
            + urlencode({"package_type": "generic", "package_name": PACKAGE})
        )
        packages = [
            p
            for p in packages
            if p["name"] == PACKAGE and BUILD.fullmatch(p["version"])
        ]
        existing = [p for p in packages if p["version"] == build]
        completed = any(r["tag_name"] == build for r in managed)
        if not completed:
            # A retry can replace only its own incomplete package, never a published build.
            for package in existing:
                api.request("DELETE", f"/packages/{package['id']}")
            for path in files:
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

        notes = release_notes(manifest)
        links = []
        for key in ("live", "offline"):
            item = manifest[key]
            for suffix in ("", ".sha256"):
                links.append(
                    {
                        "name": item["name"] + suffix,
                        "url": item["url"] + suffix,
                        "direct_asset_path": f"/{key}/instantos.iso{suffix}",
                        "link_type": "package",
                    }
                )
        links.append(
            {
                "name": "Build metadata",
                "url": f"{base}/build.json",
                "direct_asset_path": "/build.json",
                "link_type": "other",
            }
        )
        if not completed:
            api.request(
                "POST",
                "/releases",
                {
                    "name": f"instantOS {version}",
                    "tag_name": build,
                    "ref": project["default_branch"],
                    "description": notes,
                    "assets": {"links": links},
                },
            )
        notes_path.write_text(notes)

    # Only prune after a complete release is publicly available. Leave unrelated packages alone.
    successful = sorted(
        {r["tag_name"] for r in managed} | {build}, key=build_order, reverse=True
    )
    retained = set(successful[:2])
    for release in managed:
        tag = release["tag_name"]
        if tag not in retained:
            api.request("DELETE", f"/releases/{quote(tag)}")
    for package in packages:
        tag = package["version"]
        if tag not in retained and build_order(tag) <= order:
            api.request("DELETE", f"/packages/{package['id']}")
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
    )
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"published={str(published).lower()}\n")


if __name__ == "__main__":
    main()
