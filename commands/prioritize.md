---
description: 이슈 트래커(Linear/GitHub/GitLab) 미완료 이슈를 루브릭 점수로 분석해 우선순위 Top N 추천
argument-hint: [--top N] [--team <name>] [--state <name>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/core/lib.sh:*), Bash(bash:*), Agent
---

`prioritize-issues` 스킬을 호출하세요.

스킬 절차 요약:
1. `bash -c 'source ${CLAUDE_PLUGIN_ROOT}/scripts/core/lib.sh && orch_settings_issue_tracker'` 로 트래커 확인
2. linear / github / gitlab → `Agent(general-purpose)` 위임 — list/get 호출은 모두 서브에이전트가 처리 (메인 컨텍스트 효율)
3. none → "트래커 미사용 — 대상 없음" 안내 후 종료
4. 결과 (점수표 + Top N + 묶음 추천) 만 메인이 받아 사용자에게 표시

**언제 사용**:
- 작업 큐가 길어 어디서부터 손대야 할지 모를 때
- 새 사이클 시작 전 backlog 정리
- PR 머지 후 다음 픽업할 이슈 결정

**왜 서브에이전트로 위임?**
issue description 본문이 메인 컨텍스트에 누적되면 후속 작업 토큰 효율이 떨어짐. 위임하면 메인은 점수표 + Top N (수백 byte) 만 받고, 무거운 read 는 서브에이전트가 격리된 context 에서 처리.

**인자**:
- `--top N` — 추천 개수 (기본 3)
- `--team <name>` — Linear team 지정 (미지정 시 settings.json 의 team 또는 첫 team)
- `--state <name>` — 상태 필터 (기본: Backlog + Todo + In Progress)

**금지**:
- Top 1 이슈로 자동 작업 시작 금지 — 사용자가 어느 트랙으로 갈지 결정
- 루브릭 임의 변경 금지 — 일관성이 비교 가치
