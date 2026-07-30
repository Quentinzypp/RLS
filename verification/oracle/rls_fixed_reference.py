#!/usr/bin/env python3
"""Bit-accurate event model for the frozen 12-tap complex RLS matrix core."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from rls_event_schedule import (
    DESIRED_START_INDEX,
    EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE,
    EXTERNAL_REFILL_DELAY_CLOCKS,
    EXTERNAL_UPDATE_INTERVAL,
    REFERENCE_START_INDEX,
    REFILL_DESIRED_START_INDEX,
    REFILL_EVENT,
    REFILL_REFERENCE_START_INDEX,
    coefficient_event_for_sample,
    event_input_schedule,
    external_meaningful_samples,
    required_source_lengths,
)


ORDER = 12
INPUT_WIDTH = 24
INPUT_FRACTIONAL_BITS = 13
P_WIDTH = 36
P_FRACTIONAL_BITS = 29
WEIGHT_WIDTH = 36
WEIGHT_FRACTIONAL_BITS = 27
ERROR_WIDTH = 36
ERROR_FRACTIONAL_BITS = 25
GAIN_WIDTH = 24
GAIN_FRACTIONAL_BITS = 20
DEFAULT_UPDATES = 1000
LAMBDA_RAW = 33_551_077
RECIPROCAL_Q16_RAW = 65_543
RECIPROCAL_Q22_RAW = 4_194_752
P0_RAW = 4_294_967_296
DIVIDER_FRACTIONAL_BITS = 32
EXTERNAL_COUNTER_LENGTH = 16_384
EXTERNAL_REFERENCE_LEAD = 2
EXTERNAL_STARTUP_VALID_BUBBLES = 3
EXTERNAL_FIRST_TOP_VALID_EDGE = 38
INPUT_REFERENCE_SHA256 = "E2BF0414C1152A72C43CC7D43DAA535DB26ABA0C981E10993C37F2E83F5782E2"
INPUT_DESIRED_SHA256 = "3B6EA83037A0142250D4E0D18441046D45F8CE7F50A6056C41FD0B518C7D4856"

ComplexInt = tuple[int, int]


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


def load_packed_complex_int(path: Path) -> list[ComplexInt]:
    values: list[ComplexInt] = []
    with path.open("r", encoding="ascii") as stream:
        for line_number, raw_line in enumerate(stream, start=1):
            bits = raw_line.strip()
            if not bits:
                continue
            if len(bits) != 48 or any(bit not in "01" for bit in bits):
                raise ValueError(f"{path}:{line_number}: expected exactly 48 binary digits")
            values.append((signed_from_bits(bits[:24]), signed_from_bits(bits[24:])))
    if not values:
        raise ValueError(f"No packed samples found in {path}")
    return values


def hex_signed(value: int, width: int) -> str:
    digits = (width + 3) // 4
    return f"{value & ((1 << width) - 1):0{digits}x}"


def packed_hex(value: ComplexInt, lane_width: int, upper: str = "real") -> str:
    real, imag = value
    if upper == "real":
        bits = ((real & ((1 << lane_width) - 1)) << lane_width) | (
            imag & ((1 << lane_width) - 1)
        )
    elif upper == "imag":
        bits = ((imag & ((1 << lane_width) - 1)) << lane_width) | (
            real & ((1 << lane_width) - 1)
        )
    else:
        raise ValueError(f"Unsupported upper lane: {upper}")
    return f"{bits:0{(2 * lane_width + 3) // 4}x}"


class ArithmeticStats:
    def __init__(self) -> None:
        self.counts: Counter[str] = Counter()
        self.stage_counts: Counter[str] = Counter()

    def note(self, category: str, stage: str) -> None:
        self.counts[category] += 1
        self.stage_counts[f"{category}:{stage}"] += 1

    def snapshot(self) -> dict[str, int]:
        return dict(self.counts)


def wrap_signed(value: int, width: int, stats: ArithmeticStats, stage: str) -> int:
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    if value < minimum or value > maximum:
        stats.note("wrap_events", stage)
    value &= (1 << width) - 1
    return value - (1 << width) if value & (1 << (width - 1)) else value


def slice_signed(
    value: int,
    input_width: int,
    high: int,
    low: int,
    stats: ArithmeticStats,
    stage: str,
) -> int:
    if not (0 <= low <= high < input_width):
        raise ValueError(
            f"Invalid slice [{high}:{low}] for input width {input_width} at {stage}"
        )
    input_value = value & ((1 << input_width) - 1)
    if low and input_value & ((1 << low) - 1):
        stats.note("nonzero_truncation_events", stage)
    signed_input = (
        input_value - (1 << input_width)
        if input_value & (1 << (input_width - 1))
        else input_value
    )
    output_width = high - low + 1
    shifted = signed_input >> low
    minimum = -(1 << (output_width - 1))
    maximum = (1 << (output_width - 1)) - 1
    if shifted < minimum or shifted > maximum:
        stats.note("slice_overflow_events", stage)
    field = (input_value >> low) & ((1 << output_width) - 1)
    return field - (1 << output_width) if field & (1 << (output_width - 1)) else field


def complex_wrap(
    value: ComplexInt, width: int, stats: ArithmeticStats, stage: str
) -> ComplexInt:
    return (
        wrap_signed(value[0], width, stats, f"{stage}.real"),
        wrap_signed(value[1], width, stats, f"{stage}.imag"),
    )


def complex_add(
    left: ComplexInt,
    right: ComplexInt,
    width: int,
    stats: ArithmeticStats,
    stage: str,
) -> ComplexInt:
    return complex_wrap((left[0] + right[0], left[1] + right[1]), width, stats, stage)


def complex_sub(
    left: ComplexInt,
    right: ComplexInt,
    width: int,
    stats: ArithmeticStats,
    stage: str,
) -> ComplexInt:
    return complex_wrap((left[0] - right[0], left[1] - right[1]), width, stats, stage)


def complex_conj(
    value: ComplexInt, width: int, stats: ArithmeticStats, stage: str
) -> ComplexInt:
    return value[0], wrap_signed(-value[1], width, stats, f"{stage}.imag_negate")


def complex_multiply(
    left: ComplexInt,
    right: ComplexInt,
    output_width: int,
    stats: ArithmeticStats,
    stage: str,
) -> ComplexInt:
    real = left[0] * right[0] - left[1] * right[1]
    imag = left[0] * right[1] + left[1] * right[0]
    return complex_wrap((real, imag), output_width, stats, f"{stage}.full_precision")


def complex_slice(
    value: ComplexInt,
    input_width: int,
    high: int,
    low: int,
    stats: ArithmeticStats,
    stage: str,
) -> ComplexInt:
    return (
        slice_signed(value[0], input_width, high, low, stats, f"{stage}.real"),
        slice_signed(value[1], input_width, high, low, stats, f"{stage}.imag"),
    )


def sequential_sum(
    terms: Sequence[ComplexInt],
    width: int,
    stats: ArithmeticStats,
    stage: str,
) -> ComplexInt:
    accumulator = (0, 0)
    for index, term in enumerate(terms):
        accumulator = complex_add(
            accumulator, term, width, stats, f"{stage}.accumulate_{index}"
        )
    return accumulator


def rtl_tree_sum_12(
    terms: Sequence[ComplexInt],
    width: int,
    stats: ArithmeticStats,
    stage: str,
) -> ComplexInt:
    if len(terms) != 12:
        raise ValueError(f"{stage}: expected twelve terms, found {len(terms)}")
    level1 = [
        complex_add(terms[index], terms[index + 1], width, stats, f"{stage}.l1_{index // 2}")
        for index in range(0, 12, 2)
    ]
    level2 = [
        complex_add(level1[0], level1[1], width, stats, f"{stage}.l2_0"),
        complex_add(level1[2], level1[3], width, stats, f"{stage}.l2_1"),
        complex_add(level1[4], level1[5], width, stats, f"{stage}.l2_2"),
    ]
    level3 = complex_add(level2[0], level2[1], width, stats, f"{stage}.l3_0")
    return complex_add(level3, level2[2], width, stats, f"{stage}.l4_0")


def divider_rounded_q32(
    dividend: int, divisor: int, stats: ArithmeticStats, stage: str
) -> int:
    if divisor == 0:
        stats.note("division_by_zero_events", stage)
        raise ZeroDivisionError(f"Zero fixed-point divider denominator at {stage}")
    numerator = dividend << DIVIDER_FRACTIONAL_BITS
    floor_value = numerator // divisor
    remainder = numerator - floor_value * divisor
    if 2 * abs(remainder) > abs(divisor):
        quotient = floor_value + 1
    else:
        quotient = floor_value
    return wrap_signed(quotient, 72, stats, f"{stage}.quotient72")


def complex_reciprocal_q20(
    denominator: ComplexInt, stats: ArithmeticStats, stage: str
) -> ComplexInt:
    numerator_real_25 = slice_signed(
        1 << 25, 34, 33, 9, stats, f"{stage}.numerator_real_25q16"
    )
    numerator_imag_25 = 0
    denominator_real_25 = slice_signed(
        denominator[0], 34, 33, 9, stats, f"{stage}.denominator_real_25q16"
    )
    denominator_imag_25 = slice_signed(
        denominator[1], 34, 33, 9, stats, f"{stage}.denominator_imag_25q16"
    )

    ac = wrap_signed(
        numerator_real_25 * denominator_real_25,
        50,
        stats,
        f"{stage}.ac_product",
    )
    bd = wrap_signed(
        numerator_imag_25 * denominator_imag_25,
        50,
        stats,
        f"{stage}.bd_product",
    )
    ad = wrap_signed(
        numerator_real_25 * denominator_imag_25,
        50,
        stats,
        f"{stage}.ad_product",
    )
    bc = wrap_signed(
        numerator_imag_25 * denominator_real_25,
        50,
        stats,
        f"{stage}.bc_product",
    )
    cc = wrap_signed(
        denominator_real_25 * denominator_real_25,
        50,
        stats,
        f"{stage}.cc_product",
    )
    dd = wrap_signed(
        denominator_imag_25 * denominator_imag_25,
        50,
        stats,
        f"{stage}.dd_product",
    )
    products = [
        slice_signed(value, 50, 48, 9, stats, f"{stage}.{name}_40q23")
        for name, value in (("ac", ac), ("bd", bd), ("ad", ad), ("bc", bc), ("cc", cc), ("dd", dd))
    ]
    ac40, bd40, ad40, bc40, cc40, dd40 = products
    real_numerator = wrap_signed(ac40 + bd40, 40, stats, f"{stage}.real_numerator")
    imag_numerator = wrap_signed(bc40 - ad40, 40, stats, f"{stage}.imag_numerator")
    magnitude = wrap_signed(cc40 + dd40, 40, stats, f"{stage}.magnitude")
    real_q32 = divider_rounded_q32(real_numerator, magnitude, stats, f"{stage}.real_divider")
    imag_q32 = divider_rounded_q32(imag_numerator, magnitude, stats, f"{stage}.imag_divider")
    real_q27 = slice_signed(real_q32, 72, 44, 5, stats, f"{stage}.real_q27")
    imag_q27 = slice_signed(imag_q32, 72, 44, 5, stats, f"{stage}.imag_q27")
    return (
        slice_signed(real_q27, 40, 30, 7, stats, f"{stage}.real_q20"),
        slice_signed(imag_q27, 40, 30, 7, stats, f"{stage}.imag_q20"),
    )


@dataclass(frozen=True)
class FixedEvent:
    event: int
    reference_index: int
    desired_index: int
    reference: ComplexInt
    desired_q13: ComplexInt
    taps_q13: tuple[ComplexInt, ...]
    prediction_q25: ComplexInt
    residual_q25: ComplexInt
    denominator_q25: ComplexInt
    reciprocal_q20: ComplexInt
    gain_q20: tuple[ComplexInt, ...]
    weights_q27: tuple[ComplexInt, ...]
    p_q29: tuple[tuple[ComplexInt, ...], ...]
    event_arithmetic_counts: dict[str, int]
    cumulative_arithmetic_counts: dict[str, int]


@dataclass(frozen=True)
class FixedRun:
    events: tuple[FixedEvent, ...]
    arithmetic_counts: dict[str, int]
    arithmetic_stage_counts: dict[str, int]


@dataclass(frozen=True)
class ExternalResidual:
    valid_ordinal: int
    top_edge: int
    meaningful_sample: int | None
    reference_stream_ordinal: int | None
    reference_source_index: int | None
    desired_source_index: int | None
    coefficient_event: int | None
    desired_q13: ComplexInt
    prediction_q13: ComplexInt
    residual_q13: ComplexInt


@dataclass(frozen=True)
class ExternalRun:
    outputs: tuple[ExternalResidual, ...]
    arithmetic_counts: dict[str, int]
    arithmetic_stage_counts: dict[str, int]


def run_fixed_rls(
    reference: Sequence[ComplexInt], desired: Sequence[ComplexInt], updates: int
) -> FixedRun:
    required_reference, required_desired = required_source_lengths(updates, ORDER)
    if len(reference) < required_reference or len(desired) < required_desired:
        raise ValueError(
            "Insufficient input samples for aligned fixed run: "
            f"reference needs {required_reference}, has {len(reference)}; "
            f"desired needs {required_desired}, has {len(desired)}"
        )

    stats = ArithmeticStats()
    p_matrix: list[list[ComplexInt]] = [
        [(P0_RAW, 0) if row == column else (0, 0) for column in range(ORDER)]
        for row in range(ORDER)
    ]
    weights: list[ComplexInt] = [(0, 0) for _ in range(ORDER)]
    events: list[FixedEvent] = []

    for event_index in range(updates):
        before_counts = stats.snapshot()
        schedule = event_input_schedule(event_index, ORDER)
        reference_index = schedule.reference_index
        desired_index = schedule.desired_index
        current_reference = reference[reference_index]
        current_desired = desired[desired_index]
        taps = [
            reference[index] if index is not None else (0, 0)
            for index in schedule.reference_window_indices
        ]

        a_vector: list[ComplexInt] = []
        for row in range(ORDER):
            terms = []
            for column in range(ORDER):
                product = complex_multiply(
                    p_matrix[row][column],
                    taps[column],
                    61,
                    stats,
                    f"event{event_index}.A.r{row}.c{column}",
                )
                terms.append(
                    complex_slice(
                        product,
                        61,
                        52,
                        13,
                        stats,
                        f"event{event_index}.A_slice.r{row}.c{column}",
                    )
                )
            a_vector.append(
                sequential_sum(terms, 40, stats, f"event{event_index}.A_sum.r{row}")
            )

        denominator_terms: list[ComplexInt] = []
        for index in range(ORDER):
            a_q25 = complex_slice(
                a_vector[index],
                40,
                39,
                4,
                stats,
                f"event{event_index}.C.a_q25.{index}",
            )
            tap_conjugate = complex_conj(
                taps[index], 24, stats, f"event{event_index}.C.tap_conj.{index}"
            )
            product = complex_multiply(
                a_q25,
                tap_conjugate,
                61,
                stats,
                f"event{event_index}.C.product.{index}",
            )
            denominator_terms.append(
                complex_slice(
                    product,
                    61,
                    48,
                    9,
                    stats,
                    f"event{event_index}.C.product_slice.{index}",
                )
            )
        denominator_sum = rtl_tree_sum_12(
            denominator_terms, 40, stats, f"event{event_index}.C.tree"
        )
        denominator = (
            wrap_signed(
                slice_signed(
                    denominator_sum[0],
                    40,
                    37,
                    4,
                    stats,
                    f"event{event_index}.C.real_slice",
                )
                + LAMBDA_RAW,
                34,
                stats,
                f"event{event_index}.C.real_lambda_add",
            ),
            slice_signed(
                denominator_sum[1],
                40,
                37,
                4,
                stats,
                f"event{event_index}.C.imag_slice",
            ),
        )
        reciprocal = complex_reciprocal_q20(
            denominator, stats, f"event{event_index}.reciprocal"
        )

        gain: list[ComplexInt] = []
        for index in range(ORDER):
            a_q28 = complex_slice(
                a_vector[index],
                40,
                36,
                1,
                stats,
                f"event{event_index}.K.a_q28.{index}",
            )
            product = complex_multiply(
                a_q28,
                reciprocal,
                61,
                stats,
                f"event{event_index}.K.product.{index}",
            )
            gain.append(
                complex_slice(
                    product,
                    61,
                    51,
                    28,
                    stats,
                    f"event{event_index}.K.slice.{index}",
                )
            )

        prediction_terms: list[ComplexInt] = []
        for index in range(ORDER):
            conjugate_weight = complex_conj(
                weights[index],
                36,
                stats,
                f"event{event_index}.Y.weight_conj.{index}",
            )
            product = complex_multiply(
                conjugate_weight,
                taps[index],
                61,
                stats,
                f"event{event_index}.Y.product.{index}",
            )
            prediction_terms.append(
                complex_slice(
                    product,
                    61,
                    51,
                    12,
                    stats,
                    f"event{event_index}.Y.product_slice.{index}",
                )
            )
        prediction_q28 = rtl_tree_sum_12(
            prediction_terms, 40, stats, f"event{event_index}.Y.tree"
        )
        prediction_q25 = complex_slice(
            prediction_q28,
            40,
            38,
            3,
            stats,
            f"event{event_index}.Y.q25",
        )
        desired_q25 = (
            wrap_signed(current_desired[0] << 12, 36, stats, f"event{event_index}.desired.real"),
            wrap_signed(current_desired[1] << 12, 36, stats, f"event{event_index}.desired.imag"),
        )
        residual = complex_sub(
            desired_q25,
            prediction_q25,
            36,
            stats,
            f"event{event_index}.error",
        )

        residual_conjugate = complex_conj(
            residual, 36, stats, f"event{event_index}.weight.error_conj"
        )
        new_weights: list[ComplexInt] = []
        for index in range(ORDER):
            correction_product = complex_multiply(
                residual_conjugate,
                gain[index],
                61,
                stats,
                f"event{event_index}.weight.product.{index}",
            )
            correction = complex_slice(
                correction_product,
                61,
                53,
                18,
                stats,
                f"event{event_index}.weight.correction.{index}",
            )
            new_weights.append(
                complex_add(
                    weights[index],
                    correction,
                    36,
                    stats,
                    f"event{event_index}.weight.update.{index}",
                )
            )

        scaled_conjugate_taps: list[ComplexInt] = []
        for index, tap in enumerate(taps):
            tap_conjugate = complex_conj(
                tap, 24, stats, f"event{event_index}.B.tap_conj.{index}"
            )
            product = complex_multiply(
                tap_conjugate,
                (RECIPROCAL_Q16_RAW, 0),
                43,
                stats,
                f"event{event_index}.B.lambda_product.{index}",
            )
            scaled_conjugate_taps.append(
                complex_slice(
                    product,
                    43,
                    39,
                    16,
                    stats,
                    f"event{event_index}.B.lambda_slice.{index}",
                )
            )

        b_vector: list[ComplexInt] = []
        for column in range(ORDER):
            terms = []
            for row in range(ORDER):
                product = complex_multiply(
                    p_matrix[row][column],
                    scaled_conjugate_taps[row],
                    61,
                    stats,
                    f"event{event_index}.B.r{row}.c{column}",
                )
                terms.append(
                    complex_slice(
                        product,
                        61,
                        51,
                        12,
                        stats,
                        f"event{event_index}.B_slice.r{row}.c{column}",
                    )
                )
            b_vector.append(
                sequential_sum(terms, 40, stats, f"event{event_index}.B_sum.c{column}")
            )

        new_p: list[list[ComplexInt]] = []
        for row in range(ORDER):
            new_row: list[ComplexInt] = []
            for column in range(ORDER):
                pprime_product = complex_multiply(
                    p_matrix[row][column],
                    (RECIPROCAL_Q22_RAW, 0),
                    61,
                    stats,
                    f"event{event_index}.Pprime.r{row}.c{column}",
                )
                pprime = complex_slice(
                    pprime_product,
                    61,
                    57,
                    22,
                    stats,
                    f"event{event_index}.Pprime_slice.r{row}.c{column}",
                )
                b_q28 = complex_slice(
                    b_vector[column],
                    40,
                    37,
                    2,
                    stats,
                    f"event{event_index}.KB.b_q28.c{column}",
                )
                kb_product = complex_multiply(
                    b_q28,
                    gain[row],
                    61,
                    stats,
                    f"event{event_index}.KB.r{row}.c{column}",
                )
                kb = complex_slice(
                    kb_product,
                    61,
                    54,
                    19,
                    stats,
                    f"event{event_index}.KB_slice.r{row}.c{column}",
                )
                new_row.append(
                    complex_sub(
                        pprime,
                        kb,
                        36,
                        stats,
                        f"event{event_index}.P_update.r{row}.c{column}",
                    )
                )
            new_p.append(new_row)

        weights = new_weights
        p_matrix = new_p
        after_counts = stats.snapshot()
        event_counts = {
            key: after_counts.get(key, 0) - before_counts.get(key, 0)
            for key in sorted(set(before_counts) | set(after_counts))
        }
        events.append(
            FixedEvent(
                event=event_index,
                reference_index=reference_index,
                desired_index=desired_index,
                reference=current_reference,
                desired_q13=current_desired,
                taps_q13=tuple(taps),
                prediction_q25=prediction_q25,
                residual_q25=residual,
                denominator_q25=denominator,
                reciprocal_q20=reciprocal,
                gain_q20=tuple(gain),
                weights_q27=tuple(weights),
                p_q29=tuple(tuple(row) for row in p_matrix),
                event_arithmetic_counts=event_counts,
                cumulative_arithmetic_counts=after_counts,
            )
        )

    return FixedRun(
        events=tuple(events),
        arithmetic_counts=dict(stats.counts),
        arithmetic_stage_counts=dict(stats.stage_counts),
    )


def fir_extract_q13(
    value: int, stats: ArithmeticStats, stage: str
) -> int:
    value = wrap_signed(value, 64, stats, f"{stage}.raw64")
    unsigned = value & ((1 << 64) - 1)
    if unsigned & ((1 << 27) - 1):
        stats.note("nonzero_truncation_events", stage)
    sign = (unsigned >> 63) & 1
    omitted = (unsigned >> 50) & ((1 << 13) - 1)
    expected = (1 << 13) - 1 if sign else 0
    if omitted != expected:
        stats.note("fir_slice_overflow_events", stage)
    output = (sign << 23) | ((unsigned >> 27) & ((1 << 23) - 1))
    return output - (1 << 24) if output & (1 << 23) else output


def run_external_fir(
    reference: Sequence[ComplexInt],
    desired: Sequence[ComplexInt],
    fixed_run: FixedRun,
) -> ExternalRun:
    if len(reference) < EXTERNAL_COUNTER_LENGTH or len(desired) < EXTERNAL_COUNTER_LENGTH:
        raise ValueError(
            "External FIR model requires at least the 16,384 samples addressed by test_rls"
        )
    if not fixed_run.events:
        raise ValueError("External FIR model requires at least one fixed RLS update")

    stats = ArithmeticStats()
    outputs: list[ExternalResidual] = []
    for bubble in range(EXTERNAL_STARTUP_VALID_BUBBLES):
        outputs.append(
            ExternalResidual(
                valid_ordinal=bubble,
                top_edge=EXTERNAL_FIRST_TOP_VALID_EDGE + bubble,
                meaningful_sample=None,
                reference_stream_ordinal=None,
                reference_source_index=None,
                desired_source_index=None,
                coefficient_event=None,
                desired_q13=(0, 0),
                prediction_q13=(0, 0),
                residual_q13=(0, 0),
            )
        )

    meaningful_samples = external_meaningful_samples(len(fixed_run.events))
    zero_weights = tuple((0, 0) for _ in range(ORDER))
    for sample in range(meaningful_samples):
        reference_ordinal = sample + EXTERNAL_REFERENCE_LEAD
        reference_index = reference_ordinal % EXTERNAL_COUNTER_LENGTH
        desired_index = sample % EXTERNAL_COUNTER_LENGTH
        coefficient_event = coefficient_event_for_sample(
            sample, len(fixed_run.events)
        )
        weights = (
            zero_weights
            if coefficient_event is None
            else fixed_run.events[coefficient_event].weights_q27
        )

        taps = []
        for tap in range(ORDER):
            tap_ordinal = reference_ordinal - tap
            taps.append(
                reference[tap_ordinal % EXTERNAL_COUNTER_LENGTH]
                if tap_ordinal >= 0
                else (0, 0)
            )

        imag_times_wr = 0
        real_times_wr = 0
        imag_times_wi = 0
        real_times_wi = 0
        for tap, (data, weight) in enumerate(zip(taps, weights)):
            real, imag = data
            weight_real, weight_imag = weight
            imag_times_wr += imag * weight_real
            real_times_wr += real * weight_real
            imag_times_wi += imag * weight_imag
            real_times_wi += real * weight_imag

        path_imag_wr = fir_extract_q13(
            imag_times_wr, stats, "external.fir.imag_wr"
        )
        path_real_wr = fir_extract_q13(
            real_times_wr, stats, "external.fir.real_wr"
        )
        path_imag_wi = fir_extract_q13(
            imag_times_wi, stats, "external.fir.imag_wi"
        )
        path_real_wi = fir_extract_q13(
            real_times_wi, stats, "external.fir.real_wi"
        )
        prediction = (
            wrap_signed(
                path_real_wr - path_imag_wi,
                24,
                stats,
                "external.fir.prediction_real",
            ),
            wrap_signed(
                path_imag_wr + path_real_wi,
                24,
                stats,
                "external.fir.prediction_imag",
            ),
        )
        current_desired = desired[desired_index]
        residual = complex_sub(
            current_desired,
            prediction,
            24,
            stats,
            "external.residual",
        )
        outputs.append(
            ExternalResidual(
                valid_ordinal=EXTERNAL_STARTUP_VALID_BUBBLES + sample,
                top_edge=(
                    EXTERNAL_FIRST_TOP_VALID_EDGE
                    + EXTERNAL_STARTUP_VALID_BUBBLES
                    + sample
                ),
                meaningful_sample=sample,
                reference_stream_ordinal=reference_ordinal,
                reference_source_index=reference_index,
                desired_source_index=desired_index,
                coefficient_event=coefficient_event,
                desired_q13=current_desired,
                prediction_q13=prediction,
                residual_q13=residual,
            )
        )

    return ExternalRun(
        outputs=tuple(outputs),
        arithmetic_counts=dict(stats.counts),
        arithmetic_stage_counts=dict(stats.stage_counts),
    )


def convergence_event(residual_power: Sequence[float], steady_power: float) -> int | None:
    window = min(50, len(residual_power))
    if window == 0:
        return None
    moving = [
        sum(residual_power[index : index + window]) / window
        for index in range(len(residual_power) - window + 1)
    ]
    threshold = steady_power * 1.10
    for index in range(max(0, len(moving) - 2)):
        if all(value <= threshold for value in moving[index : index + 3]):
            return index + window - 1
    return None


def calculate_metrics(run: FixedRun) -> dict[str, object]:
    error_scale = float(1 << ERROR_FRACTIONAL_BITS)
    input_scale = float(1 << INPUT_FRACTIONAL_BITS)
    residuals = [
        complex(event.residual_q25[0] / error_scale, event.residual_q25[1] / error_scale)
        for event in run.events
    ]
    desired = [
        complex(event.desired_q13[0] / input_scale, event.desired_q13[1] / input_scale)
        for event in run.events
    ]
    predictions = [
        complex(event.prediction_q25[0] / error_scale, event.prediction_q25[1] / error_scale)
        for event in run.events
    ]
    residual_power_samples = [abs(value) ** 2 for value in residuals]
    desired_power_samples = [abs(value) ** 2 for value in desired]
    steady_window = min(100, len(residuals))
    residual_power = sum(residual_power_samples) / len(residual_power_samples)
    desired_power = sum(desired_power_samples) / len(desired_power_samples)
    steady_power = sum(residual_power_samples[-steady_window:]) / steady_window
    cancellation_db = (
        10.0 * math.log10(desired_power / residual_power)
        if residual_power > 0.0 and desired_power > 0.0
        else None
    )
    max_hermitian_raw = 0.0
    for event in run.events:
        for row in range(ORDER):
            for column in range(ORDER):
                left = event.p_q29[row][column]
                right = event.p_q29[column][row]
                drift = math.hypot(left[0] - right[0], left[1] + right[1])
                max_hermitian_raw = max(max_hermitian_raw, drift)
    return {
        "updates": len(run.events),
        "mse": residual_power,
        "desired_power": desired_power,
        "residual_power": residual_power,
        "residual_real_power": sum(value.real**2 for value in residuals) / len(residuals),
        "residual_imag_power": sum(value.imag**2 for value in residuals) / len(residuals),
        "cancellation_db": cancellation_db,
        "steady_state_window": steady_window,
        "steady_state_residual_power": steady_power,
        "steady_state_mean_abs_error": sum(abs(value) for value in residuals[-steady_window:]) / steady_window,
        "maximum_transient_abs_error": max(abs(value) for value in residuals),
        "output_peak_abs": max(abs(value) for value in predictions),
        "convergence_rule": (
            "first 50-update moving residual-power window at or below 110% of "
            "the final 100-update residual power for three consecutive windows"
        ),
        "convergence_event_zero_based": convergence_event(residual_power_samples, steady_power),
        "minimum_denominator_magnitude": min(
            abs(complex(event.denominator_q25[0], event.denominator_q25[1]))
            / (1 << ERROR_FRACTIONAL_BITS)
            for event in run.events
        ),
        "maximum_denominator_imag_abs": max(
            abs(event.denominator_q25[1]) / (1 << ERROR_FRACTIONAL_BITS)
            for event in run.events
        ),
        "final_weight_norm": math.sqrt(
            sum(
                (weight[0] / (1 << WEIGHT_FRACTIONAL_BITS)) ** 2
                + (weight[1] / (1 << WEIGHT_FRACTIONAL_BITS)) ** 2
                for weight in run.events[-1].weights_q27
            )
        ),
        "maximum_p_hermitian_drift": max_hermitian_raw / (1 << P_FRACTIONAL_BITS),
        "arithmetic_counts": run.arithmetic_counts,
        "top_arithmetic_stage_counts": dict(
            sorted(
                run.arithmetic_stage_counts.items(),
                key=lambda item: (-item[1], item[0]),
            )[:50]
        ),
    }


def calculate_external_metrics(run: ExternalRun) -> dict[str, object]:
    meaningful = [row for row in run.outputs if row.meaningful_sample is not None]
    scale = float(1 << INPUT_FRACTIONAL_BITS)
    residuals = [
        complex(row.residual_q13[0] / scale, row.residual_q13[1] / scale)
        for row in meaningful
    ]
    desired = [
        complex(row.desired_q13[0] / scale, row.desired_q13[1] / scale)
        for row in meaningful
    ]
    predictions = [
        complex(row.prediction_q13[0] / scale, row.prediction_q13[1] / scale)
        for row in meaningful
    ]
    residual_power = [abs(value) ** 2 for value in residuals]
    desired_power = [abs(value) ** 2 for value in desired]
    steady_window = min(EXTERNAL_COUNTER_LENGTH, len(residuals))
    mean_residual_power = sum(residual_power) / len(residual_power)
    mean_desired_power = sum(desired_power) / len(desired_power)
    return {
        "valid_outputs": len(run.outputs),
        "startup_valid_bubbles": EXTERNAL_STARTUP_VALID_BUBBLES,
        "meaningful_outputs": len(meaningful),
        "mse": mean_residual_power,
        "desired_power": mean_desired_power,
        "residual_power": mean_residual_power,
        "residual_real_power": sum(value.real**2 for value in residuals) / len(residuals),
        "residual_imag_power": sum(value.imag**2 for value in residuals) / len(residuals),
        "cancellation_db": (
            10.0 * math.log10(mean_desired_power / mean_residual_power)
            if mean_desired_power > 0.0 and mean_residual_power > 0.0
            else None
        ),
        "steady_state_window": steady_window,
        "steady_state_residual_power": (
            sum(residual_power[-steady_window:]) / steady_window
        ),
        "maximum_transient_abs_error": max(abs(value) for value in residuals),
        "output_peak_abs": max(abs(value) for value in predictions),
        "arithmetic_counts": run.arithmetic_counts,
        "top_arithmetic_stage_counts": dict(
            sorted(
                run.arithmetic_stage_counts.items(),
                key=lambda item: (-item[1], item[0]),
            )[:50]
        ),
    }


def write_csv(path: Path, header: Iterable[str], rows: Iterable[Iterable[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def write_outputs(
    repo_root: Path,
    artifact_root: Path,
    report_root: Path,
    reference_path: Path,
    desired_path: Path,
    run: FixedRun,
    metrics: dict[str, object],
    external_run: ExternalRun,
    external_metrics: dict[str, object],
) -> None:
    artifact_root.mkdir(parents=True, exist_ok=True)
    report_root.mkdir(parents=True, exist_ok=True)
    oracle_path = artifact_root / "rls_fixed_oracle.csv"
    weights_path = artifact_root / "rls_fixed_weights.csv"
    gains_path = artifact_root / "rls_fixed_gains.csv"
    p_path = artifact_root / "rls_fixed_p.csv"
    external_path = artifact_root / "rls_fixed_external_residual.csv"
    metrics_path = report_root / "rls_fixed_metrics.json"
    external_metrics_path = report_root / "rls_fixed_external_metrics.json"
    manifest_path = artifact_root / "rls_fixed_manifest.json"
    report_path = report_root.parent / "phase1b_fixed_reference.md"

    oracle_rows = []
    weight_rows = []
    gain_rows = []
    p_rows = []
    for event in run.events:
        oracle_rows.append(
            (
                event.event,
                event.reference_index,
                event.desired_index,
                event.reference[0],
                event.reference[1],
                event.prediction_q25[0],
                event.prediction_q25[1],
                event.residual_q25[0],
                event.residual_q25[1],
                packed_hex(event.residual_q25, 36, upper="imag"),
                event.denominator_q25[0],
                event.denominator_q25[1],
                packed_hex(event.denominator_q25, 34, upper="imag"),
                event.reciprocal_q20[0],
                event.reciprocal_q20[1],
                packed_hex(event.reciprocal_q20, 24, upper="imag"),
                event.event_arithmetic_counts.get("wrap_events", 0),
                event.event_arithmetic_counts.get("slice_overflow_events", 0),
                event.event_arithmetic_counts.get("nonzero_truncation_events", 0),
                event.cumulative_arithmetic_counts.get("wrap_events", 0),
                event.cumulative_arithmetic_counts.get("slice_overflow_events", 0),
                event.cumulative_arithmetic_counts.get("nonzero_truncation_events", 0),
            )
        )
        for tap, weight in enumerate(event.weights_q27):
            weight_rows.append(
                (
                    event.event,
                    tap,
                    11 - tap,
                    weight[0],
                    weight[1],
                    packed_hex(weight, 36, upper="real"),
                    format(weight[0] / (1 << WEIGHT_FRACTIONAL_BITS), ".17g"),
                    format(weight[1] / (1 << WEIGHT_FRACTIONAL_BITS), ".17g"),
                )
            )
        for tap, gain in enumerate(event.gain_q20):
            gain_rows.append(
                (
                    event.event,
                    tap,
                    gain[0],
                    gain[1],
                    packed_hex(gain, 24, upper="imag"),
                )
            )
        for row in range(ORDER):
            for column in range(ORDER):
                value = event.p_q29[row][column]
                p_rows.append(
                    (
                        event.event,
                        row,
                        column,
                        value[0],
                        value[1],
                        packed_hex(value, 36, upper="imag"),
                    )
                )

    write_csv(
        oracle_path,
        (
            "event",
            "reference_source_index_zero_based",
            "desired_source_index_zero_based",
            "reference_real_q13_raw",
            "reference_imag_q13_raw",
            "prediction_real_q25_raw",
            "prediction_imag_q25_raw",
            "residual_real_q25_raw",
            "residual_imag_q25_raw",
            "residual_internal_upper_imag_hex",
            "denominator_real_q25_raw",
            "denominator_imag_q25_raw",
            "denominator_internal_upper_imag_hex",
            "reciprocal_real_q20_raw",
            "reciprocal_imag_q20_raw",
            "reciprocal_internal_upper_imag_hex",
            "event_wrap_events",
            "event_slice_overflow_events",
            "event_nonzero_truncation_events",
            "cumulative_wrap_events",
            "cumulative_slice_overflow_events",
            "cumulative_nonzero_truncation_events",
        ),
        oracle_rows,
    )
    write_csv(
        weights_path,
        (
            "event",
            "tap",
            "serializer_position",
            "weight_real_q27_raw",
            "weight_imag_q27_raw",
            "weight_external_upper_real_hex",
            "weight_real",
            "weight_imag",
        ),
        weight_rows,
    )
    write_csv(
        gains_path,
        ("event", "tap", "gain_real_q20_raw", "gain_imag_q20_raw", "gain_internal_upper_imag_hex"),
        gain_rows,
    )
    write_csv(
        p_path,
        ("event", "row", "column", "p_real_q29_raw", "p_imag_q29_raw", "p_internal_upper_imag_hex"),
        p_rows,
    )
    write_csv(
        external_path,
        (
            "valid_ordinal",
            "top_edge_from_130208ps_origin",
            "meaningful_sample_zero_based",
            "reference_stream_ordinal",
            "reference_source_index_zero_based",
            "desired_source_index_zero_based",
            "coefficient_event_zero_based",
            "desired_real_q13_raw",
            "desired_imag_q13_raw",
            "prediction_real_q13_raw",
            "prediction_imag_q13_raw",
            "residual_real_q13_raw",
            "residual_imag_q13_raw",
            "top_bus_upper_imag_lower_real_hex",
        ),
        (
            (
                row.valid_ordinal,
                row.top_edge,
                row.meaningful_sample,
                row.reference_stream_ordinal,
                row.reference_source_index,
                row.desired_source_index,
                row.coefficient_event,
                row.desired_q13[0],
                row.desired_q13[1],
                row.prediction_q13[0],
                row.prediction_q13[1],
                row.residual_q13[0],
                row.residual_q13[1],
                packed_hex(row.residual_q13, 24, upper="imag"),
            )
            for row in external_run.outputs
        ),
    )
    metrics_path.write_text(
        json.dumps(metrics, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="ascii",
    )
    external_metrics_path.write_text(
        json.dumps(external_metrics, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="ascii",
    )

    model_path = Path(__file__).resolve()
    schedule_path = model_path.with_name("rls_event_schedule.py")
    equation_path = repo_root / "verification/oracle/rls_algorithm_equations.md"
    divider_csv = repo_root / "verification/vectors/divider/divider_vectors.csv"
    manifest = {
        "status": "PHASE1B_FIXED_REFERENCE_GENERATED",
        "model_source": model_path.relative_to(repo_root).as_posix(),
        "model_source_sha256": sha256_file(model_path),
        "event_schedule_source": schedule_path.relative_to(repo_root).as_posix(),
        "event_schedule_source_sha256": sha256_file(schedule_path),
        "equation_contract_sha256": sha256_file(equation_path),
        "divider_vector_source_sha256": sha256_file(divider_csv),
        "order": ORDER,
        "updates": len(run.events),
        "external_packing": "upper_real_lower_imaginary_signed_24Q13",
        "internal_packing": "upper_imaginary_lower_real",
        "reference_start_index_zero_based": REFERENCE_START_INDEX,
        "desired_start_index_zero_based": DESIRED_START_INDEX,
        "refill_event_zero_based": REFILL_EVENT,
        "refill_reference_start_index_zero_based": REFILL_REFERENCE_START_INDEX,
        "refill_desired_start_index_zero_based": REFILL_DESIRED_START_INDEX,
        "p0_raw_q29": P0_RAW,
        "lambda_raw_q25": LAMBDA_RAW,
        "reciprocal_raw_q16": RECIPROCAL_Q16_RAW,
        "reciprocal_raw_q22": RECIPROCAL_Q22_RAW,
        "divider_policy": "signed Q32 round-to-nearest, ties toward negative infinity, wrap to 72 bits",
        "external_fir_contract": {
            "testbench_counter_length": EXTERNAL_COUNTER_LENGTH,
            "reference_lead_samples": EXTERNAL_REFERENCE_LEAD,
            "first_weight_output_sample_zero_based": EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE,
            "weight_update_interval_samples": EXTERNAL_UPDATE_INTERVAL,
            "refill_delay_samples": EXTERNAL_REFILL_DELAY_CLOCKS,
            "startup_valid_bubbles": EXTERNAL_STARTUP_VALID_BUBBLES,
            "first_top_valid_edge_from_130208ps_origin": EXTERNAL_FIRST_TOP_VALID_EDGE,
            "fir_output_slice": "{raw[63],raw[49:27]} per signed 64Q40 lane",
            "top_output_packing": "upper_imaginary_lower_real_signed_24Q13",
        },
        "inputs": {
            "reference": {
                "path": reference_path.relative_to(repo_root).as_posix(),
                "sha256": sha256_file(reference_path),
                "samples": len(load_packed_complex_int(reference_path)),
            },
            "desired": {
                "path": desired_path.relative_to(repo_root).as_posix(),
                "sha256": sha256_file(desired_path),
                "samples": len(load_packed_complex_int(desired_path)),
            },
        },
        "outputs": {
            path.name: sha256_file(path)
            for path in (
                oracle_path,
                weights_path,
                gains_path,
                p_path,
                external_path,
                metrics_path,
                external_metrics_path,
            )
        },
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="ascii",
    )

    report_lines = [
        "# Phase 1B Bit-Accurate Fixed-Point Reference",
        "",
        "## Status",
        "",
        "- Model execution: **RUN / PASS**",
        "- Arithmetic outputs complete and finite: **PASS**",
        "- Original RTL correlation: **RUNNER GATE REQUIRED**",
        "- External full-rate FIR residual: **GENERATED**",
        "- Completion marker: `PHASE1B_T1B03_FIXED_MODEL_GENERATED`",
        "",
        "## Actual Core Metrics",
        "",
        f"- Updates: {metrics['updates']}",
        f"- Refill schedule: event `{REFILL_EVENT}` jumps to reference `{REFILL_REFERENCE_START_INDEX}` and desired `{REFILL_DESIRED_START_INDEX}`",
        f"- MSE/residual power: `{metrics['mse']:.17g}`",
        f"- Cancellation: `{metrics['cancellation_db']:.17g} dB`" if metrics["cancellation_db"] is not None else "- Cancellation: `UNDEFINED`",
        f"- Steady-state residual power: `{metrics['steady_state_residual_power']:.17g}`",
        f"- Convergence event: `{metrics['convergence_event_zero_based']}`",
        f"- Maximum P Hermitian drift: `{metrics['maximum_p_hermitian_drift']:.17g}`",
        f"- Wrap events: `{metrics['arithmetic_counts'].get('wrap_events', 0)}`",
        f"- Slice-overflow events: `{metrics['arithmetic_counts'].get('slice_overflow_events', 0)}`",
        f"- Nonzero truncation events: `{metrics['arithmetic_counts'].get('nonzero_truncation_events', 0)}`",
        "",
        "## External FIR Metrics",
        "",
        f"- Valid outputs including startup bubbles: `{external_metrics['valid_outputs']}`",
        f"- Meaningful full-rate outputs: `{external_metrics['meaningful_outputs']}`",
        f"- Startup valid bubbles: `{external_metrics['startup_valid_bubbles']}`",
        f"- One-time coefficient activation delay after event `{REFILL_EVENT - 1}`: `{EXTERNAL_REFILL_DELAY_CLOCKS}` clocks",
        f"- MSE/residual power: `{external_metrics['mse']:.17g}`",
        f"- Cancellation: `{external_metrics['cancellation_db']:.17g} dB`" if external_metrics["cancellation_db"] is not None else "- Cancellation: `UNDEFINED`",
        f"- Steady-state residual power: `{external_metrics['steady_state_residual_power']:.17g}`",
        f"- Wrap events: `{external_metrics['arithmetic_counts'].get('wrap_events', 0)}`",
        f"- FIR slice-overflow events: `{external_metrics['arithmetic_counts'].get('fir_slice_overflow_events', 0)}`",
        f"- Nonzero truncation events: `{external_metrics['arithmetic_counts'].get('nonzero_truncation_events', 0)}`",
        "",
        "The external CSV includes the three observed top-valid startup bubbles, the frozen testbench counter wrap, reference/desired source indices, active weight event and actual upper-imaginary/lower-real top bus packing. The runner must still correlate it against the original generated-IP trace before T1B.03 can pass.",
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
    if sha256_file(reference_path) != INPUT_REFERENCE_SHA256:
        raise ValueError("Frozen reference vector SHA-256 mismatch")
    if sha256_file(desired_path) != INPUT_DESIRED_SHA256:
        raise ValueError("Frozen desired vector SHA-256 mismatch")
    artifact_root = (
        args.artifact_dir.resolve()
        if args.artifact_dir is not None
        else repo_root / "build/oracle/fixed/artifacts"
    )
    report_root = (
        args.report_dir.resolve()
        if args.report_dir is not None
        else repo_root / "build/oracle/fixed/reports"
    )
    reference = load_packed_complex_int(reference_path)
    desired = load_packed_complex_int(desired_path)
    run = run_fixed_rls(reference, desired, args.updates)
    metrics = calculate_metrics(run)
    external_run = run_external_fir(reference, desired, run)
    external_metrics = calculate_external_metrics(external_run)
    write_outputs(
        repo_root,
        artifact_root,
        report_root,
        reference_path,
        desired_path,
        run,
        metrics,
        external_run,
        external_metrics,
    )
    print("PHASE1B_T1B03_FIXED_MODEL_GENERATED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
