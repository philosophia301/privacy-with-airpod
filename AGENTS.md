# 프로젝트 작업 안내

AirPods 착용 중 고개를 돌리거나 자리를 벗어나면 Mac 화면을 블러 처리하는 앱을 준비 중임. 현재는 승인된 사용자 흐름의 첫 실험 앱을 구현 중이며 제품의 최종 실패·복귀 정책은 확정 전임.

작업 시작 시 이 파일과 [TODO](TODO.md)를 먼저 읽음. 승인된 제품 행동은 [spec](docs/spec.md), 결정 절차는 [spec 결정 규칙](docs/rules/spec-decisions.md)이 소유함. 대화에서 받은 최신 사용자 지시를 우선하고 중요한 결정을 정본에 반영함.

## 배치 지도

| 경로 | 소유 내용 |
| --- | --- |
| `Package.swift` | Swift target·의존성·지원 OS |
| `Sources/PrivacyCore/` | 각도와 블러 분포·순수 계측 계산. OS UI 의존 금지 |
| `Sources/PrivacyAirPods/` | 앱 조립·메뉴/설정·센서·화면 어댑터. `AppModel`은 보정·배치·보호·입력 중단 정책을 소유하고 `HeadMotionSource`·`FrameClock`·화면 목록·알림 경계를 주입받음. `RenderSettings`는 화면 위치별 블러 규칙, `ScreenCover`와 `SpaceTransitionBackdrop`은 실제 보호의 독립 공간 가변 블러·정확한 마스크 캐시·창 수명, `PreviewRenderer`는 설정 미리보기 비동기 수명 소유. `DisplayLayout`은 연결 화면 조회와 물리 초기 배치 변환, `SpatialScene`은 3D 표시·모니터 클릭 선택, `LaunchOptions`는 실행 인자, `ProtectionSmokeTest`는 배포 산출물 확인을 소유함 |
| `Sources/PrivacyBackdrop/` | 본체와 Lab이 공유하는 Objective-C backdrop/독립 합성 공간 어댑터. 비공개 API 경계·오류·소유 공간 정리 |
| `Tests/PrivacyAppTests/` | 실제 Core Image 렌더링·앱 어댑터 검증. `ProtectionFlowTests`는 실제 가림 창 마스크를 관측하는 사용자 흐름 e2e, `Support/ProtectionHarness.swift`는 AirPods·시계·알림 대역을 소유함 |
| `Tests/PrivacyCoreTests/` | 각도 경계·독립 입력으로 검증하는 계측 테스트 |
| `scripts/diagnostics/` | `GridMetrics.swift`는 전체 프레임의 수치 격자 추출, `audit-grid.py`는 기준 대비 공간 품질 분석, `verify-diagnostics.py`는 독립 검사 병렬 실행·내용 기반 캐시를 소유함. `metric-log.py`는 일반/압축 수치 로그 읽기, `fixtures/transition/`은 과거 실패·불충분의 재현 입력을 소유함. `audit-transition.py`는 기존 노출 분류를 재사용해 제스처 유효성·관측 공백·장면 재등장 신호를 종합함. 합성 예제 기반의 격리 화면 실험과 별도 Blur Lab 빌드·수동/AirPods 비교. 제품 설정과 분리하며 화면 내용은 저장하지 않음. `BackdropSPI`는 공통 PrivacyBackdrop 어댑터 위에 비교용 속성·계측만 추가함 |
| `scripts/build-app.sh` | 개발 실행·배포 후보 앱 번들의 유일한 조립 경로. 서명과 SDK 기록 검사 |
| `scripts/package-dmg.sh` | 직접 배포 DMG의 Developer ID 서명·보호 smoke test·공증·ticket 첨부·Gatekeeper 확인 |
| `Resources/Info.plist` | 앱 메타데이터·권한 용도 설명 |
| `docs/development.md` | 실행·복구·실물 실험 방법 |
| `docs/blur-research.md` | 예쁜 가변 블러·전환 강건성 후보의 조사 근거와 검증 설계 |
| `docs/performance.md` | 성능 조사 조건·비교 결과·다음 최적화 우선순위 |
| `README.md` | 프로젝트 목적·현재 사용 가능 여부·문서 진입점 |
| `AGENTS.md` | 작업 진입점·배치 지도·검증 안내 |
| `ROADMAP.md` | 큰 개발 단위·선행 조건 |
| `TODO.md` | 현재 Phase·완료 조건·미결·다음 행동 |
| `docs/spec.md` | 사용자 행동·결정 후보·승인된 선택과 이유 |
| `docs/feasibility.md` | 플랫폼 조사 근거·기술 가정·실기기 검증 계획 |
| `docs/assets/blur-reference/` | 사용자가 제공한 블러 reference 이미지 원본. 해석과 결정은 spec 소유 |
| `docs/rules/` | spec 결정·작업·테스트·작성 규칙 |
| `docs/agent-workflow/README.md` | agent 역할·위임·static/dynamic 운영 방식 |
| `docs/agent-workflow/experiments/` | 날짜별 실험 방법·결과·비용·한계 |
| `docs/references.md` | 이번 규칙의 출처와 차용 범위 |

사용자가 구현 방법을 자율 위임했으므로 승인된 행동·권한·데이터 경계 안에서 구조를 결정하고 소스 작성 전에 이 지도에 반영함. 기존 책임을 다른 경로에 복제하지 않으며, 예정 모듈을 이미 존재하는 것처럼 쓰지 않음. 구체 위임은 [spec](docs/spec.md#구현자에게-맡긴-범위--사용자-위임)이 소유함.

## 작업별 읽을 규칙

| 작업 | 읽을 곳 |
| --- | --- |
| 제품 행동·권한·저장·구조·scope 결정 | [spec-decisions](docs/rules/spec-decisions.md) |
| 착수·finding·검증·리뷰·커밋 | [workflow](docs/rules/workflow.md) |
| 테스트 추가·수정·완료 근거 판정 | [testing-levels](docs/rules/testing-levels.md) |
| 문서·주석·이름·사용자 설명 | [writing](docs/rules/writing.md) |
| subagent·orchestration·workflow 실험 | [agent-workflow](docs/agent-workflow/README.md) |

## 현재 검증

`swift test`는 각도·계측 계약, Core Image 렌더링, 실제 가림 창을 쓰는 보호 흐름 e2e를 검사함. 주 화면에 가림 창이 잠깐 뜨므로 연결된 화면이 필요함. `./scripts/build-app.sh`는 로컬 실행 앱을 조립·서명함. `./scripts/package-dmg.sh`는 배포 DMG를 만들며 공증 준비가 필요함. 실행 결과와 실물 검증 경계는 [개발 안내](docs/development.md)에 기록함. 테스트 통과는 실제 AirPods·다중 화면 보호의 증명이 아님.

수치 진단 회귀는 `python3 scripts/diagnostics/verify-diagnostics.py --jobs 4 --replay-manifest scripts/diagnostics/fixtures/transition/replay-manifest.json`으로 병렬 실행함. `--fresh`는 캐시를 재사용하지 않음. 캐시 재사용은 오프라인 계약에 한하며 실물 전환 통과가 아님.

문서 변경은 상대 링크 대상, 미정·승인 상태, 정본 중복, 공백을 확인함. Git 초기화 전에는 각 새 파일에 `git diff --no-index --check /dev/null <파일>`을 사용함. 초기화 후에는 `git diff --check`를 사용하고 untracked 파일은 별도로 검사함. 문서 검사는 앱 동작의 증거가 아님.

## 공통 경계

기본 언어는 한국어, 어투는 역할 기반 명사형 음슴체임. 실행하지 못한 검증은 이유와 남은 위험을 공개함. gate와 정본을 약화하거나 `--no-verify`로 우회하지 않음.

UI·UX·권한 확대·완료 조건 변경·외부 반영은 사람이 정함. 승인 범위 안의 가역적 작업은 매 단계 재승인을 기다리지 않음. 진입점은 파싱·호출·출력을 맡고 정책은 한 곳에 둠. 파일 약 500줄과 한 가지 일을 하는 함수 원칙을 지킴.

상위 규범의 출처는 [cito 헌법](/Users/eunjongkim/Projects/cito-agent/constitution.md)임. 이 저장소에서는 헌법 자체나 다른 프로젝트 규칙을 수정하지 않음.
