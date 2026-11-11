#!/usr/bin/env python3
"""Strict offline transition evidence audit, not a visual acceptance certificate."""
import argparse
from bisect import bisect_right
import importlib.util
import json
import math
from pathlib import Path


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


detector = module("exposure", "detect-blur-exposure.py")
gestures = module("fixed_mask", "analyze-fixed-mask.py")


def scene(frame):
    regions = frame.get("REGIONS", [])
    middle = regions[1:15]
    if len(middle) == 14 and middle[0] in (1, 2) and all(x == middle[0] for x in middle):
        return int(middle[0])
    return None


def mixed(frame):
    regions = frame.get("REGIONS", [])
    return (1 in regions and 2 in regions) or any(value in (3, 7) for value in regions)


def audit(raw, shown, cycles, baseline, seconds_per_tick, protected_bins,
          max_gap_ms=50, settle_ms=50):
    if not seconds_per_tick or not math.isfinite(seconds_per_tick) or seconds_per_tick <= 0:
        raise ValueError("Valid clock metadata required")
    if not cycles or not protected_bins or len(set(protected_bins)) != len(protected_bins) or any(
            not isinstance(i, int) or not 0 <= i < 16 for i in protected_bins):
        raise ValueError("Complete gestures and unique protected bins required")
    if any(not math.isfinite(x) or x <= 0 for x in (max_gap_ms, settle_ms)):
        raise ValueError("Positive finite diagnostic limits required")
    detector.classify({}, baseline)
    gap_limit = max_gap_ms / 1000 / seconds_per_tick
    tail = settle_ms / 1000 / seconds_per_tick
    issues, results = [], []
    start = cycles[0]["begin"]
    end = max(shown, default=cycles[-1]["done"] + tail)
    counts = dict.fromkeys(("blurred", "exposed", "unknown", "uncertain"), 0)
    exposures, stale = [], []
    observed = {t: f for t, f in shown.items() if start <= t <= end}
    for t, frame in sorted(observed.items()):
        states = detector.classify(frame, baseline)
        for i in protected_bins:
            counts[states[i]] += 1
        if any(states[i] == "exposed" for i in protected_bins):
            exposures.append(t)
    if counts["unknown"] or counts["uncertain"]:
        issues.append("protected_regions_unresolved")
    if not observed:
        issues.append("no_shown_frames")
    if raw and shown and abs(max(raw) - max(shown)) > gap_limit:
        issues.append("unmatched_observation_tail")

    # Evaluate every gesture separately: global sample counts cannot hide an unobserved transition.
    for index, cycle in enumerate(cycles):
        begin, done = cycle["begin"], cycle["done"]
        kind, terminal = cycle["terminal"]
        if kind not in ("end", "cancel") or not begin <= terminal <= done or cycle["interrupted"]:
            raise ValueError("Interrupted or invalid gesture lifecycle")
        if index and begin < cycles[index - 1]["done"]:
            raise ValueError("Overlapping gesture lifecycle")
        local = []
        post_end = cycles[index + 1]["begin"] if index + 1 < len(cycles) else min(
            max(raw, default=done), max(shown, default=done))
        required_end = max(done + tail, post_end)
        for label, frames in (("raw", raw), ("shown", shown)):
            times = sorted(frames)
            before = [t for t in times if t <= begin]
            after = [t for t in times if t >= required_end]
            if not before or not after:
                local.append(label + "_missing_boundary")
                continue
            span = [t for t in times if before[-1] <= t <= after[0]]
            if max((b - a for a, b in zip(span, span[1:])), default=math.inf) > gap_limit:
                local.append(label + "_observation_gap")
        prior = sorted((t, scene(f)) for t, f in raw.items() if begin - gap_limit <= t <= begin)
        source = prior[-1][1] if prior else None
        post = [(t, scene(f)) for t, f in sorted(raw.items()) if done <= t <= post_end]
        window = [f for t, f in raw.items() if begin <= t <= done]
        moved = any(mixed(f) or (scene(f) is not None and scene(f) != source) for f in window)
        if source is None:
            local.append("source_scene_unidentified")
        if not moved:
            local.append("no_observed_transition")
        destination = source if kind == "cancel" else 3 - source if source else None
        stable_tail = []
        for t, value in reversed(post):
            if value != destination:
                break
            stable_tail.append(t)
        if destination is None or len(stable_tail) < 2 or stable_tail[0] - stable_tail[-1] < tail:
            local.append("destination_not_settled")
        issues.extend(f"gesture_{index}:{value}" for value in local)
        results.append({"index": index, "kind": kind, "source": source,
                        "expected_destination": destination, "observed_motion": moved,
                        "issues": local})

    # Compare independent raw observations against shown output; never require equal stream timestamps.
    raw_times = sorted(raw)
    stable_since, last_scene = None, None
    stability = {}
    previous = None
    for t in raw_times:
        value = scene(raw[t])
        if value is None or value != last_scene or (previous is not None and t - previous > gap_limit):
            stable_since = t if value is not None else None
        stability[t] = stable_since
        last_scene, previous = value, t
    for t, frame in sorted(observed.items()):
        position = bisect_right(raw_times, t) - 1
        if position < 0:
            continue
        rt = raw_times[position]
        since = stability[rt]
        if t - rt > gap_limit or since is None or rt - since < tail:
            continue
        visible, actual = scene(frame), scene(raw[rt])
        if visible is not None and visible != actual:
            stale.append(t)
    return {"verdict": "regression_detected" if exposures or stale else
            "inconclusive" if issues else "no_regression_detected_in_observed_strip",
            "exposure_frames": len(exposures), "first_exposure_tick": exposures[0] if exposures else None,
            "stale_scene_frames": stale, "protected_counts": counts,
            "validity_issues": issues, "gestures": results,
            "diagnostic_limits": {"max_gap_ms": max_gap_ms, "settle_ms": settle_ms},
            "unverified": ["outside_central_strip", "between_samples", "double_blur_strength",
                           "boundary_motion_smoothness", "physical_trackpad_equivalence", "scene_mismatch_within_settle_window"],
            "scope": "Static protected bins; scene mismatch is a symptom, not proof of old-frame replay. No beauty/pass verdict."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clear-baseline", type=Path, required=True)
    parser.add_argument("--gesture-log", type=Path, required=True)
    parser.add_argument("--protected-bins", required=True)
    parser.add_argument("--max-gap-ms", type=float, default=50)
    parser.add_argument("--settle-ms", type=float, default=50)
    parser.add_argument("observation", type=Path)
    args = parser.parse_args()
    try:
        mode, clear = detector.read_frames(args.clear_baseline)
        if mode != "off":
            raise ValueError("Clear baseline must be an off run")
        observation_mode, shown = detector.read_frames(args.observation)
        if observation_mode in ("dynamic", "continuous"):
            raise ValueError("Moving masks require time-varying expected regions; static-bin audit refused")
        _, raw = detector.read_frames(args.observation, stream="raw")
        result = audit(raw, shown, gestures.read_gestures(args.gesture_log), detector.calibrate(clear),
                       detector.read_timebase(args.observation), gestures.parse_protected_bins(args.protected_bins),
                       args.max_gap_ms, args.settle_ms)
    except (ValueError, OSError, IndexError) as error:
        result = {"verdict": "invalid_observation", "error": str(error)}
    print(json.dumps(result, indent=2))
    # Zero means only that this limited diagnostic found no signal with adequate coverage.
    return {"regression_detected": 1, "inconclusive": 2, "invalid_observation": 2}.get(result["verdict"], 0)


if __name__ == "__main__":
    raise SystemExit(main())
