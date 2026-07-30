#!/usr/bin/env python3
"""Require fresh divopt convergence metrics to match the preserved public evidence."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return {
            row["signal"]: row
            for row in csv.DictReader(stream)
            if row.get("implementation") == "divopt"
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fresh", type=Path, required=True)
    parser.add_argument("--preserved", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()
    fresh = rows(args.fresh)
    preserved = rows(args.preserved)
    failures: list[str] = []
    exact = (
        "valid_samples",
        "update_buckets",
        "xz_valid_samples",
        "steady_state_update",
        "result",
        "detail",
    )
    numeric = (
        "early_power_updates_1_100",
        "previous_power_updates_801_900",
        "late_power_updates_901_1000",
        "late_to_early_db",
    )
    for signal in ("dout_sub_data1", "dout_sub_data2"):
        if signal not in fresh or signal not in preserved:
            failures.append(f"missing metric row: {signal}")
            continue
        for field in exact:
            if fresh[signal][field] != preserved[signal][field]:
                failures.append(f"{signal}.{field}: {fresh[signal][field]} != {preserved[signal][field]}")
        for field in numeric:
            left = float(fresh[signal][field])
            right = float(preserved[signal][field])
            tolerance = 1e-9 * max(1.0, abs(right))
            if abs(left - right) > tolerance:
                failures.append(f"{signal}.{field}: {left} != {right}")
    lines = [
        "# Fresh convergence reproduction",
        "",
        f"- Status: **{'PASS' if not failures else 'FAIL'}**",
        "- Run: portable/divopt RTL, 1,000 updates, repository vectors",
        "- Comparison: fresh metrics versus preserved public evidence",
        "- Claim boundary: `IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED`",
        "",
    ]
    if failures:
        lines.extend(["## Failures", "", *[f"- {failure}" for failure in failures], ""])
    args.summary.write_text("\n".join(lines), encoding="utf-8")
    if failures:
        raise RuntimeError("; ".join(failures))
    print("FRESH_PRESERVED_METRICS_MATCH")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
