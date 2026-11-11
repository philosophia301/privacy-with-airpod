# 규칙의 출처와 차용 범위

2026-09-14 사용자가 지정한 로컬 reference를 읽고 새 프로젝트에 맞게 작성했음. 아래 경로는 원본을 다시 찾기 위한 출처이며 이 프로젝트의 실행 의존성이 아님.

| 원본 | 가져온 기준 | 가져오지 않은 것 |
| --- | --- | --- |
| [nAssetFong spec-decisions](/Users/eunjongkim/Projects/nAssetFong/docs/rules/spec-decisions.md) | 사용자 결정·내부 위임·사실 조사 구분, 이번 단위에 필요한 결정만 닫기, 요구 출처 표시 | 제품 가정·저장 계약·과거 승인 |
| [nAssetFong testing-levels](/Users/eunjongkim/Projects/nAssetFong/docs/rules/testing-levels.md) | 행동 계약·독립 기대값·대역 경계·실제 시스템 증거 | Nest·DB·TypeScript 배치, use case 파일 1:1, pnpm 명령 |
| [Belay workflow](/Users/eunjongkim/Projects/Belay/docs/rules/workflow.md) | Phase의 목적·완료 조건·검증·미커밋 리뷰 | Belay의 특정 날짜 승인 의미와 make 명령 |
| [Belay ROADMAP](/Users/eunjongkim/Projects/Belay/ROADMAP.md) | 큰 단위와 선행 결정, 단계별 결과·미관측 경계 | Swift 이식 순서·기기 검증 결과 |
| [Belay TODO](/Users/eunjongkim/Projects/Belay/TODO.md) | 현재 Phase·열린 결정·관측 가능한 완료 조건, 완료 기록 축약 | 기존 Phase와 구현·테스트 수치 |
| [Reachy writing](/Users/eunjongkim/Projects/reachy-mini/docs/rules/writing.md) | 결론→근거, 역할 기반 음슴체, 작은 시각화, 정본 단일화 | Reachy 제품 용어와 저장소 전용 링크 |
| [Reachy workflow-insights](/Users/eunjongkim/Projects/reachy-mini/docs/workflow-insights.md) | 과제·도구·품질 실패 분리, 메인 보정 비용, 동일 판본·실행 경계 | 다른 과제의 비용 절감률·모델 우열·Claude 적용 효과 |
| [nAssetFong agent-workflow](/Users/eunjongkim/Projects/nAssetFong/docs/agent-workflow/README.md) | 좁은 소유권·근거 있는 리뷰·셀 수 있는 예산·회수·재검증 | 개인 agent 정의 파일·모델 조합·동시 수·runner 전용 제약 |

상위 규범은 [cito 헌법](/Users/eunjongkim/Projects/cito-agent/constitution.md)과 이 세션에 주어진 지시를 참조했음. 헌법 개정이나 다른 저장소 변경은 수행하지 않았음.

규칙 적용 결과의 정본은 이 저장소의 [AGENTS](../AGENTS.md)와 `docs/rules/`임. upstream 변경을 자동으로 수입하거나 동일 문단의 사본을 동기화하는 시스템은 만들지 않음.
