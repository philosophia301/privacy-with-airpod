# GPU 출력 구현의 제한 병렬 운영

목적은 구현 품질을 유지하면서 낮은 비용 모델에 맡길 수 있는 책임과 필요한 메인 보정을 관측하는 것임. 메인이 Metal 출력·통합·실제 화면 probe·자동 검사·문서를 맡고, 처음 정한 static 분담으로 미리보기 수명만 별도 worker에 맡겼음. Metal 구현이 준비된 뒤 오류/중단 경계의 불확실성 때문에 dynamic하게 읽기 전용 리뷰를 추가함. 같은 파일의 병렬 쓰기는 없었음.

Run `run_566dce03c36d`, runtime `27e47291-7958-4d96-89ff-e5526f377ad1`, Orca 1.4.197임. 두 worker 모두 worker-start receipt가 요청/실제 `gpt-5.6-luna`, high를 확인했음.

| 책임 | Task / Dispatch | 관측 시간 |
| --- | --- | --- |
| 미리보기 구현 | task_ec580605c7f4 / ctx_743c80e36317 | Task 생성 06:48:15 UTC → worker_done 06:52:32 UTC, 257초 |
| GPU 읽기 전용 리뷰 | task_7b7e76eb7c39 / ctx_277727192462 | Task 생성 06:50:52 UTC → worker_done 06:55:52 UTC, 300초 |

시간은 준비 전 작업·메인의 최종 통합·전체 검증을 포함하지 않음. 메인 작업 및 두 worker가 일부 동시 실행됐으며, 독립 과제여서 동일 과제 A/B 비교가 아님. 토큰·요금은 미측정이고 절감률 또는 최적 모델 확정으로 보고하지 않음.

미리보기 결과는 비동기 큐·세대 무효화·창 알림을 채택했음. 메인 리뷰에서 요청마다 CIContext를 다시 만드는 부분을 장기 유지 객체로 고쳤고, 렌더 실패의 조용한 continue를 로그와 미리보기 초기화로 보완함. worker의 ‘전체 40개’ 보고는 Swift Testing 부분만 센 수치이므로 최종 XCTest 포함 수는 개발 안내가 소유함.

GPU reviewer의 스트림 오류 직후 중단 누락은 채택하고 MainActor가 처리하기 전 presenter가 닫히는 회귀 검사를 추가함. Core Image task 오류 확인도 채택함. 무조건 비동기 command 제출 권고는 그대로 채택하지 않았음. 현재 GPU 대기는 화면별 전용 큐에 한정되며 pending 하나 보장과 MainActor의 즉시 중단을 유지함. drawable 고갈·GPU hang의 실제 지연은 미관측으로 남김.

두 worker 모두 유효한 worker_done을 회수한 뒤 worker-release가 closed_agent_terminal을 반환했고 Delivery를 ack했음. 추가 상향·재위임은 하지 않았음. 이번 관측은 좁은 구현도 메인의 통합 보정이 필요하다는 근거이며, static/dynamic 중 어느 쪽이 더 저렴한지의 통제 실험은 아님.
