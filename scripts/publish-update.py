#!/usr/bin/env python3
"""공증한 DMG를 GitHub Release에 올리고 appcast.xml에 업데이트 항목을 추가함.

사용법:
  scripts/publish-update.py DMG [--required-below BUILD] [--notes TEXT]
  scripts/publish-update.py DMG --local-base-url URL --appcast PATH [--required-below BUILD]

--required-below BUILD는 BUILD보다 낮은 빌드를 필수 업데이트 대상으로 표시함. 앱은 이 표시가 있으면 설정 창을 막음.
한 번 정한 기준은 다음 항목에도 이어 붙임. Sparkle은 가장 새 항목의 표시만 보므로 이어 붙이지 않으면 오래된 앱이 풀림.
--local-base-url은 GitHub에 올리지 않고 로컬 서버 시험용 appcast만 씀.
appcast 변경의 커밋과 push는 이 스크립트가 하지 않음.
"""
import argparse
import email.utils
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = 'philosophia301/privacy-with-airpod'
SIGN_UPDATE = ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
KEY_ACCOUNT = 'privacy-airpods'
APP_NAME = 'Privacy AirPods.app'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def sparkle(tag):
    return f'{{{SPARKLE}}}{tag}'


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def bundle_info(dmg):
    """DMG 안의 실제 앱에서 판본을 읽고 서명을 확인함."""
    with tempfile.TemporaryDirectory() as mount:
        run('hdiutil', 'attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', mount, str(dmg))
        try:
            app = Path(mount) / APP_NAME
            run('codesign', '--verify', '--strict', '--deep', str(app))
            with open(app / 'Contents/Info.plist', 'rb') as file:
                return plistlib.load(file)
        finally:
            run('hdiutil', 'detach', mount)


def ed_signature(dmg):
    output = run(str(SIGN_UPDATE), '--account', KEY_ACCOUNT, str(dmg))
    signature = re.search(r'sparkle:edSignature="([^"]+)"', output)
    length = re.search(r'length="(\d+)"', output)
    if not signature or not length:
        fail(f'sign_update 출력을 읽지 못함: {output}')
    return signature.group(1), length.group(1)


def load_channel(appcast):
    if not appcast.exists():
        fail(f'appcast가 없음: {appcast}')
    tree = ET.parse(appcast)
    channel = tree.getroot().find('channel')
    if channel is None:
        fail(f'appcast에 channel이 없음: {appcast}')
    return tree, channel


def existing_builds(channel):
    builds, required = [], []
    for item in channel.findall('item'):
        builds.append(int(item.findtext(sparkle('version'))))
        critical = item.find(sparkle('criticalUpdate'))
        if critical is not None and critical.get(sparkle('version')):
            required.append(int(critical.get(sparkle('version'))))
    return builds, required


def add_item(channel, info, url, signature, length, required_below):
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = info['CFBundleShortVersionString']
    ET.SubElement(item, 'pubDate').text = email.utils.formatdate(localtime=True)
    ET.SubElement(item, sparkle('version')).text = info['CFBundleVersion']
    ET.SubElement(item, sparkle('shortVersionString')).text = info['CFBundleShortVersionString']
    ET.SubElement(item, sparkle('minimumSystemVersion')).text = info['LSMinimumSystemVersion']
    if required_below is not None:
        ET.SubElement(item, sparkle('criticalUpdate'), {sparkle('version'): str(required_below)})
    ET.SubElement(item, 'enclosure', {'url': url, 'length': length, 'type': 'application/octet-stream',
                                      sparkle('edSignature'): signature})
    # 새 항목을 맨 위 item 자리에 넣음.
    first = next((index for index, child in enumerate(channel) if child.tag == 'item'), len(channel))
    channel.insert(first, item)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('dmg', type=Path)
    parser.add_argument('--required-below', type=int)
    parser.add_argument('--notes', default='')
    parser.add_argument('--appcast', type=Path, default=ROOT / 'appcast.xml')
    parser.add_argument('--local-base-url')
    args = parser.parse_args()

    dmg = args.dmg.resolve()
    if not SIGN_UPDATE.exists():
        fail('sign_update가 없음. swift package resolve를 먼저 실행할 것.')
    info = bundle_info(dmg)
    version, build = info['CFBundleShortVersionString'], int(info['CFBundleVersion'])
    if dmg.name != f'Privacy-AirPods-{version}.dmg':
        fail(f'DMG 이름({dmg.name})이 앱 판본 {version}과 다름.')
    tree, channel = load_channel(args.appcast)
    builds, required = existing_builds(channel)
    if builds and build <= max(builds):
        fail(f'빌드 {build}가 appcast의 최신 빌드 {max(builds)}보다 높지 않음.')
    required_below = max(required + ([args.required_below] if args.required_below else []), default=None)
    if required_below is not None and required_below > build:
        fail(f'필수 기준 빌드 {required_below}가 이번 빌드 {build}보다 높아 이번 판본도 필수 대상이 됨.')

    if args.local_base_url:
        url = args.local_base_url.rstrip('/') + '/' + dmg.name
    else:
        # 공증 ticket이 붙은 DMG만 올림. 서명은 ticket을 붙인 뒤의 파일 기준이어야 함.
        run('xcrun', 'stapler', 'validate', str(dmg))
        url = f'https://github.com/{REPO}/releases/download/v{version}/{dmg.name}'
    signature, length = ed_signature(dmg)
    if not args.local_base_url:
        run('gh', 'release', 'create', f'v{version}', str(dmg), '--repo', REPO,
            '--title', f'Privacy AirPods {version}', '--notes', args.notes or f'Privacy AirPods {version}')

    add_item(channel, info, url, signature, length, required_below)
    ET.indent(tree, space='  ')
    tree.write(args.appcast, encoding='utf-8', xml_declaration=True)
    with open(args.appcast, 'a', encoding='utf-8') as file:
        file.write('\n')
    state = f'빌드 {required_below} 미만 필수' if required_below is not None else '필수 표시 없음'
    print(f'{version}(빌드 {build}) 항목 추가, {state}: {args.appcast}')
    if not args.local_base_url:
        print('appcast.xml 변경을 커밋하고 main에 push해야 앱이 새 판본을 봄.')


if __name__ == '__main__':
    main()
