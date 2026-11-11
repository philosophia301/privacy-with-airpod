#!/usr/bin/env python3
"""Build a pinned, isolated gesture diagnostic; no installation or event posting."""
import hashlib
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
out = root / ".build/gesture-hold"
out.mkdir(parents=True, exist_ok=True)
source = out / "dockswipe-reference.m"
revision = "1a761f6f47bdb3259bdbac5d207fefd82fe364d8"
expected = "e0ddcbf2d4d45809e3357f6c6a26f1dfdb4eb280457e9f2b2f1961873005860e"
if not source.exists():
    subprocess.run(["curl", "-fLsS", f"https://raw.githubusercontent.com/oomol-lab/dockswipe/{revision}/dockswipe.m", "-o", str(source)], check=True)
if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
    raise SystemExit("Upstream source hash differs; review before building")
subprocess.run(["clang", "-O2", "-Wall", "-framework", "CoreGraphics", "-framework", "ApplicationServices",
                f'-DDOCKSWIPE_REFERENCE="{source}"', str(root / "scripts/diagnostics/gesture-hold.m"),
                "-o", str(out / "gesture-hold")], check=True)
print(out / "gesture-hold")
