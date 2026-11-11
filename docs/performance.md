# 보호 화면 성능 조사 — 2026-09-14

GPU 직접 표시와 숨긴 설정 미리보기 중단을 실행 앱에 적용했음. 블러 계산과 강도는 유지하며, 실제 화면 출력에서 CGImage 중간 생성을 제거함. 아래 수치는 합성 렌더 실험이며 실제 사용자 입력부터 화면 표시까지의 지연은 아님.

## 적용 전 후보 비교 기록

M4 Pro, 3456×2234px, 움직이는 합성 체크무늬, radius 62.5, 동일 BlurRenderer.outputImage 필터를 사용함. 조건별 2회 준비 후 16회씩 CGImage/Metal 순서를 번갈아 실행함. CGImage는 픽셀 데이터 접근까지 강제하고 Metal은 private BGRA8 텍스처의 command buffer 완료까지 기다림. 중간 버퍼 캐시는 끔. 캡처·WindowServer 합성·디스플레이 표시·다중 모니터·실제 화면의 색상/HDR 차이는 측정하지 않았음. 두 출력 경로는 context와 command queue 구성도 달라 차이 전부를 단일 메모리 복사 비용으로 해석하면 안 됨.

| 입력 조건 | 기존 CGImage 중앙값 | Metal 텍스처 중앙값 | 현재/후보 범위 |
| --- | ---: | ---: | --- |
| 선명 | 8.49ms | 1.19ms | 7.85~9.18 / 0.97~1.40ms |
| 부분 블러 | 11.51ms | 5.23ms | 10.79~12.00 / 4.54~5.64ms |
| 전체 블러 | 11.23ms | 4.80ms | 10.53~12.00 / 4.40~5.34ms |

재현 명령은 `./scripts/benchmark-renderer.sh`임. 실제 앱의 필터 정본을 함께 컴파일하며 별도 알고리즘 복사본을 유지하지 않음. 합성 입력만 사용하고 화면 저장·외부 전송은 없음. 여러 프로그램의 GPU 작업·열 상태에 따라 결과가 달라질 수 있음. 현재 비교만으로 60fps 달성 또는 전체 지연 절반 감소를 주장하지 않음.

## 이번에 적용한 수정

렌더 요청뿐 아니라 메인 액터에 전달하는 완료 프레임도 최신 하나로 병합함. 메인 액터가 밀린 동안 지나간 프레임을 차례로 표시하지 않음. 메인 액터를 동기 구간으로 점유하면서 100개 제출 후 최신 결과 하나만 받는 회귀 검사를 추가했음.

비상 가림 시 이후 렌더 요청과 대기 결과를 닫고 입력 참조를 해제함. stop 이후 캡처 콜백은 이미지를 다시 보관하지 않음. 이미 시작한 GPU 연산 하나는 즉시 취소하지 못하지만 완료 결과는 표시하지 않음. 기존 generation 검증과 검은 가림은 유지함.

표시 중인 가림 창에 매 프레임 orderFrontRegardless를 호출하지 않고 보이지 않을 때만 표시함. 이 변경의 WindowServer 비용 감소량은 따로 측정하지 않았음.

## GPU 직접 표시 적용 후

ScreenOutput은 필터 그래프를 MetalPresenter에 넘기고, 화면별 CAMetalLayer의 drawable 텍스처에 직접 렌더함. drawable은 화면에 표시할 GPU 버퍼임. Core Image task와 Metal command의 성공을 모두 확인한 뒤 표시함. 첫 프레임만 MainActor에 준비 알림을 보내므로 매 프레임 이미지 전달·창 갱신 작업이 없어짐. 실제 화면 경로에서는 CGImage용 CIContext도 생성하지 않음.

레이어와 렌더 목적지에 같은 화면 색공간을 지정하고 위쪽 행부터 저장하도록 설정함. 캡처와 출력 픽셀 크기가 다르면 억지로 확대하지 않고 기존 처리 실패 경로로 넘김. Retina 강도 환산과 전체 패널 frame은 유지함. 출력·스트림 오류 시 큐와 presenter를 즉시 닫고 MainActor가 레이어를 제거해 검은 창을 유지함. 중단과 present를 같은 잠금으로 직렬화해 중단 후 늦은 표시를 막음.

GPU 대기는 화면별 전용 직렬 큐에서 수행함. 처리 중 하나+최신 대기 하나라는 메모리 한계를 유지하기 위해 무제한 비동기 command 제출을 하지 않음. nextDrawable은 시스템 정체 시 최대 약 1초 기다릴 수 있고 GPU 완료 대기에는 별도 앱 timeout이 없음. 이때 해당 화면의 출력 갱신은 늦어질 수 있지만 MainActor의 보호 끄기·레이어 제거는 GPU 완료를 기다리지 않음. 실제 GPU hang 주입은 미실행이며, 추가 watchdog은 후속 검토 대상임.

PreviewRenderer는 장기 유지하는 별도 CIContext와 직렬 큐로 예제를 렌더함. 설정 창 닫힘·최소화·앱 숨김·occlusion을 감시하고 숨겨진 동안 제출과 계산을 중단함. 다시 보이면 현재 설정으로 요청하고 이전 표시 세대의 결과는 폐기함. 센서 유효성 감시와 실제 보호 갱신은 계속 수행함.

### 적용한 GPU 인코딩 경로의 재측정

앞선 합성 조건을 유지하되 현재 MetalPresenter.encode와 Core Image task 오류 확인까지 실행함. 캡처·drawable 대기·실제 presentation은 제외한 값임.

| 입력 | 기존 CGImage 중앙값 | 적용한 Metal 인코딩 중앙값 |
| --- | ---: | ---: |
| 선명 | 8.69ms | 1.32ms |
| 부분 블러 | 11.49ms | 5.01ms |
| 전체 블러 | 11.23ms | 5.12ms |

실행 명령은 동일한 benchmark-renderer.sh임. 후속의 첫 준비 알림 축소와 CGImage context 지연 생성은 이 인코딩 결과를 바꾸지 않지만 실제 표시 비용은 별도 측정해야 함.

## 다음 관측

현재 연결한 외장 2대의 캡처·GPU 출력·각도 갱신·비상 가림·종료를 합성 각도로 확인했음. 실물 결과와 자동 검사 정본은 [개발 안내](development.md)의 GPU 직접 표시 항목임. 내장 화면이 비활성이라 노치 실물 재확인은 하지 못했음. 실제 고개 회전·장시간 스크롤·P3/HDR·GPU 고갈·메뉴 조작·최소화 복귀는 전부 통과한 것으로 간주하지 않음.

다음 성능 판정은 동일 모니터·스크롤·입력 조건에서 CPU/GPU, 캡처 누락률, 표시 FPS, 입력부터 표시까지의 p95를 측정하는 것임. 전혀 가리지 않는 화면의 출력 생략은 보호 시작 지연·가림 누락 검증이 필요한 후속 후보임.

API 근거: [Apple 영상 최적화 안내](https://developer.apple.com/videos/play/wwdc2020/10008/), [Core Image 출력 방향](https://developer.apple.com/documentation/coreimage/cirenderdestination/isflipped), 로컬 Xcode SDK의 CIRenderDestination.h·CAMetalLayer.h. 후보 비교를 현재 전체 화면 성능이나 보안 품질의 보장으로 해석하지 않음.


## 독립 합성 공간 Lab의 상시 실행 점검 — 2026-09-15

사용자가 장시간 켜두는 비용을 질문해 현재 프로세스와 반복 경로를 읽기 전용 점검했음. PID97199는 약7시간25분 실행 중이었고 UI는 AirPods 입력 선택/블러 해제 상태였음. 이 uptime을 연속 블러 실행 시간으로 해석하지 않음. 09:26:44~09:26:53 `top -l 5 -s 2 -pid 97199 -stats pid,command,cpu,mem,threads,time`의5표본은 CPU0.0%, MEM22M, 누적 CPU TIME03.90초였음. RSS와 top MEM은 다른 지표이며 메모리 누수·GPU 전력·WindowServer 비용의 측정 결과가 아님. 다른 앱 작업이 진행 중인 환경으로 전체 시스템 부하를 이 앱에 귀속하지 않음. 보호/센서 설정을 바꾸지 않았음.

현재 independent 경로는 화면 캡처를 블러 입력으로 사용하지 않고 한 화면 크기 창/레이어를 유지함. PrivateCover.update는 RenderSettings가 동일하면 mask/filter 갱신을 생략함. 그러나 BlurLab.beginTicking은8ms sleep 반복으로 값을 확인하고, 각도가 조금이라도 달라지면 mask와 CAFilter를 다시 만들어 commit함. CPU 사용률만이 아니라 wakeup·필터 전달·WindowServer/GPU 합성 비용을 함께 봐야 함. [Apple timer 안내](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)는 불필요한 깨움이 저전력 체류를 방해함을 설명함.

후속 권장 검증은 동일 장면의 OFF/ON 비교(정적 화면·스크롤/영상·연속 각도 변경), 앱/WindowServer CPU와 GPU 전력·메모리 추세, 수시간 반복과 잠자기/깨우기/입력 재연결임. 수동 입력은 변경 이벤트 중심, 센서 입력은 새 sample 중심으로 갱신하고 별도 stale 감시는 유지하는 방식이 최적화 후보임. 감지 지연·외형을 바꾸는 임계값/프레임 제한은 승인된 UX를 검증하며 결정해야 함. 이번 점검에서는 구현 변경이나 활성 블러 장시간 시험을 수행하지 않았음.


## 기능을 유지한 이벤트 갱신 최적화 — 2026-09-15

별도 Blur Lab에 적용했음. 기본8ms polling을 없애고 연속 slider action과 새 sample 이벤트에서 갱신함. MainActor에 동시에 몰린 sample은 pending task 하나로 최신값만 처리함. 입력 침묵 감시는 HeadSample.freshnessRemaining으로 계산한 기존0.75초 유효 기간 끝에 최신 sample을 다시 확인함. 새 sample마다 감시 task를 재생성하지 않음. 명시적 `--trace-transitions` 진단에서만90초8ms loop를 유지함.

PrivateCover는 실제 제출할 RGBA mask 데이터와 반경이 모두 같으면 CGImage/filter 생성과 WindowServer 제출을 생략함. 기존256샘플·8bit alpha·각도/강도식은 유지했으며 각도 임계값·프레임 제한·블러 해상도 축소를 추가하지 않았음. 같은 데이터 비교는 제출 성공 뒤에만 저장하고 stop 시 제거함. filter 객체를 직접 재사용하는 변경은 기존 WindowServer 갱신 실패 근거 때문에 하지 않았음.

### 내장 화면 비교

사용자 요청으로 내장1728×1117pt/Retina2x에만 창과 블러를 출력했음. 외장1920×1080 두 대가 함께 연결된 상태였고 외장 작업을 유지하도록 `open -g`, 비활성 창 표시, `--built-in-only`를 사용함. 전역 키/제스처는 보내지 않았음. 비교 앱은 과거/현재 실제 소스 사본에 호출 수·제출 수·프로세스 자원 계측을 추가해 빌드했음. 화면 픽셀은 캡처/저장하지 않았음.

| 약8초 구간 | 이전 앱 CPU | 이후 앱 CPU | 이전→이후 update 호출 | 이전→이후 filter 제출 |
| --- | ---: | ---: | ---: | ---: |
| 수동 각도 정지 | 2.70% | 0.02% | 881→0 | 0→0 |
| 같은 각도의 합성 센서 입력 | 3.18% | 1.63% | 902→480 | 0→0 |
| 동일 픽셀을 만드는 미세 합성 입력 | 5.52% | 2.41% | 879→480 | 479→0 |
| 큰 각도의 합성 회전 | 5.46% | 3.05% | 882→480 | 479→219 |

CPU는 getrusage의 user+system CPU 시간 차이/실제 경과 시간으로 계산하며100%는 한 CPU 코어 상당임. 합성 입력 발생 자체의 비용을 포함함. static/jitter/sweep는 각각480입력을16ms sleep 간격으로 전달함. jitter 진폭은0.000001°, sweep 진폭은15°이며 중심45°임. 임의로 다른 픽셀을 같은 값으로 취급하지 않음. 완전히 선명/흐린 구간 등 실제 mask가 같으면 sweep에서도 제출이 줄 수 있음.

정지 구간 interrupt wakeup은895→6, sweep는1274→488였음. 이 값은 프로세스의 해당 카운터이며 시스템 전체 wakeup이나 전력량이 아님. 이후 physical footprint는 각 구간 시작 약24.3~25.1MB, 종료 약24.2~24.7MB였음. 짧은 비교에서 증가 추세를 증명/기각하거나 수시간 누수가 없다고 주장하지 않음. 이후 정지 구간의 실제 경과는8.52초로, sleep 요청8초와 동일하지 않으며 실제 경과를 분모로 사용했음.

로그: `/tmp/privacy-perf-builtin-before2/{run,errors}.log`, `/tmp/privacy-perf-builtin-after/{run,errors}.log`; 각 폴더의 생성 Swift 소스가 실행 판본임. 두 앱 모두 정상 종료0·4개 RESULT·DONE을 확인했고 모든 PANEL은 `(0,0,1728,1117)`이었음. 같은 시점의 통제된 GPU/WindowServer 측정, 무작위 순서 반복, 배터리/발열과 수시간 soak는 미실행임. UI 문구의 외형이나 전환 구조를 바꿔 얻은 절감이 아니지만 실물 미감 acceptance를 대체하지 않음.

### 회귀와 관측 제한

`swift test` 종료0: XCTest6개, Swift Testing53개 통과. HeadSample의 측정/수신 시각 중 먼저 만료되는 경계 검사를 추가했음. 실제 수정 Lab의 `--smoke-test --built-in-only`도 종료0이며 동일 픽셀 생략·반경과 각도 변화 반영·입력 침묵 해제·새 sample 유효 기간 연장·100개 burst 최신1회 반영·시작 취소·반복 시작/종료·빈 설정 거부가 기대값을 출력했음. `/tmp/privacy-builtin-smoke{,-errors}.log`가 근거임. 소스/판본 정적 수명 리뷰도 수행했음.

사용자 내장 전용 지시 전 외장 구성에서 수행한 `/tmp/privacy-perf-transition/`은 명령 종료0이지만 예제 색 안정 변화가 없고 fixedangle의2520구간 중2516이 unknown이어서 유효한 전환 회귀로 판정하지 않음. 화면/입력 대상이 맞는다는 근거가 부족함. 지시 이후 전역 전환 입력을 중단했으므로 최적화 판본의 실제 Spaces 전환 재검증은 미완료임. 보호 공간/창 배치/필터 종류는 그대로이며 이를 실측 통과로 대체하지 않음.

초기 `/tmp/privacy-perf-before/`는 다중 화면 gate 때문에 시작하지 못했는데 harness precondition으로 종료되어 무효임. `/tmp/privacy-perf-before2/`의 CPU 필드는 proc_pid_rusage 시간을 ns로 가정해 산출했으므로 폐기했음. 이후 getrusage로 새로 측정한 `/tmp/privacy-perf-before3/`, `/tmp/privacy-perf-after2/`는 외장 첫 화면의 별도 비교이고 위 내장 수치와 혼합하지 않음. 내장 과거 판본 사본의 첫 컴파일 실패도 실행 결과에서 제외했음.

## 본체 통합의 성능 경계 — 2026-09-15

Lab의 정확한 마스크/반경 중복 제출 제거를 본체 ScreenCover/SpaceTransitionBackdrop로 옮겼음. Lab 기본 경로도 본체 구현을 호출함. AppModel은 기존 반응 속도 보간을 유지하기 위해 활성20Hz 타이머를 유지하며 미리보기·수신·보호·계측이 모두 비활성일 때만 멈춤. 이전 Lab 이벤트 갱신 CPU 수치를 본체 AppModel의 CPU로 인용하지 않음. 통합 본체의 GPU·WindowServer·전력·수시간 사용 측정은 후속임.
