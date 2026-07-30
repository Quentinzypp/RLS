#!/usr/bin/env python3
"""Compare generated bit-accurate oracle weights with a fresh RTL capture."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def read(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--oracle", type=Path, required=True)
    parser.add_argument("--rtl", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    expected = {
        (int(row["event"]), int(row["serializer_position"])): row["weight_external_upper_real_hex"].lower()
        for row in read(args.oracle)
    }
    actual = {
        (int(row["event"]), int(row["tap_index"])): row["weight_raw"].lower()
        for row in read(args.rtl)
    }
    keys = sorted(set(expected) | set(actual))
    mismatches = [key for key in keys if expected.get(key) != actual.get(key)]
    result = {
        "status": "PASS" if len(keys) == 12000 and not mismatches else "FAIL",
        "compared": len(keys),
        "mismatches": len(mismatches),
        "first_mismatches": [
            {
                "event": key[0],
                "serializer_position": key[1],
                "oracle": expected.get(key, "MISSING"),
                "rtl": actual.get(key, "MISSING"),
            }
            for key in mismatches[:20]
        ],
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if result["status"] != "PASS":
        raise RuntimeError(json.dumps(result, sort_keys=True))
    print("GENERATED_ORACLE_RTL_WEIGHTS_MATCH compared=12000 mismatches=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
