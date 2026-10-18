#!/usr/bin/env python3
"""Verify that the version in README.md matches MARKETING_VERSION in project.pbxproj.

Usage:
  python3 scripts/verify-readme-version.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
PBXPROJ = ROOT / "LocalTranscriber.xcodeproj" / "project.pbxproj"


def read_version_from_pbxproj() -> str:
    content = PBXPROJ.read_text()
    matches = re.findall(r"MARKETING_VERSION\s*=\s*([^;]+);", content)
    if not matches:
        sys.stderr.write("No MARKETING_VERSION found in project.pbxproj\n")
        sys.exit(1)
    versions = {m.strip() for m in matches}
    if len(versions) != 1:
        sys.stderr.write(f"Multiple MARKETING_VERSION values found: {sorted(versions)}\n")
        sys.exit(1)
    return versions.pop()


def read_version_from_readme() -> str:
    content = README.read_text()
    matches = re.findall(r"The current version is \*\*v([0-9]+\.[0-9]+\.[0-9]+)\*\*", content)
    if not matches:
        matches = re.findall(r"当前版本.*?v([0-9]+\.[0-9]+\.[0-9]+)", content)
    if not matches:
        # Look for the Japanese wording (現在のバージョンは vX.Y.Z)
        matches = re.findall(r"現在のバージョンは \*\*v([0-9]+\.[0-9]+\.[0-9]+)\*\*", content)
    if not matches:
        matches = re.findall(r"\| バージョン \| v([0-9]+\.[0-9]+\.[0-9]+) \|", content)
    if not matches:
        sys.stderr.write("No version found in README.md\n")
        sys.exit(1)
    versions = set(matches)
    if len(versions) != 1:
        sys.stderr.write(f"Multiple versions found in README.md: {sorted(versions)}\n")
        sys.exit(1)
    return versions.pop()


def main() -> int:
    pbx_version = read_version_from_pbxproj()
    readme_version = read_version_from_readme()
    if pbx_version != readme_version:
        sys.stderr.write(
            f"Version mismatch: pbxproj={pbx_version} README={readme_version}\n"
        )
        return 1
    print(f"OK: README version v{readme_version} matches MARKETING_VERSION {pbx_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
