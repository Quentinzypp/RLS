#!/usr/bin/env python3
"""Frozen testbench event and coefficient-activation schedule for Phase 1B."""

from __future__ import annotations

from dataclasses import dataclass


REFERENCE_START_INDEX = 13
DESIRED_START_INDEX = 11
REFILL_EVENT = 986
REFILL_REFERENCE_START_INDEX = 8_745
REFILL_DESIRED_START_INDEX = 8_743
EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE = 369
EXTERNAL_UPDATE_INTERVAL = 175
EXTERNAL_REFILL_DELAY_CLOCKS = 33


@dataclass(frozen=True)
class EventInputSchedule:
    event: int
    reference_index: int
    desired_index: int
    reference_window_indices: tuple[int | None, ...]


def event_input_schedule(event: int, order: int) -> EventInputSchedule:
    if event < 0:
        raise ValueError(f"Event must be non-negative, found {event}")
    if order <= 0:
        raise ValueError(f"Order must be positive, found {order}")

    if event < REFILL_EVENT:
        reference_index = REFERENCE_START_INDEX + event
        desired_index = DESIRED_START_INDEX + event
        window = tuple(
            reference_index - tap if tap <= event else None for tap in range(order)
        )
    else:
        refill_offset = event - REFILL_EVENT
        reference_index = REFILL_REFERENCE_START_INDEX + refill_offset
        desired_index = REFILL_DESIRED_START_INDEX + refill_offset
        window = tuple(reference_index - tap for tap in range(order))

    return EventInputSchedule(
        event=event,
        reference_index=reference_index,
        desired_index=desired_index,
        reference_window_indices=window,
    )


def required_source_lengths(updates: int, order: int) -> tuple[int, int]:
    if updates <= 0:
        raise ValueError(f"Updates must be positive, found {updates}")
    schedule = event_input_schedule(updates - 1, order)
    return schedule.reference_index + 1, schedule.desired_index + 1


def coefficient_activation_sample(event: int) -> int:
    if event < 0:
        raise ValueError(f"Event must be non-negative, found {event}")
    refill_delay = EXTERNAL_REFILL_DELAY_CLOCKS if event >= REFILL_EVENT else 0
    return EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE + event * EXTERNAL_UPDATE_INTERVAL + refill_delay


def coefficient_event_for_sample(sample: int, updates: int) -> int | None:
    if sample < 0:
        raise ValueError(f"Sample must be non-negative, found {sample}")
    if updates <= 0:
        raise ValueError(f"Updates must be positive, found {updates}")
    if sample < EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE:
        return None

    shifted_refill_start = coefficient_activation_sample(REFILL_EVENT)
    if updates <= REFILL_EVENT or sample < shifted_refill_start:
        event = (sample - EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE) // EXTERNAL_UPDATE_INTERVAL
        if updates > REFILL_EVENT:
            event = min(event, REFILL_EVENT - 1)
    else:
        event = REFILL_EVENT + (
            sample - shifted_refill_start
        ) // EXTERNAL_UPDATE_INTERVAL

    return min(event, updates - 1)


def external_meaningful_samples(updates: int) -> int:
    if updates <= 0:
        raise ValueError(f"Updates must be positive, found {updates}")
    refill_delay = EXTERNAL_REFILL_DELAY_CLOCKS if updates > REFILL_EVENT else 0
    return (
        EXTERNAL_FIRST_WEIGHT_OUTPUT_SAMPLE
        + updates * EXTERNAL_UPDATE_INTERVAL
        + refill_delay
    )
