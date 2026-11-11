# 이벤트 갱신과 중복 제출 최적화 — 2026-09-15

사용자는 기존 기능·외형을 유지한 성능 최적화를 요청했고, 도중에 내장 화면에서만 테스트하도록 범위를 한정했음. 메인은 PrivateCover의 정확한 mask 비교, HeadSample 유효 기간 정본, 성능 계측과 통합을 소유했음. Luna `event_updates` 한 개가 BlurLab.swift만 소유해 이벤트 갱신·감시 task·smoke를 구현한 뒤 읽기 전용 수명 리뷰에 재사용됐음. 다른 파일/GUI/빌드/추가 worker는 위임하지 않았음.

메인은 반환 코드의 동일 scope 중복 `guard let self`를 수정했고, 비활성 cover의 sample task 생성 방지와 시작 전 generation 확인/시작 후 최신 설정 적용을 보완했음. worker 리뷰에서 추가 구체 결함은 보고되지 않았으며 실제 빌드와 GUI 회귀는 메인이 수행했음. 입력 갱신과 timeout 정책을 한 작업에 묶어 구현한 뒤 별도 최신 sample 갱신/침묵 검사를 추가함.

실행 환경이 내장1대에서 외장2대로 바뀌어 첫 benchmark가 Lab 단일 화면 guard에 막혔음. 이를 성공으로 취급하지 않고 비교 사본의 대상을 명시했음. 이후 사용자가 내장을 열고 외장 작업을 요청하자 내장 display 식별·비활성 창 표시·전역 제스처 중단으로 전환했음. 현재 제품 지원 범위를 다중 화면 보호로 확장하지 않음.

초기 CPU 계측의 proc_pid_rusage 시간 단위 가정을 기각하고 getrusage의 초/마이크로초 누적 CPU 시간을 사용해 비교를 새로 수행했음. update/commit 카운터와 실제 픽셀 동일성은 별도로 판정함. 잘못된 계측값을 절감 수치로 사용하지 않음.

native collaboration runtime의 Luna 선택은 확인했으나 별도 fast/tier·시간/토큰 비용 receipt는 제공되지 않았음. fast mode를 요청하지 않았고 비용 절감률은 계산하지 않음. GUI 실험은 메인 직렬 실행, 코드는 파일 소유권을 나눠 병렬 작업했음. 동일 과제의 static/dynamic A/B나 최저 모델을 입증한 실험은 아님. 범위가 작은 수정은 다음에도 동일 worker의 짧은 재사용을 우선하되 통합·빌드 시간을 포함해 평가해야 함.
