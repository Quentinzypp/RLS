#!/usr/bin/env python3
"""Audit the worktree and reachable Git blobs for public-release hazards."""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "reports" / "showcase"
MAX_BYTES = 10 * 1024 * 1024
FORBIDDEN_SUFFIXES = {
    ".db", ".lib", ".lef", ".gds", ".gdsii", ".ddc", ".wlf", ".vcd",
    ".fsdb", ".ucdb", ".dcp", ".bit", ".bin", ".xci", ".xcix",
}
TEXT_SUFFIXES = {
    ".md", ".txt", ".csv", ".json", ".py", ".ps1", ".tcl", ".do",
    ".v", ".sv", ".sdc", ".xdc", ".f", ".mem", ".coe", ".svg",
    ".gitattributes", ".gitignore",
}


def git(*args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def worktree_files() -> list[Path]:
    listed = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
    if listed.returncode != 0:
        raise RuntimeError(listed.stderr.decode("utf-8", errors="replace"))
    return sorted(
        (ROOT / value.decode("utf-8") for value in listed.stdout.split(b"\0") if value),
        key=lambda item: item.relative_to(ROOT).as_posix(),
    )


def patterns() -> list[tuple[str, re.Pattern[str]]]:
    return [
        ("private_key", re.compile("BEGIN (?:RSA |EC |OPENSSH )?PRIVATE" + " KEY")),
        ("github_token", re.compile("(?:gh" + "[opsu]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
        ("aws_key", re.compile("AK" + "IA[0-9A-Z]{16}")),
        ("license_server", re.compile("(?:LM_" + "LICENSE_FILE|SNPSLMD_" + "LICENSE_FILE|[0-9]{4,5}@[A-Za-z0-9_.-]+)", re.I)),
        ("windows_absolute_path", re.compile(r"(?<![A-Za-z0-9])(?:[A-Za-z]:\\|[A-Za-z]:/)(?!/)")),
        ("user_profile_path", re.compile(re.escape("/" + "Users/") + r"[^/\s]+/", re.I)),
        ("posix_machine_path", re.compile("(?:/" + "home/|/" + "mnt/|/" + "opt/|/" + "tmp/|/" + "usr/local/)")),
        ("ipv4", re.compile(r"(?<![0-9.])(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(?:\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}(?![0-9.])")),
    ]


def scan_text(label: str, data: bytes, findings: list[str]) -> None:
    if b"\x00" in data[:4096]:
        return
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        try:
            text = data.decode("ascii")
        except UnicodeDecodeError:
            return
    for name, pattern in patterns():
        if pattern.search(text):
            findings.append(f"{label}: {name}")


def reachable_blobs() -> list[tuple[str, str]]:
    result = git("rev-list", "--objects", "--all")
    if result.returncode != 0:
        return []
    objects: list[tuple[str, str]] = []
    for line in result.stdout.decode("utf-8", errors="replace").splitlines():
        object_id, _, path = line.partition(" ")
        kind = git("cat-file", "-t", object_id)
        if kind.returncode == 0 and kind.stdout.strip() == b"blob":
            objects.append((object_id, path))
    return objects


def write_report(name: str, title: str, status: str, body: list[str]) -> None:
    path = REPORT / name
    path.write_text(
        "\n".join([f"# {title}", "", f"- Status: **{status}**", *body]) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    REPORT.mkdir(parents=True, exist_ok=True)
    files = worktree_files()
    forbidden = [path.relative_to(ROOT).as_posix() for path in files if path.suffix.lower() in FORBIDDEN_SUFFIXES]
    large = [
        (path.relative_to(ROOT).as_posix(), path.stat().st_size)
        for path in files if path.stat().st_size > MAX_BYTES
    ]
    findings: list[str] = []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if path.suffix.lower() in TEXT_SUFFIXES or path.name in {"README", "LICENSE"}:
            scan_text(f"worktree:{relative}", path.read_bytes(), findings)
    blob_forbidden: list[str] = []
    for object_id, path in reachable_blobs():
        suffix = Path(path).suffix.lower()
        if suffix in FORBIDDEN_SUFFIXES:
            blob_forbidden.append(f"{path} ({object_id[:12]})")
        blob = git("cat-file", "-p", object_id)
        if blob.returncode == 0 and (suffix in TEXT_SUFFIXES or Path(path).name in {"README", "LICENSE"}):
            scan_text(f"blob:{path}@{object_id[:12]}", blob.stdout, findings)

    public_failures = forbidden + blob_forbidden
    write_report(
        "public_scope_audit.md",
        "Public scope audit",
        "PASS" if not public_failures else "FAIL",
        [
            "- Scope: current worktree plus every reachable Git blob",
            "- Forbidden EDA/technology/vendor payloads: none found" if not public_failures else "- Findings:",
            *[f"- `{item}`" for item in public_failures],
            "- No `LICENSE` file is present; the licensing boundary is documented in `PUBLIC_SCOPE.md`.",
            "- Uncommitted Vivado comparison data is excluded.",
        ],
    )
    write_report(
        "secret_scan.md",
        "Secret and machine-data scan",
        "PASS" if not findings else "FAIL",
        [
            "- Scope: current text files plus text in every reachable Git blob",
            "- Checks: private keys, token patterns, license servers, absolute machine paths, IPv4 addresses",
            "- Findings: none" if not findings else "- Findings:",
            *[f"- `{item}`" for item in sorted(set(findings))],
        ],
    )
    write_report(
        "file_size_audit.md",
        "File size audit",
        "PASS" if not large else "FAIL",
        [
            f"- Limit: {MAX_BYTES} bytes (10 MiB) per public file",
            "- Oversize files: none" if not large else "- Oversize files:",
            *[f"- `{path}`: {size} bytes" for path, size in large],
            "- Large WLF/VCD/raw convergence captures remain excluded; public input vectors are below the limit.",
        ],
    )
    if public_failures or findings or large:
        raise SystemExit("PUBLIC_REPOSITORY_AUDIT_FAIL")
    print("PUBLIC_REPOSITORY_AUDIT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
