#!/usr/bin/env python3
"""Copy commit-eligible source only; never export ignored personal resources."""
import pathlib
import shutil
import sys
from security_check import candidates, check_file, check_repo, report


def stage(root, destination):
    if destination.exists():
        raise ValueError("Source staging destination must not exist")
    problems = check_repo(root, history=True)
    if problems:
        report(problems)
        raise ValueError("Source checks failed")
    destination.mkdir(parents=True)
    for name in candidates(root):
        if name == "THIRD_PARTY_NOTICES.md" or name.startswith("Resources/Licenses/"):
            continue
        source = root / name
        if not source.exists():
            continue  # Tracked deletion in the working tree.
        if not source.is_file() or source.is_symlink():
            raise ValueError("Only regular source files can be exported")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if check_file(target, name):
            raise ValueError("Exported source did not pass credential checks")


if __name__ == "__main__":
    try:
        stage(pathlib.Path(__file__).resolve().parents[1], pathlib.Path(sys.argv[1]))
        print("PASS: source export includes only checked, commit-eligible files")
    except Exception:
        print("BLOCKED: source export failed; no source archive approved.", file=sys.stderr)
        sys.exit(1)
