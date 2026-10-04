#!/usr/bin/env python3
"""Reject unexpected bundle contents; check copied resources against source."""
import argparse
import hashlib
import pathlib
import sys
from security_check import check_file, report


def verify(app, root, signed=True):
    manifest = root / "scripts/bundle-files.txt"
    expected = set(manifest.read_text().splitlines())
    if signed:
        expected.add("Contents/_CodeSignature/CodeResources")
    directories = {str(parent) for name in expected for parent in pathlib.PurePosixPath(name).parents if str(parent) != "."}
    problems = []
    found = set()
    if app.is_symlink() or not app.is_dir():
        return [("bundle", "missing-or-linked-bundle")]
    for path in app.rglob("*"):
        name = path.relative_to(app).as_posix()
        if path.is_symlink():
            problems.append((name, "symbolic-link-not-allowed"))
        elif path.is_dir():
            if name not in directories:
                problems.append((name, "unexpected-directory"))
        elif path.is_file():
            found.add(name)
            if name not in expected:
                problems.append((name, "unexpected-bundle-file"))
            problems.extend(check_file(path, name))
            source = None
            if name == "Contents/Info.plist":
                source = root / "Info.plist"
            elif name == "Contents/Resources/PrivacyInfo.xcprivacy":
                source = root / "PrivacyInfo.xcprivacy"
            elif name.startswith("Contents/Resources/"):
                source = root / name.removeprefix("Contents/")
            if source and (not source.is_file() or source.is_symlink() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(source.read_bytes()).digest()):
                problems.append((name, "resource-does-not-match-source"))
        else:
            problems.append((name, "non-regular-file"))
    problems.extend((name, "required-bundle-file-missing") for name in expected - found)
    return problems


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--unsigned", action="store_true")
    args = parser.parse_args()
    try:
        result = report(verify(args.app, pathlib.Path(__file__).resolve().parents[1], not args.unsigned))
        if not result:
            print("PASS: exact bundle allowlist, resource integrity and credential checks")
        sys.exit(result)
    except (OSError, ValueError):
        print("BLOCKED: bundle verification could not complete.", file=sys.stderr)
        sys.exit(1)
