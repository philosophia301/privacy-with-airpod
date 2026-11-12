# 격리 backdrop 진단

제품 앱에 연결되지 않은 실험 코드임. 비공개 API의 존재·오류를 검사하되 OS 호환성이나 보호 성공을 보증하지 않음. 결과와 후보 판정은 [블러 조사](../../docs/blur-research.md)가 소유함.

- `BackdropSPI.h/.m`: 동적 클래스·필터·창 속성 접근. Objective-C 예외를 명시적 오류로 바꿈. 시험 창에만 적용함. 공용 `PrivacyBackdrop` target의 object와 함께 링크함.
- `BackdropProbe.swift`: 두 창의 알려진 줄무늬와 가변 반경을 정지 상태에서 비교함.
- `TransitionPatternFixture.swift`: 서로 다른 프로세스의 초록/자홍 전체 화면 줄무늬 예제. 600초 뒤 종료함.
- `PrivateCover.swift`: 시험용 전체 화면 가림. 제품 기본 블러와 동시에 켜지 않음.
- `PrivateTransitionProbe.swift`: 같은 displayTime의 원본/가림 포함 중앙 띠를 비교함. 캡처는 관측 전용이며 블러의 입력으로 재표시하지 않음.
- `BlurLab.swift`, `build-blur-lab.py`: 별도 bundle ID의 단일 화면 수동/AirPods 비교 앱. 제품 설정을 읽거나 저장하지 않음.
- `summarize-transition.py`: 한 실행의 수치 로그를 요약함. 준비/종료 누락·유효한 전환 표본 없음·여러 실행이 섞인 로그를 거부함.

화면 픽셀은 메모리에서만 처리함. 로그에는 시각·색 분류 비율·인접 픽셀 대비와 시험 창 상태만 남음. 시험용 전체 화면 앱 두 개가 실제 전환 대상인지 확인해야 함. 예제가 종료된 로그나 단색만 비교한 로그로 블러 유지 성공을 판정하지 않음.

컴파일은 저장소 루트에서 수행함. Python 빌더는 `PrivacyCore`와 `PrivacyBackdrop` target을 먼저 빌드하고, 공용 `PrivacyBackdrop.m.o`와 modulemap을 진단 코드에 연결함. Swift 6.4의 기본 swiftbuild는 이 object 배치를 만들지 않으므로 `--build-system native`가 필요함.

```sh
swift build --build-system native --target PrivacyCore
swift build --build-system native --target PrivacyBackdrop
bin_path="$(swift build --build-system native --show-bin-path)"
backdrop_build="$bin_path/PrivacyBackdrop.build"
clang -fobjc-arc -fmodules -fmodule-map-file="$backdrop_build/module.modulemap" \
  -I Sources/PrivacyBackdrop/include -c scripts/diagnostics/BackdropSPI.m -o /tmp/privacy-backdrop-spi.o
swiftc -parse-as-library -import-objc-header scripts/diagnostics/BackdropSPI.h \
  -I "$bin_path/Modules" -I "$backdrop_build" \
  -Xcc "-fmodule-map-file=$backdrop_build/module.modulemap" \
  scripts/diagnostics/BackdropProbe.swift /tmp/privacy-backdrop-spi.o \
  "$backdrop_build/PrivacyBackdrop.m.o" -o /tmp/privacy-backdrop-probe
swiftc -parse-as-library scripts/diagnostics/TransitionPatternFixture.swift -o /tmp/privacy-transition-pattern-fixture
```

전환 probe는 `PrivacyAirPodsApp.swift`와 Sparkle 연결부 `SparkleUpdater.swift`를 제외한 앱 소스, PrivacyCore object, `PrivateCover.swift`, `GridMetrics.swift`, `PrivateTransitionProbe.swift`, 위 ObjC object를 링크함. 앱 번들은 제품과 별도 경로·실행 파일로 조립하며 화면 기록 권한을 갖는 로컬 개발 서명을 사용함. 제품 번들을 덮어쓰지 않음. 실험 종료 후 소유한 예제 프로세스만 종료함.

`/tmp/privacy-private-measure-mode`에 선택한 조건을 기록함: `off`, `plain`, `host`, `tag23`, `tag16`, `unflattened`, `moving`, `native`. 이 값은 제품 설정이 아님. probe는 준비 후 16초 관측하고 가림/스트림을 종료함. 준비 로그를 확인한 뒤 시험 앱 사이 Control+좌/우를 왕복함. 로그 경로는 매 실행 새로 지정함.

```sh
python3 scripts/diagnostics/summarize-transition.py /tmp/privacy-pattern3-transition-tag23.log
```

대비 비율 1은 원본과 비슷한 줄무늬 대비, 0에 가까우면 대비 감소를 뜻함. 0.5는 후보 비교용 보고 구간이며 사용자 승인된 품질 기준이 아님. 중앙 띠·캡처 경로의 측정은 실제 패널 전체를 육안 검증한 결과와 구분함.


## 최신 비교 앱

```sh
python3 scripts/diagnostics/build-blur-lab.py
open ".build/blur-lab/Privacy AirPods Blur Lab.app"
```

제품 앱과 별도 bundle ID(`local.privacy-with-airpod.blurlab`)임. 제품의 보호는 꺼두고 사용함. 수동 각도와 강도를 조절한 뒤 블러 켜기로 비교함. AirPods 입력 사용을 선택하면 이 실험 앱의 동작 권한이 필요할 수 있음. 착용 후 정면을 맞추고 시작하며 입력이 끊기면 해제함. 설정·보정은 저장하지 않음. Blur Lab 메뉴의 해제/종료 또는 실험 창 닫기로 정리함.

현재 후보는 내장 1대에서 검증하는 도구임. 화면이 여러 대면 시작하지 않고, 실험 중 화면 구성이 바뀌면 종료함. 화면 캡처를 블러 입력으로 사용하지 않음. macOS 26.6.2에서 앱 소유 독립 합성 공간을 사용하는 연구 후보로, 제품 적용·다중 화면 지원·다른 OS 호환성이 완료된 앱이 아님. 이전 화면 폭+64pt 보정 경로와의 비교는 블러 조사 문서를 참조함.

앱 실행에 `--smoke-test`를 주면 수동 블러 시작→각도/강도 변경→해제→종료를 짧게 수행함. `LAB SMOKE true true`와 정상 종료를 함께 확인함. 이 검사는 실제 AirPods 수신이나 전환 acceptance를 대신하지 않음.

최신 전환 probe는 Retina 원해상도의 중앙8pt 여러 행을 측정함. `DETAIL`은 인접 픽셀 대비 합을 432 기준으로 정규화한 지표임. `PROFILE`은 16구간 대비, `REGIONS`는 합성 예제의 색 구간, `TRANSFORM`은 시험 창의 역변환을 나타냄. 모두 수치만 기록함. 처음의 432×4 결과와 최신 원해상도 결과를 같은 표본처럼 합치지 않음.

요약기는 예제 색이 사라진 실행과 실제 왕복8회가 확인되지 않는 실행도 거부함. 정지 화면은 새 complete 프레임이 나오지 않을 수 있어 READY 직전 마지막 안정 장면을 전환 횟수의 시작값으로 사용함. 독립 스트림의 시각 미일치 표본 수를 공개하며, 두 스트림이 물리 패널과 동일한 합성 경로라고 보증하지 않음.

`--profiles`를 요약기에 추가하면16분할의 일부 구간에서 원본/표시 대비 비율을 출력함. 순색 구간과 이웃2구간이 같은 색일 때만 포함하여 Space 사이의 큰 색 경계를 제외함. `TARGET` 로그가 있으면 각 입력 구간의 앞10%·뒤20%를 제외해 갱신된 방향을 비교함. 따라서 이 결과를 응답 지연 측정으로 사용하지 않음.


간헐 노출 비교 조건 `fixedangle`과 `continuous`는 동일한 +45° 부근에서 입력 갱신 빈도를 구분함. fixture에 `--windowed`를 주면 별도 전체 화면 Space 대신 일반 데스크톱을 덮는 줄무늬 창을 만듦. 기존 사용자 창은 변경하지 않으며 fixture 종료 시 제거됨.

Blur Lab을 종료한 뒤 `open --stdout /tmp/새로운-진단-로그.log ".build/blur-lab/Privacy AirPods Blur Lab.app" --args --trace-transitions`로 실행하면 캡처 없는 수명 진단을 켤 수 있음. 블러 시작마다90초간 `TRANSFORM`을 기록하며 `LAB EVENT`는 시작·정지·입력 중단·Space 알림·출력 오류를 기록함. 머리 각도·화면 픽셀은 기록하지 않음. 전환 화면의 블러 유무는 별도 사용자 관측이 필요함. 기존 실행 앱에는 `open --args`만으로 새 옵션이 전달되지 않으므로 재실행 여부를 확인함.


`labobserver`는 실행 중인 Blur Lab만 관측하는 조건임. 별도 가림을 만들지 않으며 원본 스트림에서 Lab을 제외함. Lab의 블러를 켜고 시험하고, 종료 뒤 Lab 블러도 별도로 해제함. Lab 부재는 오류로 종료함. fixture의 `--metal`은 동일한 줄무늬를 Metal drawable에 그려 일반 NSView와 비교함. 다른 앱의 내용은 재현 입력으로 사용하지 않음.


## 노출 검출기 양성 대조군

`detect-blur-exposure.py`는 균일 블러 실험 전용임. 원본과 시각이 일치하는 표시 프레임만 고르는 대신, 표시 프레임의16구간을 블러 없는 같은 예제 기준선과 비교함. 선명/흐림의 진단 비율은0.65/0.15이며 사용자 승인된 보호 품질 기준이 아님. 경계 혼합·자료 누락은 unknown, 중간 대비는 uncertain으로 집계함. 노출이 없더라도 verdict는 not_established이며 실제 패널 전체 보호를 통과로 표시하지 않음. 중앙 띠 밖, 캡처가 내놓지 않은 프레임, 잘못 준비된 기준선은 이 검사로 보장할 수 없음.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/diagnostics/test-exposure-detector.py
python3 scripts/diagnostics/detect-blur-exposure.py --clear-baseline /tmp/privacy-pattern27-transition-off.log /tmp/privacy-hold28-overscan.log
python3 scripts/diagnostics/detect-blur-exposure.py --clear-baseline /tmp/privacy-pattern27-transition-off.log --verify-fault-pulse /tmp/privacy-fault30.log
```

위 로그 경로는 이번 실측 산출물임. 다른 환경에서 재현하려면 해당 예제·off 기준선을 새로 수집해야 함. 기존 다른 크기·색·해상도 기준선을 재사용하지 않음. 동일 시각의 같은 metric 중복은 조용히 덮지 않고 오류로 처리함. CLOCK 정보가 있으면 가장 긴 표시 표본 간격을 보고하되, 그 구간이 실제로 선명했다거나 가려졌다고 추정하지 않음.

`faultpulse`는 좌우 확장된 균일 backdrop을 유지하고 READY4초 뒤 opacity를200ms 동안0으로 만든 뒤 복구하는 의도적 노출 조건임. 표면 교체 없이 실패를 주입함. `--verify-fault-pulse`는 노출 검출, 모든 구간의 노출, 주입 전 가림·후 복구, 주입 구간 관측과 범위 밖 오탐을 검사함. commit 이후50ms 여유는 이 주입 검사에만 쓰이며 제품의 허용 노출 시간이 아님. 대기 취소 시에도 opacity를 복구한 뒤 창을 정리함.

probe 실행 인자 `--manual-hold`는 관측을120초로 늘려 실제 트랙패드 중간 유지·취소를 수동으로 수행하게 함. 키보드 왕복으로 이 조건을 대신하지 않음. 예제가 자동 종료되기 전인지, 사용자에게 시작 지시가 보이는지 확인함. `highoverscan`은 overscan과 같은 가림에서 창 level만1000으로 변경하는 비교임. 서로 다른 조건은 새 로그에 기록하며 제품 앱과 Lab의 보호는 먼저 해제해야 함.


## 진행 유지·취소 제스처 자동화

computer-use의 scroll/drag에는 다중 손가락 Space 전환의 진행·유지·취소 인자가 없음. 별도 격리 진단은 Dock이 처리하는 비공개 제스처 이벤트를 합성함. 실제 트랙패드 접촉을 그대로 재현하는 것은 아님.

```sh
python3 scripts/diagnostics/build-gesture-hold.py
.build/gesture-hold/gesture-hold -0.5 --dry-run
```

빌드는 dockswipe의 고정 revision과 SHA256을 확인하고 `.build/gesture-hold/`에만 소스와 실행 파일을 둠. 제품 의존성·전역 설치가 아님. `--dry-run`을 빼면 실제 데스크톱을 움직이므로 합성 fixture와 보호 해제 상태를 먼저 준비함. 입력 절댓값은0.05~1이며 부호로 방향을 바꿈. 값0.5는 화면의 정확한50%를 뜻하지 않음. 도착 화면의 실제 색 비율로 진행을 확인함.

`gesture-hold.m`은 진행 후 약2초 유지하고 취소하며200ms 뒤 취소를 한 번 더 보냄. 종료 속도는0으로 고정한 특정 입력 조건임. SIGINT/SIGTERM에서는 취소 후 종료하며 SIGKILL·프로세스 충돌의 복구는 보장하지 않음. 화면 내용을 저장하지 않고 mach 시각과 단계만 출력함. 이벤트 게시 권한이 없으면 요청 창 없이 오류로 종료함.

검증 환경은 macOS26.6.2임. 다른 OS의 비공개 필드 호환성과 실제 손동작의 동일성은 미검증임. 외부 소스의 제품 재배포·라이선스 적합성은 별도 검토 대상임. [실측과 한계](../../docs/blur-research.md#제스처-자동화-가능성의-정정과-실측)를 참조함.


## 빠른 완료 전환과 알려진 실패의 반복

`gesture-hold.m`의 `--fast`는 약80ms 진행 뒤 END를 보내는 완료 제스처임. `--fast --cancel`은 같은 빠른 진행 뒤 취소함. 둘 다 `--dry-run`과 조합 가능하며, 옵션 없는 기존2초 유지/취소와 구분함. agent fast mode와 무관함.

`run-fast-transition.py`는 현재 로컬 진단 번들·서명 설정을 재사용함. `/tmp/Privacy Private Transition.app`, `/tmp/privacy-pattern-fixture-metal`, 기존 fixture A의 plist, `.build/signing-identity`, 빌드된 gesture-hold가 선행 조건임. 새 설치 환경용 패키저가 아님. 제품과 Lab의 보호가 해제된 상태에서 단일 모니터의 합성 예제만 시험함.

```sh
python3 scripts/diagnostics/run-fast-transition.py --probe-executable /tmp/privacy-private-transition-probe-clip-safe --modes clipoverscan --screens 4 --output-dir /tmp/privacy-fast-next
python3 scripts/diagnostics/detect-blur-exposure.py --clear-baseline /tmp/privacy-pattern36-transition-off.log /tmp/privacy-fast-next/probe-clipoverscan.log
```

위 executable과 baseline은 이번 기기의 실측 산출물임. 다른 환경은 앞의 전환 probe 컴파일 절차와 새 off 기준선 수집이 필요함. output-dir는 기존 경로를 덮지 않도록 새 경로만 허용함. `--screens`는 물리 모니터 수가 아니라 합성 전체 화면 앱 수(2/4)임. 앱을 순차로 준비하고 각 조건 전 A를 활성화함. 2앱은16회 왕복,4앱은 한 방향3회 후 복귀를2번 수행함. `--activation-race --activation-offset-ms 0`은 END를 받은 직후 목적 앱을 활성화함. pattern37의 ‘BEGIN60ms 뒤 반대 앱 활성화’와 다른 조건임.

runner는 자신이 준비한 네 fixture 경로와 probe만 정리하며, probe에 강제 SIGKILL을 보내지 않음. READY/DONE·명령 종료·제스처 뒤 표시 표본이 남아 있는지 확인함. 명령 완료만으로 실제 Space 전환이나 무노출을 판정하지 않음. 별도 raw 색 변화와 검출 결과를 대조해야 함. 정상 실행 뒤 임시 mode 값은 복구함.

`analyze-fixed-mask.py`는 fixedangle 모드에서 계속 흐려야 하는 구간만 선택해 검사함. 기존 균일 검출기의 파싱·기준선·분류를 재사용하고, 의도된 선명 영역을 노출 오류로 세지 않음. 선택한 구간이 실제로 보호 대상이라는 전제는 실험자가 확인해야 함. 현재+45° 실험의 왼쪽4구간 예:

```sh
python3 scripts/diagnostics/analyze-fixed-mask.py --clear-baseline /tmp/privacy-pattern36-transition-off.log --gesture-log /tmp/privacy-gesture38-fixedangle-events.log --protected-bins 0,1,2,3 /tmp/privacy-pattern38-transition-fixedangle.log
PYTHONDONTWRITEBYTECODE=1 python3 scripts/diagnostics/test-fixed-mask.py
```

노출마다 가장 가까운 END와의 부호 있는 시간 차이를 보고함. 음수는 END 이전임. 이 값은 물리 패널 지연이 아님. 혼합 색/미관측은 unknown이며 통과 판정을 출력하지 않음.

추가 mode는 실패 원인 비교용임. wideoverscan(7화면 폭), stickyoverscan/flatoverscan/nojoinoverscan/immovable(창 속성), tiled/weaktiled/broadtiles(비중첩 분할), prepared/preallocatedtiles/unclippedtiles/preparedtiles/broadunclippedtiles(배경 준비 속성), mesh/preparedmesh(고정 mesh), menutag/statusbartag(창 tag), rebasedoverscan(좌표 재배치), clipoverscan(local clip 조회)을 지원함. `--rebase`는 기존 모드에 좌표 재배치를 추가하는 진단 인자임. 모두 제품 채택 전이며, 정지 블러부터 실패하거나 간헐 노출이 남은 후보를 포함함. [실험 판정](../../docs/blur-research.md#빠른-완료-제스처와-여러-전체-화면의-연속-이동)을 먼저 읽고 사용함. clipoverscan은 실패한 placement 조회를 제거한 최신 빌드만 사용함.


### 독립 합성 공간 후보

Blur Lab은 `PrivateCover.start(host:true, independent:true)`를 사용함. 화면 크기 창을 앱 소유 보조 Space에 부착하며 확장/반복 마스크/역이동을 사용하지 않음. 이전 실패 후보는 명시적인 비교 진단에만 남음. 비공개 API이며 현재 OS 실험 결과와 제한은 [조사 정본](../../docs/blur-research.md#데스크톱-이동과-분리한-출력--2026-09-15)을 참조함.

probe의 `independent`는 균일 블러임. `fixedangle` 또는 `continuous`에 `--independent`를 추가하면 같은 공간에서 가변 블러를 비교함. runner는 `--probe-arg=--independent`로 이를 전달함. `--hold-cancel`은 빠른 완료 대신 A에서 +0.45 유지/취소, +0.65 완료로 B 이동, B에서 −0.45 유지/취소를 수행함. activation-race와 동시 사용은 거부함. 실제 이동량과 노출은 로그로 별도 판정함.

`build-blur-lab.py`로 빌드 후 `--smoke-test` 실행은 시작·각도/강도 변경·입력 중단 모사·시작 직후 취소·3회 재시작/중복 종료·화면 매칭 없는 시작 거부를 관측함. 정상 종료와 출력의 true 값을 함께 확인해야 하며 시각적 acceptance를 대신하지 않음.


### 내장 화면에서만 실행하기

외장 화면에서 다른 작업을 하는 동안에는 다음처럼 실행함. `--built-in-only`는 `CGDisplayIsBuiltin`으로 내장 화면을 선택하고 창/블러를 그곳에만 배치함. 창을 표시할 때 앱 활성화나 키 창 전환을 요청하지 않음. 외장 화면까지 보호하는 다중 화면 지원을 의미하지 않으며 내장 화면이 없으면 시작하지 않음. 기본 실행의 단일 화면 조건은 유지함.

```sh
open -g ".build/blur-lab/Privacy AirPods Blur Lab.app" --args --built-in-only
```

이미 실행 중이면 새 인자가 적용되는 재실행이 필요함. 실제로 다른 화면을 사용 중일 때 전역 Control+좌우·합성 Dock swipe를 실행하지 않음. 전환 회귀는 외장 작업에 영향을 주지 않는 입력 경로가 확보되기 전까지 별도 미검증으로 둠.

`benchmark-blur-lab.py`는 명시한 과거/현재 Lab·PrivateCover 소스로 비교용 앱을 빌드함. 실행은 별도이며 생성 소스에 호출 계측만 추가함. 비교 사본의 화면 선택과 창 표시도 내장 화면에 고정함. `--benchmark --built-in-only`는 수동 정지, 합성 센서 정지/미세 변화/큰 회전의4구간을 각각 약8초 실행함. `getrusage` CPU 시간, `proc_pid_rusage` interrupt wakeup/physical footprint, update와 mask 제출 횟수를 출력함. 출력의 기존 `commits` 필드는 과거 로그 호환용 이름이며 현재 `PrivateCover.maskUpdateCount` 차이를 사용함. 해당 속성이 없는 과거 소스에는 연구용 카운터만 생성해 기존 비교를 유지함. 합성 입력의 발생 비용도 포함하며 WindowServer/GPU 전력은 포함하지 않음.

```sh
python3 scripts/diagnostics/benchmark-blur-lab.py --lab-source scripts/diagnostics/BlurLab.swift --cover-source scripts/diagnostics/PrivateCover.swift --output /tmp/privacy-bench-new
open -n -g -W --stdout /tmp/privacy-bench-new/run.log --stderr /tmp/privacy-bench-new/errors.log "/tmp/privacy-bench-new/Privacy Blur Benchmark.app" --args --benchmark --built-in-only
```

`BENCH DONE`·4개 `BENCH RESULT`·프로세스 정상 종료를 함께 확인함. 도구는 기존 output 경로를 덮지 않음. 과거 소스는 별도 보존한 판본을 입력하며 현재 코드에서 과거 동작을 흉내내는 플래그로 대조군을 만들지 않음.

최적화된 Lab의 `--smoke-test --built-in-only`는 동일 마스크 생략/강도와 각도 변경 반영, callback 침묵 시 해제, 새 sample의 유효 기간 연장,100개 연속 sample의 최신값 합치기도 확인함. 검사 로그의 참/거짓과 정상 종료를 함께 판정함.

## 전환 증거의 엄격한 감사

`audit-transition.py`는 기존 노출 분류와 제스처 파서를 재사용함. 고정된 보호 구간을 가진 실험에서 전환마다 raw 출발/도착 장면·실제 이동·취소 복귀를 확인하고, raw/shown 관측 공백과 미판정 구간을 보고함. 입력 DONE을 애니메이션 완료로 취급하지 않으며 다음 입력 전까지 도착 장면이 안정됐는지 확인함. 마지막 입력 뒤 남은 표시 표본도 버리지 않음.

```sh
python3 scripts/diagnostics/audit-transition.py \
  --clear-baseline /path/to/off.log \
  --gesture-log /path/to/gesture-events.log \
  --protected-bins 0,1,2,3 /path/to/probe-fixedangle.log
python3 scripts/diagnostics/test-transition-audit.py
```

- 종료1 / `regression_detected`: 보호 구간 선명 노출 또는 안정된 raw 장면과 다른 표시 장면을 검출함. 장면 불일치는 증상 신호이며 캡처 재표시 원인의 증명이 아님.
- 종료2 / `inconclusive`: 실제 이동·관측 범위·안정된 도착 장면을 입증하지 못했거나 unknown/uncertain 구간이 남음. `invalid_observation`은 로그·시계·인자 오류임.
- 종료0 / `no_regression_detected_in_observed_strip`: 이 로그의 제한된 관측 구간에서 신호를 찾지 못함. 미감·전체 화면·제품 acceptance 통과가 아님.

`--max-gap-ms`와 `--settle-ms`의 기본50ms는 진단 조건이며 허용 노출 시간이나 제품 UX 기준이 아님. 더 짧게 지정할 수 있지만 기존 로그의 표본 간격보다 짧으면 증거 불충분이 됨. 중앙 띠 밖·표본 사이·안정 판정 전 장면 재등장·중복 블러 강도·경계 움직임은 아직 충분히 검사하지 못함. 색 두 개의 합성 예제에서 인접 장면을 구별하며 동일 색의 비인접 앱 정체는 식별하지 못함. 동적 마스크는 시간별 정답 구간이 없으므로 이 정적 감사에서 거절함.

이 도구는 저장된 수치 로그만 읽고 화면·앱·제스처를 조작하지 않음. `run-fast-transition.py`의 종료0은 여전히 실행 수명 완료만 의미하므로 별도 감사 결과 없이 품질 통과로 해석하지 않음.

## 반복 검사의 병렬 실행과 캐시

```sh
python3 scripts/diagnostics/verify-diagnostics.py --jobs 4 --fresh --output /tmp/diagnostics-fresh.json
python3 scripts/diagnostics/verify-diagnostics.py --jobs 4 --output /tmp/diagnostics-cached.json
```

`test-*.py` 독립 프로세스를 병렬 실행함. Swift 수치 격자 검사는 가상 BGRA 입력만 사용하며 화면을 캡처하거나 앱을 조작하지 않음. 실제 화면/Space 검사를 이 병렬 작업에 섞지 않음. unittest가 실행한 검사 수가0이거나 종료가 실패하면 성공으로 캐시하지 않음.

캐시 키에는 진단·제품·테스트 소스 전체 내용, 명령/정답 판정, 입력 로그 내용, Python·Swift 도구 버전, 실행 환경을 포함함. 수정 시각만으로 재사용하지 않으며 실제 실행은 내용 키별 bytecode 경로를 사용해 오래된 Python .pyc를 피함. 성공 영수증은 내용 checksum을 검사함. 검사는 소스·입력 스냅샷에서 실행하고 그 스냅샷 내용으로 키를 만들며, 원본과의 일치까지 확인한 뒤 원자적으로 저장함. `--fresh`는 항상 실행하며 실패하면 같은 키의 과거 성공을 폐기함.

`--replay-manifest`는 과거 수치 로그의 기대 판정 회귀를 같은 실행에 추가함. JSON 배열의 각 항목에 `id`, `kind`(transition/grid), `expected_verdict`를 넣음. transition은 `baseline`, `gesture`, `observation`, `protected_bins`가 필요하고 grid는 `reference`, `observation`이 필요함. 경로는 manifest 기준임. `expected_fields`로 노출 프레임 수 같은 필수 결과도 함께 고정함. 알려진 결함의 `regression_detected`가 기대 판정이면 그 결함을 잡았다는 회귀 성공이지 제품 품질 성공이 아님.

보고서는 실제 실행과 캐시 재사용 개수·과제별 근거를 나눠 남김. 캐시는 오프라인 코드/로그 계약에만 적용하며 현재 GPU·OS·센서·전환의 실측 결과를 대신하지 않음. 제품 소스가 바뀌면 검출기 검사도 재실행하는 보수적 무효화를 사용함. 변경 영향의 더 좁은 선택 실행은 아직 적용하지 않음.


## 화면 전체 격자 계측

전환 probe의 `--grid --built-in-only`는 캡처 영역을 전체 내장 화면으로 확장함. 기본 중앙 띠 방식은 유지함. 전체 버퍼에서 가로/세로4픽셀 간격으로 샘플링해 16×9셀의 대비·장면색·유효 샘플 수만 JSONL로 남김. 원본 픽셀은 저장하지 않으며 모든 픽셀을 전수 관측했다는 뜻도 아님. 프로브 측정 부하는 제품의 상시 실행 부하와 별도임.

```sh
python3 scripts/diagnostics/audit-grid.py --reference /path/to/reference.log /path/to/observation.log
python3 scripts/diagnostics/verify-diagnostics.py --jobs 4 --fresh \
  --replay-manifest scripts/diagnostics/fixtures/transition/replay-manifest.json
```

reference는 같은 화면 구성·배율·블러 설정에서 얻은 기준 출력이어야 함. 셀/장면색별로 원본 대비가 얼마나 줄었는지 보정하고, 관측 프레임마다 비교함. 강도가 과해짐/약해짐과 고정 경계의 공간적 어긋남을 신호로 보고하며 중복 레이어라는 원인까지 확정하지 않음. 같은 장면색의 기준이 부족하거나 혼합/누락·표본 공백·포화 등으로 비교할 수 없으면 불충분으로 남김.

50ms 대응 시각·관측 공백·기준 변동·변화량 옵션은 진단 설정이며 사용자가 승인한 미감의 허용치가 아님. 실제 기준선 캡처와 전체 화면 전환 실험은 별도로 수행해야 함. `--built-in-only`는 캡처/보호 대상 제한이며 전역 제스처 자체를 내장 화면 전용으로 만드는 옵션이 아님. 외장 작업 중 전역 입력을 보내지 않음.

## 자리 이탈 실측 기록

`SeatRecorder.swift`(명령행과 AirPods 기록), `SeatRecording.swift`(기록 형식, 앱 규칙 재현, 보고), `SeatProtocol.swift`(측정 순서와 합성 기록)는 자리 이탈 판정 기준을 실제 AirPods로 재는 명령행 도구임. 제품 앱과 별도이며 제품 설정을 읽거나 쓰지 않음. 판정 방식과 임시 기준값은 [개발 안내](../../docs/development.md#자리-이탈-감지--2026-11-12)가 소유함.

빌드는 `.build/signing-identity`의 개발 서명을 씀(설정은 [개발 안내](../../docs/development.md) 앞부분). `--no-sign`은 서명 없이 만들며 replay와 시험에만 씀.

```sh
python3 scripts/diagnostics/build-seat-recorder.py
.build/seat-recorder/seat-recorder record --out /tmp/seat-새이름.csv
.build/seat-recorder/seat-recorder replay /tmp/seat-새이름.csv --stand-level 0.2
```

- `record`: AirPods를 끼고 앉은 채 실행함. 한국어 안내 음성(`--no-voice`면 화면만)에 따라 가만히 앉기, 타자, 일어서기와 앉기 반복(`--repeat`, 기본 3), 자세 고침, 숙이기, 걸어갔다 돌아오기, 걷다 바로 앉기를 약 3분 동안 함. 단계마다 판정 사건을 바로 보여 주고 끝나면 단계별 보고를 냄. 기록은 1초마다 파일에 써서, Ctrl+C나 창 닫기, kill로 멈춰도 그때까지 기록이 남고 보고도 냄(강제 종료는 보고 없이 기록만 남음).
- 기록 파일은 `--out`으로 지정한 새 파일에만 씀. 이미 있는 파일은 덮어쓰지 않고 소유자만 읽게(0600) 만듦. AirPods 입력이 `--wait`초(기본 20) 안에 오지 않으면 파일을 만들지 않고 종료 코드 69로 끝남. 처음 실행의 동작 접근 허용 창이 떠 있는 동안은 기다린 시간에 넣지 않고, 거절하면 종료 코드 77로 끝남.
- 기록에는 표본마다 받은 시각, 센서 시각, 사용자 가속도와 중력(g 단위), 센서 위치, 걷기 판정 항목과 신뢰도, 단계 시작 표시가 들어감. 머리 방향(yaw)과 화면 내용은 쓰지 않음. 원시 움직임 값이므로 실제 기록 전에 보관 방식(예: 분석 뒤 바로 지움)을 사용자가 정함([판단 규칙](../../docs/rules/spec-decisions.md)). 도구는 파일을 지우지 않으므로 정한 방식대로 직접 처리함.
- `replay`: 기록을 `SeatPresence`와 앱의 자리 비움 규칙으로 다시 돌림. `SeatPresence.Tuning`의 모든 값과 `--standing-delay`, `--return-settle`을 인자로 바꿔 볼 수 있고 `--json`은 기계 처리용 보고를 냄.
- 보고: 단계마다 기대(앉은 채 유지, 자리 비움, 다시 앉음, 비움 뒤 앉음)와 판정(맞음, 놓침, 잘못 가림, 못 돌아옴, 해당 없음), 자리 비움과 복귀까지 걸린 시간, 높이 추정치의 최고와 최저, 움직임 구간마다 반영된 높이 변화, 일어섬, 앉음, 걷기 판정 시각을 보임. 시간은 단계 시작부터 재므로 안내를 듣고 움직이기까지의 반응 시간을 포함함.
- 앱 규칙 재현(`AwayRule`)은 `AppModel`의 `receiveActivity`, `trackPosture`, `advanceAway`, `resumeProtection`과 `AwayTiming` 값을 옮긴 것임. 앱 규칙을 바꾸면 이 도구도 함께 고침. 보호와 스위치는 늘 켜진 것으로 보고, 앱의 매 화면 주기 확인은 기록 행마다(약 40ms) 확인하는 것으로 근사함. `AppModel.receive`처럼 센서 시각이 앞서지 않는 표본은 버림. 이어버드가 바뀐 표본과 0.75초 넘게 늦은 표본은 앱이라면 입력 중단이지만 replay는 판정을 이어가고 보고의 '입력 주의'에 횟수만 보임. 가림 전환(0.5초), 입력 중단 유지, 화면 구성 변경은 재현하지 않음.
- `synth`는 측정 순서를 이상적인 움직임으로 흉내 낸 합성 기록을 만들고, `record --simulate`는 그 합성 입력을 실제 시간에 맞춰 기록 경로에 넣음. 둘 다 AirPods 없이 형식과 보고를 점검하는 용도이며 실측을 대신하지 않음. 합성 기록에서 걷다 바로 앉기는 알려진 한계대로 '못 돌아옴'이 나옴.

`test-seat-recorder.py`는 도구를 임시 폴더에 서명 없이 빌드해 합성 기록의 replay 판정, 기준값 인자 반영, 앱이 쓰지 않을 입력의 집계, 덮어쓰기 거부, 잘못된 기록 거부를 확인함. `verify-diagnostics.py`가 함께 돌림.
