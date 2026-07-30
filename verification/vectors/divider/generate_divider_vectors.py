#!/usr/bin/env python3
"""Generate deterministic exact-Q32 divider vectors for Phase 4."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import re
from pathlib import Path


INPUT_WIDTH = 40
OUTPUT_WIDTH = 72
FRACTIONAL_WIDTH = 32
INPUT_MASK = (1 << INPUT_WIDTH) - 1
OUTPUT_MASK = (1 << OUTPUT_WIDTH) - 1
INPUT_SIGN = 1 << (INPUT_WIDTH - 1)


def signed_from_bits(value: int, width: int) -> int:
    sign = 1 << (width - 1)
    mask = (1 << width) - 1
    value &= mask
    return value - (1 << width) if value & sign else value


def exact_q32(dividend: int, divisor: int) -> tuple[int, bool]:
    dividend = signed_from_bits(dividend, INPUT_WIDTH)
    divisor = signed_from_bits(divisor, INPUT_WIDTH)
    if divisor == 0:
        return 0, True
    negative = (dividend < 0) ^ (divisor < 0)
    scaled = abs(dividend) << FRACTIONAL_WIDTH
    quotient, remainder = divmod(scaled, abs(divisor))
    twice_remainder = remainder << 1
    if twice_remainder > abs(divisor) or (
        twice_remainder == abs(divisor) and negative
    ):
        quotient += 1
    if negative:
        quotient = -quotient
    return quotient & OUTPUT_MASK, False


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def add_case(rows: list[dict[str, object]], vector_class: str, dividend: int, divisor: int) -> None:
    expected, divide_by_zero = exact_q32(dividend, divisor)
    rows.append(
        {
            "index": len(rows),
            "class": vector_class,
            "dividend_signed": signed_from_bits(dividend, INPUT_WIDTH),
            "divisor_signed": signed_from_bits(divisor, INPUT_WIDTH),
            "dividend_hex": f"{dividend & INPUT_MASK:010x}",
            "divisor_hex": f"{divisor & INPUT_MASK:010x}",
            "expected_hex": f"{expected:018x}",
            "divide_by_zero": int(divide_by_zero),
        }
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    script = Path(__file__).resolve()
    default_root = script.parents[2]
    parser.add_argument("--repo-root", type=Path, default=default_root)
    parser.add_argument("--random-count", type=int, default=1024)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x524C5332)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    output = root / "verification" / "divider_vectors"
    output.mkdir(parents=True, exist_ok=True)
    semantics = root / "reports" / "phase1b" / "phase1b_divider_semantics.csv"
    portable_probe = root / "reports" / "phase2" / "t2_10_divider" / "phase2_t2_10_portable_probe.log"
    runtime_trace = root / "reports" / "divider_optimization" / "divider_runtime_trace.csv"
    if not semantics.is_file() or not portable_probe.is_file() or not runtime_trace.is_file():
        raise FileNotFoundError("Required retained or runtime divider trace is missing")

    rows: list[dict[str, object]] = []
    with semantics.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            add_case(
                rows,
                "retained_phase1b",
                int(row["dividend_hex"], 16),
                int(row["divisor_hex"], 16),
            )

    pair_pattern = re.compile(
        r"DIV_REFERENCE_PAIR cycle=\d+ index=(\d+) dividend=([0-9a-fA-F]{10}) "
        r"divisor=([0-9a-fA-F]{10}) expected=([0-9a-fA-F]{18})"
    )
    retained_pairs = pair_pattern.findall(portable_probe.read_text(encoding="utf-16"))
    if len(retained_pairs) != 32 or [int(row[0]) for row in retained_pairs] != list(range(32)):
        raise RuntimeError(f"Expected 32 ordered retained probe pairs, found {len(retained_pairs)}")
    for _, dividend_hex, divisor_hex, expected_hex in retained_pairs:
        expected, _ = exact_q32(int(dividend_hex, 16), int(divisor_hex, 16))
        if f"{expected:018x}" != expected_hex.lower():
            raise RuntimeError("Independent oracle differs from retained portable probe")
        add_case(rows, "retained_phase2_32", int(dividend_hex, 16), int(divisor_hex, 16))

    directed_dividends = [0, 1, -1, 2, -2, (1 << 39) - 1, -(1 << 39)]
    directed_divisors = [0, 1, -1, 2, -2, 3, -3, 1 << 32, 1 << 33, (1 << 39) - 1, -(1 << 39)]
    for dividend in directed_dividends:
        for divisor in directed_divisors:
            add_case(rows, "directed_boundary", dividend, divisor)

    with runtime_trace.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if row["event"] != "request":
                continue
            denominator = int(row["common_denominator"], 16)
            add_case(rows, "rls_trace_real", int(row["real_numerator"], 16), denominator)
            add_case(rows, "rls_trace_imag", int(row["imag_numerator"], 16), denominator)

    rng = random.Random(args.seed)
    lower = -(1 << 39)
    upper = 1 << 39
    for index in range(args.random_count):
        dividend = rng.randrange(lower, upper)
        divisor = 0 if index % 127 == 0 else rng.randrange(lower, upper)
        if divisor == 0 and index % 127 != 0:
            divisor = 1
        add_case(rows, "deterministic_random", dividend, divisor)

    csv_path = output / "divider_vectors.csv"
    fieldnames = list(rows[0].keys())
    with csv_path.open("w", newline="", encoding="ascii") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    memories = {
        "dividend.mem": "dividend_hex",
        "divisor.mem": "divisor_hex",
        "expected.mem": "expected_hex",
        "divide_by_zero.mem": "divide_by_zero",
    }
    for filename, field in memories.items():
        with (output / filename).open("w", encoding="ascii", newline="\n") as handle:
            for row in rows:
                value = row[field]
                if field == "divide_by_zero":
                    value = str(value)
                handle.write(f"{value}\n")

    class_counts: dict[str, int] = {}
    for row in rows:
        name = str(row["class"])
        class_counts[name] = class_counts.get(name, 0) + 1
    metadata = {
        "status": "PASS",
        "marker": "PHASE4_DIVIDER_VECTOR_GENERATION_PASS",
        "input_width": INPUT_WIDTH,
        "fractional_width": FRACTIONAL_WIDTH,
        "output_width": OUTPUT_WIDTH,
        "rounding": "nearest_ties_negative_infinity",
        "divide_by_zero_numeric_result": 0,
        "seed": f"0x{args.seed:08X}",
        "random_count": args.random_count,
        "vector_count": len(rows),
        "class_counts": class_counts,
        "source_hashes": {
            str(semantics.relative_to(root)).replace("\\", "/"): sha256(semantics),
            str(portable_probe.relative_to(root)).replace("\\", "/"): sha256(portable_probe),
            str(runtime_trace.relative_to(root)).replace("\\", "/"): sha256(runtime_trace),
        },
        "output_hashes": {},
    }
    for filename in ["divider_vectors.csv", *memories.keys()]:
        metadata["output_hashes"][filename] = sha256(output / filename)
    metadata_path = output / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="ascii")
    print(metadata["marker"])
    print(f"vectors={len(rows)}")


if __name__ == "__main__":
    main()
