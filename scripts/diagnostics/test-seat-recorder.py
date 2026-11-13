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

    def test_default_replay_follows_protocol_and_every_checked_step_is_ok(self):
        report, verdicts = self.verdicts()
        for step in ("settle", "typing", "shift", "lean", "walk-away", "sit-after-walk", "walk-sit"):
            self.assertEqual(verdicts[step], "ok", step)
        for index in (1, 2, 3):
            self.assertEqual(verdicts[f"stand-{index}"], "ok")
            self.assertEqual(verdicts[f"sit-{index}"], "ok")
        self.assertEqual(verdicts["ready"], "unchecked")
        stand = next(step for step in report["steps"] if step["id"] == "stand-1")
        # 합성 일어섬은 1.5초 뒤 1.2초 동안 0.45m 오름. 일어섬은 상승 시작 0.3초쯤 잡히고 3초 뒤 자리 비움임.
        self.assertAlmostEqual(stand["awayAfter"], 4.8, delta=0.2)
        # 0.45m를 1.2초에 오르는 경로의 최고 속도는 0.59m/s이고, 속도 누수로 조금 줄어듦.
        self.assertTrue(0.45 <= stand["maxVelocity"] <= 0.7, stand["maxVelocity"])
        walk = next(step for step in report["steps"] if step["id"] == "walk-away")
        self.assertAlmostEqual(walk["awayAfter"], 3.5, delta=0.1)
        self.assertIn("자리 비움(걷기)", [event["kind"] for event in walk["events"]])
        self.assertEqual(report["counts"], {"ok": 13})
        self.assertEqual(report["data"]["gaps"], 0)
        self.assertEqual((report["data"]["droppedSamples"], report["data"]["sourceChanges"], report["data"]["lateSamples"]), (0, 0, 0))

    def test_tuning_flags_change_the_replayed_verdicts(self):
        report, verdicts = self.verdicts("--stand-speed", "2.0")
        self.assertEqual(report["tuning"]["standSpeed"], 2.0)
        for index in (1, 2, 3):
            self.assertEqual(verdicts[f"stand-{index}"], "missed")
            self.assertEqual(verdicts[f"sit-{index}"], "not-applicable")
        # 걷기 판정은 속도 기준과 상관없이 자리 비움으로 봄.
        self.assertEqual(verdicts["walk-away"], "ok")
        report, verdicts = self.verdicts("--standing-delay", "8")
        self.assertEqual(report["timing"]["standingDelay"], 8)
        stand = next(step for step in report["steps"] if step["id"] == "stand-1")
        self.assertAlmostEqual(stand["awayAfter"], 9.8, delta=0.2)
        # 15초 단계 안에서 일어섬이 잡힌 뒤 14초를 기다리면 자리 비움은 다음 단계로 밀림. 그러면 놓침임.
        _, verdicts = self.verdicts("--standing-delay", "14")
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
        self.assertEqual(report["counts"], {"ok": 7})

    def test_check_order_follows_the_third_protocol(self):
        path = self.dir / "check.csv"
        result = self.run_tool("synth", "--out", path, "--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_tool("replay", path, "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        ids = [step["id"] for step in report["steps"] if step["id"] not in ("ready", "end")]
        self.assertEqual(ids, ["settle", "seated-mix", "quick-stand-sit", "half-stand-1", "half-stand-2",
                               "walk-sit-1", "walk-sit-2", "walk-sit-pause", "walk-stop-level", "back-after-level",
                               "walk-stop-down", "back-after-down", "slow-stand", "slow-sit"])
        verdicts = {step["id"]: step["verdict"] for step in report["steps"]}
        self.assertEqual(verdicts["half-stand-1"], "unchecked")
        self.assertEqual(verdicts["half-stand-2"], "unchecked")
        checked = [step for step in ids if step not in ("half-stand-1", "half-stand-2")]
        # 한 단계씩 맞추지 않고 전체 판정을 한 번에 비교해, 틀린 단계가 여럿이면 모두 보이게 함.
        # 합성 천천히 앉기(2.5초 동안 0.45m)는 속도 최저가 앉음 기준 바로 아래라 못 돌아옴이 나옴. 알려진 한계로 고정해 둠.
        expected = {step: "ok" for step in checked}
        expected["slow-sit"] = "stuck"
        self.assertEqual({step: verdicts[step] for step in checked}, expected)
        self.assertEqual(report["counts"], {"ok": 11, "stuck": 1})

    def test_check_cannot_be_combined_with_quick_or_repeat(self):
        for flags in (["--check", "--quick"], ["--check", "--repeat", "2"]):
            result = self.run_tool("synth", "--out", self.dir / "combined.csv", *flags)
            self.assertEqual(result.returncode, 64, flags)
            self.assertFalse((self.dir / "combined.csv").exists())

    def test_text_report_lists_each_step_and_a_summary(self):
        result = self.run_tool("replay", self.recording)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stand-1  맞음  (기대: 자리 비움, 비움까지", result.stdout)
        self.assertRegex(result.stdout, r"stand-1  맞음.*\n    속도 최고 \+0\.\d\dm/s 최저 -\d\.\d\dm/s")
        self.assertNotIn("cm", result.stdout)
        self.assertIn("요약: 맞음 13, 놓침 0, 잘못 가림 0, 못 돌아옴 0, 해당 없음 0", result.stdout)
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
        for flags in (["--pairing", "1.5"], ["--step-interval-min", "1.0"], ["--sit-confirmation", "0"],
                      ["--standing-delay", "-1"], ["--stand-speed", "abc"], ["--unknown", "1"]):
            result = self.run_tool("replay", self.recording, *flags)
            self.assertEqual(result.returncode, 64, flags)


if __name__ == "__main__":
    unittest.main()
