#!/usr/bin/env python3
"""Compare stationary full-frame raw/shown grid metrics with an observation.

This is a numeric diagnostic.  It does not inspect pixels or claim visual
acceptance.  A lower shown/raw energy ratio means stronger blur; a higher
ratio means weaker blur.
"""
import argparse
from bisect import bisect_left
import json
import math
from pathlib import Path
import statistics


CELLS = 16 * 9
UINT64_MAX = 2**64 - 1
STREAMS = ("raw", "shown")
PURE_SCENES = (1, 2)
DEFAULT_TOLERANCE_MS = 50.0
DEFAULT_GAP_MS = 100.0
DEFAULT_DELTA = 0.15
DEFAULT_FLOOR = 1.0
DEFAULT_REFERENCE_SPREAD = 0.30
RATIO_FLOOR = 0.01
ENERGY_CEILING = 510.0


class InvalidLog(ValueError):
    """Input violates the metrics, clock, or completion contract."""


def _integer(value, name, minimum=0, maximum=None):
    if (isinstance(value, bool) or not isinstance(value, int) or value < minimum
            or maximum is not None and value > maximum):
        raise InvalidLog(f"{name} must be an integer >= {minimum}")
    return value


def _number(value, name, minimum=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidLog(f"{name} must be numeric")
    value = float(value)
    if not math.isfinite(value) or minimum is not None and value < minimum:
        raise InvalidLog(f"{name} must be finite and >= {minimum}")
    return value


def _metric_frame(value, line_number):
    if not isinstance(value, dict) or value.get("schema") != 1:
        raise InvalidLog(f"line {line_number}: schema must be 1")
    stream = value.get("stream")
    if stream not in STREAMS:
        raise InvalidLog(f"line {line_number}: unknown stream")
    tick = _integer(value.get("tick"), "tick", 0, UINT64_MAX)
    width = _integer(value.get("width"), "width", 1)
    height = _integer(value.get("height"), "height", 1)
    if value.get("cols") != 16 or value.get("rows") != 9:
        raise InvalidLog(f"line {line_number}: grid must be 16x9")
    energy = value.get("energy")
    regions = value.get("regions")
    samples = value.get("samples")
    if not isinstance(energy, list) or not isinstance(regions, list) or not isinstance(samples, list):
        raise InvalidLog(f"line {line_number}: metric arrays are required")
    if not (len(energy) == len(regions) == len(samples) == CELLS):
        raise InvalidLog(f"line {line_number}: metric arrays must contain 144 cells")
    clean_energy = [_number(item, "energy", 0.0) for item in energy]
    clean_regions = []
    for item in regions:
        region = _integer(item, "region", 1)
        if region > 7:
            raise InvalidLog(f"line {line_number}: region bitmask must be 1..7")
        clean_regions.append(region)
    clean_samples = [_integer(item, "samples", 1) for item in samples]
    return {"stream": stream, "tick": tick, "width": width, "height": height,
            "energy": clean_energy, "regions": clean_regions, "samples": clean_samples}


def parse_log(path):
    """Read one complete JSONL run and its optional legacy clock markers."""
    path = Path(path)
    frames = {stream: {} for stream in STREAMS}
    clock = None
    ready = None
    mode = None
    done = False
    target_angles = set()
    ignored = {"POLICY", "PANEL", "WINDOW", "DISPLAY", "OWNED_SPACE", "TRANSFORM",
               "DETAIL", "MEASURE"}
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        text = line.strip()
        if not text:
            continue
        fields = text.split()
        if fields[0] == "CLOCK":
            if len(fields) != 3 or clock is not None:
                raise InvalidLog(f"line {line_number}: invalid or duplicate CLOCK")
            numerator = _integer(int(fields[1]) if fields[1].isdigit() else None, "clock numerator", 1)
            denominator = _integer(int(fields[2]) if fields[2].isdigit() else None, "clock denominator", 1)
            clock = numerator / denominator / 1_000_000_000.0
            continue
        if fields[:2] == ["MEASURE", "READY"]:
            if len(fields) != 4 or ready is not None:
                raise InvalidLog(f"line {line_number}: invalid or duplicate READY")
            mode = fields[2]
            if not mode:
                raise InvalidLog(f"line {line_number}: empty mode")
            ready = _integer(int(fields[3]) if fields[3].isdigit() else None,
                             "ready tick", 0, UINT64_MAX)
            continue
        if fields[:2] == ["MEASURE", "DONE"]:
            if len(fields) != 3 or done or ready is None or fields[2] != mode:
                raise InvalidLog(f"line {line_number}: invalid DONE")
            done = True
            continue
        if fields[:2] == ["GRID", "STATUS"]:
            if len(fields) != 5 or fields[2] not in STREAMS or not fields[3].isdigit() or not fields[4].isdigit():
                raise InvalidLog(f"line {line_number}: malformed GRID STATUS")
            continue
        if fields[0] == "TARGET":
            if len(fields) < 2:
                raise InvalidLog(f"line {line_number}: malformed TARGET")
            try:
                target_angles.add(float(fields[-1]))
            except ValueError as error:
                raise InvalidLog(f"line {line_number}: malformed TARGET") from error
            continue
        if fields[0] in ignored:
            continue
        if text.startswith("{"):
            if done:
                raise InvalidLog(f"line {line_number}: record follows DONE")
            try:
                value = json.loads(text)
            except json.JSONDecodeError as error:
                raise InvalidLog(f"line {line_number}: invalid JSON: {error.msg}") from error
            frame = _metric_frame(value, line_number)
            stream = frame["stream"]
            tick = frame["tick"]
            if tick in frames[stream]:
                raise InvalidLog(f"line {line_number}: duplicate {stream} tick {tick}")
            frames[stream][tick] = frame
            continue
        raise InvalidLog(f"line {line_number}: unknown log record")
    if clock is None or ready is None or not done:
        raise InvalidLog("CLOCK, READY, and DONE are required")
    if mode in ("dynamic", "continuous"):
        raise InvalidLog("dynamic/continuous mode is not a static profile audit")
    if len(target_angles) > 1:
        raise InvalidLog("TARGET angle changed during run")
    frames = {stream: {tick: frame for tick, frame in values.items() if tick >= ready}
              for stream, values in frames.items()}
    if any(not values for values in frames.values()):
        raise InvalidLog("both raw and shown streams require frames")
    geometry = {(frame["width"], frame["height"])
                for stream in STREAMS for frame in frames[stream].values()}
    if len(geometry) != 1:
        raise InvalidLog("inconsistent frame geometry")
    return {"frames": frames, "clock": clock, "mode": mode,
            "geometry": next(iter(geometry))}


def _max_gap_ms(log):
    gaps = []
    for stream in STREAMS:
        ticks = sorted(log["frames"][stream])
        gaps.extend(later - earlier for earlier, later in zip(ticks, ticks[1:]))
    return (max(gaps) * log["clock"] * 1000.0) if gaps else 0.0


def _nearest_pairs(log, tolerance_ms):
    raw = log["frames"]["raw"]
    shown = log["frames"]["shown"]
    raw_ticks = sorted(raw)
    pairs = []
    for shown_tick in sorted(shown):
        position = bisect_left(raw_ticks, shown_tick)
        candidates = []
        if position:
            candidates.append(raw_ticks[position - 1])
        if position < len(raw_ticks):
            candidates.append(raw_ticks[position])
        raw_tick = min(candidates, key=lambda tick: (abs(tick - shown_tick), tick))
        delta_ms = abs(raw_tick - shown_tick) * log["clock"] * 1000.0
        if delta_ms <= tolerance_ms:
            pairs.append((raw[raw_tick], shown[shown_tick], delta_ms))
    return pairs


def _ratio(raw, shown, cell, floor, ceiling):
    if raw["regions"][cell] not in PURE_SCENES or shown["regions"][cell] != raw["regions"][cell]:
        return None
    value = raw["energy"][cell]
    if value <= floor or value >= ceiling or raw["samples"][cell] <= 0 or shown["samples"][cell] <= 0:
        return None
    result = shown["energy"][cell] / value
    return result if math.isfinite(result) else None


def _cell(row, col, scene, reference, observed, delta, normalized, direction):
    return {"row": row, "col": col, "cell": row * 16 + col, "scene": scene,
            "reference_ratio": reference, "observed_ratio": observed,
            "delta": delta, "normalized_delta": normalized, "direction": direction}


def audit(reference, observation, tolerance_ms=DEFAULT_TOLERANCE_MS,
          max_gap_ms=DEFAULT_GAP_MS, delta_threshold=DEFAULT_DELTA,
          raw_energy_floor=DEFAULT_FLOOR,
          reference_spread_limit=DEFAULT_REFERENCE_SPREAD):
    """Return a JSON-serializable comparison report."""
    for name, value in (("tolerance_ms", tolerance_ms), ("max_gap_ms", max_gap_ms),
                        ("delta_threshold", delta_threshold), ("raw_energy_floor", raw_energy_floor),
                        ("reference_spread_limit", reference_spread_limit)):
        if not math.isfinite(value) or value <= 0:
            raise InvalidLog(f"{name} must be finite and positive")
    if reference["geometry"] != observation["geometry"]:
        return {"verdict": "inconclusive", "reason": "geometry_mismatch",
                "compared_cells": 0, "unresolved_cells": CELLS,
                "max_gap_ms": max(_max_gap_ms(reference), _max_gap_ms(observation)),
                "anomalies": [], "top_anomalies": [], "bottom_anomalies": []}
    ref_pairs = _nearest_pairs(reference, tolerance_ms)
    obs_pairs = _nearest_pairs(observation, tolerance_ms)
    reference_by_scene = [[[] for _ in PURE_SCENES] for _ in range(CELLS)]
    for raw, shown, _ in ref_pairs:
        for cell in range(CELLS):
            value = _ratio(raw, shown, cell, raw_energy_floor, ENERGY_CEILING)
            if value is not None:
                reference_by_scene[cell][raw["regions"][cell] - 1].append(value)
    ref_valid = sum(1 for raw, shown, _ in ref_pairs
                    if any(_ratio(raw, shown, cell, raw_energy_floor, ENERGY_CEILING) is not None
                           for cell in range(CELLS)))
    observed_values = [[ ] for _ in range(CELLS)]
    unresolved = set()
    anomalies = []
    pair_scene_mismatch = False
    reference_medians = {}
    reference_spread_cells = []
    near_zero_reference_cells = []
    for cell in range(CELLS):
        for scene_index, values in enumerate(reference_by_scene[cell]):
            if len(values) < 5:
                continue
            median = statistics.median(values)
            spread = (max(values) - min(values)) / max(abs(median), RATIO_FLOOR)
            reference_medians[(cell, scene_index + 1)] = median
            if spread > reference_spread_limit:
                reference_spread_cells.append(cell)
            if median <= RATIO_FLOOR:
                near_zero_reference_cells.append(cell)
    obs_valid = 0
    compared_cells = set()
    unsupported_scene_cells = set()
    for raw, shown, _ in obs_pairs:
        frame_valid = False
        for cell in range(CELLS):
            scene = raw["regions"][cell]
            value = _ratio(raw, shown, cell, raw_energy_floor, ENERGY_CEILING)
            if value is None:
                unresolved.add(cell)
                if scene in PURE_SCENES and shown["regions"][cell] != scene:
                    pair_scene_mismatch = True
                if scene == 4 or scene not in PURE_SCENES:
                    unsupported_scene_cells.add(cell)
                continue
            frame_valid = True
            observed_values[cell].append(value)
            baseline = reference_medians.get((cell, scene))
            if baseline is None:
                unresolved.add(cell)
                unsupported_scene_cells.add(cell)
                continue
            compared_cells.add(cell)
            normalized = (value - baseline) / max(abs(baseline), RATIO_FLOOR)
            if abs(normalized) > delta_threshold and not (
                    baseline <= RATIO_FLOOR and normalized < 0):
                row, col = divmod(cell, 16)
                direction = "weaker_blur" if normalized > 0 else "stronger_blur"
                anomalies.append(_cell(row, col, scene, baseline, value,
                                       value - baseline, normalized, direction))
                anomalies[-1].update(shown_tick=shown["tick"], raw_tick=raw["tick"])
        if frame_valid:
            obs_valid += 1
    per_cell = {}
    for item in anomalies:
        current = per_cell.get(item["cell"])
        score = abs(item["normalized_delta"]) if item["normalized_delta"] is not None else -1.0
        old_score = (abs(current["normalized_delta"])
                     if current and current["normalized_delta"] is not None else -1.0)
        if current is None or score > old_score:
            per_cell[item["cell"]] = item
    anomalies = list(per_cell.values())
    comparable = sorted(compared_cells)
    reference_pure_cells = sum(1 for cell in range(CELLS)
                               if any(frame["regions"][cell] in PURE_SCENES
                                      for frame in reference["frames"]["raw"].values()))
    pure_cells = sum(1 for values in reference_by_scene
                     if any(values[scene] for scene in range(len(PURE_SCENES))))
    saturated = sum(1 for cell in range(CELLS)
                    if reference_pure_cells and any(frame["regions"][cell] in PURE_SCENES
                                                    for frame in reference["frames"]["raw"].values()) and all(
                        frame["energy"][cell] >= ENERGY_CEILING
                        for frame in reference["frames"]["raw"].values()))
    reasons = []
    if len(ref_pairs) < 5 or ref_valid < 5:
        reasons.append("fewer_than_5_valid_reference_pairs")
    if len(obs_pairs) < 5 or obs_valid < 5:
        reasons.append("fewer_than_5_valid_observation_pairs")
    if len(obs_pairs) != len(observation["frames"]["shown"]):
        reasons.append("unmatched_shown_frames")
    if saturated and saturated == reference_pure_cells:
        reasons.append("all_reference_raw_energy_saturated")
    shown_saturated = sum(1 for cell in range(CELLS)
                          if reference_pure_cells and any(frame["regions"][cell] in PURE_SCENES
                                                          for frame in reference["frames"]["raw"].values()) and all(
                              frame["energy"][cell] >= ENERGY_CEILING
                              for frame in reference["frames"]["shown"].values()))
    if shown_saturated and shown_saturated == reference_pure_cells:
        reasons.append("all_reference_shown_energy_saturated")
    if pure_cells and all(frame["energy"][cell] <= raw_energy_floor
                          for cell in range(CELLS) if any(reference_by_scene[cell][scene]
                                                         for scene in range(len(PURE_SCENES)))
                          for frame in reference["frames"]["raw"].values()):
        reasons.append("all_reference_raw_energy_at_or_below_floor")
    if any(frame["regions"][cell] not in (1, 2, 4)
           for stream in STREAMS for frame in reference["frames"][stream].values()
           for cell in range(CELLS)):
        reasons.append("unknown_reference_region_cells")
    if not pure_cells:
        reasons.append("no_identifiable_pure_scene_cells")
    if any(frame["regions"][cell] not in (1, 2, 4)
           for stream in STREAMS for frame in observation["frames"][stream].values()
           for cell in range(CELLS)):
        reasons.append("unknown_region_cells")
    if reference_spread_cells:
        reasons.append("reference_ratio_spread_over_limit")
    if near_zero_reference_cells:
        reasons.append("near_zero_reference_ratio_limits_stronger_blur_detection")
    if _max_gap_ms(reference) > max_gap_ms or _max_gap_ms(observation) > max_gap_ms:
        reasons.append("observation_gap_over_limit")
    if len(comparable) < 1:
        reasons.append("no_compared_cells")
    if unresolved:
        reasons.append("unresolved_observation_cells")
    if unsupported_scene_cells:
        reasons.append("scene_mismatch_reference")
    if pair_scene_mismatch:
        reasons.append("raw_shown_scene_mismatch_within_pair")
    top = sorted((item for item in anomalies if item["normalized_delta"] is not None),
                 key=lambda item: item["normalized_delta"], reverse=True)[:10]
    bottom = sorted((item for item in anomalies if item["normalized_delta"] is not None),
                    key=lambda item: item["normalized_delta"])[:10]
    verdict = "regression_detected" if anomalies and not reasons else "inconclusive" if reasons else "no_regression_detected_in_observed_grid"
    return {"verdict": verdict, "reference_pairs": len(ref_pairs), "observed_pairs": len(obs_pairs),
            "valid_reference_pairs": ref_valid, "valid_observation_pairs": obs_valid,
            "compared_cells": len(comparable), "unresolved_cells": len(unresolved),
            "max_gap_ms": max(_max_gap_ms(reference), _max_gap_ms(observation)),
            "anomalies": sorted(anomalies, key=lambda item: item["cell"]),
            "top_anomalies": top, "bottom_anomalies": bottom,
            "reference_spread_cells": sorted(set(reference_spread_cells)),
            "near_zero_reference_cells": sorted(set(near_zero_reference_cells)),
            "reasons": reasons, "delta_threshold": delta_threshold,
            "match_tolerance_ms": tolerance_ms,
            "reference_spread_limit": reference_spread_limit,
            "calibration_protocol": [
                "stationary reference must keep the blur profile and geometry; pure scene masks may alternate",
                "pair each shown frame to nearest raw frame within match_tolerance_ms",
                "use per-cell median shown/raw ratio from at least five valid reference pairs",
                "exclude pure scene cells with raw energy at/below floor or byte-energy saturation",
                "require reference ratio spread to remain within reference_spread_limit",
                "same render parameters are a collection protocol requirement, not provable from this JSONL",
            ],
            "scope": "Observed 16x9 numeric grid only; static profile mismatch is a boundary signal, not a double-layer root cause."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True,
                        help="stationary reference JSONL")
    parser.add_argument("observation", type=Path)
    parser.add_argument("--match-tolerance-ms", type=float, default=DEFAULT_TOLERANCE_MS)
    parser.add_argument("--max-gap-ms", type=float, default=DEFAULT_GAP_MS)
    parser.add_argument("--delta-threshold", type=float, default=DEFAULT_DELTA)
    parser.add_argument("--raw-energy-floor", type=float, default=DEFAULT_FLOOR)
    parser.add_argument("--reference-spread-limit", type=float, default=DEFAULT_REFERENCE_SPREAD)
    args = parser.parse_args(argv)
    try:
        reference = parse_log(args.reference)
        observation = parse_log(args.observation)
        result = audit(reference, observation, args.match_tolerance_ms, args.max_gap_ms,
                       args.delta_threshold, args.raw_energy_floor,
                       args.reference_spread_limit)
    except (InvalidLog, OSError, ValueError) as error:
        result = {"verdict": "invalid_observation", "error": str(error),
                  "scope": "Observed 16x9 numeric grid only; no visual acceptance."}
    print(json.dumps(result, indent=2, sort_keys=True))
    return {"regression_detected": 1,
            "inconclusive": 2,
            "invalid_observation": 2,
            "no_regression_detected_in_observed_grid": 0}[result["verdict"]]


if __name__ == "__main__":
    raise SystemExit(main())
