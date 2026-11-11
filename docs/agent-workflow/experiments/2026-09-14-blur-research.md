# 예쁜 블러의 다방면 조사 — 2026-09-14

사용자 지시로 Luna 독립 조사를 적극 사용함. 동일 주제를 20개로 복제하지 않고 공개 라이브러리, 비공개 compositor, 기존 캡처 경로 세 갈래로 나눔. 메인은 출처 대조·사용자 요구·배포 경계·검증 설계를 통합함. 결과 정본은 [블러 조사](../../blur-research.md)임.

## Orca 시작 실패와 정리

CLI는 Luna medium, service_tier=default, features.fast_mode=false 인자로 실행함. 새 SessionEnd hook의 검토 화면을 열어 cito-agent/hooks/codex_hook.py임을 확인한 뒤 검토 UI를 닫았음. 신뢰 추가·기존 hook 비활성·전역 설정 변경은 하지 않음. 터미널에는 Luna medium의 일반 입력 프롬프트가 보였으나 worker-start는 codex-interactive-prompt, dispatch/terminal send는 agent_prompt_blocked로 작업 전달을 차단함. 이 단계에서 조사 worker가 실행됐다고 세지 않음.

| 역할 | task | terminal |
| --- | --- | --- |
| 공개 라이브러리 | task_24a27137e626 | term_6b2f7ae6-6787-46da-8b4a-56b23ef816da |
| compositor | task_84361e7a9e70 | term_c576547d-10bf-42fd-a03e-5683dbe58bc0 |
| 캡처 | task_96e779b1745c | term_9291205d-1807-4ff9-b189-04137d1958c9 |

첫 dispatch는 각각 ctx_487da82e60b7, ctx_fa40b552fcd1, ctx_d1bc0f4bfb39였음. 공개 역할의 수동 preamble 회수 dispatch ctx_4abc400f9bdd도 입력 전달은 실패함. 모두 abandon 처리하고 정확한 소유 terminal close의 ptyKilled=true를 확인함. task는 실패로 기록함. 원본 `/tmp/privacy-blur-research-workers.json`, `/tmp/privacy-dispatch-public.json`.

## 내장 subagent로 별도 조사

Orca 반복 시작 비용을 멈추고 내장 collaboration의 gpt-5.6-luna worker public_blur/compositor_blur/capture_alternatives에 필요한 문맥만 전달함(fork_turns=none). 이는 Orca dispatch가 성공한 것이 아니라 별도 실행임. 내장 도구는 service tier/fast mode 설정을 노출하지 않으므로 비활성 준수 확인을 주장하지 않으며 사용자에게 이 한계를 알렸음. CLI 경로에서 지정한 설정을 내장 도구에 적용했다고 기록하지 않음.

Static 세 갈래 조사 뒤 메인이 추가로 찾은 반례(BackdropView의 변형 시 실패), 공개 backgroundFilters의 샘플링 범위, CGS 균일 blur와 variable blur 구분을 해당 worker에 한정 전달함. 같은 주제를 새 worker로 반복하지 않음. 실제 소비 토큰·과금은 미관측이고 실패 복구 비용까지 있어 절감 성과를 주장하지 않음. 수집한 근거로 기술 후보를 분류하는 실험이며 최적 모델·workflow의 통제 A/B는 아님.


세 내장 worker 보고 회수를 완료함: `/tmp/privacy-public-blur-research.md`, `/tmp/privacy-compositor-blur-research.md`, `/tmp/privacy-capture-blur-research.md`. 메인은 ‘native 유지가 가장 좋음’이라는 제안을 최신 미감 요구와 충돌하여 채택하지 않았음. ‘variableBlur는 iOS 근거만 있음’도 GlurBackdrop의 macOS 소스로 보완함. 다만 그 코드의 backdrop 생성에는 windowServerAware 설정이 없어 즉시 desktop 지원으로 확대하지 않았음. 공개 API 선택지가 오직 두 개라는 일반화 대신 이번에 확인한 후보 범위로 한정함. 보고서 일부가 요청보다 길어 회수 비용이 늘었으며 토큰 절감 성공으로 기록하지 않음.

## 승인 뒤 동적 수명 감사

기존 세 갈래 조사 뒤 새 불확실성인 창/레이어 수명만 `backdrop_lifetime_audit` Luna worker(fork none)에 한정 위임했음. 결과 `/tmp/privacy-backdrop-lifetime-audit.md` 회수 완료. 메인은 독립된 화면 실험을 수행함. 추가 worker를 무작정 20개로 늘리지 않고 동일 데스크톱 입력을 메인에 직렬화하여 실험 충돌을 피했음.

감사 보고의 ‘host 재생성·tag 등이 모두 필수’라는 표현은 실측으로 일반화되지 않았음. 기본 직접 backdrop도 정지 블러를 만들었고 제안된 tag 두 값 모두 전환 유지에 실패했음. 보고를 해결책으로 채택하지 않고 검사할 가설로 사용한 사례임. 내장 runtime fast mode 비활성 receipt·토큰·비용은 여전히 미관측이며 비용 절감이나 최적 조합을 확인했다고 주장하지 않음.

## 비대화형 Luna 감사와 실측 통합

후속에서는 `codex exec --model gpt-5.6-luna -c model_reasoning_effort='"medium"' -c service_tier='"default"' -c features.fast_mode=false -s read-only --skip-git-repo-check --json`로 두 제한 감사를 실행했음. 대화형 worker-start의 입력 준비 차단을 반복하지 않았고 hook 신뢰·전역 설정·권한은 변경하지 않았음. 두 프로세스 모두 종료코드0과 최종 보고를 회수했음. 명시한 모델/effort는 session turn_context와 일치했으나 실제 endpoint의 service tier/fast 비활성 receipt는 별도 노출되지 않았으므로 설정 지정과 준수 검증을 구분함.

| 역할 | 결과 파일 | CLI input / cached / output |
| --- | --- | --- |
| 측정 타당성, 진단2파일 | `/tmp/privacy-measure-audit-result.md` | 107941 / 83968 / 2463 |
| 주기 마스크 좌표, 진단2파일 | `/tmp/privacy-periodic-audit-result.md` | 116928 / 90112 / 4440 |

원본 JSONL은 각각 `/tmp/privacy-measure-audit-events.jsonl`, `/tmp/privacy-periodic-audit-events.jsonl`임. 첫 session은 `01a09fb7-1bd0-7131-9ac5-e71a3777da01`. 이 수치는 CLI 보고이며 요청한 최종 답변 길이만의 토큰이 아님. 온보딩 문맥과 반복 입력 비용도 들어가므로 작게 위임했다고 실제 비용이 작았다고 주장하지 않음. 달러 비용·통제된 시간 절감률은 산출하지 않았음.

첫 감사에서 제시한 축소/위상 위험과 off 기준선 부족을 실험 보강에 반영함. 동일 displayTime이 물리 패널 합성까지 보증한다는 근거는 없으므로 관측 경계를 명시함. 다만 콜백 지연만으로 서로 다른 장면이라고 확정한 표현은 받아들이지 않음.

두 번째 감사는 부호·호출 조건을 잘못 해석한 제안을 포함했음. `tx + origin.x`는 정지 상태(1728 + −1728)에서0이 되고 표식 실측과 일치함. 제안된 반대 부호는 정지부터−3456이 되어 기각함. 비주기 부분 실험도 overscan이 켜진 호출이므로 화면폭 차감이 필요함. fold 범위의 원점 이동은 의도한 간격 여백임. 보고를 그대로 반영하지 않았음. 이후 수동/AirPods 설정에 재사용할 분기는 전체 maskWidth 분모와 공통 마스크 생성 함수로 정리했음.

운영 결론: 소스의 좁은 측정 위험 탐색에는 Luna 보고가 도움이 됐으나 좌표 수학의 확정 판정은 실측 반례 대조가 필요했음. 이 역할에서 최저 모델의 무조건 채택이 최적이라는 증거는 얻지 못했음. 메인이 한 데스크톱의 입력을 직렬화하고 새 가설이 생길 때만 다음 시험을 추가한 dynamic 운영임. static/dynamic의 동등 조건 A/B나20개 병렬 실행의 우위를 주장하지 않음.


### 간헐 노출 후속의 제한 감사

같은 비대화형 Luna/medium/read-only 명령과 default tier·fast_mode=false 지정으로 진단3파일+연구 문서의 최대2가설 감사를 수행했음. 결과 `/tmp/privacy-intermittent-audit-result.md`, 원본 `/tmp/privacy-intermittent-audit-events.jsonl`, 종료코드0 회수. CLI usage input228424 / cached181760 / output3353임. 실제 endpoint fast receipt는 여전히 별도 미관측임.

메인은 물리 화면 시험을 직렬 실행하는 동안 worker가 읽기 전용 가설을 검토함. worker의 ‘1792pt 배수 점프가 remainder를 틀리게 만든다’는 설명은 정확한 정수 주기 점프라면 위상이 유지되므로 확정 결함으로 채택하지 않음. WindowServer 재합성 가설도 실물 증거가 없으므로 미확인으로 유지함. 근거 없는 수정은 하지 않았으며 계측 빈도/시작 Space 비교와 캡처 없는 수명 진단을 메인이 수행함.

작은 최종 보고에도 누적 입력이 컸고 이미 검토한 가설 반복이 있었음. 이번 위임이 시간·토큰을 절감했다고 판정하지 않음. 같은 파일의 추가 broad 감사를 반복하지 않고 다음 위임은 실패 시간축이 확보된 경우로 제한함. static/dynamic 통제 A/B는 수행하지 않았음.


### 노출 검출기 독립 검토

새 검출기와 회귀2파일만 Luna/medium/read-only에 검토 위임했고 메인은 실제 양성 대조군·수동 중간 정지를 직렬 수행했음. 실행 명령은 앞선 비대화형 방식과 같으며 default tier·fast_mode=false를 명시했음. 실제 endpoint fast receipt는 별도 미관측임. 결과 `/tmp/privacy-detector-review-result.md`, 원본 `/tmp/privacy-detector-review-events.jsonl`, 종료코드0 회수. CLI input181940 / cached129536 / output3197임.

같은 시각 metric을 뒤의 값으로 덮어 노출을 놓칠 수 있다는 지적을 채택하여 중복 입력 거부와 회귀를 추가했음. baseline 이상값 지적은 잘못된 환경/라벨을 판별하는 독립 정보가 필요하므로 임의 범위 검사로 해결했다고 쓰지 않음. 현재 기준선 전제와 한계를 문서화했음. Worker의 순수 테스트는4개 통과·2개 임시 디렉터리 생성 제한 오류였으며 메인이 최종8개를 실행해 통과함. Worker 실행 오류를 성공으로 세지 않음.

이번은 새 실패 검출기의 한정 독립 검토와 실물 계측을 병행한 dynamic 위임임. static/dynamic 통제 비교·최적 모델·달러 비용 절감은 판정하지 않음. 큰 기본 문맥 비용이 계속 관측되어 동일 파일의 추가 broad review는 실행하지 않았음.


### Dock 제스처 자동화의 한정 검토

메인이 computer-use capability와 합성 제스처를 실측하는 동안 Luna/medium/read-only 한 개에 dockswipe/MMF 원본의 유지·취소 함정을 검토시켰음. 기존 비대화형 CLI 방식에 default tier·fast_mode=false를 지정했음. 실제 endpoint fast receipt는 미관측임. 결과 `/tmp/privacy-gesture-review-result.md`, 원본 `/tmp/privacy-gesture-review-events.jsonl`, 종료0 회수. CLI input96111 / cached42240 / output2296임. 읽기 전용 환경에서 온보딩 lifecycle.lock 쓰기는 실패했고 우회하지 않았음.

Worker는 종료 속도0과 원본 마지막 delta 속도의 차이, 원본의200/500ms 취소 재전송과 wrapper의200ms 한 번 차이를 지적했음. 물리 입력 동일성·부하 중 복구의 미검증 조건으로 채택했으며 현재 정지 뒤 취소 실측의 실패로 단정하지 않았음. 메인이 별도로 dry-run SIGTERM 복구와 실제 양방향 유지/취소를 확인했음. 물리 화면은 직렬 사용함. static/dynamic 통제 비교와 최적 모델·비용 절감은 판정하지 않음. 동일 자료의 broad 재검토를 추가하지 않았음.


### 빠른 완료 전환의 재현과 제한 구현 위임 — 2026-09-14~15

native collaboration runtime에서 Luna worker 두 개를 사용했음. `fast_transition_audit`는 정적 감사→독립 fixed-mask 검출기2파일→반복 runner1파일을 순차 재사용했고, `stationary_backdrop_options`는 최대3개 원본의 좌표 고정 후보를 읽기 전용 조사했음. GUI/실물은 메인만 직렬 사용함. worker에 fast mode 금지를 전달했으며 이 runtime의 별도 service/fast receipt는 제공되지 않아 비활성 검증 완료라고 기록하지 않음. 사용량·달러·전체 소요 시간의 독립 receipt도 없어 추정 절감 수치를 만들지 않음.

메인은 정적 가설을 실측과 대조했음. 창 transform을 절대값으로 대입하므로 레이어 연산의 누적 덧셈 버그라는 설명은 채택하지 않음. isMovable=false·Space tag 등의 후보는 실측 실패로 기각함. 새 fixed-mask 검출기는 기존 파싱/분류를 재사용하며4개 검사와 기존8개 검사를 worker와 메인에서 확인했음. 실제 고정 마스크 로그에서 의도된 선명한 오른쪽을 제외하고 왼쪽 노출23프레임을 검출함.

runner의 첫 worker 판본은 help/문법 검사만 했고 실행 가능한 검증이 부족했음. 메인이 template 삭제 뒤 복사, 동시 fixture 실행으로 순서 미보장, -g로 활성화 미실행, mode별 시작 위치 미설정, 로그 덮어쓰기 문제를 찾아 한 번 보정시켰음. worker는4개 앱 조립의 격리 mock을 실행했고 메인은 불필요한 AppleScript 활성화를 LaunchServices open -a로 바꾸고 전체 제스처의 관측 범위 검사를 추가했음. 최종 runner를 실제4앱 조건에서 실행해 정상 종료·정리·색 변화12회·노출 재현을 확인했음. CLI 성공만으로 GUI 경로가 맞는다고 보지 않음.

메인 임시 driver는 비공개 placement 조회 크래시 뒤 open -W가0을 반환해 DONE을 출력했으나 probe 정상 완료 표식이 없어 무효로 처리했음. 새 runner의 정상 완료 검사는 이 누락을 차단함. 해당 위험 조회는 제거했고 clip-only 실측을 새 로그로 수행함. 실패를 낮은 기준으로 통과시키지 않았음.

이번은 고정된 빠른 입력 비교와 관측에 따른 추가 후보를 결합한 운영 기록임. static/dynamic 동일 과제 A/B나 최적 모델을 입증한 실험은 아님. 반복 렌더 후보가 늘고 runner 보정이 필요했으므로 시간·토큰 절감 성과로 판정하지 않음. 다음에는 알려진 실패의 원인 한 축과 이를 기각할 관측을 먼저 고정하고, 정지 기본 효과가 실패한 후보를 전환 전체 시험까지 실행하지 않도록 준비 검사를 강화함.


### 독립 합성 공간의 원본 조사와 수명 검토 — 2026-09-15

Luna `system_surface_route` 한 개를 최대3개 원본 조사 후 최대2개 수명 결함 검토에 재사용했음. GUI는 메인만 직렬 실행함. foreign window 이동의 SIP 제한을 자체 창에도 일반화한 worker 가설은 실제 SIP 활성·mask15 부착 확인·identity transform 관측으로 수정했음. 정적 가설보다 현재 실행 증거를 우선함. 수명 검토에서 화면 매칭 없는 성공과 이전 unmanaged membership 조회 누락을 반영했음.

알려진4앱 실패→독립 공간 균일 비교→고정/연속 가변 비교 순서를 유지하고 중간 결과에 따라 수명 검토를 추가했음. fast mode를 요청하지 않았으며 native runtime의 별도 tier receipt·토큰/시간 비용은 제공되지 않았음. 최저 모델이나 정량 절감의 입증으로 기록하지 않음.

최종 수명 수정본을 같은 Luna worker에 읽기 전용 재검토시켰고 추가 실제 결함 보고는 없었음. UI와 실측은 메인이 수행함. 중간 유지 시험의 raw 색을 검사해 LaunchServices 활성화만으로 반대 출발 앱이 확정되지 않음을 발견했으므로, 완료 제스처로 실제 이웃 화면으로 이동한 뒤 반대 유지 시험을 수행하도록 runner를 수정했음. 시작 앱 가정을 로그 대신 믿지 않음.

상시 실행 질문 후속: Luna `steady_cost_review` 한 개에3개 파일의 반복 작업/수명을 읽기 전용 검토시켰음. 메인의 대기 상태 CPU 측정과 독립 진행했음.8ms polling과 입력 변화마다 mask/filter 생성은 현재 코드와 일치함. `isReleasedWhenClosed=false`만으로 NSPanel 누적을 추정한 항목은 Swift/ARC 소유와 실제 해제 관측 없이 결함으로 채택하지 않았음. 메모리 추세 실측 대상으로만 남김. native runtime의 별도 비용/fast receipt는 없고 fast mode를 요청하지 않았음. 짧은 질문에서 위임 결과가 메인 발견과 중복됐으므로 다음 같은 규모의 점검은 메인 단독을 우선함.
