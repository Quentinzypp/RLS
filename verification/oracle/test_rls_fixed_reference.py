#!/usr/bin/env python3
"""Deterministic primitive and end-to-end self-tests for the fixed RLS model."""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))

import rls_fixed_reference as fixed


@dataclass(frozen=True)
class Result:
    group: str
    check: str
    status: str
    detail: str


class SelfTests:
    def __init__(self) -> None:
        self.results: list[Result] = []

    def check(self, group: str, name: str, condition: bool, detail: str) -> None:
        self.results.append(Result(group, name, "PASS" if condition else "FAIL", detail))

    def guarded(self, group: str, operation: Callable[[], None]) -> None:
        try:
            operation()
        except Exception as error:  # noqa: BLE001 - a self-test must retain every exception
            self.check(group, "uncaught_exception", False, f"{type(error).__name__}: {error}")


def in_signed_range(value: int, width: int) -> bool:
    return -(1 << (width - 1)) <= value < (1 << (width - 1))


def make_case(kind: str) -> tuple[list[fixed.ComplexInt], list[fixed.ComplexInt]]:
    reference = [(0, 0) for _ in range(fixed.EXTERNAL_COUNTER_LENGTH)]
    desired = [(0, 0) for _ in range(fixed.EXTERNAL_COUNTER_LENGTH)]
    if kind == "zero":
        return reference, desired
    if kind == "impulse":
        reference[fixed.REFERENCE_START_INDEX] = (1 << fixed.INPUT_FRACTIONAL_BITS, 0)
        desired[fixed.DESIRED_START_INDEX] = (1 << (fixed.INPUT_FRACTIONAL_BITS - 1), 0)
        return reference, desired
    if kind == "real_only":
        return (
            [(1 << (fixed.INPUT_FRACTIONAL_BITS - 1), 0)] * fixed.EXTERNAL_COUNTER_LENGTH,
            [(1 << (fixed.INPUT_FRACTIONAL_BITS - 2), 0)] * fixed.EXTERNAL_COUNTER_LENGTH,
        )
    if kind == "imaginary_only":
        return (
            [(0, 1 << (fixed.INPUT_FRACTIONAL_BITS - 1))] * fixed.EXTERNAL_COUNTER_LENGTH,
            [(0, 1 << (fixed.INPUT_FRACTIONAL_BITS - 2))] * fixed.EXTERNAL_COUNTER_LENGTH,
        )
    if kind == "maximum_positive":
        maximum = (1 << (fixed.INPUT_WIDTH - 1)) - 1
        return (
            [(maximum, maximum)] * fixed.EXTERNAL_COUNTER_LENGTH,
            [(maximum, maximum)] * fixed.EXTERNAL_COUNTER_LENGTH,
        )
    if kind == "maximum_negative":
        minimum = -(1 << (fixed.INPUT_WIDTH - 1))
        return (
            [(minimum, minimum)] * fixed.EXTERNAL_COUNTER_LENGTH,
            [(minimum, minimum)] * fixed.EXTERNAL_COUNTER_LENGTH,
        )
    raise ValueError(f"Unknown self-test case: {kind}")


def check_primitives(tests: SelfTests) -> None:
    stats = fixed.ArithmeticStats()
    tests.check(
        "primitive",
        "signed_wrap_positive_overflow",
        fixed.wrap_signed(1 << 23, 24, stats, "primitive.wrap") == -(1 << 23),
        "24-bit +2^23 wraps to -2^23",
    )
    tests.check(
        "primitive",
        "signed_slice_negative",
        fixed.slice_signed(-3, 8, 7, 2, stats, "primitive.slice") == -1,
        "8-bit -3 sliced [7:2] is signed -1",
    )
    tests.check(
        "primitive",
        "complex_multiply",
        fixed.complex_multiply((3, -4), (5, 2), 16, stats, "primitive.cmul") == (23, -14),
        "(3-j4)*(5+j2)=23-j14",
    )
    terms = [(index, -index) for index in range(12)]
    tests.check(
        "primitive",
        "rtl_tree_sum_12",
        fixed.rtl_tree_sum_12(terms, 16, stats, "primitive.tree") == (66, -66),
        "balanced twelve-term tree preserves the known sum",
    )
    tests.check(
        "primitive",
        "divider_exact",
        fixed.divider_rounded_q32(1, 1, stats, "primitive.div.exact") == 1 << 32,
        "1/1 emits Q32 unity",
    )
    tests.check(
        "primitive",
        "divider_positive_tie",
        fixed.divider_rounded_q32(1, 1 << 33, stats, "primitive.div.tie_pos") == 0,
        "positive exact half tie chooses floor",
    )
    tests.check(
        "primitive",
        "divider_negative_tie",
        fixed.divider_rounded_q32(-1, 1 << 33, stats, "primitive.div.tie_neg") == -1,
        "negative exact half tie chooses negative infinity",
    )
    tests.check(
        "primitive",
        "fir_extract_positive",
        fixed.fir_extract_q13(1234 << 27, stats, "primitive.fir.pos") == 1234,
        "64Q40 FIR sign-plus-[49:27] slice preserves +1234",
    )
    tests.check(
        "primitive",
        "fir_extract_negative",
        fixed.fir_extract_q13(-1234 << 27, stats, "primitive.fir.neg") == -1234,
        "64Q40 FIR sign-plus-[49:27] slice preserves -1234",
    )
    tests.check(
        "primitive",
        "diagnostic_counters_exercised",
        stats.counts["wrap_events"] == 1 and stats.counts["nonzero_truncation_events"] >= 1,
        f"counts={dict(stats.counts)}",
    )


def check_case(tests: SelfTests, kind: str) -> None:
    reference, desired = make_case(kind)
    first = fixed.run_fixed_rls(reference, desired, 1)
    second = fixed.run_fixed_rls(reference, desired, 1)
    external_first = fixed.run_external_fir(reference, desired, first)
    external_second = fixed.run_external_fir(reference, desired, second)
    event = first.events[0]
    group = f"case.{kind}"

    tests.check(group, "fixed_determinism", first == second, "two complete matrix-core runs are equal")
    tests.check(
        group,
        "external_determinism",
        external_first == external_second,
        "two complete external-FIR runs are equal",
    )
    tests.check(
        group,
        "no_divide_by_zero",
        first.arithmetic_counts.get("division_by_zero_events", 0) == 0,
        f"counts={first.arithmetic_counts}",
    )
    width_checks = [
        all(in_signed_range(value, 36) for value in event.residual_q25),
        all(in_signed_range(value, 34) for value in event.denominator_q25),
        all(in_signed_range(value, 24) for value in event.reciprocal_q20),
        all(in_signed_range(value, 24) for gain in event.gain_q20 for value in gain),
        all(in_signed_range(value, 36) for weight in event.weights_q27 for value in weight),
        all(
            in_signed_range(value, 36)
            for row in event.p_q29
            for entry in row
            for value in entry
        ),
    ]
    tests.check(group, "stored_width_ranges", all(width_checks), f"checks={width_checks}")
    tests.check(
        group,
        "external_row_contract",
        len(external_first.outputs) == 547
        and all(
            row.residual_q13 == (0, 0)
            for row in external_first.outputs[: fixed.EXTERNAL_STARTUP_VALID_BUBBLES]
        )
        and external_first.outputs[371].coefficient_event is None
        and external_first.outputs[372].coefficient_event == 0,
        "3 bubbles + 544 meaningful rows; event 0 starts at meaningful sample 369",
    )
    external_ranges = all(
        all(in_signed_range(value, 24) for value in row.prediction_q13 + row.residual_q13)
        for row in external_first.outputs
    )
    tests.check(group, "external_width_ranges", external_ranges, "all predictions/residuals are signed 24-bit")

    if kind == "zero":
        tests.check(
            group,
            "zero_core_outputs",
            event.prediction_q25 == (0, 0)
            and event.residual_q25 == (0, 0)
            and all(value == (0, 0) for value in event.gain_q20)
            and all(value == (0, 0) for value in event.weights_q27),
            "zero input leaves prediction, error, gain and weights at zero",
        )
        tests.check(
            group,
            "zero_external_outputs",
            all(row.residual_q13 == (0, 0) for row in external_first.outputs),
            "all external residuals including bubbles are zero",
        )
    elif kind == "impulse":
        tests.check(
            group,
            "impulse_tap_orientation",
            event.taps_q13[0] == reference[fixed.REFERENCE_START_INDEX]
            and all(value == (0, 0) for value in event.taps_q13[1:]),
            f"taps={event.taps_q13}",
        )
        tests.check(
            group,
            "impulse_first_update",
            event.prediction_q25 == (0, 0)
            and event.residual_q25 == (desired[fixed.DESIRED_START_INDEX][0] << 12, 0)
            and event.weights_q27[0] != (0, 0)
            and all(value == (0, 0) for value in event.weights_q27[1:]),
            "first impulse updates only newest weight",
        )
    elif kind == "real_only":
        all_imag_zero = (
            event.denominator_q25[1] == 0
            and event.reciprocal_q20[1] == 0
            and event.residual_q25[1] == 0
            and all(value[1] == 0 for value in event.gain_q20)
            and all(value[1] == 0 for value in event.weights_q27)
            and all(entry[1] == 0 for row in event.p_q29 for entry in row)
            and all(
                row.prediction_q13[1] == 0 and row.residual_q13[1] == 0
                for row in external_first.outputs
            )
        )
        tests.check(group, "real_axis_invariance", all_imag_zero, "all imaginary states and outputs remain zero")
    elif kind == "imaginary_only":
        real_outputs_zero = (
            event.denominator_q25[1] == 0
            and event.reciprocal_q20[1] == 0
            and event.residual_q25[0] == 0
            and all(
                row.prediction_q13[0] == 0 and row.residual_q13[0] == 0
                for row in external_first.outputs
            )
        )
        tests.check(group, "imaginary_axis_invariance", real_outputs_zero, "real residual/prediction lanes remain zero")
    else:
        tests.check(
            group,
            "boundary_arithmetic_exercised",
            first.arithmetic_counts.get("nonzero_truncation_events", 0) > 0,
            f"counts={first.arithmetic_counts}",
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tests = SelfTests()
    tests.guarded("primitive", lambda: check_primitives(tests))
    for kind in (
        "zero",
        "impulse",
        "real_only",
        "imaginary_only",
        "maximum_positive",
        "maximum_negative",
    ):
        tests.guarded(f"case.{kind}", lambda current=kind: check_case(tests, current))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(("group", "check", "status", "detail"))
        writer.writerows((row.group, row.check, row.status, row.detail) for row in tests.results)

    failures = [row for row in tests.results if row.status != "PASS"]
    for row in tests.results:
        print(f"{row.status} {row.group}.{row.check}: {row.detail}")
    print(f"SELF_TEST_TOTAL={len(tests.results)} SELF_TEST_FAILURES={len(failures)}")
    if failures:
        print("PHASE1B_T1B04_FIXED_SELF_TEST_FAIL")
        return 1
    print("PHASE1B_T1B04_FIXED_SELF_TEST_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
