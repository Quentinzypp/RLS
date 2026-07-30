#!/usr/bin/env python3
"""Write a deterministic SHA-256 manifest for the public tree, excluding itself."""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "reports" / "showcase" / "repository_manifest.sha256"


def main() -> int:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    )
    paths = [ROOT / value.decode("utf-8") for value in result.stdout.split(b"\0") if value]
    paths = [path for path in paths if path != OUTPUT]
    lines = []
    for path in sorted(paths, key=lambda item: item.relative_to(ROOT).as_posix()):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(ROOT).as_posix()}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"REPOSITORY_MANIFEST_WRITTEN files={len(lines)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
