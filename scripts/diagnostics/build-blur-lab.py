#!/usr/bin/env python3
"""Build the isolated local Blur Lab. Does not replace or launch the product app."""
import plistlib
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / '.build' / 'blur-lab'
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['swift', 'build', '--target', 'PrivacyCore'], cwd=root, check=True)
subprocess.run(['swift', 'build', '--target', 'PrivacyBackdrop'], cwd=root, check=True)
bin_path = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
backdrop_build = bin_path / 'PrivacyBackdrop.build'
backdrop_object = backdrop_build / 'PrivacyBackdrop.m.o'
backdrop_modulemap = backdrop_build / 'module.modulemap'
if not backdrop_object.exists() or not backdrop_modulemap.exists():
    raise SystemExit('Build PrivacyBackdrop with swift build first')
objc = out / 'BackdropSPI.o'
subprocess.run([
    'clang', '-fobjc-arc', '-fmodules',
    f'-fmodule-map-file={backdrop_modulemap}', '-I', str(root / 'Sources/PrivacyBackdrop/include'),
    '-c', str(root / 'scripts/diagnostics/BackdropSPI.m'), '-o', str(objc)
], check=True)
objects = list((bin_path / 'PrivacyCore.build').glob('*.o'))
if not objects:
    raise SystemExit('Build PrivacyCore with swift build first')
sources = [p for p in (root / 'Sources/PrivacyAirPods').glob('*.swift') if p.name != 'PrivacyAirPodsApp.swift']
binary = out / 'PrivacyBlurLab'
subprocess.run([
    'swiftc', '-parse-as-library', '-import-objc-header', str(root / 'scripts/diagnostics/BackdropSPI.h'),
    '-I', str(bin_path / 'Modules'), '-I', str(backdrop_build),
    '-Xcc', f'-fmodule-map-file={backdrop_modulemap}', *map(str, sources),
    str(root / 'scripts/diagnostics/PrivateCover.swift'), str(root / 'scripts/diagnostics/BlurLab.swift'),
    str(objc), str(backdrop_object), *map(str, objects), '-o', str(binary)
], check=True)
app = out / 'Privacy AirPods Blur Lab.app'
executable = app / 'Contents/MacOS/PrivacyBlurLab'
executable.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(binary, executable)
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
info.update(CFBundleExecutable='PrivacyBlurLab', CFBundleIdentifier='local.privacy-with-airpod.blurlab',
            CFBundleName='Privacy AirPods Blur Lab', LSUIElement=True)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
identity = (root / '.build/signing-identity').read_text().strip()
subprocess.run(['codesign', '--force', '--sign', identity, str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
print(app)
