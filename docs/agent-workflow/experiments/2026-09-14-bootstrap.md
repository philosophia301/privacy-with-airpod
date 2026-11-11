# E001 — 초기 문서 작업의 위임 관측

2026-09-14. 상태: reference 조사 보고 회수·핵심 근거 대조 완료. 대조군 없는 운영 관측이며 static/dynamic의 효율 비교는 아직 아님.

## 질문과 조건

규칙 문서를 메인이 작성하는 동안 좁은 reference 조사를 분리하면 차용 근거와 이식 금지 가정을 독립적으로 확인할 수 있는지 관측함.

입력은 사용자 지정 Reachy `workflow-insights.md`와 nAssetFong `docs/agent-workflow/README.md` 두 로컬 파일임. 경로는 [references](../../references.md)에 있음. 조사자는 읽기 전용, 출력 2,000자와 원본 2개를 과제 예산으로 전달했음. 메인이 문서 작성과 보정을 맡고 모델·effort override는 지정하지 않았음. 강제 예산으로 확인된 것은 아님.

| runtime 항목 | 실제 값 |
| --- | --- |
| Orca 버전 | `1.4.197` |
| Run | `run_035375c40c79` |
| 조사 Task | `task_b55ade56e892` |
| 조사 Dispatch | `ctx_3eafc38c636e` |
| 실행 위치 | 현재 프로젝트 폴더의 새 Codex terminal, 파일 수정 금지 |

`orca status --json`에서 runtime ready를 확인했고 `worker-start`가 `ready / input_accepted`를 반환했음. 이는 시작 접수의 증거이며 조사 완료나 품질 통과의 증거가 아님.

## 결과

`worker_done`의 `outcome: succeeded`를 수신했음. 조사자는 원칙 6개·이식 금지 가정 3개·동일 판본의 최소 비교안을 보고했고 수정 파일은 없음. 메인은 Reachy 원본 249~289행과 nAssetFong 27~36행을 대조해 고정 절차와 의미 검증의 분리, 실제 판본 증거, 셀 수 있는 예산, 전체 보정 비용의 근거를 확인했음. 연결된 개별 실험 원본 전체를 재현한 것은 아님.

운영 문서에는 두 비교 후보의 동일 판본·완료 조건, 메인 준비/보정 비용, 독립 최종 검토를 반영함. 다른 프로젝트의 모델 조합·gate·절감률을 새 프로젝트 기본값으로 정하지 않았음. 대부분 메인의 초안과 겹치는 확인이어서 독립 위임의 고유 추가 발견이나 비용 우위는 입증하지 못했음.

종료 후 `worker-release`는 `retained / user_takeover / processAction: none`을 반환했음. runtime이 사용자 인수 상태로 분류해 자동 종료하지 않은 것이며 메인이 별도 강제 종료하지 않았음. 완료 메시지는 처리 후 ack했음.

제품 센서·블러 코드를 실행하지 않았음. 토큰·비용·작업별 시간은 미계측이며 절감률을 주장하지 않음.

## 후속 관측 — 결정 상태 리뷰

사용자 후속 결정 반영 뒤, 결정과 제안의 혼동만 확인하는 새 읽기 전용 reviewer를 추가했음. 원본 조사 결과를 근거로 제품을 확정하지 않으며 문서 6개·지적 최대 3개·보고 1,500자의 과제 범위를 전달했음. 메인은 동시에 링크·공백 검사를 수행했음. 상황에 맞춰 역할을 추가한 운영 관측이며 고정 workflow와의 대조 실험은 아님.

Task는 `task_6a44723f2c99`, Dispatch는 `ctx_cd3491b6be7e`임. 실제 Task/Dispatch를 조회했고 `worker_done / succeeded`를 회수했음. 읽은 경계는 AGENTS·TODO·spec·feasibility·spec-decisions·workflow 여섯 문서임. 리뷰 당시 spec SHA-256은 `09e0e8e335d31a39fea4c7aca998ddee9c018bc8d1f94db28c18d4902dd28e41`, TODO는 `4ef811700aaf77c5594ce6cf0f12d91a0128a846d984d0686a39330af4eed69f`였음.

추가 발견 1건: TODO 첫 문장은 제품 spec 전체가 사용자 결정 전이라고 했으나 spec에는 D3 일부 확정이 기록돼 있었음. 메인이 두 문장을 대조하고 TODO를 ‘D3 효과 종류는 선택 완료, 나머지는 결정 중’으로 보정했음. 공개된 미정 항목은 reviewer가 결함으로 세지 않았음. 이 리뷰만으로 모든 spec 누락이 없다고 보장하지 않음.

리뷰 후 release는 `released / closed_agent_terminal`, transcript archive는 `captured`를 반환했으며 완료 메시지 ack도 확인했음. 메인의 문서 수정·최종 검사 비용은 미계측이며 효율 비교는 여전히 미실행임.

초기 reference 일괄 읽기의 도구 출력이 잘려 필요한 원본 구간을 나눠 재조회했음. 조사 출력량과 메인의 재독해도 비용임. 다음에는 문서별 필요한 절을 먼저 정해 잘림을 줄이는 방식을 적용할 수 있으나 효과는 아직 비교하지 않았음.
