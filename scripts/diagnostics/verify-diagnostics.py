#!/usr/bin/env python3
"""Parallel offline diagnostics with content-addressed successful-result caching."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def source_files(root=ROOT):
    here = root / "scripts/diagnostics"
    paths = set()
    for suffix in ("*.py", "*.swift", "*.m", "*.h"):
        paths.update(here.glob(suffix))
    paths.update(p for p in (here / "fixtures").rglob("*") if p.is_file())
    for directory in (root / "Sources", root / "Tests"):
        paths.update(p for p in directory.rglob("*") if p.suffix in (".swift", ".m", ".h"))
    paths.add(root / "Package.swift")
    return sorted(paths)


def source_fingerprint(root=ROOT):
    return digest(encoded([(str(p.relative_to(root)), digest(p.read_bytes())) for p in source_files(root)]))


def snapshot_tasks(tasks, destination, expected_hash):
    for path in source_files():
        target = destination / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
    if source_fingerprint(destination) != expected_hash:
        raise ValueError("Sources changed while creating immutable test snapshot")
    commands = []
    for task in tasks:
        mapping = {}
        input_hashes = []
        for path_string in task["inputs"]:
            path = Path(path_string)
            try:
                target = destination / path.relative_to(ROOT)
            except ValueError:
                target = destination / "inputs" / digest(path_string.encode()) / path.name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            if digest(target.read_bytes()) != digest(path.read_bytes()):
                raise ValueError("Input changed while creating test snapshot")
            mapping[path_string] = str(target)
            input_hashes.append((path_string, digest(target.read_bytes())))
        commands.append(([mapping.get(arg, str(destination / Path(arg).relative_to(ROOT))
                         if arg.startswith(str(ROOT) + "/") else arg) for arg in task["command"]], input_hashes))
    return commands


@lru_cache(maxsize=1)
def toolchain_identity():
    result = subprocess.run(["swiftc", "--version"], capture_output=True, text=True)
    if result.returncode != 0:
        raise ValueError("Swift compiler identity unavailable")
    compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()).resolve()
    return result.stdout + result.stderr + str(compiler) + digest(compiler.read_bytes())


def cache_key(task, source_hash, input_hashes=None):
    return digest(encoded({"format": 1, "sources": source_hash, "python": sys.version,
                           "executable": str(Path(sys.executable).resolve()), "swift": toolchain_identity(), "platform": platform.platform(),
                           "environment": digest(encoded(dict(os.environ))), "task": task, "inputs": input_hashes if input_hashes is not None else [(p, digest(Path(p).read_bytes())) for p in task["inputs"]]}))


def accepted(task, result):
    if task["kind"] == "test":
        counts = re.findall(r"Ran (\d+) tests? in", result["stderr"] + result["stdout"])
        return result["returncode"] == 0 and bool(counts) and sum(map(int, counts)) > 0
    try:
        report = json.loads(result["stdout"])
    except (ValueError, TypeError):
        return False
    return (isinstance(report, dict) and report.get("verdict") == task["expected_verdict"]
            and result["returncode"] == task["expected_exit"]
            and all(report.get(k) == v for k, v in task.get("expected_fields", {}).items()))


def write_receipt(cache_dir, key, result):
    cache_dir.mkdir(parents=True, exist_ok=True)
    entry = {"key": key, "result": result, "digest": digest(encoded(result))}
    with tempfile.NamedTemporaryFile(mode="w", dir=cache_dir, delete=False) as file:
        json.dump(entry, file)
        temporary = file.name
    os.replace(temporary, cache_dir / (key + ".json"))


def run_task(task, source_hash, cache_dir, fresh=False, timeout=120, defer_cache=False, execution_command=None, input_hashes=None):
    key = cache_key(task, source_hash, input_hashes)
    path = cache_dir / (key + ".json")
    if not fresh:
        try:
            entry = json.loads(path.read_text())
            result = entry["result"]
            if entry["key"] == key and entry["digest"] == digest(encoded(result)) and accepted(task, result):
                return {"id": task["id"], "ok": True, "cached": True, "key": key, "result": result}
        except (OSError, ValueError, KeyError, TypeError):
            pass
    began = time.monotonic()
    try:
        # The source/input key also namespaces bytecode; same-mtime edits cannot reuse older .pyc.
        bytecode = cache_dir / "bytecode" / key
        command = execution_command or task["command"]
        command = [command[0], "-X", "pycache_prefix=" + str(bytecode.resolve()), *command[1:]]
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
        result = {"returncode": process.returncode, "stdout": process.stdout, "stderr": process.stderr,
                  "duration_seconds": time.monotonic() - began}
    except subprocess.TimeoutExpired:
        result = {"returncode": -1, "stdout": "", "stderr": "Diagnostic timed out", "duration_seconds": time.monotonic() - began}
    ok = accepted(task, result)
    if ok and not defer_cache:
        write_receipt(cache_dir, key, result)
    elif not ok:
        # A failed fresh run invalidates any prior successful receipt under this same key.
        path.unlink(missing_ok=True)
    return {"id": task["id"], "ok": ok, "cached": False, "key": key, "result": result}


def tasks_for(manifest=None):
    tasks = [{"id": p.stem, "kind": "test", "command": [sys.executable, str(p)], "inputs": []}
             for p in sorted(HERE.glob("test-*.py"))]
    if manifest:
        entries = json.loads(manifest.read_text())
        if not isinstance(entries, list):
            raise ValueError("Replay manifest must be an array")
        for entry in entries:
            kind = entry.get("kind", "transition")
            if kind not in ("transition", "grid"):
                raise ValueError("Unknown replay kind")
            names = ["reference", "observation"] if kind == "grid" else ["baseline", "gesture", "observation"]
            paths = {name: str((manifest.parent / entry[name]).resolve()) for name in names}
            if kind == "grid":
                command = [sys.executable, str(HERE / "audit-grid.py"), "--reference", paths["reference"], paths["observation"]]
            else:
                command = [sys.executable, str(HERE / "audit-transition.py"), "--clear-baseline", paths["baseline"],
                           "--gesture-log", paths["gesture"], "--protected-bins", entry["protected_bins"], paths["observation"]]
            verdict = entry["expected_verdict"]
            codes = {"regression_detected": 1, "inconclusive": 2, "invalid_observation": 2,
                     "no_regression_detected_in_observed_strip": 0, "no_regression_detected_in_observed_grid": 0}
            if verdict not in codes:
                raise ValueError("Unknown expected verdict")
            tasks.append({"id": entry["id"], "kind": "replay", "command": command, "inputs": list(paths.values()),
                          "expected_verdict": verdict, "expected_exit": codes[verdict], "expected_fields": entry.get("expected_fields", {})})
    ids = [task["id"] for task in tasks]
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate task IDs")
    return tasks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    parser.add_argument("--fresh", action="store_true", help="execute every task, bypassing cache reads")
    parser.add_argument("--cache-dir", type=Path, default=ROOT / ".build/diagnostic-cache")
    parser.add_argument("--replay-manifest", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 20:
        parser.error("jobs must be between 1 and 20")
    began = time.monotonic()
    try:
        tasks = tasks_for(args.replay_manifest)
        source_hash = source_fingerprint()
        with tempfile.TemporaryDirectory(prefix="privacy-diagnostic-snapshot-") as snapshot:
            commands = snapshot_tasks(tasks, Path(snapshot), source_hash)
            with ThreadPoolExecutor(max_workers=args.jobs) as pool:
                results = list(pool.map(lambda pair: run_task(pair[0], source_hash, args.cache_dir, args.fresh,
                                    defer_cache=True, execution_command=pair[1][0], input_hashes=pair[1][1]), zip(tasks, commands)))
        # Never publish receipts as current if source/input content changed during the run.
        stable = source_fingerprint() == source_hash and all(cache_key(t, source_hash) == r["key"] for t, r in zip(tasks, results))
        if stable:
            for item in results:
                if item["ok"] and not item["cached"]:
                    write_receipt(args.cache_dir, item["key"], item["result"])
        summary = {"ok": stable and all(r["ok"] for r in results), "inputs_stable": stable,
                   "wall_seconds": time.monotonic() - began, "jobs": args.jobs,
                   "cached": sum(r["cached"] for r in results), "executed": sum(not r["cached"] for r in results),
                   "tasks": results, "scope": "Offline code/log contracts only. Live GPU/OS/gesture results are never reused as current evidence."}
    except (OSError, ValueError, KeyError) as error:
        summary = {"ok": False, "error": str(error)}
    text = json.dumps(summary, indent=2)
    if args.output:
        args.output.write_text(text + "\n")
    print(text)
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
