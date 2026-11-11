#!/usr/bin/env python3
"""Summarize RAM-only stripe metrics; these are diagnostics, not acceptance gates."""
import argparse
import statistics
from pathlib import Path


def summarize(path, include_profiles=False):
    edges = {"raw": {}, "shown": {}}
    colors = {}
    profile = {"raw": {}, "shown": {}}
    regions = {}
    targets = []
    coverage = {}
    stable_scene = {}
    ready = None
    done = False
    for line in path.read_text().splitlines():
        fields = line.split()
        if "FAIL" in fields:
            raise ValueError(f"{path}: probe reported failure")
        if fields[:2] == ["MEASURE", "READY"]:
            if ready is not None:
                raise ValueError(f"{path}: multiple runs; use one fresh log per run")
            ready = int(fields[3])
        elif fields[:2] == ["MEASURE", "DONE"]:
            done = True
        elif fields[:1] == ["PROFILE"]:
            profile[fields[1]][int(fields[2])] = list(map(float, fields[3].split(",")))
        elif fields[:2] == ["REGIONS", "raw"]:
            regions[int(fields[2])] = list(map(int, fields[3].split(",")))
        elif fields[:1] == ["TARGET"]:
            targets.append((int(fields[1]), float(fields[2])))
        elif fields[:1] == ["DETAIL"]:
            edges[fields[1]][int(fields[2])] = float(fields[3])
        elif fields[:2] == ["MEASURE", "raw"]:
            time = int(fields[2])
            green, magenta = float(fields[4]), float(fields[5])
            colors[time] = green
            coverage[time] = green + magenta
            stable_scene[time] = "A" if green > .9 else "B" if magenta > .9 else None
    if ready is None or not done:
        raise ValueError(f"{path}: missing READY or DONE")
    if any(value < .9 for time, value in coverage.items() if time >= ready):
        raise ValueError(f"{path}: fixture colors missing; expired or wrong Space")
    before = [scene for time, scene in sorted(stable_scene.items()) if time < ready and scene]
    scenes = before[-1:] + [scene for time, scene in sorted(stable_scene.items()) if time >= ready and scene]
    switches = sum(left != right for left, right in zip(scenes, scenes[1:]))
    if switches != 8:
        raise ValueError(f"{path}: expected 8 fixture switches, observed {switches}")
    ratios = [(time, value / edges["raw"][time])
              for time, value in edges["shown"].items()
              if time >= ready and edges["raw"].get(time, 0) > 10]
    moving = [ratio for time, ratio in ratios if .05 < colors[time] < .95]
    if not moving:
        raise ValueError(f"{path}: no matched moving pattern frames; invalid comparison")
    raw_times = {time for time in edges["raw"] if time >= ready}
    shown_times = {time for time in edges["shown"] if time >= ready}
    print(path.name, "raw frames", len(raw_times), "shown frames", len(shown_times),
          "raw-only", len(raw_times - shown_times), "shown-only", len(shown_times - raw_times),
          "matched", len(ratios), "all max", round(max(r for _, r in ratios), 4), "moving", len(moving),
          "moving median", round(statistics.median(moving), 4),
          "moving max", round(max(moving), 4),
          "moving ratio > 0.5", sum(value > .5 for value in moving))


    if include_profiles:
        report_profiles(profile, regions, colors, ready, targets)


def report_profiles(profile, regions, colors, ready, targets):
    groups = {}
    targets.sort()
    for time, shown in profile["shown"].items():
        raw, region = profile["raw"].get(time), regions.get(time)
        if time < ready or raw is None or region is None:
            continue
        if targets:
            # 각도 변경 직후의 응답 속도를 판정하는 검사가 아님.
            intervals = [(start, angle, end) for (start, angle), (end, _) in zip(targets, targets[1:])]
            match = [(angle, end-start) for start, angle, end in intervals
                     if start + .1*(end-start) <= time <= start + .8*(end-start)]
            if not match:
                continue
            group = f"angle {match[0][0]:g}"
        else:
            group = "moving" if .05 < colors.get(time, 0) < .95 else "near endpoints"
        for index in [1, 3, 5, 7, 9, 12, 14]:
            area = region[max(0, index-2):min(16, index+3)]
            if raw[index] <= 10 or len(set(area)) != 1 or area[0] not in (1, 2):
                continue
            groups.setdefault((group, index), []).append(shown[index] / raw[index])
    for (group, index), values in sorted(groups.items()):
        print(group, "bin", index, "n", len(values), "min/median/max",
              *(round(value, 4) for value in (min(values), statistics.median(values), max(values))))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--profiles", action="store_true")
    args = parser.parse_args()
    for log in args.logs:
        summarize(log, args.profiles)
