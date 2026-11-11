#!/usr/bin/env python3
"""Synthetic contracts for the raw/shown transition evidence audit."""

import importlib.util
import math
from pathlib import Path
import unittest


_SPEC = importlib.util.spec_from_file_location(
    "transition_audit", Path(__file__).with_name("audit-transition.py")
)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError("Unable to load audit-transition.py")
_AUDIT = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_AUDIT)


class TransitionAuditTests(unittest.TestCase):
    baseline = [100.0] * 16
    protected = [1, 2, 3, 4]
    seconds_per_tick = 0.01

    def frame(self, scene_value=1, energy=0.0, mixed=False):
        """Build metrics in the same bit-mask shape as the transition probe."""
        regions = [scene_value] * 16
        if mixed:
            # 3 is the probe's green+magenta boundary marker (1|2).
            regions[2] = 3
        return {"PROFILE": [float(energy)] * 16,
                "REGIONS": [float(value) for value in regions]}

    def transition(self, terminal="end", shown_energy=0.0, tail_end=30):
        """One 10..25 gesture, sampled every 10ms through its 50ms tail."""
        raw, shown = {}, {}
        final_scene = 1 if terminal == "cancel" else 2
        for tick in range(0, tail_end + 1):
            if tick <= 10:
                raw[tick] = self.frame(1, 100.0)
                shown[tick] = self.frame(1, shown_energy)
            elif tick < 20:
                raw[tick] = self.frame(1, 100.0, mixed=True)
                # During a mixed raw frame the displayed scene is allowed to
                # remain the source; stale detection only uses pure raw bins.
                shown[tick] = self.frame(1, shown_energy)
            else:
                raw[tick] = self.frame(final_scene, 100.0)
                shown[tick] = self.frame(final_scene, shown_energy)
        cycle = {"begin": 10, "terminal": (terminal, 20), "done": 25,
                 "interrupted": 0}
        return raw, shown, [cycle]

    def audit_result(self, raw, shown, cycles, **kwargs):
        return _AUDIT.audit(raw, shown, cycles, self.baseline,
                            self.seconds_per_tick, self.protected, **kwargs)

    def assert_result_shape(self, result):
        for key in ("verdict", "exposure_frames", "stale_scene_frames",
                    "validity_issues", "gestures"):
            self.assertIn(key, result)
        self.assertIsInstance(result["exposure_frames"], int)
        self.assertIsInstance(result["stale_scene_frames"], list)
        self.assertIsInstance(result["validity_issues"], list)
        self.assertIsInstance(result["gestures"], list)

    def test_one_exposed_shown_frame_is_regression(self):
        raw, shown, cycles = self.transition()
        shown[22] = self.frame(2, 100.0)

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertEqual(result["exposure_frames"], 1)
        self.assertEqual(result["stale_scene_frames"], [])

    def test_raw_without_any_motion_is_inconclusive(self):
        raw, shown, cycles = self.transition()
        for tick in raw:
            raw[tick] = self.frame(1, 100.0)
            shown[tick] = self.frame(1, 0.0)

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertTrue(result["validity_issues"])
        self.assertEqual(len(result["gestures"]), 1)

    def test_cancel_with_mixed_motion_and_return_to_source_is_valid(self):
        raw, shown, cycles = self.transition(terminal="cancel")

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"],
                         "no_regression_detected_in_observed_strip")
        self.assertEqual(result["exposure_frames"], 0)
        self.assertEqual(result["stale_scene_frames"], [])
        self.assertEqual(result["validity_issues"], [])
        self.assertEqual(len(result["gestures"]), 1)

    def test_unknown_or_uncertain_protected_frame_is_inconclusive(self):
        unknown = self.frame(2, 0.0)
        unknown["REGIONS"][2] = 3.0
        for label, frame in (
            ("unknown", unknown),
            ("uncertain", self.frame(2, 40.0)),
        ):
            with self.subTest(label=label):
                raw, shown, cycles = self.transition()
                shown[22] = frame

                result = self.audit_result(raw, shown, cycles)

                self.assert_result_shape(result)
                self.assertEqual(result["verdict"], "inconclusive")
                self.assertTrue(result["validity_issues"])

    def test_missing_post_done_settle_tail_is_inconclusive(self):
        raw, shown, cycles = self.transition(tail_end=29)

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertTrue(result["validity_issues"])
        self.assertTrue(any("missing" in issue.lower()
                            for issue in result["validity_issues"]))

    def test_observation_gap_over_limit_is_inconclusive(self):
        raw, shown, cycles = self.transition()
        for tick in range(14, 21):
            del raw[tick]
            del shown[tick]

        result = self.audit_result(raw, shown, cycles, max_gap_ms=50)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertTrue(any("gap" in issue.lower()
                            for issue in result["validity_issues"]))

    def test_stale_opposite_scene_after_settle_is_regression(self):
        raw, shown, cycles = self.transition()
        # Raw has been pure destination since tick 20 and has remained there
        # for the complete done+settle interval.  Tick 30 is stale source.
        shown[30] = self.frame(1, 0.0)

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertEqual(result["exposure_frames"], 0)
        self.assertEqual(result["stale_scene_frames"], [30])

    def test_late_stale_scene_after_done_settle_is_still_regression(self):
        raw, shown, cycles = self.transition(tail_end=45)
        # DONE is tick 25 and settle is 50ms = 5 ticks.  Keep observing after
        # that boundary so an audit cannot silently stop at tick 30.
        shown[40] = self.frame(1, 0.0)

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "regression_detected")
        self.assertIn(40, result["stale_scene_frames"])

    def test_gap_after_done_settle_is_inconclusive(self):
        raw, shown, cycles = self.transition(tail_end=45)
        # The 60ms hole from tick 30 to tick 36 is entirely after the
        # required DONE+settle boundary, but still invalidates the tail.
        for tick in range(31, 36):
            del raw[tick]
            del shown[tick]

        result = self.audit_result(raw, shown, cycles, max_gap_ms=50)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertTrue(any("gap" in issue.lower()
                            for issue in result["validity_issues"]))

    def test_good_end_transition_has_no_regression_in_observed_strip(self):
        raw, shown, cycles = self.transition()

        result = self.audit_result(raw, shown, cycles)

        self.assert_result_shape(result)
        self.assertEqual(result["verdict"],
                         "no_regression_detected_in_observed_strip")
        self.assertEqual(result["exposure_frames"], 0)
        self.assertEqual(result["stale_scene_frames"], [])
        self.assertEqual(result["validity_issues"], [])

    def test_nonfinite_clock_and_invalid_protected_bins_are_rejected(self):
        raw, shown, cycles = self.transition()
        for seconds in (0.0, -0.01, math.inf, math.nan):
            with self.subTest(seconds=seconds):
                with self.assertRaises(ValueError):
                    _AUDIT.audit(raw, shown, cycles, self.baseline, seconds,
                                 self.protected)

        for bins in ([], [1, 1], [-1], [16], [1.0]):
            with self.subTest(bins=bins):
                with self.assertRaises(ValueError):
                    _AUDIT.audit(raw, shown, cycles, self.baseline,
                                 self.seconds_per_tick, bins)


if __name__ == "__main__":
    unittest.main()
