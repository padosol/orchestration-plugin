---
description: 전체 위계 + inbox 상태 (orch + leader + 산하 워커)
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect/status.sh:*)
---

다음 명령으로 위계 상태를 확인하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/inspect/status.sh`

**출력 구성**:
- tmux 세션 상태 (UP/DOWN)
- settings.json 존재 여부 + 프로젝트 수
- **Top-line 집계** (active leader 가 있을 때): `active: N leaders · M workers (K dead) · pending msgs P · direction-check D ⚠` — 한눈에 전체 상태.
- `orch` inbox 상태
- 활성 leader 목록 + 각 leader 산하 워커 트리 (들여쓰기로 표시)
- 각 row 끝의 `[direction-check]` 배지 — 인박스에 PM 컨펌 요청 / leader 답신이 미처리로 남아있을 때.
- orphan 경고 (leader 없이 산하 워커만 남은 경우)

출력을 그대로 사용자에게 보여주고, 미처리 메시지(pending > 0) / `direction-check` 배지 / orphan 이 있으면 짧게 코멘트하세요. `direction-check` 가 leader 인박스에 있으면 PM 컨펌 요청 forward 가 막혀 있다는 신호 — 즉시 처리 필요.
