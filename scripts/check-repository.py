#!/usr/bin/env python3
"""Check the Git index before publishing. Reports paths/rules, never secret values.

This is a focused guard for known credential formats and local artifacts, not a
general secret detector. Review staged diffs too, especially unprefixed tokens.
"""
import re
import subprocess
import sys
from pathlib import PurePosixPath

ALLOWED_DOCS = {"docs/architecture.md", "docs/development.md", "docs/code-review.md"}
ALLOWED_ROOTS = {"native", "scripts", ".github"}
ALLOWED_FILES = {"README.md", ".gitignore"}
PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "GitHub token": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})",
    "API key": rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}",
    "bearer literal": rb"(?i)bearer\s+[A-Za-z0-9_.-]{24,}",
    "absolute home path": rb"/Users/[A-Za-z0-9._-]+/",
}


def main():
    paths = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    errors = []
    checked = 0
    for name in filter(None, paths):
        path = PurePosixPath(name)
        if name not in ALLOWED_FILES | ALLOWED_DOCS and path.parts[0] not in ALLOWED_ROOTS:
            errors.append((name, "not in repository scope"))
        if any(part.startswith((".env", ".build")) or part in {"__pycache__", "DerivedData", ".swiftpm"} for part in path.parts):
            errors.append((name, "local configuration/cache"))
        if path.suffix.lower() in {".log", ".pem", ".key", ".p12", ".mobileprovision"}:
            errors.append((name, "local diagnostic/credential file"))
        content = subprocess.check_output(["git", "show", ":" + name])
        if b"\0" in content:
            continue  # Known tracked binaries: app icon and synthetic speech fixtures.
        checked += 1
        for rule, pattern in PATTERNS.items():
            if re.search(pattern, content):
                errors.append((name, rule))
    for name, rule in errors:
        print(f"FAIL {name}: {rule}", file=sys.stderr)
    print(f"Checked {checked} staged text files; {len(errors)} findings.")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
