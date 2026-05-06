---
description: orch tmux 세션을 통째로 종료 (모든 leader/워커 강제 종료)
argument-hint: [--force]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/down.sh:*)
---

다음 명령으로 orch tmux 세션을 종료하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/down.sh $ARGUMENTS`

**역할**:
- `lol` tmux 세션을 통째로 kill — 안에 있던 orch / leader / 워커 pane 모두 강제 종료
- `.orch/inbox/`, `.orch/archive/` 메일박스는 보존 (다시 띄울 때 그대로 사용)
- worktree / 브랜치는 그대로 유지

**언제 쓰나**:
- 모든 작업이 끝났고 깨끗하게 닫고 싶을 때
- 시스템이 꼬여서 hard reset이 필요할 때
- 평소 MP 단위 종료는 `/orch:mp-down MP-XX` 사용 (leader cascade) — `/orch:down`은 최후의 수단

**사용**:
- `/orch:down` — 확인 프롬프트 후 종료
- `/orch:down --force` — 즉시 종료

세션 종료 후 다시 시작하려면 새 tmux 세션 안에서 `/orch:up` 부터 다시.
