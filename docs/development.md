# 실험 앱 개발과 실행

첫 구현은 회전 블러와 실제 입력을 확인하는 실험 앱임. 자리 이탈·기립 자동 보호와 거리 정확도는 아직 제품 기능으로 연결하지 않았음. 설정과 모니터 조합별 배치는 이 Mac의 UserDefaults에 기억하며([설정 기억](#설정-기억--2026-11-12)), 정면 기준은 기억하지 않고 연결이 끊기면 무효화함.

## 빌드와 실행

Swift 6 도구와 macOS 15 이상을 사용함. 현재 개발기는 Xcode 27.0의 Swift 6.4임. 외부 패키지 의존성은 없음.

```sh
swift test
./scripts/build-app.sh
open '.build/Privacy AirPods.app'
```

빌드 스크립트는 실행 파일과 권한 설명을 앱 번들에 넣고 고정 개발 인증서로 서명함. 기본 실행은 배포 서명·공증·릴리스가 아님. 배포는 DMG 직접 배포만 하며 [본인 계정 DMG 직접 배포](#본인-계정-dmg-직접-배포--2026-11-11)를 따름. 실행 중인 앱의 번들을 교체하지 않도록 먼저 앱을 종료해야 함.

`swift test`는 주 화면 하나에 실제 가림 창을 잠깐 띄우므로 연결된 화면이 필요함. 내장 화면 여부는 무관함. 테스트 구성과 범위는 [코드 품질 정리](#코드-품질-정리--2026-11-11)를 따름.

최초 개발기 설정 시 `security find-identity -v -p codesigning`에서 본인 인증서의 SHA-1을 확인하고 `CODE_SIGN_IDENTITY` 환경 변수로 전달하거나 `.build/signing-identity`에 한 줄로 저장함. 이 파일은 Git 제외 대상이며 인증서 이름/식별자만 담고 개인 키는 담지 않음. `.build`를 삭제하면 다시 설정함. 인증서 미설정 또는 ad-hoc 값 `-`는 빌드 실패로 처리함.

ad-hoc 서명은 빌드 내용에 따라 권한 식별 조건이 달라질 수 있음. 고정 인증서로 전환한 첫 실행에서는 이 앱의 동작 권한을 다시 허용해야 할 수 있음. [Apple의 서명 식별 조건 설명](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)을 따르며 인증서 기반 기본 조건을 사용함. 식별자만으로 검사 조건을 약화하지 않음.

## 조작과 복구

```text
AirPods 입력 자동 시작 → 책상 정면 보정 → 배치 수정 시트에서 배치 맞추기와 적용 → 미리보기와 좌우 방향 확인 → 실제 화면 회전 블러 켜기 → 메뉴나 설정 창에서 보호 끄기
```

1. 수동 미리보기는 앱이 그린 예제 화면만 바꾸며 실제 화면의 보호 입력으로 쓰이지 않음.
2. AirPods 입력은 앱 실행 시 자동으로 시작함. 첫 실행에 동작 접근 권한 창이 뜰 수 있음. 거절·미지원·끊김은 상태에 표시됨.
3. 책상 정면을 보며 정면 맞추기를 한 번 누름. 배치 수정 시트는 감지한 화면 크기를 초기값으로 쓰며 지도에서 위치·회전을, 옆 그림에서 높이를 맞춘 뒤 적용함. 좌우 반전 토글은 없고 방향은 기존 기본값으로 고정됨. 고개를 오른쪽으로 돌렸을 때 보호가 맞는 쪽에 걸리는지 실물로 확인해야 함. 실제 방향 판정 전에는 효과의 정확성을 주장하지 않음.
4. 실제 화면 블러는 화면을 캡처하지 않고 WindowServer 합성 결과에 가변 블러 마스크만 적용함. 화면 기록 권한을 요청하지 않음.
5. 가림 창은 메뉴 막대와 노치 좌우까지 덮고 클릭을 가로채지 않음. 펼친 메뉴와 보호 중인 설정 창은 가림 위에 표시됨.
6. 메뉴나 설정 창의 보호 끄기 또는 앱 종료로 가림을 해제함. 입력 중단의 기본은 블러 해제이고, 옵션을 켜면 보호를 끌 때까지 전체 블러를 유지함. 화면 출력 실패는 검은 비상 가림을 유지하고 보호 끄기를 안내함. 최종 제품 복귀 정책은 spec의 미정 상태를 따름.

화면 구성이 달라지면 보호를 끄고 정면 보정과 배치 수정을 다시 받음. 잠자기·출력 실패의 실제 화면 결과, Spaces·전체 화면과 메뉴 자동 숨김 조건은 각각 확인해야 함. 미검증 조합을 보호 완료라고 안내하지 않음.

## 이동량·기립 실험

앉은 채 정지, 제자리 자세 고침, 일어서서 정지, 걷고 정지, 의자 밀기, 다시 앉기를 별도 시행함. 사람이 고른 동작명은 관측의 비교 조건이며 앱의 판정 결과가 아님.

관측 시작 후 최대 10초 동안 중력 반대 방향으로 가속도를 투영해 수직 속도·이동량을 계산함. 실제 가속도에서 센서 오차가 누적될 수 있으므로 표시값을 실제 거리로 사용하지 않음. 정지 상태의 drift, 기립 후 정지 중 추정 이동량 변화, 자세 고침과 기립의 중복을 비교해야 함. 원시 입력·화면을 파일로 저장하지 않으며 결과 수치는 사용자가 확인한 조건과 함께 별도 요약으로만 기록함.

자동 판정에 연결하기 전 실제 반복 관측으로 누락·오탐을 확인함. 수직 계산의 합성 테스트 통과는 기립 감지 성공이 아님. 거리 추정이 부족하면 사용자 허용에 따라 기립 감지로 좁힐 수 있으나 기립의 정확도도 따로 검증함.

센서 유효 시각은 [Apple timestamp 문서](https://developer.apple.com/documentation/coremotion/cmlogitem/timestamp)의 부팅 이후 초 단위 계약을 따라 현재 uptime과 비교함. 콜백 도착 시각만으로 오래된 입력을 새 입력으로 취급하지 않음. AirPods의 실제 시계 대응도 실물 수신 검증 대상임.

## 2026-09-14 검증 결과

- `swift test`: XCTest 6개와 Swift Testing 10개, 총 16개 통과. 순수 각도·수직 적분, 오래된 측정 거부, 실제 Core Image의 좌우 선명도 차이, 백그라운드 motion 콜백을 검사했음. 콜백 반환 타입의 Sendable 명시 후 해당 회귀 검사 1개를 다시 실행하여 경고 없이 통과했음.
- `./scripts/build-app.sh`: 종료 코드 0. 로컬 앱 번들 조립·서명 성공. `NSPrincipalClass` 누락으로 처음 실행 때 창이 없던 문제를 보완한 뒤 보정·예제 화면 창을 확인했음.
- 첫 motion 콜백에서 Swift actor 실행 영역 검사로 SIGTRAP 충돌이 발생했음. Crash report의 MotionService.start 콜백과 백그라운드 operation queue를 확인하고 콜백의 Sendable 계약을 명시했음. 수정 앱에서 실제 AirPods 입력 26 samples·이어버드 1 표시를 관측했고 후속 수정본에서는 8,268 samples 수신과 동일 프로세스 유지를 확인했음. 이것은 장시간 안정성 검증이 아님.
- 실제 모니터 두 대의 이름과 설정·선명한 예제 화면을 UI에서 확인했음. 수동 +36°에서 왼쪽, −36°에서 오른쪽이 더 흐려지는 UI 출력도 확인했음. 모니터별 정면 보정, 실제 데스크톱 블러, 강도·속도의 사용자 acceptance, 메뉴 복구, Spaces·전체 화면, 기립·이탈 정확도는 미검증임.

검증 중 사용자가 직접 조작할 수 있어 화면 자동화와 고개 동작을 같은 관측으로 혼합하지 않음. 물리 방향·동작을 확인하기 전에는 회전·기립 성공 수치를 기록하지 않음.

첫 실험 번들의 빌드 최소 버전은 macOS 15임. 닫힌 단일 설정 창을 앱 재열기에서 다시 표시하는 SwiftUI defaultLaunchBehavior API를 사용함. 현재 검증 대상은 사용자 macOS 26.6.2뿐이며 다른 OS의 제품 지원 확정은 아님.

자동화 호출 사이에 설정 창이 on-screen 목록에서 빠지는 현상도 관측했음. 앱 프로세스는 살아 있었고 open 직후 같은 호출 안에서 미리보기 조작과 관측은 성공했음. 설정 창은 평소 일반 높이, 보호 중에만 가림 위로 배치하며 닫힌 단일 창의 재열기 동작을 명시했음. 자동화의 포커스/Spaces 영향과 앱의 창 유지 동작을 아직 분리하지 못했으므로 이 현상의 원인이 확정됐다고 기록하지 않음.

## 첫 프레임 준비 검증 — 같은 날 후속

ScreenCover는 각 대상 화면의 첫 렌더 결과가 패널에 전달된 뒤 CaptureReadiness에 준비를 알림. 모든 대상이 준비되기 전에는 start가 완료되지 않으므로 AppModel은 보호 시작 중 상태를 유지함. 스트림 시작 후 첫 프레임 대기는 최대 5초이며, 취소·입력 소실·렌더 오류·시간 초과가 나면 시작 실패로 정리함. 5초는 실험용 준비 한도이며 감지 지연의 제품 합격 기준이 아님.

`swift test` 전체 22개(XCTest 6개 + Swift Testing 16개)와 앱 빌드·로컬 서명 검사가 통과했음. 새 검사 6개는 대상 화면 모두 필요, 중복/다른 화면 거부, 대기 전/후 프레임, 오류 뒤 늦은 프레임, 취소·빈 대상, 첫 프레임 시간 초과를 검증함. 실제 ScreenCaptureKit 스트림·패널 출력과 사용자의 회전 acceptance를 대체하지 않음.

Orca computer capabilities는 메뉴·메뉴 막대 조작을 지원하지 않는다고 반환했음. 따라서 메뉴 복구를 자동 검사한 것으로 기록하지 않음. 실제 회전 검증을 위한 모니터별 정면 보정을 사용자에게 요청했으며 응답 전 가상의 기준으로 보호를 켜지 않았음.

## 화면 좌우 대응 — 같은 날 후속

사용자가 두 화면 보정을 완료한 뒤 실제 가림 패널 두 개와 블러 출력을 관측했음. Orca 메뉴 기능은 미지원이지만 앱 자신의 macOS Accessibility 메뉴에서 ‘보호 끄기’를 실행했고, 설정의 ‘보호 꺼짐’ 및 두 가림 창이 on-screen 목록에서 사라진 것을 확인했음. 이는 해당 실행의 메뉴 해제 복구 근거이며 전체 화면·Spaces 조합의 검증은 아님.

사용자는 오른쪽으로 고개를 돌릴 때 왼쪽 화면의 왼쪽부터 가려져야 하는데 오른쪽 화면의 왼쪽부터 가려진다고 보고했음. NSScreen에서 BK550Y는 x=-1920, 27MB35는 x=0이며 기존 배열은 오른쪽 주 화면을 먼저 반환했음. 화면 목록을 배치 좌표로 정렬하고 ‘왼쪽 · BK550Y’, ‘오른쪽 · 27MB35’를 표시하도록 수정했음. 보정값이 서로 잘못 대응했을 가능성은 있으나 기존 숫자를 확인하지 못했으므로 원인 확정이 아님. 전체 yaw 부호만 뒤집어도 상대 각도의 절댓값은 같아 가려지는 화면 자체를 바꾸지는 못하므로 부호는 변경하지 않았음.

후속 `swift test`는 총 25개(XCTest 6개 + Swift Testing 19개) 통과했으며 앱 빌드와 `codesign --verify --strict`도 종료 코드 0임. 추가 검사는 주 화면과 무관한 좌우 순서, 오른쪽 기준에서 왼쪽 화면의 왼쪽부터 가림, 왼쪽 기준에서 오른쪽 화면의 오른쪽부터 가림을 검증함. 합성 보정 기준의 계산 검사이므로 실제 착용 방향의 증명은 아님.

수정 번들을 재실행하고 새 좌우 이름이 잘리지 않고 표시되는 것을 확인했음. 보정값은 메모리에만 있어 재시작으로 초기화됐음. 실제 두 방향 재보정과 사용자 회전 확인 전에는 이 문제의 해결 완료로 판정하지 않음.

## 화면 기록 허용 반복 — 같은 날 후속

사용자가 허용 후에도 시스템 설정이 반복해서 열린다고 보고했음. 앱 UI에서 캡처 TCC 거절 오류를 확인했으며 코드에는 별도 설정 URL 호출이나 사전 권한 요청 루프가 없었음. 기존 앱의 designated requirement는 바이너리 cdhash에 묶여 있었고, tccd 로그에는 이 앱의 이전/현재 서명 불일치가 기록됐음. 해당 로그의 명시적 서비스는 Motion이므로 ScreenCapture 불일치까지 직접 관측한 것으로 넓히지 않음.

본인 명의의 설치된 Apple Development 인증서로 서명하도록 빌드를 수정했음. 빌드·엄격한 서명 검사에 성공하고 식별 조건이 cdhash 대신 앱 ID와 Apple 인증서 조건을 사용하는 것을 확인했음. `tccutil reset ScreenCapture local.privacy-with-airpod.app`는 성공했으며 다른 앱의 권한은 초기화하지 않았음.

새 서명 앱을 재실행하고 시스템 설정의 화면 기록 앱 추가를 진행했으나 macOS가 사용자 암호 인증을 요구했음. 인증 단계는 사용자 직접 입력 전이며 권한 재등록·실제 캡처 성공·재빌드 후 권한 유지는 아직 미검증임. 앱 재시작으로 정면 기준도 초기화됐음.

## 화면 위치와 모니터 연결부 — 같은 날 후속

사용자가 보호 시 영상이 아래로 밀리며 클릭 위치와 어긋나고, 한 화면이 완전히 가려진 뒤 추가 회전을 해야 다음 화면이 시작된다고 보고했음. CALayer 렌더 실험에서 기존 메뉴 제외 contentsRect는 표식을 24pt 아래로 이동시켰음. macOS 레이어의 아래쪽 원점을 유지하면서 위 메뉴만 제외하도록 고쳤으며 프레임 교체의 암묵적 애니메이션도 차단했음.

맞닿고 세로 구간이 겹치는 화면은 공통 가장자리 강도를 두 화면의 기존 가장자리 강도 평균으로 계산함. 양쪽 화면의 가장자리 25% 구간에서 기존 강도로 부드럽게 연결하며 가운데 정면 영역은 기존 계산을 유지함. 25%는 이번 실험 구현값이며 사용자 확정 수치가 아님. 떨어져 배치한 화면은 연결하지 않음. 비상 가림은 이 보간보다 우선함.

`swift test`는 총 28개(XCTest 6개 + Swift Testing 22개) 통과했음. 추가 검사는 1×/2× 원본의 실제 CALayer 표식 위치, 인접 화면의 동일 경계 강도와 겹치는 시작, 떨어진 화면의 독립 동작임. 실물 클릭 위치·연결부 느낌·각 스트림의 프레임 시각 차이는 아직 검증 전임. 화면 입력 자체는 기존과 같이 가림 창을 통과하지만 캡처 지연은 별도로 남아 있음.

## 연결 폭 조절 — 같은 날 후속

‘3 · 실제 화면에서 확인’에서 모니터 연결 폭을 0~50%로 조절함. 기본값과 초기화는 25%이며 각 모니터 폭에 대한 비율임. 값을 높이면 다음 화면의 블러가 더 안쪽까지 이어짐. 공통 가장자리 강도 자체나 정면 기준·시작 각도를 바꾸는 조절은 아님. 수동 예제 미리보기에는 적용되지 않고 실제 보호 중 다음 갱신에 반영함.

전체 29개 검사(XCTest 6개 + Swift Testing 23개) 통과. 추가 회귀 검사는 연결 끄기, 폭 증가에 따른 영향 범위 확대, 가운데 유지, 좌우 대칭을 확인함. 실제 착용 상태에서 선호하는 폭과 자연스러움은 사용자 확인 전임.

## 단일 파노라마와 책상 정면 — 같은 날 후속

현재 사용법은 spec의 ‘현재 파노라마 방식’이 소유함. 이전의 모니터별 보정·경계 보간 기록은 당시 실행 이력이며 현재 동작이 아님.

PrivacyCore의 PanoramaProfile은 표시 위치와 책상 정면 위치의 cm 차이를 시청 거리로 나눈 방향을 atan2로 계산함. 한 번 보정한 고개 방향과 그 위치의 각도 차이에서 공통 블러 분포를 만들고 PanoramaSlice가 각 모니터 구간만 선택함. 화면 간격은 전체 폭과 위치에 포함되므로 경계가 빈 구간에서도 진행함. 물리적으로 꺾인 모니터도 한 평면에 펼친 것으로 근사하며 실제 눈 위치·시선 추적은 아님.

AppModel은 yaw를 한 번 필터링하고 모든 화면에 같은 값을 전달함. 수동 예제는 유효한 크기 입력 전에는 기존 단일 예제이며, 입력 후에는 선택한 화면의 파노라마 구간을 실제 보호와 같은 함수로 계산함. 수동 값은 데스크톱 보호에 전달하지 않음.

전체 31개 검사(XCTest 6개 + Swift Testing 25개) 통과했음. 구식 독립 보정·경계 혼합 검사 5개는 대체된 계약이므로 제거하고, 단일 시야 계약 검사 7개로 대체했음. 화면 경계 연속성, 폭이 다른 화면의 위치 대응, 빈 간격, 60cm와 45°의 기하 관계, 좌우 회전 대칭, 전환 폭, 잘못된 입력 거부와 비상 가림 우선을 검사함. 초기 간격 검사는 양쪽 모두 포화된 각도를 택해 실패했으며 전환 중인 각도로 바꿔 구간별 차이를 검사했음. 실물 자연스러움·치수 정확도·스트림 시각 동기화는 별도 확인 전임.

## 3D 설정과 사전 각도표 — 같은 날 후속

> 2026-11-12 이후 이 절의 SpatialSetupView, SpatialScene, SceneKit 설명은 이력임. 현재 배치 수정은 LayoutSheet, LayoutMap, LayoutEditor가 맡음(아래 배치 수정 화면 절 참고).

SpatialSetupView는 적용 전 draft를 소유하고 SpatialScene은 설정창에서만 SceneKit 장면을 렌더링함. 위치나 각도를 변경하면 예제 텍스처와 모니터 자세를 갱신함. 일반 보호는 AppModel.applyLayout에서 만든 CompiledDisplayAngles 배열을 사용함. 실제 보호의 strength는 각도표 보간과 강도 연산만 하며 sin/cos/atan2는 호출하지 않음. 표 유효성도 생성 시 한 번 확인함. 설정창 해제 시 SCNView.scene을 제거하고 지속 재생은 켜지 않음.

SceneKit은 [Apple에서 deprecated로 안내](https://developer.apple.com/documentation/scenekit/)하는 API임. 이번 설정 전용 PoC에서는 외부 자산·패키지 없이 카메라 조작과 화면 텍스처 검증을 빠르게 수행하기 위해 사용했음. 실제 보호 계산과 분리했으며 장기 제품화 시 RealityKit 교체를 검토함.

`swift test` 전체 37개(XCTest 6개 + Swift Testing 31개), 앱 빌드·엄격한 서명 검사 통과. 새 검사는 좌표 회전·미리 계산한 표·잘못된 입력 거부 및 적용 전 draft 격리, 실패한 적용의 기존 배치 보존, 보호 중 변경 거부를 포함함. 메인 통합 중 ExampleScreen 접근 수준과 SwiftUI 색상 타입 오류를 수정한 뒤 최종 검사를 통과했음.

실행 시 시스템에는 내장 화면 한 대가 활성화되어 있었으며 34.4×22.3cm 보고값을 UI와 3D 초기 크기에 반영한 것을 확인했음. 사람·팔 가이드·책상·화면 텍스처의 실제 3D 출력, 수동 +60°에서 방향선과 화면 블러 변화를 확인했음. 관측 사이 설정 sheet가 사라지고 window_not_found가 발생하여 이번 UI 자동화에서 ‘이 배치 적용’ 완료까지의 실물 검증은 남아 있음. applyLayout의 성공/실패와 설정 전달은 자동 검사로 확인했음. 외장 두 대의 3D 배치·AirPods 실물 연계·CPU/GPU 감소 수치는 미측정임.

## 3D 조작 피드백 — 같은 날 후속

> 이 절의 SceneKit 조작 설명도 2026-11-12 이후 이력임.

보기 전환은 SCNView.pointOfView와 defaultCameraController의 실제 표시 카메라를 함께 교체하고 관성을 멈춤. 자유 회전 뒤 남는 roll도 명시적인 위쪽 벡터로 초기화함. 같은 preset의 일반 갱신은 사용자의 관찰 시점을 다시 덮어쓰지 않음. 위치·높이·거리 슬라이더는 기존 수치 필드와 같은 draft에 연결함.

여성 기본값과 성별 변경 시 팔 길이 초기화는 HumanGuide가 소유함. [Size Korea 인체항목 검색](https://sizekorea.kr/human-meas-search/human-data-search/meas-item)의 8차·20~69세 조회값을 사용함. 팔길이는 어깨점에서 노뼈위점을 지나 손목안쪽점까지의 체표 길이임. 손가락 끝까지의 길이나 눈에서 모니터까지의 수평거리가 아니므로 개인 거리 자동 측정으로 사용하지 않음. 손 모형은 도식이며 손길이 평균을 적용하지 않았음.

| 성별 | API 평균(mm) | 표본 수 | 표준편차(mm) | 앱 표시(cm) |
| --- | ---: | ---: | ---: | ---: |
| 여성 | 530.12 | 5298 | 27.40 | 53.0 |
| 남성 | 581.98 | 4339 | 28.23 | 58.2 |

2026-09-14 동일 주소 POST를 독립 재조회함. 조건은 `measItemCds=S-STa-S-[SD01~EB01~WR02]-DM`, `measDegree=8`, `agePeriod=20-69`, `searchMode=NORMAL`, `gender=F` 또는 `M`임. 집계 API 표본 수와 조사 보고서 참여자 수의 일치는 별도 확인하지 않았으며 전체 성인 인구의 가중 평균으로 단정하지 않음.

전체 38개 검사(XCTest 6개 + Swift Testing 32개), 앱 빌드·엄격한 서명 검사를 통과했음. 추가 회귀 검사는 자유 회전 카메라에서 preset 복구, 화면 위쪽 방향 초기화, 같은 preset 갱신의 자유 회전 보존을 확인함. 실제 UI에서 여성 53.0cm 초기값, 남성 58.2cm 및 모형 변화, 정면·위쪽 보기 전환과 수평 복구, 좌우 슬라이더 0→1cm 수치 반영을 확인했음. 후속 높이·거리 조작은 창을 찾지 못하여 UI 확인을 완료하지 못했음. 현재 내장 화면 한 대에서의 확인이며 외장 두 대·실물 AirPods 보호 검증은 이번 범위에서 수행하지 않았음.

## 3D 눈 시점과 조작 간소화 — 같은 날 후속

> 이 절의 SceneKit 설명과 선택 검증도 2026-11-12 이후 이력임.

정면 카메라를 계산 기준인 눈 원점에 두고 고개 yaw를 반영함. 눈 시점에서는 머리와 방향선을 숨겨 화면을 가리지 않게 함. 입체·위쪽 카메라의 거리와 화각을 줄였으며 SCNView 자유 조작을 껐음. 사람 노드 회전에 팔·손도 함께 따라감. 설정의 수치 필드를 제거하고 크기·위치 슬라이더와 가로/세로 전환 버튼을 제공함. 전환은 기존 draft 치수를 교환해 적용 시 각도표에도 반영되며 시스템 화면 회전을 요청하지 않음.

전체 38개 검사와 앱 빌드·엄격한 서명 검사를 통과했음. 기존 카메라 검사는 새 눈 원점·전방 방향 계약으로 갱신함. UI에서 가까워진 입체 보기, 눈 위치 정면 보기, 수치 필드 제거, 세로 전환 시 폭/높이 교환 및 화면 형태 변화, 위쪽 보기에서 수동 +20°와 팔 방향의 일치를 확인했음. 이후 정면 방향선 가림을 보완하여 다시 검사·빌드했음. 현재 내장 한 대의 합성 고개 입력 검증이며 외장 두 대와 실제 AirPods 착용 검증은 수행하지 않았음.

이번 변경은 같은 설정 뷰·장면의 밀접한 수정이라 메인이 단독 처리함. 추가 worker의 전달·통합 비용을 피했으며 이전 조사 위임과의 통제 비교 또는 비용 절감 수치 측정은 하지 않았음.

## 화면 크기 고정 — 같은 날 후속

가로·세로 크기 슬라이더를 제거하고 감지한 크기를 유지함. 가로/세로 전환 버튼과 배치 슬라이더는 유지하며 메인 안내도 크기 입력 대신 배치 설정으로 정정함. UI 제거와 안내 변경만 수행하여 새 테스트는 추가하지 않았음. 앱 빌드·엄격한 서명 검사 및 재실행을 완료했음. 이번 변경의 별도 UI 조작 검증은 수행하지 않았음.

## 맥북 화질과 상단 잘림 조사 — 같은 날 후속

관측 당시 내장 화면은 1728×1117pt, backingScaleFactor 2, 상단 safeArea 32pt이며 앱 보호는 꺼져 있었음. 기존 SCStreamConfiguration은 포인트 수를 픽셀 수로 지정해 Retina에서 저해상도 캡처를 확대했음. 필터의 pointPixelScale을 반영한 해상도와 레이어 contentsScale로 수정하고 메뉴 포함을 명시함. 렌더 단계에서는 실제 입력 픽셀 폭/화면 포인트 폭만큼 radius를 환산해 기존 화면상 블러 폭을 유지함.

전체 39개 검사(XCTest 6개 + Swift Testing 33개) 통과. Retina/일반 화면의 출력 픽셀 크기와 1×/2× 입력에서 24pt·32pt 메뉴 제외 후 표식 위치 보존을 확인함. 실제 화면의 상단 잘림은 재현하지 못했으며 보호 화면·3D·설정 창 중 발생 위치를 질문했음. 해상도 증가로 2× 화면의 처리 픽셀은 4배가 되며 실제 지연·GPU 부하는 미측정임. 이 검사 결과를 실물 잘림·화질 해결 확인으로 취급하지 않음.

### 실제 보호 상단 후속 실측

사용자가 실제 화면 보호 중의 문제라고 확인했음. 현재 수정 빌드의 캡처 조건과 동일한 SCContentFilter를 별도 메모리 전용 프로브로 실행하여 display/filter 1728×1117pt, pointPixelScale 2, 출력 3456×2234px, 프레임 contentRect 전체 화면·contentScale 1·scaleFactor 2를 확인했음. 화면 파일은 저장하지 않았음.

실제 NSPanel에 전체 높이의 합성 표식을 넣고 동일한 contentsRect를 적용한 뒤 SCScreenshotManager로 해당 창만 메모리 캡처했음. 상단 32pt 제외 후 표식은 예상한 창 위쪽 64~67행에 표시됐으며 위치 이동을 재현하지 못했음. 단순 CALayer 검사와 별도로 WindowServer에 표시된 NSPanel 경로를 확인한 근거임. 사용자 AirPods 방향으로 실행 중인 보호 스트림 자체의 acceptance를 대체하지 않음.

현재 앱은 재실행 후 보정·배치 적용 전이라 실제 보호가 꺼져 있음. 상단 메뉴·노치 띠에 블러가 적용되지 않는 현상인지, 앱 제목·탭 등 내용 자체가 잘리거나 밀리는 현상인지 추가 확인을 요청했음. 원인이 확인되지 않은 좌표 보정은 추가하지 않았음.

## 노치 좌우 미가림 수정 — 같은 날 후속

사용자가 상단 내용 이동이 아니라 노치 좌우에 블러가 적용되지 않는 문제라고 확인했음. 기존 topInset만큼 창과 이미지를 자르는 경로를 제거하여 화면 전체를 가림. 실제 화면 합성 실험에서 메뉴 막대 아래 레벨 23은 상단 표식을 덮어 버렸고, 메뉴 위 레벨 25에서는 상단 12~15행의 표식이 보였음. 따라서 가림 창을 메뉴 위·펼친 메뉴 아래에 두고 앱 설정은 그보다 한 단계 위에 표시함. 캡처는 메뉴를 포함하고 가림 창은 계속 마우스 이벤트를 통과시킴.

전체 39개 검사(XCTest 6개 + Swift Testing 33개), 앱 빌드와 엄격한 서명 검사를 통과했음. 기존 메뉴 제외 검사는 폐기된 동작이라 실제 NSPanel의 전체 화면 프레임·전체 이미지 영역·Retina 스케일·클릭 통과·메뉴 사이 레벨 계약 검사로 대체했음. 실제 WindowServer 합성의 상단 표식은 SCStream/SCScreenshotManager로 메모리에서만 검사했으며 화면 파일을 저장하지 않았음.

진행 중 구버전 보호 창 레벨 23과 펼친 앱 관리 메뉴 레벨 101을 관측했음. 메뉴 열기 AX 호출은 오류 -25204였으므로 호출 성공으로 기록하지 않음. 이후 기존 앱 프로세스가 사라져 보호 끄기 호출 결과는 확인하지 못했고, 최신 크래시 보고서는 과거 11:37 기록뿐이어서 이번 종료 원인은 확정하지 않음. 수정 앱을 재실행했음. 실제 AirPods 보호 중 최종 메뉴 클릭·끄기 복구와 전체 화면·메뉴 자동 숨김 조합은 사용자 확인 전임.

## 보호 화면 버벅임 — 같은 날 후속

기존 캡처는 20fps이고 캡처 콜백과 각도 변경이 각각 직렬 큐에 렌더 요청을 추가했음. 초기 프로세스 관측의 CPU는 0.2%였으므로 그 값으로 보호 중 CPU 병목을 확정하지 않음. 별도 합성 Retina 3456×2234px 실험에서 가변 블러의 계산 비용과 중복 렌더 경로를 확인했음.

BlurRenderer는 200만 픽셀 초과 입력의 블러 분기만 가로·세로 1/2로 처리하고 원본 해상도로 합성함. 강도 0 영역은 원본, 낮은 강도 경계는 유효 반경 2px까지 점진 합성함. 블러가 필요 없는 입력은 필터를 생략함. 출력 해상도·위치와 선명 영역의 세부는 유지하며 낮은 강도의 정확한 필터 출력은 기존과 동일하다고 주장하지 않음.

LatestRenderWork는 실행 중 작업과 최신 대기 작업만 유지함. ScreenOutput은 캡처 큐에서 최신 프레임을 넘기고 별도 렌더 큐에서 처리하며 각도 갱신도 같은 대기 상태를 교체함. stop 시 대기 작업 폐기·추가 요청 거부를 수행함. 캡처 목표는 60fps로 높였으며 달성 FPS는 미측정임.

동일 프로세스·합성 체크무늬·3456×2234px·radius 62.5·부분 블러에서 각 경로 9회 중 첫 회를 제외하고 CGImage 픽셀 접근까지 강제했음. 기존 순서 먼저, 수정 순서 나중이며 교차 반복 대조는 하지 않았음. warm 8회 기존 17.5~30.6ms(중앙값 21.6ms), 수정 11.3~12.2ms(중앙값 11.7ms)였음. 중간 보고의 기존 23.2ms는 짝수 표본에서 위쪽 중앙값만 사용한 값이어서 두 중앙값 평균으로 정정함. 이 값은 캡처·WindowServer·사용자 입력까지의 전체 지연이나 실제 FPS 측정이 아님.

전체 42개 검사(XCTest 6개 + Swift Testing 36개) 통과. 추가 검사는 처리 중 99개의 요청을 최신 하나로 병합, 정지 후 대기 폐기·입력 거부, 고해상도 분기의 원본 출력 크기·선명한 1픽셀 무늬 대비 보존·가려지는 쪽 대비 감소임. 실제 AirPods 입력을 쓰는 장시간 보호, 스크롤 체감, 다중 모니터 총부하·프레임 전달 대기 시간은 미측정임.

최종 앱 빌드·엄격한 서명 검사와 재실행 완료. 재실행으로 메모리의 정면 기준·배치는 초기화됐음.

## 추가 성능 감사 — 같은 날 후속

측정 정본은 [성능 기록](performance.md)임. CGImage 출력과 Metal 텍스처의 합성 비교를 수행했으며 실제 앱의 표시 방식은 CGImage로 유지함. LatestFrameDelivery를 추가해 메인 액터가 밀렸을 때 완료 프레임도 하나로 병합함. 비상 가림/정지 시 대기 렌더·전달 작업을 닫고 새 캡처 입력을 저장하지 않음. 실행 중 GPU 작업 하나는 완료될 수 있지만 결과는 폐기함. 창 올리기는 창이 보이지 않을 때만 수행함.

전체 43개 검사(XCTest 6개 + Swift Testing 37개) 통과. 새 검사는 메인 액터 점유 중 완료된 100개 프레임 중 최신 하나만 전달되는지 확인함. 빌드·서명·실물 실행 확인은 아래 최종 기록을 따름.

최종 앱 빌드·엄격한 서명 검사를 통과하고 수정 앱을 재실행했음. 화면 보호가 꺼진 초기 상태로 시작하므로 이 실행을 보호 중 성능 검증으로 기록하지 않음.

## GPU 직접 표시 — 같은 날 구현 후속

사용자 승인으로 실제 화면 출력은 MetalPresenter의 CAMetalLayer로 전환했고 설정 예제는 PreviewRenderer의 별도 큐로 옮겼음. 설계·수치·남은 성능 한계는 [성능 기록](performance.md)이 소유함.

최종 swift test 종료 0, XCTest 6개 + Swift Testing 41개 = 47개 통과. 추가 검사는 GPU 실제 텍스처의 상하 색상·1px 선명 경계·Retina 크기, 잘못된 크기 거부, 중단 후 present 금지, 스트림 오류를 MainActor에 전달하기 전 GPU 닫기, 숨김 전 결과의 재표시 세대 침범 방지임. 실제 GPU 오류/hang 주입을 통과한 것은 아님.

현재 화면은 외장 27MB35와 BK550Y 각 1920×1080px/1×이며 내장 화면은 비활성임. 생산 소스 MetalPresenter·ScreenCover·BlurRenderer·CaptureReadiness·LatestRenderWork·LatestFrameDelivery를 그대로 컴파일한 임시 probe(`/tmp/privacy-metal-capture-probe.swift`)에서 실제 두 화면 SCStream을 시작함. 합성 각도 -50°→0°→50°를 각 350ms 적용한 뒤 비상 가림과 stop을 호출했음. 최종 결과는 READY displays=2, UPDATED failure=none, EMERGENCY panels=2, STOP remaining=0임. AirPods 입력을 대신한 각도이므로 실기기 회전 acceptance가 아님. 캡처 이미지는 저장하거나 전송하지 않았음.

별도 합성 패널 probe(`/tmp/privacy-metal-window-probe.swift`)에서 실제 drawable/present를 수행하고 SCScreenshotManager로 해당 창만 메모리에서 확인함. 위쪽은 빨강, 아래쪽은 파랑이며 GPU 레이어 제거 후 양쪽 RGB가 0인 검은 가림임. 캡처 색 변환에 따른 채널 차이가 있어 P3/HDR 색 정확도 보장으로 확대하지 않음. 종료 직후 WindowServer 목록이 남던 첫 probe는 AppKit 이벤트 루프 없는 검사 실행 방식에서 창 변경 반영이 늦은 경우였음. CATransaction.flush와 NSApp.updateWindows 후 500ms 관측에서는 가림 창 0개이며 첫 실패 관측을 삭제하지 않음.

실행 앱의 설정 미리보기에서 +58.6°로 실제 슬라이더를 움직이고 블러 영상 갱신을 확인했음. 최소화 호출은 후속 상태 확인에서 window_not_found를 반환했고 창 목록이 비었음. 조작 성공만으로 판단하지 않았으며, 최소화 후 복귀·닫기 후 재열기·가림 중 메뉴 클릭의 최신 UI 실물 검증은 미완료임. 자동 검사와 창 probe가 이 UX 검증을 대신하지 않음.

내장 화면 비활성으로 노치 실물 재검증은 못 했음. 실제 고개 회전·장시간 스크롤·FPS·전체 지연 p95·GPU 고갈·HDR는 추가 관측 필요함. 기존 보호 정책·권한·캡처 무저장 경계는 유지함.

최종 build-app.sh와 codesign --verify --strict 종료 0. 수정 앱 PID 17079에서 외장 2대 감지·보호 꺼짐 상태를 확인했음. 재실행으로 정면 기준과 배치는 다시 적용해야 함. 변경 파일 16개의 공백 및 문서 상대 링크 검사에서도 오류 없음.

## Space 전환 프레임 무효화 — 2026-09-14

Control+좌/우 전환 후 이전 데스크톱이 잠깐 보인다는 사용자 보고에 대응함. 사용자 선택은 spec의 Space 전환 후속 결정이 소유함. ScreenCover가 NSWorkspace.activeSpaceDidChangeNotification을 받으면 mach 절대 시각을 경계로 삼음. ScreenOutput의 마지막 캡처와 pending 작업을 버리고, MetalPresenter는 GPU 완료 후에도 캡처의 displayTime이 경계 이전이면 present하지 않음. 이미 표시 중인 레이어는 숨기거나 교체하지 않아 정상 전환에 검은 화면·원본 노출을 추가하지 않음.

정지된 새 데스크톱에서는 SCStream의 추가 프레임이 없을 수 있어 SCScreenshotManager로 현재 필터의 화면을 메모리에서 갱신함. 실제 캡처/블러 권한 범위 안이며 저장·전송은 없음. 화면별 요청은 하나로 병합하고 연속 전환으로 결과가 오래됐으면 최신 전환에 대해 다시 갱신함. 더 최신 스트림 프레임이 먼저 도착한 경우 늦은 snapshot 결과는 폐기함. snapshot 실패는 로그에 남기고 기존 스트림을 유지함.

swift test 종료 0, XCTest 6 + Swift Testing 44 = 50개 통과. 추가 검사는 pending 폐기 뒤 재개, Space 경계 이전 프레임 거부와 레이어 유지, 갱신 중복 방지·역순 결과 폐기·연속 전환·stop 후 입력 거부임. GPU 진행 중 경합의 전체 시각적 결과를 자동 검사가 모두 증명하지는 않음.

외장 2대에서 생산 소스를 컴파일한 `/tmp/privacy-space-probe.swift`로 실제 SCStream/GPU 가림을 실행함. 처음에는 NSApplication 이벤트 루프 없이 실행하여 키 주입 후 Space 알림 0회였으므로 전환 성공으로 기록하지 않았음. AppKit 이벤트 루프를 실행한 probe에서 Control+우/좌를 주입한 결과 SPACE 1, SPACE 2, SPACE COUNT 2를 확인함. 시작 displays=2, 초기 각도 변경 failure=none, 비상 패널 2개, stop 후 WindowServer 가림 창 0개임. Orca computer는 Finder의 접근성 창을 찾지 못해 hotkey 실행이 실패했고, System Events의 control+key code 124/123으로 전환을 확인함. 키 주입 성공만으로 검증하지 않고 알림 수로 대조했음.

사용자가 본 이전 화면의 짧은 재등장과 수정 전후 영상을 직접 비교한 것은 아님. 이미 표시된 이전 블러가 새 캡처를 기다리는 시간과 macOS 애니메이션/캡처 자체의 지연은 남을 수 있음. 내장 노치·전체 화면 Space·빠른 연속 전환·장시간 사용의 시각적 acceptance는 미완료임. build-app.sh와 strict codesign은 종료 0임.

이번 좁은 수정은 메인이 직접 구현·검증하여 추가 worker를 시작하지 않았음. 기존 GPU 리뷰 결과를 재사용하고, 정지 화면의 새 프레임 누락 가능성을 발견해 갱신 경로를 추가한 dynamic 작업 관측임. static/dynamic 통제 비교나 토큰 절감률은 측정하지 않았음.

## 전체 화면 재등장 후속과 에어팟 탈착 검은 화면

앞선 timestamp fence 수정 후에도 사용자가 재등장을 확인했음. 이번 조건은 전체 화면 앱을 포함한 Space 전환임. 미처리 프레임 차단으로 이미 표시된 drawable이나 WindowServer 전환 중 창 이미지를 없앨 수는 없으므로 앞선 수정의 해결 판정을 하지 않음.

SpaceTransitionBackdrop을 추가함. Space 경계에서 MetalPresenter의 레이어를 이전 픽셀이 없는 투명 레이어로 교체하고, NSVisualEffectView.behindWindow/hudWindow가 현재 배경을 임시로 흐리게 함. 새 drawable의 addPresentedHandler 이후에만 임시 효과를 제거함. 기존 GPU 작업의 세대/시각 차단, 최신 pending 하나, snapshot 중복 방지와 역순 결과 거부는 유지함. 전환 동안 수평 블러 분포를 갱신하고 정상 전환에 검은 가림을 삽입하지 않음. 입력 중단의 forceCovered는 전체 블러 렌더로 보내며 emergencyCover를 직접 호출하지 않음. 실제 캡처·GPU 오류의 검은 가림은 유지함.

패널에는 canJoinAllApplications를 명시하여 다른 앱의 전체 화면 참여 의도를 표시함. isFloatingPanel 설정이 창 level을 3으로 초기화하는 부작용을 기존 창 높이 검사가 실제로 잡았음. isFloatingPanel을 먼저 설정하고 마지막에 의도한 level 25를 적용하도록 수정한 뒤 전체 검사를 다시 통과함. 이 실패를 생략하거나 검사를 약화하지 않았음. Dock/activation policy와 메뉴보다 아래인 가림 레벨은 제품에서 변경하지 않았음.

| 검증 | 결과와 경계 |
| --- | --- |
| 최종 swift test | 종료 0, XCTest 6 + Swift Testing 45 = 51개. 새 Space 레이어가 투명하고 이전 레이어와 다르며 Retina 크기를 유지하는 검사 추가. 전체 블러가 검은 상수가 아닌지 기존 픽셀 검사 보강 |
| 입력 중단 모사 | 생산 소스로 컴파일한 /tmp/privacy-input-loss-probe.swift에서 외장 2대 캡처 후 forceCovered=true 적용. FORCED panels=2 metalLayers=2 failure=none, 명시적 비상 가림 후 stop remaining=0. 실제 이어버드 탈착은 미실행 |
| 기본 배경 블러 외형 | 합성 체크무늬/색상만으로 hudWindow·underWindowBackground·menu와 원본을 비교. /tmp/privacy-native-backdrop.png. 실제 화면 내용의 저장이 아님. 색조 차이를 공개하고 사용자 응답 후 후보 적용 |
| 일반 실행 파일 probe | regular activation policy에서 selfExclusionUnavailable로 시작 실패. 캡처·Space 검증 통과로 세지 않음 |
| 앱 번들 probe | 실제 번들 ID·서명·regular 실행 조건에서 진단용 실행 파일을 잠시 실행함. 제품 소스에 시각/개수 print만 추가한 임시 ScreenCover 복사본을 사용. 첫 실행은 level 3 결함 조건이어서 유효한 최종 검증과 구분 |
| 올바른 level의 전체 화면 전환 | Control+우 이후 System Events에서 frontmost Orca, AXFullScreen=true 확인. SPACE COUNT 1, 두 화면 BRIDGE_BEGIN→END 0.463646s/0.501217s, failure none, bridges 0, 비상 패널 2개, stop remaining=0. 왼쪽 복귀 입력은 해당 probe 관측 시간 밖이므로 왕복 2회 성공으로 세지 않음 |
| 제품 복원 | build-app.sh로 진단 실행 파일을 실제 제품 실행 파일로 복원하고 strict 서명 확인·재실행함. 검사 파일을 배포 앱으로 남기지 않음 |

주요 실물 기록은 /tmp/privacy-native-bundle-final.log, 자동 검사 /tmp/privacy-final-bridge-tests.log임. 성공한 상태·표시 완료 이벤트를 확인한 것이며, 수정 전후의 실제 재등장 영상을 비교하거나 모든 전환에서 무깜빡임을 증명한 것은 아님. 기본 효과의 일시적 색감·강도 차이, 빠른 연속 전환, 다중 전체 화면 앱, 내장 노치, 실제 이어버드 탈착은 추가 acceptance가 남음. 임시 블러의 밝기와 효과는 macOS 외형/투명도 설정에도 영향을 받음.

API 근거는 Apple의 [전체 화면 오버레이 안내](https://developer.apple.com/forums/thread/826308), [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications), 로컬 AppKit/QuartzCore SDK임. Apple 예제의 screenSaver 레벨은 펼친 메뉴 접근과 충돌하므로 그대로 적용하지 않았음.


## AirPods 입력 중단 정책 변경 — 2026-09-14

최신 사용자 결정은 spec의 ‘AirPods 탈착 기본 해제’가 소유함. AppModel의 입력 무효화가 기본적으로 기존 stopProtection 경로를 호출하므로 창 제거·캡처 종료와 시작 요청 취소를 함께 수행함. 유지 옵션은 전체 블러를 사용하고 옵션 해제 시 즉시 종료함. 화면 처리 실패와 입력 중단 유지 상태를 구분함.

`swift test` 종료 0: XCTest 6개와 Swift Testing 48개 통과. 추가 검사는 보호 중/시작 중 기본 해제, 두 화면 전체 강도 유지와 옵션 해제, 다른 중단 상태의 옵션 변경을 검증함. 첫 실행에서 테스트 함수 선언 오타로 컴파일 실패했고 수정 후 전체 실행을 통과함. 실제 캡처를 시작하지 않은 AppModel 상태 검사이므로 물리 탈착·화면 해제 지연의 증명은 아님.

`./scripts/build-app.sh`와 `codesign --verify --strict` 종료 0. 수정 앱 PID 4382로 재실행 후 설정의 옵션 기본값 0, 클릭 후 1, 다시 클릭 후 0을 접근성 트리에서 확인함. 보호는 꺼져 있으며 재실행으로 정면 보정과 화면 배치 재적용이 필요함. 실제 AirPods 탈착 시 입력 중단까지의 시간과 화면 해제는 미검증임.


## Space 전환 후 선명한 화면 노출 보완 — 2026-09-14

사용자가 앞선 후보에서 이전 화면 재등장은 사라졌으나 새 화면이 선명하게 보였다가 블러가 붙는다고 확인함. 생성 시점의 준비 지연이 코드상 후보이며 단일 원인으로 확정하지 않음. SpaceTransitionSurface가 배경 블러와 별도 GPU 호스트를 함께 유지하도록 변경함. 전환 알림에서는 오래된 GPU 레이어만 교체하며 배경 블러·투명 창 속성을 새로 만들거나 제거하지 않음. 배경 마스크가 같으면 NSImage 갱신도 생략함. 캡처 실패는 기존 검은 비상 가림, 입력 중단은 최신 사용자 선택 정책을 따름.

Apple의 [behindWindow 문서](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow)는 창 뒤 콘텐츠의 블러를 설명함. 전환 중 준비 시간이나 무노출을 보장하지 않으므로 이 문서를 시각적 해결 증거로 쓰지 않음. GPU 아래 배경 블러가 계속 연결되어 있어 추가 합성 비용 가능성이 있으며 WindowServer/GPU 부하는 미측정임.

`swift test` 종료 0: XCTest 6개와 Swift Testing 49개 통과. 새 검사는 투명 창·활성 배경이 반복 GPU 레이어 교체 중 유지되고, 비상 가림에서 배경과 GPU 출력이 제거되는 계약을 검증함. 실제 픽셀의 시간 연속성 검사는 아님.

동일 번들/개발 서명의 임시 실물 probe에서 외장 두 화면 캡처 시작, Control+오른쪽 전체 화면 Orca 진입(AXFullScreen=true) 및 Control+왼쪽 복귀를 수행함. 실제 Space 알림 2회, 오류 없음, 유지된 배경 2개, 비상 가림 창 2개, 종료 후 가림 창 0개를 확인함. 로그는 `/tmp/privacy-persistent-space-runtime.log`임. 고정 설정 입력이며 AirPods 회전 acceptance나 고속 영상에 의한 노출 프레임 검출은 수행하지 않음.

probe 종료 뒤 build-app.sh로 제품 바이너리를 복원하고 서명 검사 종료 0, 일반 앱 PID 20805 실행을 확인함. 보호는 재설정 전이며 배치 적용·정면 보정이 필요함. 남은 검증은 사용자 환경에서의 선명한 화면 깜빡임 해소와 합성 부하임.


## 첫 Developer ID 배포 서명 — 2026-09-14

사용자가 발급한 인증서를 설치한 뒤 배포 서명 방법을 요청함. 당시에는 사용자 팀이 아닌 이전 팀의 Developer ID Application identity로 서명했음. 현재 배포 서명 identity는 사용자 팀의 `Developer ID Application: Eunjong Kim (K8QJH6APX6)`이며 절차는 [본인 계정 DMG 직접 배포](#본인-계정-dmg-직접-배포--2026-11-11)가 소유함. `swift build -c release` 종료 0 후 별도 `.build/distribution/20260914-171706/Privacy AirPods.app`에 실행 파일과 Resources/Info.plist를 조립함. 실행 중 개발 앱은 교체하지 않음.

다음 형태의 명령으로 해당 배포 후보에 서명했고 두 명령 모두 종료 0을 확인함. 당시 `--sign` 값은 이전 팀 identity였으며 아래는 현재 사용자 팀 identity로 적은 형태임.

```sh
codesign --force --sign 'Developer ID Application: Eunjong Kim (K8QJH6APX6)' --options runtime --timestamp '.build/distribution/20260914-171706/Privacy AirPods.app'
codesign --verify --strict --verbose=2 '.build/distribution/20260914-171706/Privacy AirPods.app'
```

서명 메타데이터에서 이전 팀의 TeamIdentifier, runtime 플래그, Apple 보안 타임스탬프를 확인함. Apple Silicon arm64 전용 빌드임. 공증 업로드·DMG 제작·배포는 수행하지 않았으며 hardened runtime으로 서명한 앱의 실물 기능 검증도 아직 안 했음. 알려진 화면 전환 세 증상은 이 빌드에도 남아 있으므로 제품 acceptance나 배포 완료로 취급하지 않음. 후속은 공증 인증 설정과 공증 제출, 결과 확인·ticket 첨부 및 최종 패키지 검증임.


## 전체 화면 전환의 원인 분리 — 2026-09-14 후속

사용자에게 세 증상이 다시 재현되어 앞선 후보는 acceptance 실패임. 이번에는 보호 끔, macOS 기본 배경 블러(native)만, native+GPU, GPU만을 같은 합성 전체 화면 앱 두 개에서 비교함. native는 WindowServer가 창 뒤의 현재 내용을 흐리는 방식이고, GPU 경로는 캡처된 화면을 앱에서 가공하여 덮는 방식임. 화면 내용은 RAM에서만 처리하고 색상 비율·시각·상태만 로그로 남겼음.

### 확인된 결함과 반영

`ScreenCover`의 1회 screenshot 갱신은 실제 표시 시각 대신 요청 시각으로 이미지에 날짜를 붙였음. 잠금 해제 뒤 실제 `SCScreenshotManager.captureSampleBuffer` 결과에서 displayTime과 status가 모두 missing임을 관측함(`/tmp/privacy-timeline-unlocked.log`). 이 경로를 삭제하여 실제 SCStream displayTime을 가진 완성 프레임만 받도록 단일화함. screenshot에 실제 오래된 픽셀이 담겼다는 직접 증명은 아니며, 아래 결과처럼 이것만으로 전환 문제는 해결되지 않음.

전체 화면 뒤 설정 창이 on-screen 목록에서 빠지면 ownApps를 찾지 못해 selfExclusionUnavailable로 실패했음. SCShareableContent의 onScreenWindowsOnly를 false로 변경함. 자기 앱 제외 필터와 실패 guard는 유지함. 모든 창의 픽셀을 별도로 수집하는 변경이 아님.

`CapturedScreenFrame`과 실제 CMSampleBuffer attachment 검사를 추가함. displayTime 없는 sample을 PTS로 대체해 승인하지 않고, 정상 displayTime은 보존하며 idle 프레임은 거부하는 계약을 검증함. 기존 순서·전환 경계·중단 검사는 유지하고 삭제된 screenshot coalescing 검사는 제거함. 최종 `swift test` 종료 0: XCTest 6 + Swift Testing 50 = 56개(`/tmp/privacy-transition-final-tests.log`). 앱 빌드·strict 서명 종료 0. 사용자 시각 acceptance는 미완료임.

### 정지 화면의 중복 합성 가설

합성 체크무늬에서 자기 앱 제외 캡처와 원본의 평균 절대 픽셀 차이(MAD)는 native만 켜도, native+GPU를 켜도 0임. 화면에 실제 보이는 블러와 원본의 차이는 각각 약 118임. 불투명 GPU 아래 native를 숨겨도 최종 화면 차이는 0임(`/tmp/privacy-feedback-runtime.log`). 따라서 정지 상태에서 자기 블러를 다시 캡처하거나 항상 두 블러가 겹친다는 가설은 이 조건에서 지지되지 않음. 전환 중의 중첩은 별도임.

### 잠금 해제 뒤 유효한 동적 비교

내장 화면 1대, 합성 초록/자홍 전체 화면 앱 A/B, 고정 전체 블러 radius 31.25 조건임. B 활성화 후 3초 기다리고 Control+왼쪽/오른쪽을 2초 간격으로 4회 입력함. AirPods 입력은 대체한 고정 설정임. 실제 NSWindow fullScreen 상태와 두 fixture 실행을 확인함.

관찰용 SCStream 두 개가 화면 중앙의 가로 432픽셀 띠에서 초록/자홍 비율을 계산함. raw는 자기 앱을 제외하고 shown은 최종 합성을 포함함. 관찰용 shown은 렌더 입력으로 쓰지 않음. sourceRect와 preservesAspectRatio=false로 띠 전체를 채움. 같은 displayTime 표본끼리 비교하고 원시 화면은 저장하지 않음.

| 조건 | raw/shown 프레임 | 동일 시각 쌍 | 색상 비율 차이 평균/최대 | 초록 비율 누적 이동 raw/shown |
| --- | --- | --- | --- | --- |
| 보호 끔 | 232/232 | 171 | 0.00037 / 0.00463 | 3.9167 / 3.9444 |
| native만 | 407/409 | 310 | 0.02106 / 0.02546 | 3.9167 / 4.0000 |
| native+GPU | 818/823 | 613 | 0.05441 / 1.01389 | 3.9167 / 4.0880 |
| GPU만 | 947/955 | 520 | 0.20386 / 1.97917 | 3.9167 / 4.2917 |

차이는 abs(raw 초록-shown 초록)+abs(raw 자홍-shown 자홍)으로 0~2 범위임. 누적 이동은 연속 표본 초록 비율의 절대 변화 합이며, 한 방향 전환이 되돌아가면 증가함. 블러 자체의 색조·경계 확산도 이 지표에 영향을 주므로 그대로 깜빡임 횟수나 지연 ms로 환산하지 않음. 로그 `/tmp/privacy-measure5-{off,native,hybrid,gpu}.log`는 각각 READY와 DONE을 확인함.

이전 유효 3차 실험에서도 raw 누적 이동 3.9167에 shown은 off 3.9167, native 4.0000, 혼합 6.0880에 가까웠음(정확값 6.08796296). 반복마다 크기가 달라 단일 수치로 성능 개선율을 주장하지 않음. 이번 GPU 단독에서도 편차가 남으므로 native 중복만으로 세 증상을 설명할 수 없음. 캡처되어 이동이 이미 담긴 화면을 지연 재표시하는 경로가 주요 원인 후보임. 창 자체의 이동과 레이어 교체가 각각 얼마나 기여하는지, 이전 Space의 완성 프레임이 실제 몇 번 노출되는지는 아직 분리하지 못했음.

### 무효 실행과 남은 결정

잠금 상태에서 수행한 전환 입력, 자기 앱 제외 실패로 시작하지 못한 실행, preservesAspectRatio 기본값으로 띠가 letterbox된 1~2차 색상 측정은 전환 성공으로 세지 않음. 최초 GPU 실행은 fixture 자동 종료, 재실행은 시작 위치/append 로그가 섞여 네 전환의 raw 이동이 일치하지 않았으므로 최종 비교에서 제외함. 위 표는 새 로그를 사용하고 모든 raw 이동량이 일치한 5차 결과만 사용함.

물리 디스플레이의 고속 영상이 아닌 WindowServer 캡처 관측임. 실제 AirPods 회전, 일반↔전체 화면, 외장 2대, 장시간·연속 입력과 사용자가 보고한 세 증상 각각의 시각 acceptance는 남아 있음. 테스트 통과나 native 단독 지표를 최종 해결로 처리하지 않음.

다음 추천은 native 단일 출력 후보를 평상시에도 적용해 고개 회전을 검증하는 것임. 기존 strength 마스크로 이동 경계는 표현하지만 hudWindow material은 기존 Gaussian radius·색감과 같지 않으며 강도 UX 재조정이 필요함. 사용자는 전환 중 일시적 차이만 허용했으므로 평상시 외형 변경을 별도로 질문했음. 답변 전 제품 기본 출력은 바꾸지 않음. 화면 캡처를 재표시하지 않는 후보와 기존 외형을 유지하는 추가 조사 중 선택이 필요함.

실험 뒤 fixture 2개를 종료하고 build-app.sh로 실제 제품 실행 파일을 복원했으며 strict 서명을 다시 확인함. 진단 실행 파일이나 화면 가림을 실행 상태로 남기지 않았음. 제품은 보호 꺼짐/미실행 상태이며 재실행 시 배치·정면 보정이 필요함.


## Native 단일 출력 후보 구현·검증 — 2026-09-14

사용자 승인 뒤 ScreenCover의 SCStream·GPU presenter·Space 알림 레이어 교체를 실제 보호 경로에서 제거함. 화면별 NSPanel 하나에 SpaceTransitionBackdrop 하나를 유지하고 각도 변화에는 마스크만 갱신함. 기존 캡처 출력 코드는 CapturedScreenOutput.swift로 이동하여 이전 방식 비교 진단과 회귀 검사에만 남김. 실제 보호에서 인스턴스를 생성하지 않음. 이 비교용 코드는 2026-11-11 [코드 품질 정리](#코드-품질-정리--2026-11-11)에서 삭제함. 기본 입력 중단 해제/선택적 전체 블러 유지와 화면 구성 변경 시 중단은 기존 AppModel 경로를 유지함.

기본 블러의 농도와 예제 차이는 spec 소유임. 화면 기록 안내를 현재 동작에 맞추고 ‘효과 농도’로 표시함. ScreenCover 시작은 전체 화면 ID를 먼저 확인하여 일부 창만 열린 채 실패하지 않도록 함. stop은 즉시 모든 창을 닫고 이후 update로 다시 열리지 않음.

`swift test` 종료 0: XCTest 6 + Swift Testing 52 = 58개. 이전 GPU 레이어 교체 계약 검사는 native 창 유지·종료 계약 검사로 교체함. 잘못된 화면 ID의 부분 시작 방지, 실제 NSImage 마스크의 선명 영역·농도 변화·입력 중단 최대 가림을 추가 검증함. 초기 마스크 식의 괄호 오류로 컴파일 실패했고 수정 후 통과함. capture 관련 잔존 검사는 진단 경로 검사이며 native 제품 검증 개수로 부풀리지 않음. 로그 `/tmp/privacy-native-single-tests.log`.

내장 1대에서 실제 ScreenCover를 호출한 임시 probe로 합성 전체 화면 A/B를 4회 왕복 비교함. 고정 전체 마스크이며 AirPods를 대체했음. 관찰용 캡처만 RAM에서 색상 비율을 계산하고 제품 보호 경로는 캡처하지 않음. 아래 hybrid 로그명은 이전 harness의 이름이며 이번 실행은 native 단일 ScreenCover임.

| 조건 | raw/shown 표본 | 동일 시각 쌍 | 색상 비율 차이 평균/최대 | 초록 비율 누적 이동 raw/shown |
| --- | --- | --- | --- | --- |
| 보호 끔 | 233/235 | 164 | 0.000339 / 0.004630 | 3.9167 / 3.9537 |
| native 단일 제품 후보 | 470/468 | 294 | 0.021227 / 0.023148 | 3.9167 / 4.0000 |

지표 정의와 해석 제한은 위 원인 분리 기록을 따름. 두 조건 모두 READY/DONE 및 동일 raw 이동량을 확인함(`/tmp/privacy-native-final-off.log`, `/tmp/privacy-native-final-hybrid.log`). 앞선 GPU 조건의 큰 순간 편차는 이번 조건에서 관측되지 않았음. 사람의 시각 acceptance, 외장 2대·일반↔전체 화면·농도별 보호 효과·물리 탈착을 통과로 간주하지 않음.

fixture 두 개 종료 뒤 build-app.sh로 제품 복원·strict 서명 확인, 제품 PID 35504로 실행함. computer-use로 ‘효과 농도’와 캡처 없음 안내, 보호 꺼짐·보정 전·배치 적용 전·내장 1대 상태를 확인함. AirPods 입력 시작을 눌렀으나 ‘동작 입력을 기다리는 중’으로 실제 수신·고개 회전은 미검증임. 특정 window-id 조회 한 번은 실패했으며 restore-window 조회로 살아 있는 동일 앱을 확인함. 새 충돌로 판정하지 않음.

실제 검증의 다음 행동은 AirPods 착용 → 책상 정면 보정 → 배치 수정 적용 → 실제 보호 켜기임. 후보 외형과 전환의 사용자 확인 뒤에 acceptance를 갱신함.


## 미리보기만 적용되는 듯 보인다는 후속 — 2026-09-14

사용자 보고 시 PID 2459의 UI에서 입력 수신, 정면 보정 완료, 배치 적용 완료, 실제 보호 활성, 미리보기 수동 모드 꺼짐을 확인함. 시작 조건 미충족이 아님. 당시 시작 각도 10도, 효과 농도 21.9665로 native 마스크의 최대 농도 약 27.5%가 적용됨. 미리보기는 Gaussian radius, 실제는 material의 alpha 마스크이므로 같은 숫자가 같은 흐림을 뜻하지 않음. Apple maskImage 문서는 material을 alpha로 마스킹하는 계약임을 설명함: https://developer.apple.com/documentation/appkit/nsvisualeffectview/maskimage

낮은 농도에서 실제 가독성 차단을 검증하지 않고 최대 forceCovered 조건의 전환만 비교한 공백이 있음. 이를 화면 미적용의 확정 원인으로 단정하지 않음. UI의 set-value는 value_not_settable, stale element도 발생함. 매 조작 전 새 snapshot을 얻어 advertised increment action으로 농도 80까지 올린 뒤 현재 값을 확인했음. 최대 농도에서 실제 블러가 보이는지 사용자 확인을 요청함. 원래 값은 약 21.9665이며 재보정·재시작 없이 실제 적용 중 농도만 변경함. 해결 완료 판정은 보류함.


### 내장 화면 전용 성능 최적화 Lab — 2026-09-15

수정 Lab은 `open -g ".build/blur-lab/Privacy AirPods Blur Lab.app" --args --built-in-only`로 실행하면 내장 화면에만 창과 블러를 두며 외장 앱의 활성화를 가져오지 않음. 기존 프로세스가 있으면 새 인자 적용을 위해 종료 후 실행함. 기본 실행의 단일 화면 조건과 제품 native 출력은 별개임. 내장 화면이 없으면 이 모드에서 시작하지 않음.

기본 갱신은 slider/sample 이벤트 중심이고 입력 유효 기간 감시는 별도 유지함. 기능·성능 검증과 미완료 조건은 [성능 기록](performance.md#기능을-유지한-이벤트-갱신-최적화--2026-09-15)을 참조함. 외장 화면에서 작업 중에는 전역 전환 입력을 사용하지 않음.


## 본체 통합 — 2026-09-15

Privacy AirPods의 `ScreenCover`가 화면별 패널을 앱 소유 독립 합성 공간에 부착함. `SpaceTransitionBackdrop`은 색조 없는 가변 블러와 256×1 마스크를 관리하고, 실제 RGBA와 반경이 같으면 제출을 생략함. `PrivacyBackdrop`은 본체와 Lab의 공유 Objective-C 어댑터이며 ARC를 명시해 객체·공간 수명을 관리함. Lab의 independent 기본 경로도 ScreenCover를 호출하므로 창/마스크 동작을 따로 유지하지 않음. 다른 Lab 후보는 비교 진단용임.

기존 보정·3D 배치에서 나온 RenderSettings를 그대로 사용함. AppModel은 활성 상태의 20Hz 보간을 유지하며 미리보기·입력·보호·계측이 모두 꺼졌을 때 타이머를 중단함. 입력 중단 기본 해제/선택적 전체 블러 유지와 처리 실패의 비상 가림을 구별함. 실패 중 재진입 갱신은 차단하며 종료 시 자기 창과 소유 공간만 정리함.

내장 화면 전용 실행: `open -g '.build/Privacy AirPods.app' --args --built-in-only`. 이 진단 인자는 시스템의 builtin 판정으로 보호 대상을 제한하고 설정 창을 내장 화면에 배치함. 일반 실행의 전체 화면 배치는 유지함. 기존 앱을 먼저 종료한 뒤 실행해야 인자가 적용됨. 외장 작업 중에는 전역 Space/키보드/트랙패드 입력을 보내지 않음.

통합 판본 검증 결과는 아래에 기록함. 이전 Lab의 전환 실측·CPU 수치는 본체의 재측정으로 간주하지 않음.

검증: `swift test` 종료0, Swift Testing55개와 XCTest6개 통과. 본체 보정→실제 내장 패널 생성→합성 입력 중단의 기본 해제/선택 유지, 잘못된 반경의 비상 가림·재진입1회 차단·종료, RGBA/반경 캐시·클릭 통과·노치 포함 크기를 검사했음. 센서는 합성이며 실제 탈착 acceptance를 뜻하지 않음. 로그는 `/tmp/privacy-product-integration-tests.log`임.

`./scripts/build-app.sh` 종료0으로 고정 인증서 서명·검증을 완료했음. 기존 제품/Lab 프로세스만 정상 종료하고 본체를 `--built-in-only`로 배경 실행했음. computer-use의 접근성 조회에서 Privacy AirPods 창880×760이 내장 화면에 있고 감지 화면1대,35도/농도31.25/전환0.18초, 기본 탈착 해제, 보호 꺼짐·보정 전 상태임을 확인함. 실행 시 설정을 보관하지 않는 기존 정책상 재보정이 필요함. 외장 화면 입력·Space 전환은 실행하지 않았음.

공유 출력 진단: 재빌드한 Lab의 `--built-in-only --smoke-test` 종료0. 동일 픽셀 생략·반경/각도 갱신, 입력 만료·연장,100 sample의 최신1회 제출, 시작 취소·3회 재시작·빈 대상 거부를 실제 내장 출력에서 확인했음. 모든 소유 공간 생성/정리가 짝을 이뤘으며 로그는 `/tmp/privacy-integrated-shared-smoke.log`임. 진단 종료 뒤 실행 중인 앱은 Privacy AirPods 본체만 남겼음. 이는 합성 입력 수명 검사이며 전환·외형 acceptance나 GPU 성능 측정은 아님.

## 시스템 화면 배치의 3D 초기값 — 2026-09-15

`DisplayLayout.spatialPoses`는 시스템 논리 화면 사각형의 가까운 인접 쌍부터 연결하고, 각 화면의 cm 폭·높이로 위치를 정함. 공유 가장자리의 위/아래/중앙 정렬을 대응시키므로 논리 배율을 물리 크기로 오인하지 않음. 논리 좌표의 빈 공간을 cm 거리로 추정하지 않고 기존 간격값을 사용함. 외장 화면을 우선 눈높이 기준으로 잡으며 두 가로 화면은 기존 이음새 정면 기준을 유지함. 복잡한 배열은 초기 추정이고 실제 책상과 다르면 3D에서 보정해야 함. 이미 적용한 `appliedPoses`가 있으면 재생성하지 않음.

`SpatialScene`의 화면 노드 선택은 `SpatialSetupView.selected`와 연결되어 메뉴·편집 대상이 같은 상태를 사용함. SceneKit의 가장 앞쪽 피격 노드에서 모니터 부모 ID를 찾으므로 뒤에 가려진 모니터를 관통해서 선택하지 않음. 화면 내용 대신 프레임 색으로 선택을 표시함.

검증: `swift test` 종료 코드 0, Swift Testing 58개·XCTest 6개 통과함. 추가 회귀는 혼합 배율의 위쪽 정렬·물리 간격, 외장 아래 내장 배치·전역 원점 이동 불변성과 실제 offscreen SceneKit hitTest의 모니터/다른 물체/빈 공간 선택을 검사함. 실제 설정창의 시점별 클릭·사용자 체감은 미검증임. 실행 중 앱 번들과 프로세스는 교체하지 않았음.


## 본인 계정 DMG 직접 배포 — 2026-11-11

사용자가 본인 Apple Developer 계정으로 만든 DMG 배포를 먼저 진행하고 최종적으로 App Store 제출을 원했음. 같은 날 App Store 제출을 하지 않고 DMG 직접 배포만 하기로 결정했음([spec](spec.md#배포-경로--2026-11-11-사용자-지시)). 직접 배포는 App Store 밖에서 받은 앱이 Gatekeeper를 통과하도록 Developer ID 서명과 Apple 공증을 거치는 경로임. 공증은 Apple이 제출물을 자동 검사한 뒤 통과 기록(ticket)을 발급하는 절차임. 위의 2026-09-14 Developer ID 서명은 이전 팀 인증서의 이력이며, 이번 경로의 기본 팀은 사용자 팀 K8QJH6APX6임.

```text
build-app.sh(release, hardened runtime) → --smoke-test → DMG 조립·서명 → notarytool 제출 → stapler 첨부 → spctl 확인
```

### 한 번만 하는 준비

| 항목 | 방법 | 완료 확인 |
| --- | --- | --- |
| Developer ID Application 인증서 | Keychain Access의 Certificate Assistant로 CSR을 저장하고 developer.apple.com Certificates에서 Developer ID → Developer ID Application(G2 Sub-CA)으로 발급한 `.cer`을 키체인에 추가. Account Holder만 발급 가능 | `security find-identity -v -p codesigning`에 `Developer ID Application: … (K8QJH6APX6)` 표시 |
| 공증 키체인 프로필 | account.apple.com에서 앱 암호를 만든 뒤 `xcrun notarytool store-credentials privacy-airpods-notary --apple-id <Apple ID> --team-id K8QJH6APX6` 실행, 암호는 프롬프트에 입력 | `xcrun notarytool history --keychain-profile privacy-airpods-notary` 종료 0 |

2026-11-11 갱신 직후 Xcode는 개인 팀의 역할을 Admin으로 표시하며 Developer ID 생성을 Account Holder 전용 오류로 거부했음. 웹 포털 발급은 성공했으므로 Xcode 경로를 기본 절차로 두지 않음. `!` 입력에서 `store-credentials`의 숨김 암호 입력은 401로 실패했으며 별도 터미널에서 성공했음. 팀 ID가 다르면 `TEAM_ID`, 프로필 이름이 다르면 `NOTARY_PROFILE` 환경 변수로 바꿈. 같은 팀에 Developer ID 인증서가 여럿이면 `DEVELOPER_ID_IDENTITY`에 SHA-1을 지정함. 앱 암호는 키체인에만 저장하며 저장소와 스크립트에 넣지 않음.

### 실행

```sh
./scripts/package-dmg.sh                # 서명·DMG·공증·첨부·Gatekeeper 확인
./scripts/package-dmg.sh --no-notarize  # 공증 없이 서명과 DMG 조립만 확인
```

결과는 `.build/distribution/<시각>/Privacy-AirPods-<버전>.dmg`임. 공증 전에 서명된 실행 파일을 `--smoke-test`로 실행해 주 화면에 실제 가림 창을 열고, 마스크를 갱신하고, 닫는지 확인함. 실패하면 `smoke-test.log`를 남기고 중단함. 이때 주 화면이 잠깐 흐려짐. 공증 상태가 Accepted가 아니면 같은 폴더에 `notary-result.json`과 `notary-log.json`을 남기고 실패함. 배포할 때마다 Info.plist의 `CFBundleShortVersionString`(사용자에게 보이는 버전)과 `CFBundleVersion`(빌드 번호)을 올림. DMG에만 ticket을 첨부하며 앱 단독 첨부는 하지 않음. 공증 log의 ticket 내용에 DMG 안의 앱과 실행 파일이 포함됨을 확인했음.

### 변경과 이유

- 앱 ID를 `local.privacy-with-airpod.app`에서 `io.enjoy301.PrivacyAirPods`로 바꾸고 버전 0.1.0을 추가함. 앱 ID는 사용자의 기존 iOS 앱 접두사를 따랐으며 2026-11-11 사용자가 확정했음. 앱 ID가 바뀌어 동작 권한을 한 번 다시 허용해야 함.
- Swift 6.4의 기본 build system(swiftbuild)은 실행 파일의 SDK 기록을 최소 OS인 15.0으로 남겼음. 같은 소스를 native로 빌드하면 27.0이 기록됨. 시스템 framework는 이 기록으로 구 SDK 호환 동작을 고를 수 있으므로 build-app.sh는 native를 사용하고 기록이 현재 SDK와 다르면 실패함. native는 deprecated 경고를 출력하며, 제거되어 swiftbuild로 돌아가면 이 검사가 실패로 알림.
- 배포 후보는 개발 번들과 같은 build-app.sh 조립 경로를 사용하고 release 구성에서만 hardened runtime과 보안 타임스탬프를 붙임. 추가 entitlement는 없음.
- DMG는 macOS 27에서 deprecated된 `hdiutil create` 대신 `diskutil image create from`으로 만듦. 이 명령이 없는 이전 macOS에서는 스크립트가 실패함.

### 검증

- 개발 인증서와 `--no-notarize`로 실행해 종료 0. DMG 안의 앱과 `/Applications` 링크, APFS 볼륨 이름 `Privacy AirPods`, 앱의 runtime 플래그·보안 타임스탬프, `codesign --verify --strict --deep` 통과, SDK 27.0·최소 15.0 기록을 확인함. Apple Development 서명이므로 `spctl` rejected는 예상 결과임.
- 같은 hardened runtime 앱을 실행해 프로세스 유지와 오류 로그 없음을 확인한 뒤 종료함. 보호 시작(비공개 backdrop과 소유 Space)과 AirPods 입력은 실행하지 않았으므로 hardened runtime에서의 실제 보호 동작은 미검증임.
- 개발 기본 구성을 별도 경로에 빌드해 SDK 27.0 기록과 서명을 확인함. 사용 중인 `.build/Privacy AirPods.app`은 교체하지 않았음.
- 인증서 없음, 공증 프로필 없음, 잘못된 인자의 실패 메시지를 확인함.
- 사용자 Developer ID(`K8QJH6APX6`, 2027-12-11 만료)로 전체 실행 종료 0. 제출 `2d5cdd93-e598-4225-9447-16aeeda3df39`는 Accepted, issues 없음. `stapler validate` 통과, DMG와 앱 모두 `spctl` accepted `source=Notarized Developer ID`. 산출물은 `.build/distribution/20261111-184704/Privacy-AirPods-0.1.0.dmg`임.
- 품질 정리 판본 0.1.1(빌드 2) 재배포: 전체 실행 종료 0. release `--smoke-test` OK, 제출 `6e701bd2-4bf0-47bb-a8fa-0381bfe86cb4` Accepted, issues 없음, ticket 항목 3개(DMG, 앱, 실행 파일). `stapler validate` 통과, DMG와 앱 모두 `spctl` accepted `source=Notarized Developer ID`. 실행 파일 기록은 SDK 27.0, 최소 15.0이며 `OWNED_SPACE` 문자열은 없음. 산출물은 `.build/distribution/20261111-204934/Privacy-AirPods-0.1.1.dmg`(307,710 bytes, SHA-256 `9998f67216bef538f1e56fc09fec3191d5356da4dacdf4280e0e87e92d41979c`)임.
- 업데이트 기능을 넣은 0.1.2(빌드 3) 배포: 전체 실행 종료 0. release `--smoke-test` OK, 제출 `e0921b6a-2a95-4c84-8c37-9ed61e44de96` Accepted, issues 없음. ticket 항목 17개에 앱, 실행 파일, Sparkle framework, Autoupdate, Updater.app이 포함됨. `stapler validate` 통과, DMG와 앱 모두 `spctl` accepted `source=Notarized Developer ID`. 산출물은 `.build/distribution/20261111-214459/Privacy-AirPods-0.1.2.dmg`(1,189,499 bytes, SHA-256 `5f9e94a7e8e340913cad698ea958535398b8b8c00a8435caac27d536930251f6`)이며 GitHub Release `v0.1.2`로 공개함.
- DMG 사본에 quarantine 속성을 붙여 내려받은 파일을 모사했을 때 DMG와 마운트한 앱 모두 accepted였음. 실제 다운로드 경로와 다른 Mac의 첫 실행은 미확인임. arm64 전용 빌드이며 Intel Mac은 대상이 아님.
- 품질 정리 뒤 사용자 Developer ID로 `--no-notarize` 실행 종료 0. hardened runtime release 실행 파일의 `--smoke-test`가 `smoke-test OK`로 끝나 비공개 backdrop과 소유 Space의 가림 시작, 마스크 갱신, 종료가 이 Mac에서 동작함을 확인함. AirPods 입력과 다른 Mac, 공증된 새 판본은 미확인임.

### App Store 경로를 제외한 근거

2026-11-11 사용자가 DMG 직접 배포만 하기로 결정했으므로 아래는 다시 검토할 때의 기록임. 실제 보호가 비공개 backdrop과 CGS Space 함수에 의존하므로 [배포 경계 조사](blur-research.md#시스템-합성-후보와-배포-경계)의 App Review 2.5.1 조건상 현재 판본은 제출 대상이 아님. 제출하려면 실제 보호 출력을 공개 API 경로로 바꿀지 사용자 결정이 먼저 필요함. 그 뒤에도 App Sandbox 적용과 실기기 재검증, Mac App Store용 인증서와 provisioning profile, 앱 아이콘, 앱 이름의 Apple 상표(AirPods) 사용 검토, Xcode 프로젝트 기반 archive·업로드 전환이 남음.

## 코드 품질 정리 — 2026-11-11

사용자가 확장성, 테스트 품질(억지 unit보다 e2e 위주), bad smell과 회귀 점검을 요청하고 저장소 소유를 위임함. 정리 전 상태는 Git 첫 커밋(`chore: 품질 정리 전 기준 판본 추가`)이며 정리는 두 번째 커밋임. 저장소는 사용자 지시로 public `philosophia301/privacy-with-airpod`에 올렸음. 공개 전에 다른 팀 인증서 이름과 팀 ID를 이력 기록에서 사용자 팀 기준 표현으로 바꿨음.

### 발견과 조치

| 분류 | 발견 | 조치 |
| --- | --- | --- |
| 죽은 코드 | 실제 보호에서 쓰지 않는 캡처 출력(`CapturedScreenOutput`, `MetalPresenter`, `CaptureReadiness`)과 `PanoramaProfile`, `LatestRenderWork.discardPending`, 깨진 `benchmark-renderer` | 코드와 그 테스트를 삭제함. 쓰지 않는 Info.plist 화면 기록 설명도 삭제함 |
| 구조 | `AppModel`이 센서, 시계, 화면 목록, 알림을 직접 만들어 흐름 검사가 불가능했고 모든 상태를 외부에서 쓸 수 있었음 | `HeadMotionSource`, `FrameClock`, 화면 목록 공급, 알림 센터를 주입받음. 흐름 상태는 `private(set)`이고 `startProtection()`, `stopProbe()` 같은 흐름 함수로만 바뀜 |
| 중복 | smoothstep 3곳, 시야 폭과 전환 각도 계산 2곳(`AppModel`, `SpatialScene`), 화면 정렬 2곳, 창 레벨 상수 2곳, `--built-in-only` 해석 2곳 | `smoothstep`, `CompiledLayout`, `DisplayLayout.leftToRight`, `WindowLevels`, `LaunchOptions` 한 곳으로 모음 |
| 타입 | `RenderSettings`가 선택 필드의 우선순위로 모드를 표현하고, 사람 모형을 문자열로 비교함 | `RenderSettings.Field` enum(`covered`, `hinge`, `spatial`)과 `HumanGuide` 타입을 사용함 |
| 수명 | `ScreenCover.stop()`이 동기 정리 뒤 빈 `Task`를 반환함. backdrop 상태가 IUO와 강제 unwrap에 의존함 | 반환값 없는 정리로 바꾸고 저장 속성을 비옵셔널로 초기화함 |
| 회귀 | 기본 swiftbuild에서 Blur Lab과 벤치마크 빌드가 object 경로를 찾지 못해 실패함. 링크 목록이 삭제된 소스의 오래된 object도 포함함 | 진단 빌드에 `--build-system native`를 지정하고 현재 소스에 대응하는 object만 링크함 |
| 테스트 | 흐름 테스트가 `protected = true`처럼 불가능한 상태를 직접 주입했고 내장 화면이 없으면 실패함. 고개 회전이 실제 가림 마스크를 바꾸는 핵심 경로는 검사하지 않았음 | 아래 e2e로 교체함 |
| 갱신 비용 | 설정 창 레벨 지정이 매 갱신마다 비동기 작업을 예약함 | 창 연결 시점과 값이 바뀔 때만 적용함 |

`AppModel`의 입력 판정, 보정, 배치, 보호 정책 자체는 바꾸지 않았음. 보호 시작은 이제 `toggleProtection()`이 다음 MainActor 차례에 시작하며 사용자에게 보이는 차이는 없음.

### e2e 테스트 구성

`ProtectionFlowTests`는 실제 `AppModel`, `ScreenCover`, 비공개 backdrop 가림 창을 주 화면에서 실행하고 WindowServer에 제출한 마스크 알파를 관측함. 대역은 `Tests/PrivacyAppTests/Support/ProtectionHarness.swift`의 AirPods 입력, 수동 시계, 별도 알림 센터뿐임. 배치는 화면 크기와 무관하게 40cm 화면을 정면 60cm에 둔 값을 적용함.

| 흐름 | 관측 |
| --- | --- |
| 정면 → 고개 회전 | 정면은 전체 선명, 오른쪽 45°는 왼쪽부터 가림, 왼쪽 45°는 대칭, 90°는 전체 가림. 급회전 첫 주기는 부분 가림 |
| 늦게 도착한 과거 sample | 마스크와 보호 상태가 바뀌지 않음 |
| 입력 중단 6종(무응답, 센서 오류, 이어버드 교체, 오래된 sample, 잠자기, 입력 중지) × 옵션 2종 | 기본은 보호 해제. 옵션을 켜면 전체 가림 유지, 재착용과 재보정 시도로 풀리지 않고 옵션을 끌 때 해제 |
| 화면 구성 변경 | 보호 중지, 배치 폐기, 새 배치 적용 전 시작 불가 |
| 출력 실패 | 검은 비상 가림 유지. 값 복구나 옵션 변경으로 풀리지 않고 보호 끄기로만 닫힘 |
| 배치 적용 | 옆 화면은 정면에서 가려지고 바라보면 선명해짐. 보호 중 변경과 잘못된 배치는 거부 |
| 시작 조건 | 입력, 정면 보정, 배치 중 하나라도 없거나 입력이 끊기면 시작 거부 |
| 유휴 | 미리보기, 입력, 보호가 모두 없으면 주기 갱신을 멈춤 |

실제 Core Image 렌더, backdrop 마스크 바이트, 렌더 작업 병합, SceneKit 선택과 시점, Core Motion 콜백 전달, PrivacyCore 각도 계약 검사는 유지함. 실제 AirPods 머리 움직임, 사람이 보는 외형, Spaces 전환, 다중 화면은 이 테스트가 증명하지 않음.

### 검증

- `swift test` 종료 0, 경고 없음. XCTest 6개, Swift Testing PrivacyCore 11개와 앱 29개(입력 중단 12개 사례 포함 40개 사례) 통과. 정리 전은 XCTest 6개, Swift Testing 58개였으며 줄어든 수는 삭제한 죽은 코드의 테스트와 상태 주입 테스트를 e2e로 합친 결과임.
- 결함 주입 8종 중 7종을 e2e가 잡음: 과거 sample 수용, 좌우 방향 무시, 화면 변경 뒤 배치 유지, 보호 중 재보정 허용, 평활화 제거, 주기 갱신 상시 실행, 전체 가림 유지 옵션 무시. 남은 1종(일시 중단 상태의 가림 조건 제거)은 일시 중단마다 정면 기준이 이미 없어 결과가 같은 중복 안전장치임.
- `swift build --build-system native`는 native deprecated 안내 외 경고 없음. `python3 scripts/diagnostics/build-blur-lab.py` 종료 0. `verify-diagnostics.py --jobs 4 --replay-manifest …` 10/10 ok.
- 디버그 실행 파일의 `--smoke-test` 종료 0. `./scripts/build-app.sh`로 조립한 개발 앱이 880×760 설정 창을 열고 정상 종료함. Developer ID `--no-notarize` 결과는 위 DMG 검증에 기록함.
- 제품 소스는 2243줄에서 2027줄, 테스트는 1060줄에서 958줄로 줄었음.

### 후속 정리

- 설정 창과 메뉴가 sample마다 다시 계산되던 문제: `AppModel`이 sample, sample 수, 상태 문구를 매번 publish했음. sample 수, 현재 각도, 미리보기 프레임은 `LiveReadout`으로 옮기고 이를 쓰는 작은 view만 관찰하게 함. 상태 문구에는 sample 수를 넣지 않고 값이 바뀔 때만 갱신함. e2e `steadyHeadInputRedrawsOnlyLiveReadoutNotWholeSettingsWindow`가 고개 유지 2초(sample 40개) 동안 `AppModel` 변경 알림 0회와 가림 마스크 추종을 함께 확인함. 결함 3종(수신 상태 매번 갱신, 상태 문구에 sample 수 포함, 입력 중단 뒤 각도 미갱신)을 넣으면 실패함.
- 배포 앱의 Space 진단 로그: `PrivacyBackdrop.m`의 `OWNED_SPACE` 기록을 `DEBUG` 빌드에만 남김. release 실행 파일의 문자열 0개, debug 4개를 확인함. Lab과 테스트는 debug object를 쓰므로 기존 진단 로그가 유지됨.
- 검증: `swift test` 종료 0(앱 Swift Testing 30개), Blur Lab 빌드, 진단 10/10, Developer ID `--no-notarize`와 release `--smoke-test` 통과. 개발 앱에서 미리보기가 표시되고 수동 각도 +60°에 따라 바뀌는 것을 화면으로 확인함.

### 남은 위험

- 보호 중 설정 창이 가림 위로 올라오는 동작은 창 레벨 단위 검사로만 확인했으며 실제 AirPods 보호 중 화면 확인은 하지 않았음.
- 정리 판본은 0.1.1로 다시 공증했음. 외부 공개 위치(GitHub Release 등)와 다른 Mac의 첫 실행은 미정이거나 미확인임.

## 앱 내 업데이트와 필수 업데이트 — 2026-11-11

사용자 결정과 네트워크 경계는 [spec](spec.md#앱-내-업데이트와-필수-업데이트--2026-11-11-사용자-결정)이 소유함. 업데이트는 Sparkle 2.10.1(판본 고정)을 씀. Sparkle은 macOS 앱 업데이트 오픈소스 라이브러리이며, appcast(판본 목록 RSS)를 읽어 새 판본을 찾고 EdDSA 서명이 맞는 파일만 설치함.

```text
실행 시 + 하루 1회 → appcast.xml(main, raw URL) → 새 항목?
  ├─ criticalUpdate 기준보다 낮은 빌드 → UpdateState.requiredVersion → 설정 창과 배치 시트 차단
  ├─ 일반 업데이트 → Sparkle 표준 안내
  └─ 실패, 오프라인 → 판정 유지(막지 않음)
업데이트 버튼 → Sparkle 표준 창 → DMG 내려받기 → EdDSA와 코드 서명 확인 → 교체, 재실행
```

### 구성

| 경로 | 역할 |
| --- | --- |
| `Sources/PrivacyAirPods/UpdateState.swift` | 필수 판정 상태와 설정 창 차단 modifier. Sparkle을 import하지 않아 Blur Lab에도 컴파일됨 |
| `Sources/PrivacyAirPods/SparkleUpdater.swift` | `SPUUpdater` 생성, 실행 시 확인, delegate로 판정 전달. Lab 빌드에서 제외 |
| `Resources/Info.plist` | `SUFeedURL`(main의 raw appcast), `SUPublicEDKey`, `SUEnableAutomaticChecks`. `CFBundleDevelopmentRegion`을 `ko`로 두어 Sparkle 창도 한국어로 표시함. 없으면 앱에 지역화 폴더가 없어 영어로 나옴 |
| `scripts/build-app.sh` | `Sparkle.framework`를 `Contents/Frameworks`에 넣고 XPC 서비스를 지운 뒤 Autoupdate, Updater.app, framework, 앱 순서로 같은 인증서로 서명. `codesign --verify --strict --deep`로 확인 |
| `scripts/publish-update.py` | DMG 안 앱의 판본과 서명 확인, 공증 ticket 확인, EdDSA 서명, GitHub Release 생성, appcast 항목 추가 |
| `appcast.xml` | 배포 판본 목록. 스크립트가 맨 위에 항목을 추가하고 사람이 커밋과 push를 함 |

샌드박스 앱이 아니므로 Sparkle의 Installer, Downloader XPC 서비스는 쓰지 않음. hardened runtime의 library validation 때문에 framework 안쪽 실행 파일도 앱과 같은 팀 인증서로 다시 서명함.

### 서명 키

EdDSA 비밀 키는 `generate_keys --account privacy-airpods`로 만들어 이 Mac의 로그인 키체인에 있음. 공개 키는 Info.plist의 `SUPublicEDKey`임. 비밀 키를 잃어도 업데이트 경로는 끊기지 않음. Sparkle은 일반 앱 업데이트(DMG, zip)에서 EdDSA 서명과 Apple 코드 서명 중 하나만 맞으면 설치함(`SUUpdateValidator`의 키 교체 규칙, `SUVerifyUpdateBeforeExtraction`을 켜지 않은 경우). 새 키를 만들어 새 공개 키를 Info.plist에 넣고, 같은 팀 Developer ID로 서명한 판본을 새 키로 서명해 내면 기존 앱이 코드 서명으로 받아들이고 이후는 새 키로 이어짐. 키와 같은 팀의 Developer ID 서명을 함께 잃으면 기존 앱은 업데이트를 받을 수 없음. 로그인 키체인 항목은 iCloud 키체인으로 동기화되지 않으며 이 Mac은 Time Machine 대상이 없음. 다른 곳에도 두려면 `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account privacy-airpods -x <파일>`로 내보내 암호 앱 같은 암호화 저장소에 넣고 내보낸 파일은 지움. `sign_update`가 키에 처음 접근할 때 키체인 암호 창이 뜨며 "항상 허용"을 고르면 다음 배포부터 묻지 않음.

### 배포 절차

1. `Resources/Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 올림. Sparkle은 `CFBundleVersion`(빌드 번호)로 새 판본을 판정함.
2. `./scripts/package-dmg.sh`로 공증 DMG를 만듦.
3. `scripts/publish-update.py <DMG>`를 실행함. 필수로 만들려면 `--required-below <빌드>`를 붙임. 예: 빌드 4를 내며 `--required-below 4`면 빌드 3 이하가 막힘. 기존 항목의 필수 기준이 더 높으면 그 기준을 이어 붙임. Sparkle은 가장 새 항목의 표시만 보므로 이어 붙이지 않으면 오래된 앱이 풀림.
4. 바뀐 `appcast.xml`을 커밋하고 main에 push함. raw URL 캐시 때문에 앱이 보기까지 몇 분 걸릴 수 있음.

로컬 시험은 `--local-base-url http://127.0.0.1:<포트>/ --appcast <폴더>/appcast.xml`로 GitHub 없이 appcast만 만들고, 그 폴더를 `python3 -m http.server`로 띄움. 시험 앱은 번들 ID와 `SUFeedURL`을 바꿔 다시 서명한 사본을 씀.

### 검증

- `swift test` 종료 0. XCTest 6개, Swift Testing 43개 통과. 새 e2e `RequiredUpdateFlowTests`는 가짜 설치 번들(빌드 3)과 127.0.0.1의 appcast로 실제 Sparkle을 돌려 네 경우를 확인함: 빌드 4 미만 필수면 차단, 빌드 3 미만 필수면 제안만 받고 차단 없음, 최신이면 제안 없음, 서버 연결 거부면 차단 없음. 업데이트 버튼이 같은 updater의 사용자 확인을 여는지도 확인함. 결함 3종(critical 무시, 실행 시 확인 제거, 버튼 미연결)을 넣으면 각각 실패함.
- 파일 URL appcast는 Sparkle이 거부함("download request URL must use http or https"). 그래서 시험 서버를 `Network`의 로컬 listener로 둠.
- `./scripts/build-app.sh`(개발 인증서)와 Developer ID release 조립 모두 `codesign --verify --strict --deep` 통과. framework 안 Autoupdate가 `Developer ID Application: Eunjong Kim (K8QJH6APX6)`, runtime 플래그, 보안 타임스탬프를 가짐. release `--smoke-test` OK. Blur Lab 빌드 종료 0, 진단 10/10 ok(전부 캐시, 이번 변경과 무관한 오프라인 계약).
- 로컬 실물 흐름: Developer ID로 다시 서명한 시험 번들(`io.enjoy301.PrivacyAirPods.e2e`) 0.1.2(빌드 3)를 실행하고, `publish-update.py --local-base-url`로 만든 0.1.3(빌드 4, 빌드 4 미만 필수) appcast를 `python3 -m http.server`로 제공함.
  - 실행 직후 appcast를 받고 Sparkle의 중요 업데이트 창이 뜸. 설정 창은 모든 조작이 disabled이고 "필수 업데이트 0.1.3" 안내가 덮음.
  - 업데이트 설치 → DMG 내려받기, EdDSA 확인 뒤 "설치 준비 완료" → 설치 후 재실행. 같은 경로의 앱이 0.1.3(빌드 4)으로 바뀌고 서명 검사 통과, 재실행한 앱의 설정 창은 막히지 않음. 마지막 "설치 후 재실행" 클릭은 자동 조작이 오류를 반환한 뒤 설치가 진행되어 누가 눌렀는지는 확정하지 못함.
  - Sparkle 창을 닫은 뒤에도 설정 창은 막힌 채이고 안내의 업데이트 버튼이 Sparkle 창을 다시 엶. `CFBundleDevelopmentRegion` 추가 뒤 Sparkle 창이 한국어로 표시됨.
  - 서버를 끈 채 구판본을 실행하면 설정 창이 막히지 않음.
- 실제 공개(2026-11-11, 사용자 승인): `publish-update.py`로 GitHub Release `v0.1.2`(태그는 판본 커밋 `224f720`)를 만들고 appcast 항목을 main에 push함. Release 주소에서 받은 DMG는 크기와 SHA-256이 원본과 같고, quarantine을 붙여도 `spctl` accepted `Notarized Developer ID`임. raw appcast는 push 뒤 약 3분 30초 만에 새 항목을 돌려줌(`cache-control: max-age=300`).
- 실제 주소 업데이트: 0.1.2 앱을 0.1.1(빌드 2)로 바꿔 다시 서명한 사본을 scratchpad에서 실행함. 실제 raw appcast에서 0.1.2를 일반 업데이트(나중에, 설치, 건너뛰기)로 제안했고 설정 창은 막히지 않음. 설치를 고르면 GitHub에서 받고 EdDSA 확인 뒤 "설치 & 재실행"으로 교체함. 교체된 앱은 0.1.2(빌드 3)이고 실행 파일이 배포 산출물과 같으며 `spctl` accepted `Notarized Developer ID`, 재실행 뒤 추가 제안 없음. 이번에도 마지막 클릭은 자동 조작이 오류를 반환했으나 직후 설치가 진행되어, 클릭 직후 창이 바뀌어 검증만 실패한 것으로 봄. 시험 뒤 실제 앱 ID의 사용자 기본값에 생긴 `SULastCheckTime`, `SUUpdateGroupIdentifier`와 캐시 폴더를 지움.
- 실제 설치본 업데이트(2026-11-11, 사용자 지시): 새 아이콘이 든 0.1.3(빌드 4)을 필수 표시 없이 공개함. 태그 `v0.1.3`은 판본 커밋 `6e313a5`, appcast 커밋은 `9797626`. Release에서 받은 DMG의 SHA-256이 원본과 같음(`54a9aeaa…`, 1,894,012바이트). raw appcast는 push 직후 새 항목을 돌려줌. `/Applications`의 실제 0.1.2(빌드 3)를 다시 실행하자 실행 시 확인으로 0.1.3을 일반 업데이트(나중에, 업데이트 설치, 이 버전 건너뛰기)로 제안함. 업데이트 설치 → 내려받기와 "설치 준비 완료" → "설치 & 재실행"으로 같은 경로가 0.1.3(빌드 4)으로 바뀌고 재실행됨. 교체된 앱은 `codesign --verify --strict --deep` 통과, `spctl` accepted `Notarized Developer ID`이며 메뉴의 업데이트 확인이 "0.1.3 이(가) 현재 최신 버전입니다"를 보여줌. 마지막 클릭은 이번에도 자동 조작이 결과를 돌려주기 전에 앱이 종료되어 응답이 비었고 직후 설치가 진행됨.
- 0.1.4 공개(2026-11-12, 사용자 지시): 메뉴 막대 아이콘, 설정 창 2-2, 배치 수정 지도 시트, 정면 기준 수정을 필수 표시 없이 공개함. 사용자가 개발 빌드를 실제 AirPods로 확인한 뒤 배포를 지시했고, appcast 공개 직전에 다시 확인받음. 태그 `v0.1.4`는 판본 커밋 `141c7cd`, appcast 커밋은 `153d039`. Release에서 받은 DMG는 3,222,651바이트로 SHA-256이 원본과 같고(`590fb6cb…`), quarantine을 붙여도 `spctl` accepted `Notarized Developer ID`임. 앱의 `SUFeedURL` 주소가 push 직후 빌드 5를 맨 위 항목으로 돌려줌. 개발 빌드를 끄고 `/Applications`의 실제 0.1.3(빌드 4)을 실행하자 실행 시 확인으로 0.1.4를 일반 업데이트(나중에, 업데이트 설치, 이 버전 건너뛰기)로 제안했고 설정 창은 막히지 않음. 사용자 지시로 업데이트 설치 → "설치 & 재실행"을 눌러 같은 경로가 0.1.4(빌드 5)로 바뀌고 재실행됨. 교체된 앱은 `codesign --verify --strict --deep` 통과, `spctl` accepted `Notarized Developer ID`이며 새 설정 창("Privacy AirPods 설정")이 열림. 이번 클릭은 System Events로 했고 두 단추 모두 정상 응답함.
- `publish-update.py`의 거부 경로: 같은 빌드 재게시, 이번 빌드보다 높은 필수 기준, 판본과 다른 DMG 이름에서 appcast를 바꾸지 않고 종료 1.
- 시험 뒤 시험 번들의 사용자 기본값과 캐시를 지웠음. 시험 폴더는 scratchpad에만 있음.

### 남은 위험

- 배치 시트가 열린 상태에서 필수 판정이 들어오면 시트를 닫는 동작은 화면으로 확인하지 않았음. 실행 중 판정은 하루 주기 확인이나 메뉴의 업데이트 확인에서만 생김.
- 메뉴 막대의 보호 켜기와 끄기가 차단 중에도 동작하는 것은 메뉴가 차단 modifier를 쓰지 않는 코드 구조로만 확인했으며, 차단 상태에서 실제 AirPods 보호는 실행하지 않았음.
- 실제 Release 경로의 필수(critical) 차단은 로컬 서버로만 확인함. 0.1.1 이하는 업데이트 기능이 없어 0.1.2를 직접 설치해야 함.
- EdDSA 비밀 키는 이 Mac 로그인 키체인에만 있음. 잃으면 위 키 교체 규칙으로 새 키로 넘어가야 하며, 이 경로는 Sparkle 소스로만 확인하고 실제로 시험하지 않았음.

## 앱 아이콘 — 2026-11-11

사용자 결정은 [spec](spec.md#앱-아이콘--2026-11-11-사용자-결정)이 소유함. 아이콘은 사용자가 준 아기상어 그림에서 캐릭터만 오려 단색 배경에 놓고, 앱의 가변 블러처럼 오른쪽으로 갈수록 흐리게 만든 것임. 캐릭터는 다시 그리지 않음.

### 구성

| 경로 | 역할 |
| --- | --- |
| `docs/assets/app-icon/baby-shark-source.png` | 사용자가 준 원본(282×222). 아이콘의 유일한 입력 |
| `scripts/make-app-icon.py` | 캐릭터 오리기, 배경과 가변 블러, macOS 아이콘 템플릿(1024px 안의 824px 둥근 사각형과 그림자), `iconutil`로 `.icns` 만들기. 결정값(배경색, 흐림 시작과 끝, 최대 반경)은 파일 머리에 있음 |
| `Resources/AppIcon.icns` | 16~512pt의 1x, 2x 10장. 스크립트 산출물이며 빌드는 이 파일만 씀 |
| `Resources/Info.plist` | `CFBundleIconFile`을 `AppIcon`으로 둠 |
| `scripts/build-app.sh` | `.icns`를 `Contents/Resources`에 복사한 뒤 서명함 |

원본의 캐릭터 외곽선은 뒤의 물결, 체크무늬와 같은 갈색이라 색만으로 나눌 수 없음. 그래서 노란 면과 배의 흰 면에서 외곽선 두께(원본 기준 7px)까지만 넓히고, 이미지 가장자리와 이어진 바깥과 물결 안쪽 색은 뺌. 이 임계값은 이 원본에 맞춘 값이라 그림을 바꾸면 결과를 보고 다시 맞춰야 함. 생성형 업스케일러(SeedVR2)는 홍채와 볼 띠에 원본에 없는 얼룩 질감을 더해서 쓰지 않고 Lanczos 확대와 약한 선명화만 씀.

### 다시 만들기

`scripts/make-app-icon.py`를 실행하면 `Resources/AppIcon.icns`를 덮어씀. `--png <경로>`를 붙이면 1024px 원본도 저장함. Pillow와 numpy가 필요함. 재실행 결정성은 아직 확인하지 않음.

### 검증

- 두 번 생성한 `.icns`의 SHA-256이 같음(`09c1a6df…`). 캔버스 시안을 만든 경로와의 픽셀 차이는 최대 2/255임.
- `iconutil --convert iconset`으로 되풀어 16~512pt 1x, 2x 10장을 확인함.
- `APP_DIR`을 scratchpad로 둔 `./scripts/build-app.sh`(개발 인증서) 조립에서 `Contents/Resources/AppIcon.icns`가 저장소 파일과 같고, `CFBundleIconFile`이 있으며, `codesign --verify --strict --deep`가 통과함.
- `NSWorkspace.icon(forFile:)`로 받은 시스템 아이콘이 새 아이콘으로 보임(macOS 27). 시스템이 둥근 사각형 가장자리에 자체 테두리 효과를 더하며, 규격 밖 아이콘을 회색 틀 안에 작게 넣는 처리는 없었음. 같은 방법으로 본 설치본 0.1.2는 기본 아이콘임.
- 0.1.3 배포(2026-11-11): release 조립, 공증, ticket 첨부, `spctl` 통과. Sparkle로 교체된 `/Applications` 앱의 `AppIcon.icns`가 저장소 파일과 같고, `NSWorkspace.icon(forFile:)`(Finder가 쓰는 시스템 아이콘)과 Sparkle의 "최신 버전입니다" 창이 새 아이콘을 보여줌. 업데이트 제안 창은 실행 중인 구판본의 아이콘을 쓰므로 0.1.2에서 올 때는 기본 아이콘으로 보임. 앱 아이콘이 0.7MB라 DMG가 1.19MB에서 1.89MB로 커짐.

### 남은 위험

- 원본이 282×222라 512px 이상으로 크게 보면 외곽선이 조금 부드러움. 고해상도 원본을 받으면 같은 스크립트로 다시 만들 수 있으나 오리기 결과를 다시 봐야 함.
- Dock 표시는 Dock 자동 숨김 때문에 화면으로 보지 않았음. Dock도 같은 번들 아이콘을 쓰므로 다르게 보일 이유는 확인되지 않음.

## 메뉴 막대 아이콘 — 2026-11-12

사용자 결정은 [spec](spec.md#메뉴-막대-아이콘--2026-11-12-사용자-결정)이 소유함. 메뉴 막대 아이콘은 앱 아이콘과 같은 원본 캐릭터를 쓰고, 흐림 단계별 그림 25장을 미리 만든 뒤 앱이 시각에 맞춰 골라 보여줌. 흐림 수치는 이 절에 복사하지 않고 스크립트와 코드 상수가 소유함.

### 구성

| 경로 | 역할 |
| --- | --- |
| `scripts/make-menu-bar-icon.py` | 메뉴 막대 프레임 25장 생성. 캐릭터 마스크와 원본 경로는 `scripts/make-app-icon.py`를 불러 재사용하며 그 파일은 고치지 않음. 흐림 결정값은 파일 머리에 있음 |
| `Resources/MenuBarIcon/` | `blur-00.png`부터 `blur-24.png`까지 25장, 44×36px RGBA. blur-00은 흐림 없음, blur-24는 최대 흐림. 스크립트 산출물이며 앱은 이 파일만 읽음 |
| `Sources/PrivacyAirPods/MenuBarIcon.swift` | 리듬 규칙(`MenuBarBlurRhythm`), 프레임 로드와 색 유지(template 끔), 주기 갱신(`MenuBarIconModel`), 메뉴 라벨, 판본 문구. 프레임이 없으면 SF Symbol 눈으로 대체 |
| `Sources/PrivacyAirPods/PrivacyAirPodsApp.swift` | `MenuBarExtra`의 label을 `MenuBarIconLabel`로 두고 메뉴 맨 위에 판본 문구를 둠 |
| `scripts/build-app.sh` | `Resources/MenuBarIcon`을 앱 번들 `Contents/Resources/MenuBarIcon`에 기존 복사본을 지운 뒤 복사하고, 그다음 서명함 |

### 리듬과 갱신 방식

보호가 시작된 시각을 기준으로 한 주기를 반복함. 정지 구간은 다음 구간 경계까지 예약 한 번만 두고 프레임을 바꾸지 않음. 전환 구간에서만 10fps Timer가 프레임 번호를 바꿈. 꺼짐과 손쉬운 사용 동작 줄이기에서는 예약이 없음.

```
보호 켬 → 흐려짐(전환, 10fps) → 흐림 유지(정지) → 걷힘(전환, 10fps) → 선명(정지) → 흐려짐 …
보호 끔 → 즉시 선명, 예약 취소
```

보호 상태나 동작 줄이기 설정이 바뀌면 이전 예약을 모두 취소하고 현재 시각에 맞춰 다시 계산함. 시계는 `MenuBarIconClock`으로 주입받아 테스트가 수동 시계로 경계 시각을 확인함.

전환 갱신을 10fps로 둔 이유는 `MenuBarExtra` label 갱신 비용임. 같은 프레임과 같은 리듬으로 메뉴 막대 아이콘만 바꾸는 시험 앱을 30초씩 재면 평균 CPU(코어 하나 기준)가 아래와 같았음.

| 방식 | 평균 CPU |
| --- | --- |
| SwiftUI `MenuBarExtra` label, 15fps | 약 6.3~7.1%(5회 중 4회), 1회는 약 2.9% |
| SwiftUI `MenuBarExtra` label, 10fps | 약 2.3% |
| SwiftUI `MenuBarExtra` label, 8fps | 약 1.7% |
| AppKit `NSStatusItem` 직접 갱신, 15fps | 약 1.9~2.1% |

10fps는 AppKit 직접 갱신과 비슷한 비용이면서 메뉴를 AppKit으로 다시 만들지 않아도 됨. 2초 전환이 느려 10fps에서도 끊김이 눈에 띄지 않는 것은 시험 앱으로만 봤음.

### 다시 만들기

`python3 scripts/make-menu-bar-icon.py`를 실행하면 `Resources/MenuBarIcon/` 25장을 덮어씀. Pillow와 numpy가 필요함. 같은 입력이면 같은 파일이 나옴. 원본 그림이나 캐릭터 마스크를 바꾸면 [앱 아이콘 절](#앱-아이콘--2026-11-11)의 `make-app-icon.py`를 먼저 맞춘 뒤 이 스크립트를 다시 실행함.

### 검증

- 생성: 25장이 시안에 쓴 기준 프레임과 픽셀 차이 0임. 스크립트를 두 번 더 실행해도 25장을 이은 SHA-256이 같음.
- `swift test --filter MenuBarIcon`: 8개 통과. 보호 시작 뒤 0~21초 경계 프레임과 두 번째 주기, 정지 구간에 반복 예약 없음, 전환 중 보호를 끄면 즉시 선명하고 예약이 남지 않음, 동작 줄이기 정지와 실행 중 변경, 프레임 하나가 빠지면 SF Symbol로 대체하고 예약 없음, 프레임 25장이 22×18pt 컬러로 읽힘, 판본 문구를 확인함. 보호 상태는 실제 `AppModel`과 가림 창(`ProtectionHarness`)으로 만들고 시계와 동작 줄이기 설정만 대역임.
- 결함 주입: 흐려짐과 걷힘 순서를 바꾸면 리듬 테스트와 동작 줄이기 테스트가 실패함. 보호를 꺼도 예약을 취소하지 않게 바꾸면 끄기 테스트가 실패함. 되돌린 뒤 통과함.
- 전체 `swift test`: XCTest 6개, Swift Testing 51개 통과.
- 조립: `APP_DIR`을 scratchpad로 둔 `./scripts/build-app.sh`(개발 인증서)에서 번들 안 `MenuBarIcon` 25장이 저장소와 같고 `codesign --verify --strict --deep`가 통과함.
- 실행 앱(꺼짐): 조립한 개발 빌드를 실행하자 메뉴 막대에 선명한 컬러 아이콘이 보이고, 메뉴 맨 위에 `버전 0.1.3 (빌드 4)`가 보임. 꺼짐 상태의 CPU는 0~0.2%임.
- 보호 중 리듬: 실제 앱에서는 AirPods 입력과 보정이 있어야 보호를 켤 수 있어 보지 않았음. 같은 프레임을 `MenuBarExtra` label로 바꾸는 시험 앱에서 흐림이 실제로 움직이는 것만 확인함.

### 남은 위험

- 보호 중 10초 리듬과 동작 줄이기 정지는 실제 AirPods 보호에서 눈으로 보지 않았음.
- 전환 구간 CPU는 시험 앱 수치임. 이 앱의 보호 중 렌더링 부하와 겹친 실제 수치는 측정 전임.
- 원본이 282×222px이라 22×18pt 표시의 세부가 원본 해상도에 묶임.
- 메뉴 막대 status item은 이 macOS에서 앱 소유 CGWindow로 잡히지 않아, 실물 확인은 메뉴 막대 영역 화면 캡처로만 함.

## 설정 창 — 2026-11-12

사용자 결정은 [spec](spec.md#설정-창--2026-11-12-사용자-결정)이 소유함. 설정 창은 시안 2-2 스탬프 타일 구성을 따르며, 준비 상태 규칙과 색, 글꼴, 포즈 같은 표시 값은 `Settings/` 아래 작은 타입으로 나눠 맡음.

### 구성

| 경로 | 역할 |
| --- | --- |
| `Sources/PrivacyAirPods/Settings/` | 설정 창 전체. `SettingsView`는 상태 카드와 탭, `ReadyTab`은 준비 타일, `HideTab`은 미리보기와 슬라이더, `Readiness`는 준비 상태 파생 규칙, `CheekyTheme`은 색과 글꼴과 배지, `FinSlider`는 지느러미 슬라이더, `CharacterArt`는 상태별 포즈를 맡음 |
| `Resources/Character/` | 포즈 5장(`lost`, `think`, `relax`, `cheer`, `guard`). `scripts/cut-character-poses.py`의 산출물이며 가이드 PDF는 저장소에 없음 |
| `Resources/Fonts/` | Bagel Fat One TTF와 SIL OFL 1.1 문서 |
| `scripts/build-app.sh` | 포즈 5장과 글꼴을 번들 `Contents/Resources/Character/`와 `Contents/Resources/Fonts/`로 복사함. 파일이 하나라도 없으면 실패함 |
| `Tests/PrivacyAppTests/ReadinessFlowTests.swift` | 준비 항목 상태를 실제 설정 흐름으로 검사하는 e2e |

### 캐릭터 다시 만들기

가이드 PDF가 있을 때만 다음 명령으로 포즈 5장을 다시 만듦. `-I`는 현재 폴더의 같은 이름 모듈을 읽지 않게 하는 옵션임.

```sh
python3 -I scripts/cut-character-poses.py <가이드 PDF>
```

스크립트는 가이드 6쪽을 300dpi로 그린 뒤 회색 바탕만 투명하게 바꿈. 뒤집기와 색 변경은 하지 않음.

### 글꼴 등록과 대체

Bagel Fat One은 `Resources/Fonts/BagelFatOne-Regular.ttf`에서 번들 `Contents/Resources/Fonts/`로 복사됨. `CheekyTheme`이 번들의 TTF를 CoreText로 등록한 뒤 PostScript 이름 `BagelFatOne-Regular`로 찾고, 등록이나 조회에 실패하면 `.system(design: .rounded)` bold로 대체함. 한글 글자는 항상 시스템 글꼴을 쓰며 굵기는 medium, semibold, bold만 씀.

### 검증 방법과 결과

- `swift test --filter ReadinessFlowTests`: 준비 항목의 완료, 할 일, 기다림 상태가 실제 설정 흐름에서 나오는지 확인함. 2026-11-12 전체 `swift test`에서 Swift Testing 앱 45개, Core 11개, XCTest 6개가 통과함.
- `./scripts/build-app.sh`로 조립하고 설정 창을 `screencapture -l`로 캡처해 시안 2-2와 비교함. 2026-11-12 내장 화면에서 준비 탭(AirPods 할 일, 책상 정면 기다림, 화면 할 일)과 가리기 탭(직접 돌려보기, 고개 0°)을 확인함. 가리기 탭은 확인을 위해 시작 탭만 바꾼 임시 빌드로 캡처했고 소스는 되돌렸음.
- 시안과 다른 점: 미리보기는 시안의 그림 대신 기존 예제 화면을 실제로 흐린 결과임. 화면이 두 대 이상이면 미리볼 화면 메뉴가 붙음. 직접 돌려보기의 고개 범위는 기존과 같은 -90°~90°임.
- 2026-11-12 후속 수정: 입력 중단이나 화면 구성 변경으로 정면 기준(`deskReference`)이 사라지면 `AppModel`이 가리기 탭을 직접 돌려보기로 돌려놓음. 전에는 고를 수 없는 AirPods 보기에 남아 미리보기가 전체 블러로 멈추고 고개 슬라이더가 잠겼음. `ReadinessFlowTests.losingDeskReferenceReturnsHidePreviewFromAirPodsToManual`이 두 경로를 검사하며, 수정 전 코드에서 3건 실패를 확인했음. 같은 수정에서 메뉴 상태 문구의 '실험을 중지함'을 '화면 구성이 바뀜 · 정면과 배치를 다시 맞춰 주세요'로 바꿈.

### 남은 확인

- 실제 AirPods로 상태 카드의 포즈(`lost`, `think`, `relax`, `cheer`, `guard`) 전환과 자동 시작을 확인하지 않음. 캡처한 개발 빌드는 AirPods 입력이 없는 상태였음.
- 창은 라이트 모양으로 고정함. 시스템 다크 모드에서도 고정되는지는 확인 전임.
- 보호 중 상태 카드(노랑 바탕과 체커 띠)와 VoiceOver 읽기 순서는 화면으로 확인하지 않음.

## 배치 수정 화면 — 2026-11-12

사용자 결정은 [spec](spec.md#배치-수정-화면--2026-11-12-사용자-결정)이 소유함. 배치 수정 시트는 Design 캔버스의 배치 안 2를 따르며, 설정 창의 3D 장면(`SpatialSetupView.swift`, `SpatialScene.swift`)과 그 테스트를 대체함.

### 구성

| 경로 | 역할 |
| --- | --- |
| `Sources/PrivacyAirPods/Settings/LayoutSheet.swift` | 600 폭 배치 시트. 헤더, 지도 카드, 팔 길이 칩, 선택 패널, 고개 확인 줄, 취소와 적용을 맡음 |
| `Sources/PrivacyAirPods/Settings/LayoutMap.swift` | 위에서 본 지도(`TopLayoutMap`)와 옆에서 본 높이 그림(`SideHeightView`)을 그리고, 끌기와 키보드 입력을 편집 상태에 전달함 |
| `Sources/PrivacyAirPods/Settings/LayoutEditor.swift` | 배치 편집 상태, 좌표 변환, 끌기와 키보드 규칙, 흐림 강도 조회를 맡음. SwiftUI 뷰를 가지지 않음 |
| `Tests/PrivacyAppTests/LayoutEditingFlowTests.swift` | 지도 조작이 `AppModel`의 적용을 거쳐 실제 보호 경계를 바꾸는 e2e |

### 좌표 규칙

- 위에서 본 지도: 1cm가 1.85pt(`LayoutEditor.mapScale`)임. 머리 관측점은 지도 가로 가운데, 아래쪽에서 28pt 위에 놓임(`mapOrigin` 278, 328). 지도에서 위쪽이 앞(z)이고 오른쪽이 x임.
- 옆에서 본 높이: 1cm가 0.8pt(`LayoutEditor.sideScale`)임. 눈 위치는 그림 왼쪽에서 16pt, 그림 위쪽에서 55pt 아래에 놓임(`sideOrigin`). 가로는 거리, 세로는 눈 기준 높이임.
- 화면 위치와 모양은 `DisplayPose`의 cm 값에서 바로 계산하며, 오른쪽 끝은 (x + w/2 cos yaw, z - w/2 sin yaw)임.

### 흐림 표시

모니터 앞면 띠의 흐림은 `RenderSettings.spatial(...).strength(at:)`를 그대로 씀. `LayoutEditor.faceStrengths`가 이 호출만 감쌈. 시안의 그림과 흐림 규칙을 따로 계산하면 실제 보호와 어긋날 수 있어서 한 곳에서만 계산함.

### 관찰 경계

sample마다 바뀌는 고개 각도(`LiveReadout`)는 `TopLayoutMap`, `SideHeightView`, `GazeCheckRow`만 관찰함. 시트 본체 `body`는 readout 값을 읽지 않음. 이 경계는 `ProtectionFlowTests.steadyHeadInputRedrawsOnlyLiveReadoutNotWholeSettingsWindow` 계약과 같은 목적임.

### 지도 표기

- 화면 이름은 번호 badge 위에 둠. 1.85pt/cm 축척에서는 badge와 화면 사이가 좁아 이름이 화면 몸체와 겹침.
- 거리 고리 숫자(50, 100, 150)는 고리 왼쪽 끝 아래, 머리 높이 줄 밑에 자처럼 둠. 가운데 위에 두면 고개 방향 선과 화면에 겹침.
- 화면 메뉴의 label은 글자만 줌. AppKit 메뉴 단추는 label의 그림을 글자 앞에 놓으므로 펼침 표시는 시스템 것을 씀.

### 검증 기록

- 2026-11-12: `swift test --build-system native` 전체 통과(58개 테스트, 7개 suite, XCTest 6개), `./scripts/build-app.sh` 조립과 서명 통과.
- 2026-11-12: 사용자 화면이 모두 전체 화면 Space라 개발 앱 창 캡처(`screencapture -l`, ScreenCaptureKit)가 실패했음. 저장소 밖 복사본에서 `NSHostingView`의 `cacheDisplay`로 시트를 화면에 띄우지 않고 그려 시안과 비교했음. 기본 배치와 돌린 배치 두 상태를 봄.

### 남은 위험

- 지도의 고개 표시는 실제 AirPods 입력으로 확인하지 않음.
- 실제 창에서 끌기, 손잡이, 키보드, VoiceOver 조작은 사람 확인이 남음. 자동 검증은 `LayoutEditor` 경로와 e2e까지임.
- 옆 그림과 위에서 본 지도의 실제 크기 감각은 실물 모니터 기준으로 확인하지 않음.

## 전환 녹화 확인 — 2026-11-12

[최우선 후속](../TODO.md#최우선-후속--화면-전환의-근본-원인-조사)의 세 증상(여러 전환이 겹쳐 보임, 블러가 순간 강해짐, 이전 화면이 깜빡임)을 현재 제품 가림 경로로 다시 봤음. 현재 경로는 화면마다 NSPanel 하나를 앱 소유 독립 Space(`PBIndependentSpace`)에 붙이고 `CABackdropLayer` 가변 블러로 흐리는 방식임. 결론은 키보드 전환과 Cmd+Tab 전환에서 WindowServer 합성 화면에는 세 증상이 나타나지 않았다는 것임. 트랙패드, 물리 화면, 실제 앱 내용은 확인하지 않았으므로 해결 완료로 보지 않음.

### 시험 구성

- 화면: 27MB35(1920×1080, 60Hz)에 Orca 뒤로 전체 화면 예제 A(초록), B(자홍), C(주황)를 붙임. 예제는 16px 주기 줄무늬, 고정 난수 막대 띠, 큰 글자를 그림. 줄무늬는 선명도를, 막대 띠는 가로 이동량과 흐림 폭을 재는 용도임.
- 가림: 저장소 밖 앱 복사본에 `--cover-hold` 진입점을 붙여 제품 `ScreenCover`를 고정 설정으로 띄움. 조건은 off(가림 없음), uniform(전체 최대 블러, 반경 31.25), ramp(왼쪽 끝 최대에서 오른쪽 끝 0), ramp-live(ramp를 20Hz로 ±0.8° 흔들며 다시 냄, 실제 앱의 갱신 주기와 같음)임. 2차는 27MB35와 BK550Y를 한 독립 Space의 패널 두 개로 함께 가림.
- 입력: CGEvent로 Control+←/→, Cmd+Tab, Cmd+Tab+Tab(두 Space 건너뛰기)을 보냄. 빠른 연속 입력(0.08~0.4초 간격)과 전환 중 되돌리기를 포함함.
- 녹화: ScreenCaptureKit 화면 스트림 60fps, 바뀐 프레임만 받음. 알림 배너 앱은 녹화에서 뺌. 화면 내용은 수치로만 바꾸고, 사용자 앱 내용이 담긴 녹화(BK550Y의 브라우저)는 수치를 뽑은 뒤 지웠음.

### 증상별 지표

| 증상 | 지표 | 판정 |
| --- | --- | --- |
| 여러 전환이 겹쳐 보임 | 프레임마다 보이는 예제 구성(A/B/C 구간), 세 Space 이상이 함께 보인 프레임 수, 경계 궤적의 방향 바뀜, 정착 시간과 프레임 수 | off와 같은지 비교 |
| 블러가 순간 강해짐 | 막대 띠를 선명 기준에 가우시안을 씌운 모양과 맞춘 실효 σ | 정지 σ에서 25% 넘게 벗어난 프레임 수 |
| 이전 화면 깜빡임 | 보호 구간의 16px 줄무늬 진폭(정지값보다 0.03 넘게 커진 프레임), 정착 뒤 이전 구성 재등장 | 0이어야 함 |
| 블러가 내용보다 늦음 | ramp에서 흐린 왼쪽과 선명한 오른쪽의 내용 이동량 차이 | 8px 넘는 프레임 수 |
| 옆 화면 깜빡임 | BK550Y 프레임 간 평균 밝기 차와 세로 4칸 선명도 | 27MB35 전환 중과 정지 중 비교 |

### 결과

| 조건 | 입력 수(가림) | 정착 시간 off / 가림 | 세 Space 이상 | σ 벗어남 | 줄무늬 노출 | 재등장 | 흐림과 선명 이동 차 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1차: 27MB35만 가림, Control+←/→ | 92(64) | 338~342ms / 337~349ms | 0 | 0(σ 46~58, 정지 54) | 0 | 0 | -3~+1px |
| 2차: 두 화면 가림, Control+←/→ | 50(40) | 321~354ms / 324~370ms | 0 | 0(σ 48~58, 정지 54) | 0 | 0 | -3~0px |
| 2차: 두 화면 가림, Cmd+Tab | 45(27) | 343~447ms / 346~449ms | 0 | 0(σ 48~56, 정지 54~56) | 0 | 0 | -2~+2px |

- 입력 수는 각 방식의 입력만 셈. 정착 시간은 빠른 연속 입력의 앞 입력(다음 입력에 끊김)을 뺀 값임.
- 전환 하나의 프레임 수: Control은 off와 가림 모두 17~21장임. Cmd+Tab은 off 12~14장, uniform 12~15장, ramp-live 15~18장이며 ramp-live는 마스크 갱신 프레임이 더해진 것임. 방향 바뀜은 빠른 연속 Control 입력에서만 나왔고 off에서도 같은 횟수였음.
- Cmd+Tab은 입력 뒤 176~282ms 동안 화면이 멈춘 뒤 미끄러짐. 이 대기는 off에서도 같음. 두 Space 건너뛰기(C→A)는 모든 조건에서 가운데 B를 보이지 않고 바로 미끄러졌음.
- 프레임 간격: 전환 중 16.7ms 간격 비율은 off 90~94%, uniform 89~96%, ramp-live 78~91%임. ramp-live는 정지 구간에도 마스크 갱신 프레임이 들어가 비율이 낮아짐. 60ms 넘는 간격은 미끄러짐 시작 전 대기나 정착 뒤에만 있었고 off에도 있었음.
- 옆 화면 BK550Y: uniform 27초 녹화에 바뀐 프레임은 27장(브라우저 자체 깜빡임)이었음. 27MB35 입력 뒤 0.6초 구간에 든 프레임은 1~3장으로 그 밖보다 많지 않았고, 프레임 간 밝기 차 최대도 0.0011로 같았음. ramp-live에서 세로 4칸 선명도 범위는 전환 중과 정지 중이 같았음.
- 트랙패드: 90초 녹화를 했으나 손 입력이 없었고, 사용자가 이번에는 빼기로 함. 합성 제스처 도구는 macOS 27에서 Space를 옮기지 못함.

### 시험 조건 메모

Cmd+Tab이 Space를 옮기려면 시스템 설정의 '응용 프로그램 전환 시 해당 응용 프로그램의 윈도우가 열려 있는 스페이스로 전환'(`com.apple.dock workspaces-auto-swoosh`)이 켜져 있어야 함. 이 Mac은 꺼져 있어 처음 Cmd+Tab 시험에서 Space가 바뀌지 않았음. 사용자 요청으로 켰고 그대로 둠. 켠 직후 예제를 띄우면 전체 화면 요청이 데스크톱 이동 중에 무시될 수 있어 예제가 다시 시도하게 했음.

### 한계와 남은 확인

- 관측은 WindowServer 합성 화면의 60fps 캡처임. 물리 패널의 표시와 사람 눈의 지각은 다를 수 있음.
- 입력은 모두 합성 이벤트임. 사용자가 가장 최근에 재현한 조건인 트랙패드 중간 정지와 되돌리기는 확인하지 않음.
- 예제는 단색 줄무늬 전체 화면 앱임. 실제 앱 내용, 일반 데스크톱과 전체 화면 사이 전환, BK550Y 쪽 Space 전환, Mission Control은 보지 않음.
- 가림은 실제 고개 입력이 아닌 고정 설정과 흔들림 모사임. 시험 도구(예제, 녹화기, 분석 스크립트)는 저장소 밖 임시 폴더에 있어 그대로 다시 돌릴 수 없음.

## 설정 기억 — 2026-11-12

사용자 결정은 [spec](spec.md#설정-기억--2026-11-12-사용자-결정)이 소유함. 이 절은 저장 형식, 되살리는 조건, 검증을 기록함.

### 구성

| 경로 | 역할 |
| --- | --- |
| `Sources/PrivacyAirPods/SettingsMemory.swift` | UserDefaults 읽기와 쓰기, 저장 형식(`StoredSettings`, `StoredPose`, `StoredGuide`), 조합 키, 저장 배치와 현재 화면의 대응 |
| `Sources/PrivacyAirPods/AppModel.swift` | 시작할 때 설정을 되살리고, 값이 바뀌면 저장함. 배치 적용에 성공하면 그 조합의 배치를 저장하고, 화면 목록을 다시 읽을 때 같은 조합의 배치를 되살림 |
| `Sources/PrivacyAirPods/DisplayLayout.swift` | 연결 화면마다 `CGDisplayCreateUUIDFromDisplayID`로 UUID를 붙이고, frame으로 세로 화면 여부를 판정함 |
| `Sources/PrivacyAirPods/LoginItem.swift` | '로그인할 때 열기' 상태와 `SMAppService.mainApp` 연결 |
| `Tests/PrivacyAppTests/SettingsMemoryFlowTests.swift` | 재실행, 모니터 연결과 분리, display ID 변경, 회전, 손상 값에서 설정과 배치가 되살아나는지 보는 e2e |
| `Tests/PrivacyAppTests/LoginItemFlowTests.swift` | 로그인 항목 대역으로 스위치 상태와 오류 안내를 확인함 |

### 저장 형식

- `settings.v1`: `StoredSettings` JSON. 시작 각도, 농도, 연결 폭, 반응 시간, 'AirPods를 벗으면' 선택, 팔 길이, 모형(`female`, `male`)임. 모형은 화면 문구(`HumanGuide.rawValue`)가 아닌 별도 키로 저장해 문구를 고쳐도 기억이 깨지지 않게 함.
- `layouts.v1`: 조합 키마다 `StoredPose` 배열을 담은 JSON 객체 하나. 조합 키는 연결된 화면 UUID를 정렬해 쉼표로 이은 값임. 항목을 따로 해석하므로 한 조합이 깨져도 다른 조합은 남음.
- 직접 돌려보기 각도, 보호 상태, 정면 기준, 화면 내용, 센서 값은 저장하지 않음.
- 저장소 키 이름의 `v1`은 형식을 바꿀 때 올림. 읽을 수 없는 형식은 nil로 보고 기본값을 씀.

### 되살리는 조건

- 설정: 읽은 값을 슬라이더 범위(시작 각도 0~45, 농도 15~80, 연결 폭 0~50, 반응 시간 0.03~0.5, 팔 길이 40~85)로 자름. NaN은 하한으로 보냄. 되살리는 동안에는 항목마다 다시 쓰지 않음.
- 배치: 화면 UUID가 모두 있고 서로 다르며, 저장한 화면 수와 UUID 집합이 현재와 같고, 화면마다 저장 당시 세로 여부가 같을 때만 되살림. 화면 id는 재부팅이나 재연결에서 바뀌므로 UUID로 대응시킴.
- 배치 값은 앱이 적용할 수 없는 값만 손상으로 거름(유한하지 않음, 폭과 높이와 거리가 0 이하, 위치와 크기 10m 초과, 회전 90도 초과). 배치 시트 편집기의 범위로 자르면 손대지 않은 기본 배치(세 화면을 위아래로 쌓아 높이가 60cm를 넘는 경우 등)가 되살아나지 않아서 쓰지 않음.
- 화면 구성이 바뀌면 보호를 끄고 정면 기준을 지우는 정책은 그대로임. 같은 조합이면 상태 문구가 '정면을 다시 맞춰 주세요', 처음 보는 조합이면 '정면과 배치를 다시 맞춰 주세요'임.

### 로그인할 때 열기

- 앱은 스스로 등록하지 않음. 스위치를 켤 때만 `register`, 끌 때만 `unregister`를 부름. 설정 창이 보일 때와 앱이 활성화될 때 상태를 다시 읽어 시스템 설정에서 바꾼 값을 반영함.
- 한 번도 등록하지 않은 앱의 `SMAppService.mainApp.status`는 `.notFound`임(2026-11-12 개발 빌드에서 확인, [Apple 포럼 보고](https://developer.apple.com/forums/thread/719862)와 같음). 처음 구현은 이를 '이 위치에서는 불가'로 보고 스위치를 막아 켤 길이 없었음. 지금은 `.notRegistered`와 같이 꺼짐으로 보고, 등록이 실패하면 오류 문구를 보임.
- 승인이 필요하면(`.requiresApproval`) 안내와 '시스템 설정 열기' 단추를 보임.

### 검증 기록

- 2026-11-12: `swift test --build-system native` 전체 통과(84개 테스트, 9개 suite, XCTest 6개). `./scripts/build-app.sh` 조립과 서명 통과.
- 2026-11-12: 결함 주입. `AppModel`의 설정과 배치 되살리기를 끈 임시 변경에서 `SettingsMemoryFlowTests`와 `ProtectionFlowTests`의 기억 관련 12개 시험이 실패함을 확인하고 되돌렸음.
- 2026-11-12: 실제 화면 UUID. 27MB35와 BK550Y 모두 `CGDisplayCreateUUIDFromDisplayID`가 36자 UUID를 돌려줌.
- 2026-11-12: 개발 빌드 실제 창(Orca computer, 배경 접근성 조작). 사용자 defaults 도메인을 백업한 뒤 `settings.v1`에 시험 값을 넣고 실행해 가리기 탭 30°, 50, 20%, 0.25초와 '계속 가리기'가 되살아남을 확인함. 시작 각도를 31°로 올리자 `settings.v1`에 바로 저장되고, 다시 실행해도 31°이며 보호는 꺼짐이었음. 로그인 스위치를 켜자 오류나 승인 안내 없이 켜짐, 재실행 뒤에도 켜짐, 끄자 꺼짐을 확인함. 확인 뒤 시험 값을 지워 도메인을 백업 상태로 돌리고 설치본을 다시 열었음. 640×820 창에서 로그인 줄이 'AirPods를 벗으면' 아래에 잘리지 않고 들어감.

### 남은 위험

- 실제 모니터를 빼고 꽂는 조합 전환과 재부팅 뒤 되살림은 e2e(화면 목록 대역)까지만 확인함.
- `/Applications` 설치본의 로그인 항목 등록, 실제 로그인 시 자동 실행은 배포 판본에서 사람 확인이 남음.
- 같은 모델 모니터 두 대가 같은 UUID를 보고하면 그 조합은 기억하지 않음. 실제 사례는 보지 않음.
