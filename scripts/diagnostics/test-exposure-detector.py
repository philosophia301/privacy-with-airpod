#!/usr/bin/env python3
"""Regression contracts for missed displayed frames and incomplete observations."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("detector", Path(__file__).with_name("detect-blur-exposure.py"))
detector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detector)


class ExposureTests(unittest.TestCase):
    def frame(self, energy, regions=None):
        return {"PROFILE": energy, "REGIONS": regions or [1] * 16}

    def test_one_exposed_incoming_region_is_not_hidden_by_blurred_majority(self):
        result = detector.report({100: self.frame([0] * 15 + [100])}, [100] * 16)
        self.assertEqual(result["region_counts"]["exposed"], 1)
        self.assertEqual(result["exposed_frames"], 1)
        self.assertEqual(result["verdict"], "exposure_detected")

    def test_mixed_boundary_does_not_hide_neighboring_clear_region(self):
        states = detector.classify(self.frame([100] * 16, [3, 2] + [1] * 14), [100] * 16)
        self.assertEqual(states[0], "unknown")
        self.assertEqual(states[1], "exposed")

    def test_ambiguous_contrast_and_missing_data_cannot_establish_protection(self):
        result = detector.report({100: self.frame([40] * 16), 101: {}}, [100] * 16)
        self.assertEqual(result["region_counts"]["uncertain"], 16)
        self.assertEqual(result["region_counts"]["unknown"], 16)
        self.assertEqual(result["verdict"], "not_established")

    def test_blurred_negative_control_has_no_exposure_but_no_physical_guarantee(self):
        result = detector.report({100: self.frame([1] * 16)}, [100] * 16)
        self.assertEqual(result["region_counts"]["blurred"], 16)
        self.assertEqual(result["exposed_frames"], 0)
        self.assertEqual(result["verdict"], "not_established")

    def test_single_displayed_frame_without_matching_raw_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.log"
            path.write_text("MEASURE READY probe 100\n"
                            "PROFILE shown 101 " + ",".join(["100"] * 16) + "\n"
                            "REGIONS shown 101 " + ",".join(["2"] * 16) + "\n"
                            "MEASURE DONE probe\n")
            _, frames = detector.read_frames(path)
            self.assertEqual(detector.report(frames, [100] * 16)["exposed_frames"], 1)

    def test_incomplete_capture_and_nan_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.log"
            for text in ["MEASURE READY probe 100\n",
                         "MEASURE READY probe 100\nPROFILE shown 101 " + ",".join(["nan"] * 16) + "\nMEASURE DONE probe\n"]:
                path.write_text(text)
                with self.assertRaises(ValueError):
                    detector.read_frames(path)

    def test_duplicate_metric_cannot_overwrite_exposure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.log"
            path.write_text("MEASURE READY probe 100\n" +
                            "PROFILE shown 101 " + ",".join(["100"] * 16) + "\n" +
                            "PROFILE shown 101 " + ",".join(["0"] * 16) + "\n" +
                            "MEASURE DONE probe\n")
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                detector.read_frames(path)

    def test_fault_validation_requires_recovery_and_rejects_unobserved_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "probe.log"
            path.write_text("CLOCK 1000000 1\nFAULT BEGIN 100\nFAULT END 300\n")
            frames = {50: self.frame([1] * 16), 150: self.frame([100] * 16)}
            with self.assertRaisesRegex(ValueError, "recovery"):
                detector.verify_fault_pulse(path, frames, [100] * 16)
            frames[400] = self.frame([1] * 16)
            self.assertEqual(detector.verify_fault_pulse(path, frames, [100] * 16)["detected_frames"], 1)
            frames[200] = {}
            with self.assertRaisesRegex(ValueError, "unobserved"):
                detector.verify_fault_pulse(path, frames, [100] * 16)


if __name__ == "__main__":
    unittest.main()
