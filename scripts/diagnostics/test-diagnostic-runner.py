#!/usr/bin/env python3
"""Contract tests for the offline diagnostic runner's cache boundary."""

import importlib.util
import json
from pathlib import Path
import os
import sys
from concurrent.futures import ThreadPoolExecutor
import tempfile
import unittest


_SPEC = importlib.util.spec_from_file_location(
    "verify_diagnostics", Path(__file__).with_name("verify-diagnostics.py")
)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError("Unable to load verify-diagnostics.py")
_RUNNER = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_RUNNER)


class DiagnosticRunnerTests(unittest.TestCase):
    def helper_task(
        self,
        directory,
        *,
        summary_count=1,
        exit_code=0,
        inputs=(),
        record_runs=True,
        kind="test",
        stdout="",
        expected_verdict=None,
        expected_exit=None,
    ):
        """Return a test task backed by a real, tiny Python subprocess."""
        counter = Path(directory) / "runs.txt"
        summary_label = "test" if summary_count == 1 else "tests"
        script = (
            "from pathlib import Path; import sys; "
            + (
                "p=Path(sys.argv[1]); "
                "p.write_text(str(int(p.read_text()) + 1) if p.exists() else '1'); "
                if record_runs
                else ""
            )
            + f"print('Ran {summary_count} {summary_label} in 0.001s', file=sys.stderr); "
            + (f"print({stdout!r}); " if stdout else "")
            + f"raise SystemExit({exit_code})"
        )
        if record_runs:
            command = [sys.executable, "-c", script, str(counter)]
        else:
            command = [sys.executable, "-c", script]
        task = {
            "id": "helper",
            "kind": kind,
            "command": command,
            "inputs": [str(Path(path).resolve()) for path in inputs],
        }
        if expected_verdict is not None:
            task["expected_verdict"] = expected_verdict
        if expected_exit is not None:
            task["expected_exit"] = expected_exit
        return task, counter

    def run_diagnostic(self, task, source_hash, cache_dir, *, fresh=False):
        return _RUNNER.run_task(task, source_hash, Path(cache_dir), fresh=fresh)

    def test_valid_receipt_is_a_cache_hit_without_a_second_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            task, counter = self.helper_task(directory)
            cache_dir = Path(directory) / "cache"

            first = self.run_diagnostic(task, "source-v1", cache_dir)
            second = self.run_diagnostic(task, "source-v1", cache_dir)

            self.assertTrue(first["ok"])
            self.assertFalse(first["cached"])
            self.assertTrue(second["ok"])
            self.assertTrue(second["cached"])
            self.assertEqual(counter.read_text(), "1")
            self.assertEqual(first["key"], second["key"])

    def test_input_content_change_invalidates_even_with_same_size_and_mtime(self):
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "input.log"
            input_path.write_text("aaaa")
            original_mtime = input_path.stat().st_mtime_ns
            task, counter = self.helper_task(directory, inputs=(input_path,))
            cache_dir = Path(directory) / "cache"

            first = self.run_diagnostic(task, "source-v1", cache_dir)
            input_path.write_text("bbbb")
            os.utime(input_path, ns=(original_mtime, original_mtime))
            self.assertEqual(input_path.stat().st_size, 4)
            self.assertEqual(input_path.stat().st_mtime_ns, original_mtime)
            second = self.run_diagnostic(task, "source-v1", cache_dir)

            self.assertFalse(second["cached"])
            self.assertTrue(second["ok"])
            self.assertEqual(counter.read_text(), "2")
            self.assertNotEqual(first["key"], second["key"])

    def test_source_hash_change_invalidates_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            task, counter = self.helper_task(directory)
            cache_dir = Path(directory) / "cache"

            first = self.run_diagnostic(task, "source-v1", cache_dir)
            second = self.run_diagnostic(task, "source-v2", cache_dir)

            self.assertTrue(first["ok"])
            self.assertTrue(second["ok"])
            self.assertFalse(second["cached"])
            self.assertEqual(counter.read_text(), "2")
            self.assertNotEqual(first["key"], second["key"])

    def test_fresh_forces_execution_of_a_valid_cached_task(self):
        with tempfile.TemporaryDirectory() as directory:
            task, counter = self.helper_task(directory)
            cache_dir = Path(directory) / "cache"

            self.assertTrue(self.run_diagnostic(task, "source-v1", cache_dir)["ok"])
            fresh = self.run_diagnostic(task, "source-v1", cache_dir, fresh=True)

            self.assertTrue(fresh["ok"])
            self.assertFalse(fresh["cached"])
            self.assertEqual(counter.read_text(), "2")

    def test_failed_expectation_is_not_cached(self):
        with tempfile.TemporaryDirectory() as directory:
            task, counter = self.helper_task(
                directory,
                kind="replay",
                stdout='{"verdict":"unexpected"}',
                expected_verdict="expected",
                expected_exit=0,
            )
            cache_dir = Path(directory) / "cache"

            first = self.run_diagnostic(task, "source-v1", cache_dir)
            second = self.run_diagnostic(task, "source-v1", cache_dir)

            self.assertFalse(first["ok"])
            self.assertFalse(second["ok"])
            self.assertFalse(first["cached"])
            self.assertFalse(second["cached"])
            self.assertEqual(counter.read_text(), "2")
            self.assertFalse((cache_dir / (first["key"] + ".json")).exists())

    def test_corrupted_receipt_is_ignored_and_rerun(self):
        with tempfile.TemporaryDirectory() as directory:
            task, counter = self.helper_task(directory)
            cache_dir = Path(directory) / "cache"

            first = self.run_diagnostic(task, "source-v1", cache_dir)
            receipt = cache_dir / (first["key"] + ".json")
            receipt.write_text("not-json")
            second = self.run_diagnostic(task, "source-v1", cache_dir)

            self.assertTrue(second["ok"])
            self.assertFalse(second["cached"])
            self.assertEqual(counter.read_text(), "2")

    def test_parallel_duplicate_runs_have_consistent_results_and_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            task, _counter = self.helper_task(directory, record_runs=False)
            cache_dir = Path(directory) / "cache"

            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(
                    lambda _: self.run_diagnostic(task, "source-v1", cache_dir), range(4)
                ))

            self.assertTrue(all(result["ok"] for result in results))
            self.assertTrue(all(not result["cached"] for result in results))
            self.assertEqual({result["key"] for result in results}, {results[0]["key"]})
            projections = {
                (result["result"]["returncode"], result["result"]["stdout"], result["result"]["stderr"])
                for result in results
            }
            self.assertEqual(projections, {(0, "", "Ran 1 test in 0.001s\n")})

            cached = self.run_diagnostic(task, "source-v1", cache_dir)
            self.assertTrue(cached["cached"])
            self.assertTrue(cached["ok"])

    def test_duplicate_task_ids_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            for name in ("baseline", "gesture", "observation"):
                (Path(directory) / name).write_text("")
            manifest.write_text(json.dumps([{
                "id": "test-diagnostic-runner",
                "baseline": "baseline",
                "gesture": "gesture",
                "observation": "observation",
                "protected_bins": "0",
                "expected_verdict": "no_regression_detected_in_observed_strip",
            }]))

            with self.assertRaisesRegex(ValueError, "Duplicate task IDs"):
                _RUNNER.tasks_for(manifest)

    def test_empty_test_summary_with_exit_zero_is_not_cached(self):
        with tempfile.TemporaryDirectory() as directory:
            task, counter = self.helper_task(directory, summary_count=0)
            cache_dir = Path(directory) / "cache"

            first = self.run_diagnostic(task, "source-v1", cache_dir)
            second = self.run_diagnostic(task, "source-v1", cache_dir)

            self.assertFalse(first["ok"])
            self.assertFalse(second["ok"])
            self.assertFalse(first["cached"])
            self.assertFalse(second["cached"])
            self.assertEqual(counter.read_text(), "2")
            self.assertFalse((cache_dir / (first["key"] + ".json")).exists())

    def test_snapshot_input_is_used_after_original_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "input.txt"
            source.write_text("A")
            task = {"id": "snapshot", "kind": "test", "inputs": [str(source)],
                    "command": [sys.executable, "-c",
                                "import sys; print(open(sys.argv[1]).read()); print('Ran 1 test in 0.001s', file=sys.stderr)", str(source)]}
            fingerprint = _RUNNER.source_fingerprint()
            commands = _RUNNER.snapshot_tasks([task], root / "snapshot", fingerprint)
            source.write_text("B")
            result = _RUNNER.run_task(task, fingerprint, root / "cache", defer_cache=True,
                                      execution_command=commands[0][0], input_hashes=commands[0][1])
            self.assertTrue(result["ok"])
            self.assertEqual(result["result"]["stdout"].strip(), "A")
            self.assertNotEqual(result["key"], _RUNNER.cache_key(task, fingerprint))
            self.assertFalse((root / "cache" / (result["key"] + ".json")).exists())

    def test_inconsistent_source_snapshot_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "Sources changed"):
                _RUNNER.snapshot_tasks([], Path(directory), "wrong-fingerprint")

    def test_matching_verdict_with_wrong_exposure_count_is_not_success(self):
        task = {"kind": "replay", "expected_verdict": "regression_detected", "expected_exit": 1,
                "expected_fields": {"exposure_frames": 23}}
        result = {"returncode": 1, "stdout": json.dumps({"verdict": "regression_detected", "exposure_frames": 0}), "stderr": ""}
        self.assertFalse(_RUNNER.accepted(task, result))



if __name__ == "__main__":
    unittest.main()
