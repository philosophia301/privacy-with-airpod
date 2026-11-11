#!/usr/bin/env python3
"""Regression tests for fixedangle gesture-window exposure analysis."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


_SPEC = importlib.util.spec_from_file_location("fixed_mask", Path(__file__).with_name("analyze-fixed-mask.py"))
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)


class FixedMaskTests(unittest.TestCase):
    def write_logs(self, directory, profiles, regions=None, gesture=None, mode="fixedangle"):
        regions = regions or [[1] * 16 for _ in profiles]
        observation = Path(directory) / "observation.log"
        lines = ["CLOCK 1000000 1", f"MEASURE READY {mode} 0"]
        for timestamp, values, region in zip(range(1, len(profiles) + 1), profiles, regions):
            lines.append(f"PROFILE shown {timestamp} {','.join(map(str, values))}")
            lines.append(f"REGIONS shown {timestamp} {','.join(map(str, region))}")
        lines.append(f"MEASURE DONE {mode}")
        observation.write_text("\n".join(lines) + "\n")

        baseline = Path(directory) / "baseline.log"
        baseline_lines = ["MEASURE READY off 0"]
        for timestamp in range(1, 7):
            values = ["100"] * 16
            baseline_lines.append(f"PROFILE shown {timestamp} {','.join(values)}")
            baseline_lines.append(f"REGIONS shown {timestamp} {','.join(['1'] * 16)}")
        baseline_lines.append("MEASURE DONE off")
        baseline.write_text("\n".join(baseline_lines) + "\n")

        gesture_path = Path(directory) / "gesture.log"
        gesture_path.write_text(gesture or "GESTURE BEGIN 1 0.5\nGESTURE END 3\nGESTURE DONE 4 interrupted=0\n")
        return baseline, gesture_path, observation

    def frame_values(self, protected, other=1):
        return [protected if index < 4 else other for index in range(16)]

    def test_clear_right_bin_is_excluded_from_protected_result(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline, gesture, observation = self.write_logs(
                directory,
                [self.frame_values(1, 100), self.frame_values(1, 100)],
                gesture="GESTURE BEGIN 1 0.5\nGESTURE END 2\nGESTURE DONE 3 interrupted=0\n",
            )
            result = _MODULE.analyze(baseline, gesture, [0, 1, 2, 3], observation)
            self.assertEqual(result["exposed_frame_count"], 0)
            self.assertEqual(result["protected_counts"]["blurred"], 8)
            self.assertEqual(result["protected_counts"]["exposed"], 0)

    def test_exposed_left_bins_are_reported_with_signed_end_distance(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline, gesture, observation = self.write_logs(
                directory,
                [self.frame_values(100, 1)],
                gesture="GESTURE BEGIN 0 0.5\nGESTURE END 2\nGESTURE DONE 3 interrupted=0\n",
            )
            result = _MODULE.analyze(baseline, gesture, [0, 1, 2, 3], observation)
            self.assertEqual(result["exposed_frame_count"], 1)
            self.assertEqual(result["exposed_frames"][0]["bins"], [0, 1, 2, 3])
            self.assertEqual(result["exposed_frames"][0]["nearest_end_signed_ms"], -1.0)

    def test_unknown_protected_bin_is_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline, gesture, observation = self.write_logs(
                directory,
                [self.frame_values(100, 1)],
                regions=[[3, 1, 1, 1] + [1] * 12],
                gesture="GESTURE BEGIN 1 0.5\nGESTURE END 2\nGESTURE DONE 3 interrupted=0\n",
            )
            result = _MODULE.analyze(baseline, gesture, [0, 1], observation)
            self.assertEqual(result["protected_counts"]["unknown"], 1)
            self.assertEqual(result["protected_counts"]["exposed"], 1)
            self.assertEqual(result["exposed_frames"][0]["bins"], [1])

    def test_incomplete_gesture_lifecycle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline, gesture, observation = self.write_logs(
                directory,
                [self.frame_values(1, 1)],
                gesture="GESTURE BEGIN 1 0.5\nGESTURE HOLD 2\n",
            )
            with self.assertRaisesRegex(ValueError, "Incomplete gesture"):
                _MODULE.analyze(baseline, gesture, [0, 1, 2, 3], observation)


if __name__ == "__main__":
    unittest.main()
