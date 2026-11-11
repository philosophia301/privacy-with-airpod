#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# App Store 밖 직접 배포용 DMG를 만듦: Developer ID 서명 → DMG 서명 → 공증 → ticket 첨부 → Gatekeeper 확인.
team_id="${TEAM_ID:-K8QJH6APX6}"
notary_profile="${NOTARY_PROFILE:-privacy-airpods-notary}"
notarize=1
case "${1:-}" in
    "") ;;
    --no-notarize) notarize=0 ;;
    *) printf '사용법: %s [--no-notarize]\n' "$0" >&2; exit 2 ;;
esac

identity="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning |
        awk -v suffix="($team_id)\"" '/"Developer ID Application: / && index($0, suffix) { print $2; exit }')"
fi
if [[ -z "$identity" ]]; then
    printf '팀 %s의 Developer ID Application 인증서가 키체인에 없음. docs/development.md의 직접 배포 준비를 확인할 것.\n' "$team_id" >&2
    exit 1
fi
# 빌드 전에 공증 인증을 확인해 긴 작업 뒤 실패를 피함.
if (( notarize )) && ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null; then
    printf '공증 키체인 프로필 %s를 사용할 수 없음. docs/development.md의 직접 배포 준비를 확인할 것.\n' "$notary_profile" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
out_dir="$PWD/.build/distribution/$(date +%Y%m%d-%H%M%S)"
app="$out_dir/Privacy AirPods.app"
dmg="$out_dir/Privacy-AirPods-$version.dmg"
mkdir -p "$out_dir"
BUILD_CONFIGURATION=release APP_DIR="$app" CODE_SIGN_IDENTITY="$identity" ./scripts/build-app.sh >/dev/null
# 공증 전에 hardened runtime으로 서명된 실행 파일이 실제 가림 창을 열고 마스크를 갱신하고 닫는지 확인함.
# 주 화면이 잠깐 흐려짐. 20초 안에 끝나지 않으면 실패로 봄.
if ! perl -e 'alarm shift; exec @ARGV' 20 "$app/Contents/MacOS/PrivacyAirPods" --smoke-test >"$out_dir/smoke-test.log" 2>&1; then
    printf '배포 후보의 보호 smoke test 실패. 로그: %s\n' "$out_dir/smoke-test.log" >&2
    exit 1
fi

staging="$out_dir/dmg-root"
mkdir -p "$staging"
ditto "$app" "$staging/Privacy AirPods.app"
ln -s /Applications "$staging/Applications"
diskutil image create from --format UDZO --volumeName "Privacy AirPods" "$staging" "$dmg" >/dev/null
rm -rf "$staging"
codesign --force --sign "$identity" --timestamp "$dmg"
codesign --verify --strict "$dmg"

if (( notarize )); then
    result="$out_dir/notary-result.json"
    # Invalid 판정도 결과 JSON과 로그로 남기기 위해 종료 코드 대신 status를 판정함.
    xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait --output-format json >"$result" || true
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || printf 'unknown')"
    if [[ "$status" != Accepted ]]; then
        submission="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
        if [[ -n "$submission" ]]; then
            xcrun notarytool log "$submission" --keychain-profile "$notary_profile" "$out_dir/notary-log.json" || true
        fi
        printf '공증 상태 %s. 결과: %s\n' "$status" "$out_dir" >&2
        exit 1
    fi
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
    spctl --assess --type execute --verbose=2 "$app"
fi
printf '%s\n' "$dmg"
