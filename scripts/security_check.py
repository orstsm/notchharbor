#!/usr/bin/env python3
"""Offline release guard. Reports paths/rules only, never credential values.

Pattern detection is defense in depth, not proof that arbitrary secrets are absent.
No Keychain, user preferences, network, or third-party dependencies are accessed.
"""
import argparse
import pathlib
import re
import subprocess
import sys

LIMIT = 32 * 1024 * 1024
RULES = {
    "private-key": rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    "github-token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "aws-access-key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "slack-token": rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
    "google-api-key": rb"\bAIza[A-Za-z0-9_-]{35}\b",
    "stripe-secret": rb"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b",
    "spotify-token": rb"\bBQ[A-Za-z0-9_-]{80,}\b",
    "literal-bearer": rb"(?i)\bBearer [A-Za-z0-9_.-]{24,}",
    "literal-credential": rb'''(?i)(?:client[_-]?secret|access[_-]?token|refresh[_-]?token|api[_-]?key|password)\s*["']?\s*[:=]\s*["'][A-Za-z0-9_./+\-=]{16,}["']''',
    "typed-literal-credential": rb'''(?i)(?:clientSecret|accessToken|refreshToken|apiKey|password)\s*:\s*String\??\s*=\s*"[A-Za-z0-9_./+\-=]{16,}"''',
    "embedded-client-id": rb'''(?i)client[_-]?id\s*["']?\s*[:=]\s*["'][a-f0-9]{32}["']''',
}
PATTERNS = {name: re.compile(pattern) for name, pattern in RULES.items()}


def findings(data):
    return [name for name, pattern in PATTERNS.items() if pattern.search(data)]


def forbidden_name(name):
    path = pathlib.PurePosixPath(name)
    base = path.name.lower()
    return (base == ".env" or base.startswith(".env.") or
            base in {"credentials", "credentials.json", "secrets.json", "secrets.yml", "secrets.yaml", "id_rsa", "id_ed25519", ".netrc"} or
            path.suffix.lower() in {".pem", ".p12", ".pfx", ".key", ".keychain", ".keychain-db", ".mobileprovision"})


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)


def candidates(root):
    return sorted(set(x.decode() for x in git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0") if x))


def check_file(path, label):
    if path.is_symlink():
        return [(label, "symbolic-link-not-allowed")]
    if not path.is_file():
        return []
    if path.stat().st_size > LIMIT:
        return [(label, "file-too-large-to-scan")]
    rules = findings(path.read_bytes())
    if forbidden_name(label):
        rules.append("credential-filename")
    return [(label, rule) for rule in rules]


def blob_findings(root, objects):
    problems = []
    # Never print Git contents or subprocess output, including on failures.
    for oid in sorted(set(objects)):
        if git(root, "cat-file", "-t", oid).strip() != b"blob":
            continue
        if int(git(root, "cat-file", "-s", oid)) > LIMIT:
            problems.append(("git-object:" + oid, "file-too-large-to-scan"))
            continue
        problems.extend(("git-object:" + oid, rule) for rule in findings(git(root, "cat-file", "blob", oid)))
    return problems


def check_repo(root, history=False):
    problems = []
    try:
        git(root, "rev-parse", "--show-toplevel")
    except subprocess.CalledProcessError:
        if history:
            raise ValueError("History check requires a Git checkout")
        for path in root.rglob("*"):
            if not any(part in {".build", "dist", "__pycache__"} for part in path.relative_to(root).parts):
                problems.extend(check_file(path, str(path.relative_to(root))))
        return problems
    for name in candidates(root):
        problems.extend(check_file(root / name, name))
    # Check staged bytes too: a safe working copy may conceal a staged secret.
    staged = git(root, "ls-files", "--stage", "-z").split(b"\0")
    for entry in staged:
        if entry:
            name = entry.split(b"\t", 1)[1].decode()
            if forbidden_name(name):
                problems.append((name, "staged-credential-filename"))
    objects = [entry.split()[1].decode() for entry in staged if entry]
    if history:
        objects += [line.split()[0].decode() for line in git(root, "rev-list", "--objects", "--all").splitlines()]
    problems.extend(blob_findings(root, objects))
    for path in (root / ".github/workflows").glob("*.y*ml"):
        for match in re.finditer(r"\buses:\s*([^\s#]+)", path.read_text()):
            if not re.fullmatch(r"[\w.-]+/[\w./-]+@[0-9a-f]{40}", match[1]):
                problems.append((str(path.relative_to(root)), "action-not-pinned-to-full-sha"))
    return problems


def report(problems):
    for label, rule in sorted(set(problems)):
        print(f"BLOCKED: {ascii(label)} [{rule}]", file=sys.stderr)
    if problems:
        print("Resolve findings before committing or packaging. Values are intentionally redacted.", file=sys.stderr)
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
    parser.add_argument("--history", action="store_true")
    args = parser.parse_args()
    try:
        problems = check_repo(args.root, args.history)
        result = report(problems)
        if not result:
            print("PASS: commit candidates, staged contents, action pins" + (" and reachable history" if args.history else "") + " passed credential checks")
        return result
    except (OSError, ValueError, subprocess.SubprocessError):
        print("BLOCKED: security scan could not complete; no release approved.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
