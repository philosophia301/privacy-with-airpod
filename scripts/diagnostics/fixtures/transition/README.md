# 전환 replay fixture

과거 수치 로그를 새 `audit-transition.py` 판정으로 재생하는 최대 4개 입력임. 실제 화면을 다시 조작하지 않으며, 화면 픽셀·창 제목·`OWNED_SPACE` ID를 보존하지 않음. 모든 로그는 `CLOCK`, `MEASURE READY`/`DONE` 및 `raw`/`shown`, `PROFILE`, `REGIONS`, `GESTURE` 레코드만 남긴 `.log.gz`임. gzip header의 mtime은 0으로 고정함.

원본 provenance와 재현 기대값은 다음과 같음.

| id | 원본 로그 | 기대값 | 의미 |
| --- | --- | --- | --- |
| `fail38-regression` | `/tmp/privacy-pattern38-transition-fixedangle.log` + `/tmp/privacy-gesture38-fixedangle-events.log` | `regression_detected`, 노출 23프레임 | 알려진 fixedangle 부분 블러 실패의 회귀 기준 |
| `fail39-regression` | `/tmp/privacy-pattern39-transition-overscan.log` + `/tmp/privacy-gesture39-overscan-events.log` | `regression_detected`, 노출 273프레임 | 알려진 overscan 연속 전환 실패의 회귀 기준 |
| `fast57-inconclusive` | `/tmp/privacy-fast57/probe-fixedangle.log` + `/tmp/privacy-fast57/gesture-fixedangle-events.log` | `inconclusive`, 노출 0 | 알려진 개선 후보. 노출은 없었지만 protected 구간 미판정이 남아 통과가 아님 |
| `invalid-inconclusive` | `/tmp/privacy-perf-transition/probe-fixedangle.log` + `/tmp/privacy-perf-transition/gesture-fixedangle-events.log` | `inconclusive`, 노출 0 | 원래 실행에서 실제 이동·충분한 관측을 입증하지 못한 입력. 종료 0을 성공으로 재해석하지 않음 |

모든 항목의 기준선은 `/tmp/privacy-pattern32-transition-off.log`임. 원본 수치와 동일한 줄만 압축 보존하며, 기준선·제스처·관측 경로는 [replay-manifest.json](replay-manifest.json)에 상대 경로로 기록함. `.log.gz` 입력은 `scripts/diagnostics/metric-log.py`의 `read_text()`가 plain log와 같은 방식으로 읽음.

재생 예:

```sh
python3 scripts/diagnostics/audit-transition.py \
  --clear-baseline scripts/diagnostics/fixtures/transition/pattern32-transition-off.log.gz \
  --gesture-log scripts/diagnostics/fixtures/transition/gesture38-fixedangle-events.log.gz \
  --protected-bins 0,1,2,3 \
  scripts/diagnostics/fixtures/transition/pattern38-transition-fixedangle.log.gz
```

압축 파일의 SHA-256은 [SHA256SUMS](SHA256SUMS)에 고정함. checksum은 데이터 변경 시 함께 갱신하며, 이 fixture의 수치 결과는 실제 AirPods·Spaces·시각 acceptance를 증명하지 않음.
