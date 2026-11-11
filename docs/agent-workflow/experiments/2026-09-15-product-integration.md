# 본체 통합의 제한 병렬 운영

목적: 이미 승인·검증한 출력의 제품 통합에서 중복 구현과 검증 누락을 줄임. 메인이 공통 어댑터·출력·본체 실행·정본 통합을 소유함. 고정 소유권으로 Luna worker에게 AppModel 타이머/내장 선택, CoverGeometryTests, 진단 빌더를 각각 맡김. 이후 기존 AppModel worker에 읽기 전용 수명 검토를 추가한 부분이 dynamic 운영임.

실제 native collaboration task: `/root/integrate_model`, `/root/integration_tests`, `/root/integration_builders`. 모델 요청은 `gpt-5.6-luna`, 좁은 fresh 문맥을 사용함. Orca Run/Dispatch 실험으로 기록하지 않음. fast mode를 요청하지 않았으며 runtime 도구에 별도 tier receipt가 없어 비활성 확인·비용 수치를 주장하지 않음.

메인 보정: 공통 ObjC 타깃에 ARC를 명시하고 CoreTests의 불필요한 의존성을 제거함. 독립 Lab 경로를 제품 ScreenCover에 위임함. 본체 보정→실제 출력→입력 중단 검사를 별도로 연결함. 첫 전체 테스트는 worker의 기존 테스트 교체 완료 전에 실행돼 컴파일 실패했으므로 완료 뒤 재실행이 필요했음. 이는 병렬 작업의 준비 완료 경계를 기다리지 않은 운영 낭비로 기록함.

토큰·비용 대조군과 같은 과제의 단독 수행 시간은 미측정임. 낮은 모델 위임 자체를 절감 성과로 환산하지 않음. 최종 검증 결과의 정본은 development 문서임.

회수 검토: 테스트 worker 완료 후에도 native 속성2곳과 try 누락이 남아 메인이 수정했음. 최종 전체 검사55+6개는 종료0임. AppModel worker의 읽기 전용 수명 검토에서는 확정 회귀를 찾지 못했으며 실기기 증거로 사용하지 않음.
