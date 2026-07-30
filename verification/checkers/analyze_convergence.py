#!/usr/bin/env python3
"""Reduce a ModelSim capture to deterministic convergence metrics and a compact curve."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path


SIGNALS = ("dout_sub_data1", "dout_sub_data2")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--expected-updates", type=int, default=1000)
    return parser.parse_args()


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        return list(csv.DictReader(stream))


def write_rows(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def moving_mean(values: list[float], window: int) -> list[float | None]:
    output: list[float | None] = [None] * len(values)
    running = 0.0
    for index, value in enumerate(values):
        running += value
        if index >= window:
            running -= values[index - window]
        if index + 1 >= window:
            output[index] = running / window
    return output


def bool_text(value: bool) -> str:
    return "True" if value else "False"


def analyze_signal(
    rows: list[dict[str, str]], signal: str, expected_updates: int, schedule_normal: bool
) -> tuple[dict[str, object], list[float]]:
    buckets: defaultdict[int, list[int]] = defaultdict(list)
    valid_samples = 0
    xz_samples = 0
    for row in rows:
        if row.get("valid", "").strip() != "1":
            continue
        update = int(row.get("update_index", "-1"))
        if not 1 <= update <= expected_updates:
            continue
        valid_samples += 1
        raw = row.get(f"{signal}_raw", "").lower()
        if row.get("xz", "0") != "0" or "x" in raw or "z" in raw:
            xz_samples += 1
            continue
        buckets[update].append(int(row[f"{signal}_signed"]))

    powers: list[float] = []
    peaks: list[int] = []
    for update in range(1, expected_updates + 1):
        values = buckets.get(update, [])
        if not values:
            raise ValueError(f"{signal}: update {update} has no valid samples")
        powers.append(statistics.fmean(float(value) * float(value) for value in values))
        peaks.append(max(abs(value) for value in values))

    early = statistics.fmean(powers[:100])
    previous = statistics.fmean(powers[800:900])
    late = statistics.fmean(powers[900:1000])
    ratio = late / early
    db = 10.0 * math.log10(ratio)
    moving_power = moving_mean(powers, 50)
    threshold = late * 1.10
    steady: int | None = None
    for index in range(49, expected_updates - 2):
        if all(moving_power[index + offset] is not None and moving_power[index + offset] <= threshold for offset in range(3)):
            steady = index + 1
            break
    stable = late <= previous * 1.25
    converged = (
        xz_samples == 0
        and late <= early * 0.50
        and steady is not None
        and stable
        and schedule_normal
    )
    metric: dict[str, object] = {
        "implementation": "divopt",
        "signal": signal,
        "valid_samples": valid_samples,
        "update_buckets": len(buckets),
        "xz_valid_samples": xz_samples,
        "early_power_updates_1_100": early,
        "previous_power_updates_801_900": previous,
        "late_power_updates_901_1000": late,
        "late_to_early_power_ratio": ratio,
        "late_to_early_db": db,
        "peak_abs": max(peaks),
        "steady_state_update": steady if steady is not None else "NOT_AVAILABLE",
        "final_region_stable": bool_text(stable),
        "schedule_normal": bool_text(schedule_normal),
        "result": "CONVERGED" if converged else "INCONCLUSIVE",
        "detail": "IMPLEMENTATION_RESIDUAL_CONVERGENCE_OBSERVED" if converged else "CONVERGENCE_INCONCLUSIVE",
    }
    rms50 = [math.sqrt(value) if value is not None else math.nan for value in moving_power]
    return metric, rms50


def main() -> int:
    args = parse_args()
    capture = args.capture_dir.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    residual = read_rows(capture / "residual_cycle_samples.csv")
    updates = read_rows(capture / "update_timing_raw.csv")
    weights = read_rows(capture / "weights_samples_raw.csv")

    intervals = [int(row["interval_cycles"]) for row in updates]
    positive = intervals[1:] if intervals and intervals[0] == 0 else [value for value in intervals if value > 0]
    histogram = Counter(positive)
    expected_histogram = Counter({175: args.expected_updates - 2, 208: 1})
    schedule_normal = len(updates) == args.expected_updates and histogram == expected_histogram

    metrics: list[dict[str, object]] = []
    curves: dict[str, list[float]] = {}
    for signal in SIGNALS:
        metric, curve = analyze_signal(residual, signal, args.expected_updates, schedule_normal)
        metrics.append(metric)
        curves[signal] = curve
    fields = list(metrics[0])
    write_rows(output / "convergence_metrics.csv", fields, metrics)
    curve_rows: list[dict[str, object]] = []
    for index in range(args.expected_updates):
        curve_rows.append(
            {
                "update": index + 1,
                "dout_sub_data1_moving_rms_50": "" if math.isnan(curves[SIGNALS[0]][index]) else f"{curves[SIGNALS[0]][index]:.9f}",
                "dout_sub_data2_moving_rms_50": "" if math.isnan(curves[SIGNALS[1]][index]) else f"{curves[SIGNALS[1]][index]:.9f}",
            }
        )
    write_rows(
        output / "convergence_curve.csv",
        ["update", "dout_sub_data1_moving_rms_50", "dout_sub_data2_moving_rms_50"],
        curve_rows,
    )

    status_values: dict[str, str] = {}
    status_path = capture / "convergence_capture_status.txt"
    if status_path.exists():
        for line in status_path.read_text(encoding="ascii").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                status_values[key] = value
    summary = {
        "status": "MODELSIM_CONVERGENCE_FRESH_PASS" if all(row["result"] == "CONVERGED" for row in metrics) else "MODELSIM_CONVERGENCE_FRESH_FAIL",
        "updates": len(updates),
        "weights": len(weights),
        "weight_xz": sum(row.get("xz", "0") != "0" for row in weights),
        "schedule": {str(key): histogram[key] for key in sorted(histogram)},
        "capture": status_values,
    }
    (output / "fresh_run.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if summary["status"] != "MODELSIM_CONVERGENCE_FRESH_PASS" or len(weights) != 12000:
        raise RuntimeError(json.dumps(summary, sort_keys=True))
    print("MODELSIM_CONVERGENCE_ANALYSIS_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
