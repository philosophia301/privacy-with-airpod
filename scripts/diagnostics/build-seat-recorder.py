#!/usr/bin/env python3
"""Build the seat motion recorder CLI. Does not touch the product app or its settings."""
import argparse
import platform
import plistlib
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, default=root / '.build' / 'seat-recorder')
parser.add_argument('--no-sign', action='store_true', help='skip the local development signature (offline tests)')
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
# 제품과 같은 최소 OS로 맞춤. CMHeadphoneActivityManager가 macOS 15부터 있음.
target = f'{platform.machine()}-apple-macos15.0'
common = ['swiftc', '-swift-version', '6', '-target', target]
# PrivacyCore는 의존이 없어 소스에서 바로 정적 라이브러리로 만듦. 앱 target과 Sparkle은 넣지 않음.
core = sorted((root / 'Sources/PrivacyCore').glob('*.swift'))
subprocess.run([*common, '-parse-as-library', '-emit-library', '-static', '-module-name', 'PrivacyCore',
                '-emit-module', '-emit-module-path', str(out / 'PrivacyCore.swiftmodule'),
                *map(str, core), '-o', str(out / 'libPrivacyCore.a')], check=True)
# 명령행 도구도 동작 접근 설명이 있어야 하므로 Info.plist를 실행 파일 안에 넣음.
info = out / 'Info.plist'
info.write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.privacy-with-airpod.seatrecorder',
    'CFBundleName': 'Seat Recorder',
    'NSMotionUsageDescription': '자리 이탈 판정 기준을 재려고 AirPods 머리 움직임과 걷기 판정을 기록함',
}))
binary = out / 'seat-recorder'
here = root / 'scripts/diagnostics'
subprocess.run([*common, '-parse-as-library', '-I', str(out), str(out / 'libPrivacyCore.a'),
                str(here / 'SeatRecording.swift'), str(here / 'SeatProtocol.swift'), str(here / 'SeatRecorder.swift'),
                '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__info_plist', '-Xlinker', str(info),
                '-o', str(binary)], check=True)
if not args.no_sign:
    identity = (root / '.build/signing-identity').read_text().strip()
    subprocess.run(['codesign', '--force', '--sign', identity, '--identifier', 'local.privacy-with-airpod.seatrecorder',
                    str(binary)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True)
print(binary)
