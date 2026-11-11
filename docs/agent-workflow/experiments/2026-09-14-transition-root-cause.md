# 전환 근본 원인 조사 — 2026-09-14

목적은 사용자에게 재현된 중복 이동·강도 증가·이전 화면 재등장을 독립 가설로 분리하는 것임. 제품 증거는 [개발 안내](../../development.md)가 소유함. 최대 20개는 상한으로 적용하고 중복 과제를 만들지 않았음.

## 실제 운영

Orca run `run_069d2870e753`에서 캡처 시각, Spaces/창 합성, GPU 수명을 읽기 전용 Luna worker 3개에 병렬 위임함. 메인은 합성 화면 실험과 보고 대조를 수행함. 이후 변경된 캡처 경로에 별도 Luna 리뷰 1개를 추가함. worker는 제품 소스를 수정하지 않았음.

| 역할 | task | dispatch | 회수 결과 |
| --- | --- | --- | --- |
| 캡처 감사 | task_ea64cab67581 | ctx_bcbbc02d814b | 파일 보고 회수, RPC 실패 후 abandon |
| Spaces 감사 | task_c5766cc5aec6 | ctx_bd26a2e7bae6 | 파일 보고 회수, RPC 실패 후 abandon |
| GPU 감사 | task_ad70fc6efd8d | ctx_fb5b1f60933d | 파일 보고 회수, RPC 실패 후 abandon |
| 변경 리뷰 | task_5a183d17c247 | ctx_a7e595693367 | worker_done 수신·ack, release 후 소유 terminal 종료 |

명시적 실행 인자는 `--model gpt-5.6-luna -c model_reasoning_effort="medium" -c service_tier="default" -c features.fast_mode=false`임. 재사용 terminal의 worker receipt에는 모델 필드가 비어 있으므로 실제 서버 처리 tier를 receipt로 확인했다고 주장하지 않음. 기본 계정의 priority 설정을 그대로 상속하지 않도록 실행 인자로 덮어씀.

첫 3개는 기본 sandbox가 로컬 Orca RPC를 차단함. worker가 이를 runtime 중단으로 오인하고 범위 밖 재실행을 시도했음. 메인은 정상 runtime을 확인하고 중단시켰으며, 파일 보고를 직접 회수함. worker-stop의 stop_unknown을 종료 성공으로 처리하지 않음. dispatch를 abandon으로 fence한 뒤 메인이 만든 정확한 terminal만 close하여 ptyKilled=true를 확인하고 task를 수동 완료로 기록함. 정상 worker_done 3건으로 세지 않음.

후속 리뷰는 부모와 동일한 `-s danger-full-access -a never`로 실행하여 로컬 RPC를 사용할 수 있게 함. worker_done `msg_a77ea070a980`를 수신했음. 외부 terminal release는 retained이므로 해당 소유 terminal도 별도로 닫았음. 원본 receipt는 `/tmp/privacy-root-workers.json`, `/tmp/privacy-review-worker.json`임.

## 발견과 메인 보정

요청 시각을 캡처 시각으로 사용하는 1회 갱신 경로, 전환 알림 이후 처리의 한계, 실제 sample attachment 회귀 공백을 회수함. 메인은 실제 metadata 검사를 추가하고 갱신 경로를 제거함. GPU 최종 검사와 present 호출은 같은 lock 안에 있으므로 단순 check-then-present race 주장을 확정 결함으로 채택하지 않았음. WindowServer의 실제 표시 순서는 별도 관측이 필요한 가설로 남김.

## 최적화 판정

3개 독립 감사는 static 분담, 발견 뒤 1개 리뷰는 dynamic 추가에 해당함. 최초 task 생성 09:31:49 UTC 뒤 약 1.5~2분에 보고 파일이 준비됐으나 RPC 복구·회수·메인 검증 시간이 추가됐음. 전체 토큰·과금·메인 단독 대조군은 미관측이므로 비용 절감이나 최적 모델을 입증한 실험은 아님. 이번에 확인한 개선은 로컬 RPC가 필요한 worker의 sandbox 조건을 착수 전에 맞추고, 종료 receipt와 실제 terminal 종료를 구분해야 한다는 점임.


## Native 후보 후속 리뷰 시도

사용자 승인 뒤 좁은 수명·마스크 리뷰 1개를 Luna에 추가 위임하려 했음. task `task_62818be657c8`, dispatch `ctx_5150c3b5bc49`, terminal `term_7e396062-627f-455a-8e84-9798e487e0a5`임. 이전과 같은 Luna medium/default tier/fast_mode=false 실행 인자를 사용했으나 agent_readiness 단계에서 `Agent startup blocked: codex-hooks-review-prompt`로 실패함. 해당 gate를 건너뛰지 않았고 worker 리뷰는 수행되지 않았음.

dispatch abandon과 정확한 소유 terminal close(ptyKilled=true)를 확인하고 task를 실패로 기록함. 메인이 화면 전체 ID 선검증·시작/종료 비동기 경계·늦은 갱신·마스크 full override·실제 경로에 capture 인스턴스가 없는지를 검토함. 독립 리뷰 통과로 세지 않음. 추가 위임을 반복하기보다 메인 검증을 진행했으며 이번 시작 비용의 절감 효과는 입증하지 못함.
