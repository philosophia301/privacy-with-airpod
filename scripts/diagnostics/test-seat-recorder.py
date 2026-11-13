#!/usr/bin/env python3
"""Build the seat recorder and replay a synthetic recording, without AirPods or product settings."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class SeatRecorderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="seat-recorder-test-")
        cls.dir = Path(cls.temp.name)
        subprocess.run([sys.executable, str(HERE / "build-seat-recorder.py"), "--out", str(cls.dir / "build"), "--no-sign"],
                       check=True, capture_output=True)
        cls.tool = cls.dir / "build" / "seat-recorder"
        cls.recording = cls.dir / "synthetic.csv"
        subprocess.run([str(cls.tool), "synth", "--out", str(cls.recording)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_tool(self, *args):
        return subprocess.run([str(self.tool), *map(str, args)], capture_output=True, text=True)

    def verdicts(self, *flags):
        result = self.run_tool("replay", self.recording, "--json", *flags)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        return report, {step["id"]: step["verdict"] for step in report["steps"]}

    def test_default_replay_follows_protocol_and_shows_known_walk_sit_miss(self):
        report, verdicts = self.verdicts()
        for step in ("settle", "typing", "shift", "lean"):
            self.assertEqual(verdicts[step], "ok", step)
        for index in (1, 2, 3):
            self.assertEqual(verdicts[f"stand-{index}"], "ok")
            self.assertEqual(verdicts[f"sit-{index}"], "ok")
        self.assertEqual(verdicts["walk-away"], "ok")
        self.assertEqual(verdicts["sit-after-walk"], "ok")
        self.assertEqual(verdicts["walk-sit"], "stuck")
        self.assertEqual(verdicts["ready"], "unchecked")
        stand = next(step for step in report["steps"] if step["id"] == "stand-1")
        # 합성 일어섬은 1.5초 뒤 1.2초 동안 0.45m 오르고 정지 확인 뒤 3초를 기다림.
        self.assertAlmostEqual(stand["awayAfter"], 6.0, delta=0.2)
        self.assertAlmostEqual(stand["heightChanges"][0], 0.45, delta=0.03)
        # 걷기 판정은 일어선 뒤 3초를 기다리지 않고 바로 자리 비움으로 봄.
        walk = next(step for step in report["steps"] if step["id"] == "walk-away")
        self.assertAlmostEqual(walk["awayAfter"], 3.5, delta=0.1)
        self.assertIn("자리 비움(걷기)", [event["kind"] for event in walk["events"]])
        self.assertEqual(report["counts"], {"ok": 12, "stuck": 1})
        self.assertEqual(report["data"]["gaps"], 0)
        self.assertEqual((report["data"]["droppedSamples"], report["data"]["sourceChanges"], report["data"]["lateSamples"]), (0, 0, 0))

    def test_tuning_flags_change_the_replayed_verdicts(self):
        report, verdicts = self.verdicts("--stand-level", "0.5")
        self.assertEqual(report["tuning"]["standLevel"], 0.5)
        for index in (1, 2, 3):
            self.assertEqual(verdicts[f"stand-{index}"], "missed")
            self.assertEqual(verdicts[f"sit-{index}"], "not-applicable")
        # 걷기 판정은 높이 기준과 상관없이 자리 비움으로 봄.
        self.assertEqual(verdicts["walk-away"], "ok")
        report, verdicts = self.verdicts("--standing-delay", "8")
        self.assertEqual(report["timing"]["standingDelay"], 8)
        stand = next(step for step in report["steps"] if step["id"] == "stand-1")
        self.assertAlmostEqual(stand["awayAfter"], 11.0, delta=0.2)
        # 15초 단계 안에 3초 정도 걸리는 일어섬과 대기가 끝나지 않으면 놓침임.
        _, verdicts = self.verdicts("--standing-delay", "13")
        self.assertEqual(verdicts["stand-1"], "missed")

    def test_quick_order_keeps_only_stand_sit_and_walk_sit(self):
        path = self.dir / "quick.csv"
        result = self.run_tool("synth", "--out", path, "--quick", "--repeat", "2")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_tool("replay", path, "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        ids = [step["id"] for step in report["steps"] if step["expectation"] != "none"]
        self.assertEqual(ids, ["settle", "stand-1", "sit-1", "stand-2", "sit-2", "walk-sit-1", "walk-sit-2"])
        # 걷다 바로 앉기는 정지 구간 없이 앉아 지금 규칙으로는 돌아오지 못하는 알려진 경우임.
        # 그래서 두 번째는 자리 비움인 채 시작해 판정하지 않음.
        self.assertEqual(report["counts"], {"ok": 5, "stuck": 1, "not-applicable": 1})

    def test_text_report_lists_each_step_and_a_summary(self):
        result = self.run_tool("replay", self.recording)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stand-1  맞음  (기대: 자리 비움, 비움까지", result.stdout)
        self.assertIn("walk-sit  못 돌아옴", result.stdout)
        self.assertIn("요약: 맞음 12, 놓침 0, 잘못 가림 0, 못 돌아옴 1(walk-sit), 해당 없음 0", result.stdout)
        self.assertNotIn("ready", result.stdout.split("\n\n", 1)[1])

    def test_existing_files_are_never_overwritten(self):
        target = self.dir / "existing.csv"
        target.write_text("keep")
        for command in (["synth", "--out", target], ["record", "--out", target, "--no-voice", "--wait", "1"]):
            result = self.run_tool(*command)
            self.assertNotEqual(result.returncode, 0, command)
            self.assertIn("덮어쓰지 않음", result.stderr)
            self.assertEqual(target.read_text(), "keep")

    def test_input_the_app_would_not_use_is_counted(self):
        lines = self.recording.read_text().splitlines()
        motion = [i for i, line in enumerate(lines) if line.startswith("m,")]
        duplicate, switched = motion[10], motion[20]
        fields = lines[switched].split(",")
        fields[9] = "2"
        changed = lines[:switched] + [",".join(fields)] + lines[switched + 1:]
        changed.insert(duplicate + 1, lines[duplicate])
        path = self.dir / "input-issues.csv"
        path.write_text("\n".join(changed) + "\n")
        result = self.run_tool("replay", path, "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)["data"]
        self.assertEqual((data["droppedSamples"], data["sourceChanges"], data["lateSamples"]), (1, 2, 0))
        text = self.run_tool("replay", path).stdout
        self.assertIn("입력 주의: 센서 시각이 앞서지 않아 버린 표본 1개, 이어버드 바뀜 2번", text)

    def test_malformed_recordings_are_rejected(self):
        lines = self.recording.read_text().splitlines()
        cases = {
            "header": ["kind,rx"] + lines[1:],
            "columns": lines[:3] + ["m,1,2,3"],
            "order": lines[:4] + [lines[3].replace(lines[3].split(",")[1], "1.0", 1)],
            "nonfinite": lines[:3] + ["m,1e999,1,0,0,0,0,0,-1,1,,,,"],
        }
        for name, content in cases.items():
            path = self.dir / f"bad-{name}.csv"
            path.write_text("\n".join(content) + "\n")
            result = self.run_tool("replay", path)
            self.assertEqual(result.returncode, 65, (name, result.stdout, result.stderr))

    def test_invalid_tuning_is_rejected_before_reading(self):
        for flags in (["--stand-level", "0.1", "--sit-level", "0.2"], ["--still-duration", "0"],
                      ["--standing-delay", "-1"], ["--stand-level", "abc"], ["--unknown", "1"]):
            result = self.run_tool("replay", self.recording, *flags)
            self.assertEqual(result.returncode, 64, flags)


if __name__ == "__main__":
    unittest.main()
