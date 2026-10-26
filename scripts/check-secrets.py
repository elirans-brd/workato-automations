#!/usr/bin/env python3
"""Fail if hardcoded secrets are found in Workato exports or other repo files.

Usage:
  check-secrets.py --staged      # files staged for commit (pre-commit hook)
  check-secrets.py --all         # all tracked files
  check-secrets.py FILE [FILE…]  # explicit files
"""
import re
import subprocess
import sys

KEYED = re.compile(
    r'"(?P<key>[A-Za-z0-9_]*(?:token|secret|password|passwd|api_?key|private_?key)[A-Za-z0-9_]*)"'
    r'\s*:\s*"(?P<val>[^"]{20,})"',
    re.I,
)
PREFIXED = re.compile(
    r"(sk-[A-Za-z0-9_\-]{20,}|xox[abpr]-[A-Za-z0-9\-]{10,}"
    r"|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}"
    r"|wrk[a-z]?_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)"
)
# Values that are Workato datapills/formulas/placeholders, not literal secrets.
SAFE_VALUE = re.compile(r"(#\{|_dp\(|^=|REDACTED|REPLACE[-_]ME|\s)")
SKIP_PREFIXES = ("wk/", "skills/recipe-skills/", "scripts/check-secrets.py")


def git_files(args):
    out = subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout
    return [f for f in out.split("\0") if f]


def scan(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
    except (IsADirectoryError, FileNotFoundError):
        return []
    hits = []
    for m in KEYED.finditer(text):
        val = m.group("val")
        if SAFE_VALUE.search(val) or val.startswith("http"):
            continue
        hits.append((m.start(), m.group("key"), val))
    for m in PREFIXED.finditer(text):
        hits.append((m.start(), "pattern", m.group(0)))
    return [(text.count("\n", 0, pos) + 1, k, f"{v[:4]}…({len(v)} chars)") for pos, k, v in hits]


def main(argv):
    if not argv or argv[0] == "--staged":
        files = git_files(["diff", "--cached", "--name-only", "--diff-filter=ACM", "-z"])
    elif argv[0] == "--all":
        files = git_files(["ls-files", "-z"])
    else:
        files = argv
    files = [f for f in files if not f.startswith(SKIP_PREFIXES)]

    found = 0
    for f in files:
        for line, key, preview in scan(f):
            found += 1
            print(f"SECRET? {f}:{line}  {key} = {preview}")
    if found:
        print(
            f"\n✖ {found} possible secret(s). Move them to a Workato account/environment "
            "property and replace the literal with REDACTED_USE_WORKATO_PROPERTY."
        )
        return 1
    print(f"✔ secret scan passed ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
