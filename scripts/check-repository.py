#!/usr/bin/env python3
"""Check the Git index before publishing. Reports paths/rules, never secret values.

This is a focused guard for known credential formats and local artifacts, not a
general secret detector. Review staged diffs too, especially unprefixed tokens.
"""
import re
import subprocess
import sys
from pathlib import PurePosixPath

ALLOWED_DOCS = {"docs/architecture.md", "docs/development.md", "docs/code-review.md", "docs/distribution.md"}
ALLOWED_ROOTS = {"native", "scripts", ".github"}
ALLOWED_FILES = {"README.md", ".gitignore", "LICENSE", "CONTRIBUTING.md", "PRIVACY.md", "SECURITY.md"}
PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "GitHub token": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})",
    "API key": rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}",
    "bearer literal": rb"(?i)bearer\s+[A-Za-z0-9_.-]{24,}",
    "absolute home path": rb"/Users/[A-Za-z0-9._-]+/",
}


def main():
    history = "--history" in sys.argv[1:]
    entries = []
    if history:
        seen = set()
        for commit in subprocess.check_output(["git", "rev-list", "--all"]).decode().splitlines():
            for row in subprocess.check_output(["git", "ls-tree", "-r", "-z", commit]).split(b"\0"):
                if not row:
                    continue
                meta, name = row.split(b"\t", 1)
                oid = meta.split()[2].decode()
                name = name.decode()
                if (oid, name) not in seen:
                    seen.add((oid, name))
                    entries.append((name, oid))
    else:
        entries = [(name, ":" + name) for name in subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0") if name]
    errors = set()
    checked = 0
    for name, ref in entries:
        path = PurePosixPath(name)
        if name not in ALLOWED_FILES | ALLOWED_DOCS and path.parts[0] not in ALLOWED_ROOTS:
            errors.add((name, "not in repository scope"))
        if any(part.startswith((".env", ".build")) or part in {"__pycache__", "DerivedData", ".swiftpm"} for part in path.parts):
            errors.add((name, "local configuration/cache"))
        if path.suffix.lower() in {".log", ".pem", ".key", ".p12", ".mobileprovision"}:
            errors.add((name, "local diagnostic/credential file"))
        content = subprocess.check_output(["git", "show", ref])
        if b"\0" in content:
            if name not in {"native/Resources/AppIcon.png", "native/Tests/Fixtures/english-meeting-v2.aiff", "native/Tests/Fixtures/english-meeting-v2.wav", "native/Tests/Fixtures/raining-question.aiff", "native/Tests/Fixtures/raining-question.wav", "native/Tests/Fixtures/english-meeting.aiff"}:
                errors.add((name, "unexpected binary; review before publication"))
            continue
        checked += 1
        for rule, pattern in PATTERNS.items():
            if re.search(pattern, content):
                errors.add((name, rule))
    for name, rule in sorted(errors):
        print(f"FAIL {name}: {rule}", file=sys.stderr)
    print(f"Checked {checked} {'historical' if history else 'staged'} text versions; {len(errors)} findings.")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
