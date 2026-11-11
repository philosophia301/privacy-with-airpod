#!/usr/bin/env python3
"""Meaningful synthetic regression cases for audit-grid.py."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("grid_audit", Path(__file__).with_name("audit-grid.py"))
GRID = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GRID)


class GridAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.reference = self.write_log("reference.jsonl", self.frames())

    def tearDown(self):
        self.temp.cleanup()

    def regions(self):
        # Both pure scenes cover every cell; mixed/other cells are unresolved
        # by contract and therefore cannot make a full-frame run pass.
        return [1] * 72 + [2] * 72

    def frames(self, ratio=.5, ticks=None, regions=None, raw_energy=None, shown_offset=0):
        ticks = range(5) if ticks is None else ticks
        regions = self.regions() if regions is None else regions
        raw_energy = [20.0 + (cell % 13) for cell in range(144)] if raw_energy is None else raw_energy
        values = []
        for tick in ticks:
            values.append({"schema": 1, "stream": "raw", "tick": tick,
                           "width": 1920, "height": 1080, "cols": 16, "rows": 9,
                           "energy": list(raw_energy), "regions": list(regions), "samples": [4] * 144})
            values.append({"schema": 1, "stream": "shown", "tick": tick + shown_offset,
                           "width": 1920, "height": 1080, "cols": 16, "rows": 9,
                           "energy": [energy * ratio for energy in raw_energy],
                           "regions": list(regions), "samples": [4] * 144})
        return values

    def write_log(self, name, frames, mode="stationary", clock="CLOCK 1000000 1"):
        path = Path(self.temp.name) / name
        lines = [clock, f"MEASURE READY {mode} 0"]
        lines.extend(json.dumps(frame, allow_nan=True) for frame in frames)
        lines.append(f"MEASURE DONE {mode}")
        path.write_text("\n".join(lines) + "\n")
        return path

    def result(self, frames, **kwargs):
        observed = self.write_log("observation.jsonl", frames, mode="observed")
        reference = GRID.parse_log(self.reference)
        return GRID.audit(reference, GRID.parse_log(observed), **kwargs)

    def test_clean_grid_passes(self):
        result = self.result(self.frames())
        self.assertEqual(result["verdict"], "no_regression_detected_in_observed_grid")
        self.assertEqual(result["compared_cells"], 144)
        self.assertEqual(result["unresolved_cells"], 0)

    def test_cli_clean_exit_is_zero(self):
        observation = self.write_log("cli-observation.jsonl", self.frames(), mode="observed")
        completed = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("audit-grid.py")),
             "--reference", str(self.reference), str(observation)],
            capture_output=True, text=True, check=False)
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(json.loads(completed.stdout)["verdict"],
                         "no_regression_detected_in_observed_grid")

    def test_top_corner_exposure_is_regression_with_top_anomaly(self):
        frames = self.frames()
        spiked = False
        for frame in frames:
            if frame["stream"] == "shown" and not spiked:
                frame["energy"][0] = frame["energy"][0] * 1.8
                spiked = True
        result = self.result(frames)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertEqual(result["top_anomalies"][0]["cell"], 0)
        self.assertEqual(result["top_anomalies"][0]["direction"], "weaker_blur")

    def test_strength_collapse_in_one_region_is_regression(self):
        frames = self.frames()
        for frame in frames:
            if frame["stream"] == "shown":
                frame["energy"][80] *= 1.8
        result = self.result(frames)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertTrue(any(item["cell"] == 80 for item in result["anomalies"]))

    def test_single_frame_stronger_blur_is_not_hidden_by_median(self):
        self.reference = self.write_log("weak-reference.jsonl", self.frames(ratio=.1))
        frames = self.frames(ratio=.1)
        for frame in frames:
            if frame["stream"] == "shown" and frame["tick"] == 0:
                frame["energy"][3] *= .3
        result = self.result(frames)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertEqual(result["bottom_anomalies"][0]["cell"], 3)
        self.assertEqual(result["bottom_anomalies"][0]["direction"], "stronger_blur")

    def test_shifted_static_mask_is_boundary_signal(self):
        frames = self.frames()
        for frame in frames:
            if frame["stream"] == "shown":
                frame["energy"][0] *= 1.8
                frame["energy"][64] *= .2
        result = self.result(frames)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertEqual({item["cell"] for item in result["anomalies"]}, {0, 64})
        self.assertEqual(result["top_anomalies"][0]["cell"], 0)
        self.assertEqual(result["bottom_anomalies"][0]["cell"], 64)

    def test_reference_scene_mismatch_is_inconclusive(self):
        regions = self.regions()
        regions[0] = 4
        result = self.result(self.frames(regions=regions))
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("scene_mismatch_reference", result["reasons"])

    def test_reference_calibrates_both_scene_values_per_cell(self):
        alternating = []
        for tick in range(10):
            regions = [1 if tick % 2 == 0 else 2] * 144
            alternating.extend(self.frames(ticks=[tick], regions=regions))
        self.reference = self.write_log("alternating-reference.jsonl", alternating)
        result = self.result(alternating)
        self.assertEqual(result["verdict"], "no_regression_detected_in_observed_grid")
        self.assertEqual(result["compared_cells"], 144)

    def test_missing_nearest_pairs_cannot_pass(self):
        result = self.result(self.frames(shown_offset=100))
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("fewer_than_5_valid_observation_pairs", result["reasons"])

    def test_gap_limit_is_separate_validity_failure(self):
        result = self.result(self.frames(ticks=[0, 200, 400, 600, 800]), max_gap_ms=50)
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("observation_gap_over_limit", result["reasons"])
        self.assertGreater(result["max_gap_ms"], 50)

    def test_nan_is_invalid(self):
        frames = self.frames()
        frames[0]["energy"][0] = float("nan")
        with self.assertRaises(GRID.InvalidLog):
            GRID.parse_log(self.write_log("nan.jsonl", frames))

    def test_duplicate_tick_is_invalid(self):
        frames = self.frames() + [self.frames()[0]]
        with self.assertRaises(GRID.InvalidLog):
            GRID.parse_log(self.write_log("duplicate.jsonl", frames))

    def test_unknown_region_bit_is_invalid(self):
        frames = self.frames()
        frames[0]["regions"][0] = 8
        with self.assertRaises(GRID.InvalidLog):
            GRID.parse_log(self.write_log("unknown.jsonl", frames))

    def test_mixed_unknown_region_cannot_pass(self):
        regions = self.regions()
        regions[0] = 3
        result = self.result(self.frames(regions=regions))
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("unknown_region_cells", result["reasons"])

    def test_all_saturated_reference_is_inconclusive(self):
        saturated = self.write_log("saturated-reference.jsonl",
                                  self.frames(raw_energy=[510.0] * 144))
        result = GRID.audit(GRID.parse_log(saturated),
                            GRID.parse_log(self.write_log("saturated-observation.jsonl",
                                                          self.frames(raw_energy=[510.0] * 144))))
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("all_reference_raw_energy_saturated", result["reasons"])

    def test_one_unobserved_other_cell_cannot_be_hidden_by_143_good_cells(self):
        regions = self.regions()
        regions[0] = 4
        self.reference = self.write_log("other-reference.jsonl", self.frames(regions=regions))
        result = self.result(self.frames(regions=regions))
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertGreater(result["unresolved_cells"], 0)

    def test_unmatched_shown_frame_is_not_dropped_even_with_five_good_pairs(self):
        frames = self.frames()
        extra = dict(frames[-1], tick=55)
        frames.append(extra)
        result = self.result(frames)
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("unmatched_shown_frames", result["reasons"])

    def test_zero_reference_cannot_prove_no_extra_blur(self):
        self.reference = self.write_log("zero-reference.jsonl", self.frames(ratio=0))
        result = self.result(self.frames(ratio=0))
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertIn("near_zero_reference_ratio_limits_stronger_blur_detection", result["reasons"])

    def test_idle_status_is_not_a_fake_frame_or_malformed_log(self):
        path = self.write_log("idle.jsonl", self.frames())
        text = path.read_text().replace("MEASURE DONE", "GRID STATUS raw 5 1\nMEASURE DONE")
        path.write_text(text)
        parsed = GRID.parse_log(path)
        self.assertEqual(len(parsed["frames"]["raw"]), 5)



if __name__ == "__main__":
    unittest.main()
