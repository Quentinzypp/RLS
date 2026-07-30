#!/usr/bin/env python3
"""Floating-point reference for the frozen 12-tap complex RLS contract."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np

from rls_event_schedule import (
    DESIRED_START_INDEX,
    REFERENCE_START_INDEX,
    REFILL_DESIRED_START_INDEX,
    REFILL_EVENT,
    REFILL_REFERENCE_START_INDEX,
    event_input_schedule,
    required_source_lengths,
)


ORDER = 12
INPUT_WIDTH = 24
INPUT_FRACTIONAL_BITS = 13
DEFAULT_UPDATES = 1000
LAMBDA_NUMERATOR = 33_551_077
LAMBDA_FRACTIONAL_BITS = 25
P0_DIAGONAL = 8.0


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def signed_from_bits(bits: str) -> int:
    value = int(bits, 2)
    sign_bit = 1 << (len(bits) - 1)
    return value - (1 << len(bits)) if value & sign_bit else value


def load_packed_complex(path: Path) -> np.ndarray:
    values: list[complex] = []
    scale = float(1 << INPUT_FRACTIONAL_BITS)
    with path.open("r", encoding="ascii") as stream:
        for line_number, raw_line in enumerate(stream, start=1):
            bits = raw_line.strip()
            if not bits:
                continue
            if len(bits) != 2 * INPUT_WIDTH or any(bit not in "01" for bit in bits):
                raise ValueError(
                    f"{path}:{line_number}: expected exactly 48 binary digits"
                )
            real = signed_from_bits(bits[:INPUT_WIDTH]) / scale
            imag = signed_from_bits(bits[INPUT_WIDTH:]) / scale
            values.append(complex(real, imag))
    if not values:
        raise ValueError(f"No packed samples found in {path}")
    return np.asarray(values, dtype=np.complex128)


def format_float(value: float) -> str:
    if not math.isfinite(value):
        raise ValueError(f"Non-finite floating-point result: {value}")
    return format(value, ".17g")


def write_csv(path: Path, header: Iterable[str], rows: Iterable[Iterable[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(header)
        for row in rows:
            writer.writerow(row)


@dataclass(frozen=True)
class FloatRun:
    reference_indices: np.ndarray
    desired_indices: np.ndarray
    references: np.ndarray
    desired: np.ndarray
    predictions: np.ndarray
    residuals: np.ndarray
    denominators: np.ndarray
    gains: np.ndarray
    weights: np.ndarray
    weight_norms: np.ndarray
    p_hermitian_drift: np.ndarray


def run_float_rls(reference: np.ndarray, desired: np.ndarray, updates: int) -> FloatRun:
    required_reference, required_desired = required_source_lengths(updates, ORDER)
    if len(reference) < required_reference or len(desired) < required_desired:
        raise ValueError(
            "Insufficient input samples for aligned run: "
            f"reference needs {required_reference}, has {len(reference)}; "
            f"desired needs {required_desired}, has {len(desired)}"
        )

    lambda_value = LAMBDA_NUMERATOR / float(1 << LAMBDA_FRACTIONAL_BITS)
    p_matrix = np.eye(ORDER, dtype=np.complex128) * P0_DIAGONAL
    weight = np.zeros(ORDER, dtype=np.complex128)
    schedules = [event_input_schedule(event, ORDER) for event in range(updates)]
    reference_indices = np.asarray(
        [schedule.reference_index for schedule in schedules], dtype=np.int64
    )
    desired_indices = np.asarray(
        [schedule.desired_index for schedule in schedules], dtype=np.int64
    )
    references = reference[reference_indices]
    desired_events = desired[desired_indices]
    predictions = np.empty(updates, dtype=np.complex128)
    residuals = np.empty(updates, dtype=np.complex128)
    denominators = np.empty(updates, dtype=np.complex128)
    gains = np.empty((updates, ORDER), dtype=np.complex128)
    weights = np.empty((updates, ORDER), dtype=np.complex128)
    weight_norms = np.empty(updates, dtype=np.float64)
    p_hermitian_drift = np.empty(updates, dtype=np.float64)

    for event in range(updates):
        u_vector = np.asarray(
            [
                reference[index] if index is not None else 0.0j
                for index in schedules[event].reference_window_indices
            ],
            dtype=np.complex128,
        )

        a_vector = p_matrix @ u_vector
        denominator = lambda_value + np.vdot(u_vector, a_vector)
        if denominator == 0:
            raise ZeroDivisionError(f"Zero denominator at update event {event}")
        gain = a_vector / denominator
        prediction = np.vdot(weight, u_vector)
        residual = desired_events[event] - prediction
        weight = weight + gain * np.conj(residual)
        u_h_p_over_lambda = (np.conj(u_vector) @ p_matrix) / lambda_value
        p_matrix = p_matrix / lambda_value - np.outer(gain, u_h_p_over_lambda)

        if not (
            np.all(np.isfinite(weight))
            and np.all(np.isfinite(p_matrix))
            and np.isfinite(denominator)
        ):
            raise FloatingPointError(f"Non-finite state at update event {event}")

        predictions[event] = prediction
        residuals[event] = residual
        denominators[event] = denominator
        gains[event] = gain
        weights[event] = weight
        weight_norms[event] = np.linalg.norm(weight)
        p_hermitian_drift[event] = np.max(np.abs(p_matrix - p_matrix.conj().T))

    return FloatRun(
        reference_indices=reference_indices,
        desired_indices=desired_indices,
        references=references,
        desired=desired_events,
        predictions=predictions,
        residuals=residuals,
        denominators=denominators,
        gains=gains,
        weights=weights,
        weight_norms=weight_norms,
        p_hermitian_drift=p_hermitian_drift,
    )


def convergence_event(residual_power: np.ndarray, steady_power: float) -> int | None:
    window = min(50, len(residual_power))
    if window == 0:
        return None
    moving = np.convolve(residual_power, np.ones(window) / window, mode="valid")
    threshold = steady_power * 1.10
    hold_windows = 3
    for index in range(0, len(moving) - hold_windows + 1):
        if np.all(moving[index : index + hold_windows] <= threshold):
            return index + window - 1
    return None


def calculate_metrics(run: FloatRun) -> dict[str, object]:
    residual_power_samples = np.abs(run.residuals) ** 2
    desired_power_samples = np.abs(run.desired) ** 2
    steady_window = min(100, len(run.residuals))
    steady_power = float(np.mean(residual_power_samples[-steady_window:]))
    desired_power = float(np.mean(desired_power_samples))
    residual_power = float(np.mean(residual_power_samples))
    cancellation_db = (
        float(10.0 * np.log10(desired_power / residual_power))
        if residual_power > 0.0 and desired_power > 0.0
        else None
    )
    converged = convergence_event(residual_power_samples, steady_power)
    return {
        "updates": int(len(run.residuals)),
        "mse": residual_power,
        "desired_power": desired_power,
        "residual_power": residual_power,
        "residual_real_power": float(np.mean(run.residuals.real**2)),
        "residual_imag_power": float(np.mean(run.residuals.imag**2)),
        "cancellation_db": cancellation_db,
        "steady_state_window": steady_window,
        "steady_state_residual_power": steady_power,
        "steady_state_mean_abs_error": float(
            np.mean(np.abs(run.residuals[-steady_window:]))
        ),
        "maximum_transient_abs_error": float(np.max(np.abs(run.residuals))),
        "output_peak_abs": float(np.max(np.abs(run.predictions))),
        "convergence_rule": (
            "first 50-update moving residual-power window at or below 110% of "
            "the final 100-update residual power for three consecutive windows"
        ),
        "convergence_event_zero_based": converged,
        "minimum_denominator_magnitude": float(np.min(np.abs(run.denominators))),
        "maximum_denominator_imag_abs": float(
            np.max(np.abs(run.denominators.imag))
        ),
        "final_weight_norm": float(run.weight_norms[-1]),
        "maximum_p_hermitian_drift": float(np.max(run.p_hermitian_drift)),
        "overflow_count": 0,
        "saturation_count": 0,
        "overflow_note": "not applicable to the floating-point reference",
    }


def write_outputs(
    repo_root: Path,
    artifact_dir: Path,
    report_dir: Path,
    reference_path: Path,
    desired_path: Path,
    run: FloatRun,
    metrics: dict[str, object],
) -> None:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)
    oracle_path = artifact_dir / "rls_float_oracle.csv"
    weights_path = artifact_dir / "rls_float_weights.csv"
    metrics_path = report_dir / "rls_float_metrics.json"
    manifest_path = artifact_dir / "rls_float_manifest.json"
    report_path = report_dir.parent / "phase1b_float_reference.md"

    oracle_rows = []
    for event in range(len(run.residuals)):
        oracle_rows.append(
            (
                event,
                int(run.reference_indices[event]),
                int(run.desired_indices[event]),
                format_float(float(run.references[event].real)),
                format_float(float(run.references[event].imag)),
                format_float(float(run.desired[event].real)),
                format_float(float(run.desired[event].imag)),
                format_float(float(run.predictions[event].real)),
                format_float(float(run.predictions[event].imag)),
                format_float(float(run.residuals[event].real)),
                format_float(float(run.residuals[event].imag)),
                format_float(float(run.denominators[event].real)),
                format_float(float(run.denominators[event].imag)),
                format_float(float(np.linalg.norm(run.gains[event]))),
                format_float(float(run.weight_norms[event])),
                format_float(float(run.p_hermitian_drift[event])),
            )
        )
    write_csv(
        oracle_path,
        (
            "event",
            "reference_source_index_zero_based",
            "desired_source_index_zero_based",
            "reference_real",
            "reference_imag",
            "desired_real",
            "desired_imag",
            "prediction_real",
            "prediction_imag",
            "residual_real",
            "residual_imag",
            "denominator_real",
            "denominator_imag",
            "gain_norm",
            "weight_norm",
            "p_hermitian_drift",
        ),
        oracle_rows,
    )

    weight_rows = []
    for event in range(run.weights.shape[0]):
        for tap in range(run.weights.shape[1]):
            weight_rows.append(
                (
                    event,
                    tap,
                    format_float(float(run.weights[event, tap].real)),
                    format_float(float(run.weights[event, tap].imag)),
                )
            )
    write_csv(weights_path, ("event", "tap", "weight_real", "weight_imag"), weight_rows)

    metrics_path.write_text(
        json.dumps(metrics, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="ascii",
    )
    model_path = Path(__file__).resolve()
    schedule_path = model_path.with_name("rls_event_schedule.py")
    manifest = {
        "status": "PHASE1B_FLOAT_REFERENCE_GENERATED",
        "model_source": model_path.relative_to(repo_root).as_posix(),
        "model_source_sha256": sha256_file(model_path),
        "event_schedule_source": schedule_path.relative_to(repo_root).as_posix(),
        "event_schedule_source_sha256": sha256_file(schedule_path),
        "order": ORDER,
        "updates": int(len(run.residuals)),
        "external_packing": "upper_real_lower_imaginary_signed_24Q13",
        "reference_start_index_zero_based": REFERENCE_START_INDEX,
        "desired_start_index_zero_based": DESIRED_START_INDEX,
        "refill_event_zero_based": REFILL_EVENT,
        "refill_reference_start_index_zero_based": REFILL_REFERENCE_START_INDEX,
        "refill_desired_start_index_zero_based": REFILL_DESIRED_START_INDEX,
        "p0_diagonal": P0_DIAGONAL,
        "lambda_numerator": LAMBDA_NUMERATOR,
        "lambda_fractional_bits": LAMBDA_FRACTIONAL_BITS,
        "lambda_value": LAMBDA_NUMERATOR / float(1 << LAMBDA_FRACTIONAL_BITS),
        "division_policy": "exact complex128 division by encoded lambda and denominator",
        "inputs": {
            "reference": {
                "path": reference_path.relative_to(repo_root).as_posix(),
                "sha256": sha256_file(reference_path),
                "samples": int(len(load_packed_complex(reference_path))),
            },
            "desired": {
                "path": desired_path.relative_to(repo_root).as_posix(),
                "sha256": sha256_file(desired_path),
                "samples": int(len(load_packed_complex(desired_path))),
            },
        },
        "outputs": {
            oracle_path.name: sha256_file(oracle_path),
            weights_path.name: sha256_file(weights_path),
            metrics_path.name: sha256_file(metrics_path),
        },
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="ascii",
    )

    cancellation = metrics["cancellation_db"]
    convergence = metrics["convergence_event_zero_based"]
    report_lines = [
        "# Phase 1B Floating-Point Reference",
        "",
        "## Status",
        "",
        "- Model execution: **RUN / PASS**",
        "- Output finiteness and completeness: **PASS**",
        "- Original RTL correlation: **NOT YET RUN**",
        "- Completion marker: `PHASE1B_T1B02_FLOAT_REFERENCE_PASS`",
        "",
        "## Frozen Inputs",
        "",
        f"- Reference SHA-256: `{sha256_file(reference_path)}`",
        f"- Desired SHA-256: `{sha256_file(desired_path)}`",
        f"- Updates: {len(run.residuals)}",
        f"- Initial source alignment: reference `{REFERENCE_START_INDEX}+n`, desired `{DESIRED_START_INDEX}+n`",
        f"- Refill alignment from event `{REFILL_EVENT}`: reference `{REFILL_REFERENCE_START_INDEX}+(n-{REFILL_EVENT})`, desired `{REFILL_DESIRED_START_INDEX}+(n-{REFILL_EVENT})`",
        f"- Lambda: `{LAMBDA_NUMERATOR}/2^{LAMBDA_FRACTIONAL_BITS}`",
        f"- P initialization: `{P0_DIAGONAL}I`",
        "",
        "## Actual Metrics",
        "",
        f"- MSE/residual power: `{format_float(float(metrics['mse']))}`",
        f"- Real residual power: `{format_float(float(metrics['residual_real_power']))}`",
        f"- Imaginary residual power: `{format_float(float(metrics['residual_imag_power']))}`",
        f"- Cancellation: `{format_float(float(cancellation)) if cancellation is not None else 'UNDEFINED'} dB`",
        f"- Steady-state residual power: `{format_float(float(metrics['steady_state_residual_power']))}`",
        f"- Maximum transient error magnitude: `{format_float(float(metrics['maximum_transient_abs_error']))}`",
        f"- Convergence event: `{convergence if convergence is not None else 'NOT_REACHED'}`",
        f"- Maximum P Hermitian drift: `{format_float(float(metrics['maximum_p_hermitian_drift']))}`",
        "",
        "## Artifacts",
        "",
        f"- `{oracle_path.relative_to(repo_root).as_posix()}`",
        f"- `{weights_path.relative_to(repo_root).as_posix()}`",
        f"- `{manifest_path.relative_to(repo_root).as_posix()}`",
        f"- `{metrics_path.relative_to(repo_root).as_posix()}`",
        "",
        "The event-level residual is the mathematical core error. It is not the independent full-rate FIR `RLS_out` oracle.",
        "",
    ]
    report_path.write_text("\n".join(report_lines), encoding="ascii")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--updates", type=int, default=DEFAULT_UPDATES)
    parser.add_argument("--artifact-dir", type=Path)
    parser.add_argument("--report-dir", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    if args.updates <= 0:
        raise ValueError("--updates must be positive")
    reference_path = repo_root / "verification/vectors/convergence/uns_matlab.txt"
    desired_path = repo_root / "verification/vectors/convergence/dns_matlab.txt"
    artifact_dir = (
        args.artifact_dir.resolve()
        if args.artifact_dir is not None
        else repo_root / "build/oracle/float/artifacts"
    )
    report_dir = (
        args.report_dir.resolve()
        if args.report_dir is not None
        else repo_root / "build/oracle/float/reports"
    )
    reference = load_packed_complex(reference_path)
    desired = load_packed_complex(desired_path)
    run = run_float_rls(reference, desired, args.updates)
    metrics = calculate_metrics(run)
    write_outputs(
        repo_root,
        artifact_dir,
        report_dir,
        reference_path,
        desired_path,
        run,
        metrics,
    )
    print("PHASE1B_T1B02_FLOAT_REFERENCE_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
