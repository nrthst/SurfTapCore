#!/usr/bin/env python3
"""Check distributable files without printing possible secret values. Not a history scanner."""
from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {".git", ".build", ".swiftpm", "__pycache__"}
FORBIDDEN_PARTS = {
    ".claude", ".codex", ".agents", ".cursor", ".idea", ".vscode", ".aws", ".ssh",
    "xcuserdata", "DerivedData",
    "Assets.xcassets", "Resources", "IncomingIcons", "build", ".build", ".swiftpm",
}
FORBIDDEN_SUFFIXES = {
    ".zip", ".p12", ".pfx", ".pem", ".key", ".keystore", ".jks",
    ".mobileprovision", ".xcconfig", ".xcuserstate",
}
FORBIDDEN_NAMES = {"Secrets.swift", ".DS_Store", ".netrc", ".npmrc", ".pypirc", "credentials.json"}
PLACEHOLDERS = {
    "YOUR_KEY_HERE", "YOUR_API_KEY_HERE", "YOUR_STORMGLASS_API_KEY_HERE",
    "YOUR_PASSWORD_HERE", "YOUR_TOKEN_HERE", "REPLACE_ME", "<REDACTED>", "REDACTED",
    "SYNTHETIC-TEST-CREDENTIAL",
}
PATTERNS = [
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b")),
    ("GitHub token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b")),
    ("AWS access identifier", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("API secret", re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b")),
    ("Stripe secret", re.compile(r"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")),
    ("Stormglass key", re.compile(r"\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}-[0-9a-f-]{8,}\b", re.I)),
    ("credential-bearing URL", re.compile(r"\b(?:https?|postgres(?:ql)?|mysql|mongodb(?:\+srv)?|rediss?|amqps?)://[^\s/:@]+:[^\s/@]+@", re.I)),
    ("local account path", re.compile(r"(?:/Users/|/home/)[A-Za-z0-9_.-]+/")),
]
# Covers common Swift, Python, JavaScript, JSON, YAML and environment assignments.
CREDENTIAL_NAME = r"(?<![.\w])\b[a-z0-9_]*(?:password|passwd|api_?key|token|secret|private_?key|signing_?key|credential)[a-z0-9_]*\b"
QUOTED_ASSIGNMENT = re.compile(
    CREDENTIAL_NAME + r'''["']?(?:\s*:\s*(?:String|str)\??)?\s*(?:=|:)\s*(["'])([^\n]*?)\1''', re.I)
BARE_ASSIGNMENT = re.compile(
    r"(?m)^\s*(?:export\s+)?" + CREDENTIAL_NAME + r"\s*(?:=|:)\s*([^\s#\"']+)\s*(?:#.*)?$", re.I)
AUTHORIZATION = re.compile(r"\b(?:Bearer|Basic)\s+([A-Za-z0-9_./+=-]{12,})", re.I)
# Personal addresses do not belong in a public tree. Reserved documentation domains are fine.
EMAIL = re.compile(r"(?<![A-Za-z0-9._%+-])([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})\b")
EXAMPLE_DOMAINS = ("example.com", "example.org", "example.net")
EXAMPLE_SUFFIXES = (".example", ".invalid", ".test")


def is_example_address(domain):
    domain = domain.lower()
    return (domain in EXAMPLE_DOMAINS
            or domain.endswith(tuple("." + name for name in EXAMPLE_DOMAINS))
            or domain.endswith(EXAMPLE_SUFFIXES))


def findings(contents):
    """Return categories only, never matched values."""
    found = {label for label, pattern in PATTERNS if pattern.search(contents)}
    for pattern, value_group in [(QUOTED_ASSIGNMENT, 2), (BARE_ASSIGNMENT, 1), (AUTHORIZATION, 1)]:
        for match in pattern.finditer(contents):
            value = match.group(value_group).strip()
            # Variable references are not embedded credentials.
            if value and value.upper() not in PLACEHOLDERS and not re.fullmatch(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?", value):
                found.add("embedded credential")
    if any(not is_example_address(match.group(2)) for match in EMAIL.finditer(contents)):
        found.add("email address")
    return sorted(found)


def forbidden_path(relative):
    return (bool(FORBIDDEN_PARTS.intersection(relative.parts))
            or relative.suffix.lower() in FORBIDDEN_SUFFIXES
            or any(part.endswith(".xcodeproj") for part in relative.parts)
            or relative.name in FORBIDDEN_NAMES
            or (relative.name.startswith(".env") and relative.name != ".env.example"))


def check(root):
    paths = set()
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in list(dirs):
            path = Path(directory) / name
            if path.is_symlink():
                paths.add(path.relative_to(root))
                dirs.remove(name)
            elif name in EXCLUDED:
                dirs.remove(name)
        paths.update((Path(directory) / name).relative_to(root) for name in files)
    # Forced additions of ignored files are still checked. Never inspect Git metadata as content.
    if (root / ".git").exists():
        result = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, check=True)
        paths.update(Path(p.decode()) for p in result.stdout.split(b"\0") if p)
    errors = []
    for relative in sorted(paths):
        if relative.parts[0] == ".git":
            continue
        path = root / relative
        if path.is_symlink():
            errors.append(f"{relative}: symlink requires manual review")
        elif forbidden_path(relative):
            errors.append(f"{relative}: private/build/credential file must not be released")
        elif path.is_file():
            try:
                contents = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                errors.append(f"{relative}: unexpected binary file requires manual review")
                continue
            for label in findings(contents):
                errors.append(f"{relative}: {label} detected (value omitted)")
    return errors, len(paths)


def main():
    errors, count = check(ROOT)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Public-file check passed ({count} files). Review Git history separately before publishing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
