#!/usr/bin/env python3
"""Check Git content before publishing. Never print matched secret values."""
import argparse
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

def git(*args):
    return subprocess.check_output(["git", *args])

def privacy_findings(path, data):
    p = PurePosixPath(path)
    name = p.name.lower()
    forbidden_dirs = {".build", "dist", ".swiftpm", ".codex", ".ssh", ".aws",
                      ".local-private", "xcuserdata", "__pycache__"}
    forbidden_names = {"settings.json", "cache.json", "credentials.json", "auth.json",
                       ".netrc", ".npmrc", "id_rsa", "id_ed25519", "hub-credential.json",
                       "hub-baseline.json", "hub-sync.json", "runtime.json"}
    forbidden_suffixes = {".pem", ".key", ".p12", ".pfx", ".keychain-db", ".db",
                          ".sqlite", ".sqlite3", ".jsonl", ".har", ".log", ".trace"}
    fixture = path in {
        "TokenMonitorNative/Tests/MonitorCoreTests/Fixtures/stats.json",
        "TokenMonitorNative/Tests/MonitorCoreTests/Fixtures/history.json",
        "TokenMonitorNative/Tests/MonitorCoreTests/Fixtures/health.json",
    }
    if (set(p.parts) & forbidden_dirs or name in forbidden_names
        or name.startswith("settings.json.") or name.startswith("cache.json.")
        or (name == ".env" or name.startswith(".env.")) and name not in {".env.example", ".env.sample"}
        or p.suffix.lower() in forbidden_suffixes
        or name in {"stats.json", "history.json", "health.json"} and not fixture):
        yield "local-data file"
    patterns = {
        "personal home path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+/",
        "conversation share link": rb"https?://(?:chatgpt\.com|chat\.openai\.com|claude\.ai)/(?:share|public)/[^\s)]+",
        "archive/binary payload requiring review": rb"^(?:PK\x03\x04|\x1f\x8b|SQLite format 3)",
    }
    for label, pattern in patterns.items():
        if re.search(pattern, data):
            yield label

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true")
    parser.add_argument("--ref", default="HEAD", help="Scan this commit and every ancestor")
    args = parser.parse_args()
    root = Path(git("rev-parse", "--show-toplevel").decode().strip())
    os.chdir(root)
    scanner = shutil.which("gitleaks")
    bundled = Path(git("rev-parse", "--git-common-dir").decode().strip()) / "tools/gitleaks"
    if not scanner and bundled.is_file():
        scanner = str(bundled.resolve())
    if not scanner:
        sys.exit("Publication blocked: install Gitleaks or provision .git/tools/gitleaks.")
    if args.staged:
        rows = git("ls-files", "--stage", "-z").split(b"\0")
    else:
        commit = git("rev-parse", "--verify", args.ref + "^{commit}").decode().strip()
        commits = git("rev-list", commit).decode().split()
        rows = []
        for revision in commits:
            rows.extend(git("ls-tree", "-r", "-z", revision).split(b"\0"))
    checked = set()
    findings = []
    for row in rows:
        if not row:
            continue
        meta, path_bytes = row.split(b"\t", 1)
        fields = meta.split()
        mode = fields[0]
        oid = fields[1] if args.staged else fields[2]
        path = path_bytes.decode("utf8", errors="replace")
        if (path, oid) in checked:
            continue
        checked.add((path, oid))
        if mode not in {b"100644", b"100755"}:
            findings.append((path, "symlink/submodule requires manual review"))
            continue
        data = git("cat-file", "blob", oid.decode())
        findings.extend((path, issue) for issue in privacy_findings(path, data))
    if findings:
        for path, issue in sorted(set(findings)):
            print(f"BLOCKED: {path}: {issue}", file=sys.stderr)
        return 1
    command = [scanner, "git", ".", "--redact", "--no-banner", "--no-color",
               "--ignore-gitleaks-allow"]
    if args.staged:
        command.extend(["--pre-commit", "--staged"])
    else:
        command.append("--log-opts=" + commit)
    result = subprocess.run(command, check=False)
    if result.returncode:
        return result.returncode
    print(f"Publication check passed: {len(checked)} file versions inspected.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
