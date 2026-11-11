#!/usr/bin/env python3
"""Run bounded fast completed Space transitions against the supplied probe."""

import argparse, math, os, plistlib, re, shutil, signal, subprocess, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
APP = Path("/tmp/Privacy Private Transition.app")
TEMPLATE = Path("/tmp/PrivacyPattern-a.app")
FIXTURE = Path("/tmp/privacy-pattern-fixture-metal")
GESTURE = ROOT / ".build/gesture-hold/gesture-hold"
IDENTITY = ROOT / ".build/signing-identity"
MODE_FILE = Path("/tmp/privacy-private-measure-mode")
FIXTURE_ROOT = Path("/tmp")
NAMES = ("a", "b", "c", "d")
def process_entries():
    output = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
    entries = []
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2:
            try:
                entries.append((int(fields[0]), Path(fields[1])))
            except ValueError:
                pass
    return entries
def matching(paths):
    wanted = {path.resolve() for path in paths}
    return [(pid, path) for pid, path in process_entries() if path.resolve() in wanted]
def terminate_fixture_processes(paths, force=True):
    for pid, _ in matching(paths):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and matching(paths):
        time.sleep(.1)
    survivors = matching(paths)
    if force:
        for pid, _ in survivors:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    return survivors
def validate(args):
    probe = args.probe_executable.resolve()
    if not probe.is_file() or not os.access(probe, os.X_OK):
        raise ValueError("probe executable must be an executable file")
    for path, label in ((FIXTURE, "fixture"), (GESTURE, "gesture executable"),
                        (TEMPLATE, "fixture template"), (APP, "probe app"), (IDENTITY, "signing identity")):
        if not path.exists():
            raise ValueError(f"Missing {label}: {path}")
    if not IDENTITY.read_text().strip():
        raise ValueError("Signing identity is empty")
    if args.output_dir.exists():
        raise ValueError("output-dir must be a new directory")
    probe_target = APP / "Contents/MacOS/PrivacyPrivateTransition"
    if matching((probe, probe_target)):
        raise RuntimeError("probe already running")
    modes = [mode.strip() for mode in args.modes.split(",") if mode.strip()]
    if (not modes or len(set(modes)) != len(modes) or
            any(not re.fullmatch(r"[A-Za-z0-9_-]+", mode) for mode in modes)):
        raise ValueError("modes must be a non-empty CSV of safe mode names")
    args.probe_executable = probe
    args.modes = modes
def prepare_probe(probe):
    target = APP / "Contents/MacOS/PrivacyPrivateTransition"
    if matching((probe, target)):
        raise RuntimeError("probe already running")
    if not (APP / "Contents/Info.plist").is_file():
        raise ValueError("probe app metadata is missing")
    shutil.copy2(probe, target)
    identity = IDENTITY.read_text().strip()
    subprocess.run(["codesign", "--force", "--sign", identity, str(APP)], check=True)
    return target
def prepare_fixtures():
    targets = [FIXTURE_ROOT / f"PrivacyPattern-{name}.app" for name in NAMES]; binaries = [target / "Contents/MacOS" / f"PrivacyPattern-{name}" for target, name in zip(targets, NAMES)]
    template_info = plistlib.loads((TEMPLATE / "Contents/Info.plist").read_bytes())
    terminate_fixture_processes(binaries)
    for target in targets:
        if target.exists():
            shutil.rmtree(target)
    for name, target, binary in zip(NAMES, targets, binaries):
        (target / "Contents/MacOS").mkdir(parents=True)
        info_path = target / "Contents/Info.plist"
        info = dict(template_info)
        suffix = ".b" if name in ("b", "d") else ".a"
        info.update(CFBundleExecutable=f"PrivacyPattern-{name}",
                    CFBundleIdentifier=f"local.privacy-pattern.{name}{suffix}",
                    CFBundleName=f"Privacy Pattern {name}")
        info_path.write_bytes(plistlib.dumps(info))
        binary.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(FIXTURE, binary)
        subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True)
    return targets, binaries
def activate_fixture(target):
    subprocess.run(["open", "-a", str(target)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
def launch_fixtures(targets, output_dir):
    for target in targets:
        name = target.stem.rsplit("-", 1)[1]
        subprocess.run(["open", "-n", "-g", "--stdout", str(output_dir / f"fixture-{name}.log"),
                        "--stderr", str(output_dir / f"fixture-{name}-errors.log"), str(target),
                        "--args", "--metal"], check=True)
        wait_ready(output_dir / f"fixture-{name}.log", "FIXTURE READY")
        time.sleep(3)
def wait_ready(log, marker, process=None):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        text = log.read_text() if log.exists() else ""
        if marker in text:
            return
        if "FAIL" in text or (process is not None and process.poll() is not None):
            raise RuntimeError(f"process failed before READY: {marker}")
        time.sleep(.1)
    raise TimeoutError(f"READY timeout: {marker}")
def run_gesture(amount, event_file, activation_target, offset_ms, hold_cancel=False):
    process = subprocess.Popen([str(GESTURE), amount, *([] if hold_cancel else ["--fast"])], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    for line in process.stdout:
        event_file.write(line)
        event_file.flush()
        if activation_target is not None and line.startswith("GESTURE END "):
            time.sleep(offset_ms / 1000)
            activate_fixture(activation_target)
    if process.wait() != 0:
        raise RuntimeError(f"gesture failed: {amount}")
def run_mode(mode, args, output_dir, targets, probe_processes):
    activate_fixture(targets[0])
    time.sleep(3)
    MODE_FILE.write_text(mode + "\n")
    log = output_dir / f"probe-{mode}.log"
    errors = output_dir / f"probe-{mode}-errors.log"
    gesture_log = output_dir / f"gesture-{mode}-events.log"
    process = subprocess.Popen(["open", "-n", "-g", "-W", "--stdout", str(log), "--stderr", str(errors), str(APP), *(["--args", *args.probe_arg] if args.probe_arg else [])])
    probe_processes.append(process)
    wait_ready(log, f"MEASURE READY {mode} ", process)
    if mode == "fixedangle":
        time.sleep(1)
    amounts = (["0.65", "-0.65"] * 8 if args.screens == 2 else ["0.65"] * 3 + ["-0.65"] * 3)
    if args.screens == 4:
        amounts *= 2
    if args.hold_cancel:
        amounts = ["0.45", "0.65", "-0.45"]
    current = 0
    with gesture_log.open("w") as events:
        for amount in amounts:
            direction = 1 if float(amount) > 0 else -1
            destination = max(0, min(len(targets) - 1, current + direction))
            target = targets[destination] if args.activation_race else None
            run_gesture(amount, events, target, args.activation_offset_ms,
                        args.hold_cancel and abs(float(amount)) == .45)
            current = destination
            time.sleep(.35)
    if process.wait(timeout=30) != 0:
        raise RuntimeError(f"probe exited nonzero: {mode}")
    text = log.read_text()
    if f"MEASURE READY {mode} " not in text or f"MEASURE DONE {mode}" not in text:
        raise RuntimeError(f"probe lifecycle incomplete: {mode}")
    observed = [int(line.split()[2]) for line in text.splitlines() if line.startswith("MEASURE shown ")]
    completed = [int(line.split()[2]) for line in gesture_log.read_text().splitlines() if line.startswith("GESTURE DONE ")]
    if not observed or len(completed) != len(amounts) or max(completed) > max(observed):
        raise RuntimeError("Gesture sequence was not fully covered by the observation")
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe-executable", type=Path, required=True)
    parser.add_argument("--probe-arg", action="append", default=[], help="argument passed to the isolated probe")
    parser.add_argument("--modes", required=True, help="comma-separated probe modes")
    parser.add_argument("--screens", type=int, choices=(2, 4), required=True)
    parser.add_argument("--hold-cancel", action="store_true", help="two opposite intermediate holds from adjacent fixtures followed by cancellation")
    parser.add_argument("--activation-race", action="store_true")
    parser.add_argument("--activation-offset-ms", type=float, default=0,
                        help="delay after GESTURE END before activation")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if not math.isfinite(args.activation_offset_ms) or args.activation_offset_ms < 0:
        parser.error("--activation-offset-ms must be nonnegative")
    if args.hold_cancel and args.activation_race:
        parser.error("--hold-cancel cannot be combined with --activation-race")
    validate(args)
    args.output_dir.mkdir(parents=True)
    previous_mode = MODE_FILE.read_bytes() if MODE_FILE.exists() else None
    targets = [FIXTURE_ROOT / f"PrivacyPattern-{name}.app" for name in NAMES]; binaries = [target / "Contents/MacOS" / f"PrivacyPattern-{name}" for target, name in zip(targets, NAMES)]
    started_probe_target = None; cleanup_error = False
    probe_processes = []
    try:
        targets, binaries = prepare_fixtures()
        started_probe_target = prepare_probe(args.probe_executable)
        launch_fixtures(targets[:args.screens], args.output_dir)
        for mode in args.modes:
            run_mode(mode, args, args.output_dir, targets[:args.screens], probe_processes)
    finally:
        for process in probe_processes:
            if process.poll() is None:
                process.terminate()
        if started_probe_target is not None:
            survivors = terminate_fixture_processes((started_probe_target,), force=False)
            if survivors:
                print("PROBE_CLEANUP_FAILED", file=sys.stderr); cleanup_error = True
        terminate_fixture_processes(binaries)
        if previous_mode is None:
            MODE_FILE.unlink(missing_ok=True)
        else:
            MODE_FILE.write_bytes(previous_mode)
    if cleanup_error:
        raise RuntimeError("probe survived SIGTERM; refusing SIGKILL")
if __name__ == "__main__":
    main()
