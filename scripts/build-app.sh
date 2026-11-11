#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# 개발 실행 번들(기본)과 배포 후보 번들(BUILD_CONFIGURATION=release, APP_DIR 지정)을 같은 조립 경로로 만듦.
configuration="${BUILD_CONFIGURATION:-debug}"
dev_app_dir="$PWD/.build/Privacy AirPods.app"
app_dir="${APP_DIR:-$dev_app_dir}"
signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -f .build/signing-identity ]]; then
    signing_identity="$(cat .build/signing-identity)"
fi
if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
    printf '%s\n' '고정 개발 인증서가 필요함. docs/development.md의 서명 설정을 확인할 것.' >&2
    exit 1
fi
if [[ "$app_dir" == "$dev_app_dir" ]] && pgrep -x PrivacyAirPods >/dev/null; then
    printf '%s\n' '실행 중인 Privacy AirPods를 종료한 뒤 빌드할 것. 실행 중 번들 교체는 권한 식별을 깨뜨릴 수 있음.' >&2
    exit 1
fi
# Swift 6.4 기본 swiftbuild는 실행 파일의 SDK 기록을 최소 OS(15.0)로 남겨 AppKit이 구 SDK 호환 동작을 고를 수 있음.
build=(swift build -c "$configuration" --build-system native)
"${build[@]}"
bin_path="$("${build[@]}" --show-bin-path)"
binary="$bin_path/PrivacyAirPods"
linked_sdk="$(vtool -show-build "$binary" | awk '$1 == "sdk" { print $2; exit }')"
active_sdk="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "$linked_sdk" != "$active_sdk" ]]; then
    printf '실행 파일의 SDK 기록(%s)이 현재 SDK(%s)와 다름. 구 SDK 호환 동작을 막기 위해 중단함.\n' "$linked_sdk" "$active_sdk" >&2
    exit 1
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp "$binary" "$app_dir/Contents/MacOS/PrivacyAirPods"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# 앱 아이콘. 원본에서 다시 만들 때는 scripts/make-app-icon.py를 씀.
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
# 메뉴 막대 아이콘 프레임(컬러 PNG 25장). 앱이 번들에서 읽고, 하나라도 없으면 SF Symbol 눈으로 대체함.
menu_bar_frames=$(find Resources/MenuBarIcon -maxdepth 1 -name 'blur-[0-9][0-9].png' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$menu_bar_frames" != 25 ]]; then
    echo "Resources/MenuBarIcon에 blur-00~blur-24 25장이 필요함(현재 $menu_bar_frames장). python3 scripts/make-menu-bar-icon.py로 다시 만듦." >&2
    exit 1
fi
rm -rf "$app_dir/Contents/Resources/MenuBarIcon"
cp -R Resources/MenuBarIcon "$app_dir/Contents/Resources/MenuBarIcon"
sign_options=(--force --sign "$signing_identity")
if [[ "$configuration" == release ]]; then
    # 공증 필수 조건: hardened runtime과 Apple 보안 타임스탬프.
    sign_options+=(--options runtime --timestamp)
fi
# 앱 내 업데이트. 샌드박스가 아니므로 Sparkle의 XPC 서비스는 쓰지 않음.
# hardened runtime의 library validation을 통과하도록 안쪽 실행 파일부터 앱과 같은 인증서로 다시 서명함.
sparkle="$app_dir/Contents/Frameworks/Sparkle.framework"
rm -rf "$sparkle"
ditto "$bin_path/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
codesign "${sign_options[@]}" "$sparkle/Versions/B/Autoupdate"
codesign "${sign_options[@]}" "$sparkle/Versions/B/Updater.app"
codesign "${sign_options[@]}" "$sparkle"
codesign "${sign_options[@]}" "$app_dir"
codesign --verify --strict --deep "$app_dir"
printf '%s\n' "$app_dir"
