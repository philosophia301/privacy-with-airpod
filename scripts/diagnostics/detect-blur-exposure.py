#!/usr/bin/env python3
"""Uniform-blur diagnostic: unmatched shown frames remain observable, never passes missing regions."""
import argparse
import importlib.util
import json
import math
import statistics
from pathlib import Path


_METRIC_LOG_SPEC = importlib.util.spec_from_file_location(
    "metric_log", Path(__file__).with_name("metric-log.py")
)
if _METRIC_LOG_SPEC is None or _METRIC_LOG_SPEC.loader is None:
    raise ImportError("Unable to load metric-log.py")
_metric_log = importlib.util.module_from_spec(_METRIC_LOG_SPEC)
_METRIC_LOG_SPEC.loader.exec_module(_metric_log)


def read_frames(path, stream="shown"):
    if stream not in ("raw", "shown"):
        raise ValueError("Unknown stream")
    frames = {}
    ready = None
    mode = None
    done = False
    for line in _metric_log.read_text(path).splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == "FAIL":
            raise ValueError("Probe failure")
        if f[:2] == ["MEASURE", "READY"]:
            if ready is not None:
                raise ValueError("Multiple runs in one log")
            mode, ready = f[2], int(f[3])
        elif f[:2] == ["MEASURE", "DONE"]:
            if done or mode != f[2]:
                raise ValueError("Mismatched completion")
            done = True
        elif f[0] in ("PROFILE", "REGIONS") and f[1] == stream:
            values = [float(x) for x in f[3].split(",")]
            if len(values) != 16 or any(not math.isfinite(x) or x < 0 for x in values):
                raise ValueError("Invalid region metrics")
            frame = frames.setdefault(int(f[2]), {})
            if f[0] in frame:
                raise ValueError("Duplicate metric for the same displayed frame")
            frame[f[0]] = values
    if ready is None or not done:
        raise ValueError("Incomplete observation")
    return mode, {t: value for t, value in frames.items() if t >= ready}


def calibrate(frames):
    result = []
    for index in range(16):
        values = [f["PROFILE"][index] for f in frames.values()
                  if "PROFILE" in f and "REGIONS" in f
                  and f["REGIONS"][index] in (1, 2) and f["PROFILE"][index] > 0]
        if len(values) < 5:
            raise ValueError(f"Insufficient clear baseline for region {index}")
        result.append(statistics.median(values))
    return result


def classify(frame, baseline, blurred=0.15, exposed=0.65):
    if not 0 <= blurred < exposed:
        raise ValueError("Invalid diagnostic thresholds")
    if len(baseline) != 16 or any(not math.isfinite(x) or x <= 0 for x in baseline):
        raise ValueError("Invalid baseline")
    if "PROFILE" not in frame or "REGIONS" not in frame:
        return ["unknown"] * 16
    states = []
    for energy, region, normal in zip(frame["PROFILE"], frame["REGIONS"], baseline):
        # Mixed scene boundaries are unknown, not silently removed from the denominator.
        if region not in (1, 2):
            states.append("unknown")
        elif energy / normal >= exposed:
            states.append("exposed")
        elif energy / normal <= blurred:
            states.append("blurred")
        else:
            states.append("uncertain")
    return states


def read_timebase(path):
    clocks = [line.split()[1:] for line in _metric_log.read_text(path).splitlines()
              if line.startswith("CLOCK ")]
    if not clocks:
        return None
    if len(clocks) != 1 or len(clocks[0]) != 2:
        raise ValueError("Ambiguous clock metadata")
    numerator, denominator = map(int, clocks[0])
    if numerator <= 0 or denominator <= 0:
        raise ValueError("Invalid clock metadata")
    return numerator / denominator / 1_000_000_000


def report(frames, baseline, seconds_per_tick=None):
    counts = dict.fromkeys(("blurred", "exposed", "uncertain", "unknown"), 0)
    exposed_frames = []
    for timestamp, frame in sorted(frames.items()):
        states = classify(frame, baseline)
        for state in states:
            counts[state] += 1
        if "exposed" in states:
            exposed_frames.append(timestamp)
    times = sorted(frames)
    gaps = [b-a for a, b in zip(times, times[1:])]
    return {"observed_frames": len(frames), "region_counts": counts,
            "exposed_frames": len(exposed_frames),
            "first_exposure_tick": next(iter(exposed_frames), None),
            "last_exposure_tick": exposed_frames[-1] if exposed_frames else None,
            "largest_observation_gap_ms": max(gaps) * seconds_per_tick * 1000 if gaps and seconds_per_tick else None,
            "verdict": "exposure_detected" if exposed_frames else "not_established",
            "scope": "Uniform blur only; central strip; missing display frames unobserved; no physical-screen guarantee"}


def verify_fault_pulse(path, frames, baseline):
    seconds = read_timebase(path)
    events = [line.split()[1:] for line in _metric_log.read_text(path).splitlines()
              if line.startswith("FAULT ")]
    if seconds is None or len(events) != 2 or [e[0] for e in events] != ["BEGIN", "END"]:
        raise ValueError("A timed, complete fault pulse is required")
    begin, end = int(events[0][1]), int(events[1][1])
    if end <= begin:
        raise ValueError("Invalid fault interval")
    observed = [(t, classify(frame, baseline)) for t, frame in sorted(frames.items())]
    if not any(t < begin and states == ["blurred"] * 16 for t, states in observed):
        raise ValueError("Pre-fault blurred control missing")
    if not any(t > end + .050 / seconds and states == ["blurred"] * 16 for t, states in observed):
        raise ValueError("Post-fault recovery control missing")
    during = [states for t, states in observed if begin <= t <= end]
    if not during or any("unknown" in states for states in during):
        raise ValueError("Fault interval contains unobserved fixture regions")
    exposed = [(t, states) for t, states in observed if "exposed" in states]
    # 50ms는 이 합성 주입 검사에서 commit 후 표시 지연을 구분하는 한계임. 제품 허용 노출 시간이 아님.
    if not exposed or any(t < begin or t > end + .050 / seconds for t, _ in exposed):
        raise ValueError("Injected pulse missing, or exposure outside injection interval")
    if any(states != ["exposed"] * 16 for _, states in exposed):
        raise ValueError("Injected full-frame exposure was not observed in all regions")
    return {"detected_frames": len(exposed),
            "first_detection_delay_ms": (exposed[0][0] - begin) * seconds * 1000,
            "exposure_sample_span_ms": (exposed[-1][0] - exposed[0][0]) * seconds * 1000}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clear-baseline", type=Path, required=True)
    parser.add_argument("log", type=Path)
    parser.add_argument("--verify-fault-pulse", action="store_true")
    args = parser.parse_args()
    mode, clear = read_frames(args.clear_baseline)
    if mode != "off":
        raise ValueError("Baseline must be a recorded off run")
    _, observed = read_frames(args.log)
    baseline = calibrate(clear)
    result = report(observed, baseline, read_timebase(args.log))
    if args.verify_fault_pulse:
        result["fault_validation"] = verify_fault_pulse(args.log, observed, baseline)
    print(json.dumps(result, indent=2))
