#!/usr/bin/env python3
"""Analyze fixedangle exposure around completed gestures without a pass verdict."""

import argparse
import importlib.util
import json
import math
import re
from pathlib import Path


_DETECTOR_SPEC = importlib.util.spec_from_file_location(
    "detect_blur_exposure", Path(__file__).with_name("detect-blur-exposure.py")
)
if _DETECTOR_SPEC is None or _DETECTOR_SPEC.loader is None:
    raise ImportError("Unable to load detect-blur-exposure.py")
_detector = importlib.util.module_from_spec(_DETECTOR_SPEC)
_DETECTOR_SPEC.loader.exec_module(_detector)
_METRIC_LOG_SPEC = importlib.util.spec_from_file_location(
    "metric_log", Path(__file__).with_name("metric-log.py")
)
if _METRIC_LOG_SPEC is None or _METRIC_LOG_SPEC.loader is None:
    raise ImportError("Unable to load metric-log.py")
_metric_log = importlib.util.module_from_spec(_METRIC_LOG_SPEC)
_METRIC_LOG_SPEC.loader.exec_module(_metric_log)


_BEGIN = re.compile(r"^GESTURE BEGIN ([0-9]+) ([^\s]+)$")
_HOLD = re.compile(r"^GESTURE HOLD ([0-9]+)$")
_TERMINAL = re.compile(r"^GESTURE (END|CANCEL) ([0-9]+)$")
_DONE = re.compile(r"^GESTURE DONE ([0-9]+) interrupted=([0-9]+)$")
_STATES = ("blurred", "exposed", "uncertain", "unknown")


def parse_protected_bins(value):
    parts = value.split(",")
    if not parts or any(not part.strip() for part in parts):
        raise ValueError("protected bins must be comma-separated integers")
    try:
        bins = [int(part.strip(), 10) for part in parts]
    except ValueError as error:
        raise ValueError("protected bins must be comma-separated integers") from error
    if len(set(bins)) != len(bins) or any(index < 0 or index > 15 for index in bins):
        raise ValueError("protected bins must be unique values from 0 through 15")
    return bins


def _event(line, line_number):
    if not line.startswith("GESTURE"):
        return None
    match = _BEGIN.match(line)
    if match:
        amount = float(match.group(2))
        if not math.isfinite(amount):
            raise ValueError(f"Invalid gesture amount at line {line_number}")
        return ("begin", int(match.group(1)), amount)
    match = _HOLD.match(line)
    if match:
        return ("hold", int(match.group(1)))
    match = _TERMINAL.match(line)
    if match:
        return (match.group(1).lower(), int(match.group(2)))
    match = _DONE.match(line)
    if match:
        return ("done", int(match.group(1)), int(match.group(2)))
    raise ValueError(f"Malformed gesture event at line {line_number}")


def read_gestures(path):
    """Read complete BEGIN -> END/CANCEL -> DONE lifecycles."""
    cycles = []
    current = None
    last_timestamp = None
    for line_number, line in enumerate(_metric_log.read_text(path).splitlines(), 1):
        parsed = _event(line.strip(), line_number)
        if parsed is None:
            continue
        kind, timestamp = parsed[0], parsed[1]
        if last_timestamp is not None and timestamp < last_timestamp:
            raise ValueError(f"Gesture timestamps go backwards at line {line_number}")
        last_timestamp = timestamp
        if kind == "begin":
            if current is not None:
                raise ValueError(f"Gesture began before previous gesture completed at line {line_number}")
            current = {"begin": timestamp, "amount": parsed[2], "terminal": None}
        elif kind == "hold":
            if current is None or current["terminal"] is not None:
                raise ValueError(f"Gesture hold is outside an active gesture at line {line_number}")
            if timestamp < current["begin"]:
                raise ValueError(f"Gesture hold precedes begin at line {line_number}")
        elif kind in ("end", "cancel"):
            if current is None or current["terminal"] is not None:
                raise ValueError(f"Gesture end is outside an active gesture at line {line_number}")
            if timestamp < current["begin"]:
                raise ValueError(f"Gesture end precedes begin at line {line_number}")
            current["terminal"] = (kind, timestamp)
        elif kind == "done":
            if current is None or current["terminal"] is None:
                raise ValueError(f"Gesture done is missing its end at line {line_number}")
            if timestamp < current["terminal"][1]:
                raise ValueError(f"Gesture done precedes end at line {line_number}")
            cycles.append({
                "begin": current["begin"],
                "terminal": current["terminal"],
                "done": timestamp,
                "interrupted": parsed[2],
            })
            current = None
    if current is not None:
        raise ValueError("Incomplete gesture lifecycle: missing END/CANCEL or DONE")
    if not cycles:
        raise ValueError("Gesture log has no complete lifecycle")
    return cycles


def _signed_ms(timestamp, end_timestamp, seconds_per_tick):
    if seconds_per_tick is None:
        return None
    return (timestamp - end_timestamp) * seconds_per_tick * 1000


def analyze(clear_baseline_path, gesture_log_path, protected_bins, observation_path):
    baseline_mode, clear_frames = _detector.read_frames(clear_baseline_path)
    if baseline_mode != "off":
        raise ValueError("Baseline must be a recorded off run")
    baseline = _detector.calibrate(clear_frames)

    mode, frames = _detector.read_frames(observation_path)
    if mode != "fixedangle":
        raise ValueError("Observation must use fixedangle mode")
    cycles = read_gestures(gesture_log_path)
    first_begin = cycles[0]["begin"]
    frames = {timestamp: frame for timestamp, frame in frames.items() if timestamp >= first_begin}
    if not frames:
        raise ValueError("Observation has no frames after the first GESTURE BEGIN")

    seconds_per_tick = _detector.read_timebase(observation_path)
    end_timestamps = [cycle["terminal"][1] for cycle in cycles if cycle["terminal"][0] == "end"]
    protected_counts = dict.fromkeys(_STATES, 0)
    per_bin = {
        index: dict.fromkeys(_STATES, 0)
        for index in protected_bins
    }
    exposed_frames = []
    for timestamp, frame in sorted(frames.items()):
        states = _detector.classify(frame, baseline)
        for index in protected_bins:
            state = states[index]
            protected_counts[state] += 1
            per_bin[index][state] += 1
        exposed = [index for index in protected_bins if states[index] == "exposed"]
        if exposed:
            nearest = min(end_timestamps, key=lambda end: abs(timestamp - end)) if end_timestamps else None
            exposed_frames.append({
                "timestamp": timestamp,
                "bins": exposed,
                "nearest_end_signed_ms": _signed_ms(timestamp, nearest, seconds_per_tick)
                if nearest is not None else None,
            })

    timestamps = sorted(frames)
    gaps = [later - earlier for earlier, later in zip(timestamps, timestamps[1:])]
    max_gap = max(gaps) if gaps else 0
    return {
        "mode": mode,
        "gesture_count": len(cycles),
        "completed_end_count": len(end_timestamps),
        "first_gesture_begin": first_begin,
        "protected_bins": protected_bins,
        "observed_frames": len(frames),
        "exposed_frame_count": len(exposed_frames),
        "exposed_frames": exposed_frames,
        "protected_counts": protected_counts,
        "protected_bin_counts": per_bin,
        "max_sample_gap_ms": max_gap * seconds_per_tick * 1000 if seconds_per_tick is not None else None,
        "verdict": "no_guarantee",
        "scope": "Fixedangle diagnostic bins only; no physical-screen or protection guarantee",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clear-baseline", type=Path, required=True)
    parser.add_argument("--gesture-log", type=Path, required=True)
    parser.add_argument("--protected-bins", required=True)
    parser.add_argument("observation", type=Path)
    args = parser.parse_args()
    result = analyze(
        args.clear_baseline,
        args.gesture_log,
        parse_protected_bins(args.protected_bins),
        args.observation,
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
