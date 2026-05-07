---
description: 현재 pane을 orch(PM)로 등록 — 첫 진입 시 1회 실행
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/up.sh:*)
---

다음 명령으로 현재 pane을 orch worker(PM)로 등록하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/up.sh`

**역할**:
- 현재 tmux pane을 `orch` 라는 worker_id로 `.orch/workers/orch.json`에 등록
- 이 pane이 PM 역할을 맡고, 이후 `/orch:issue-up MP-XX`로 leader를 띄울 수 있게 됨
- v1과 달리 role 워커(server/ui/repo) 윈도우는 자동 생성하지 않음 — 워커는 leader가 spawn

**사전 조건**:
- tmux 세션 안에서 실행되어야 함 (`TMUX_PANE` 환경변수 필수)
- `.orch/settings.json`이 없으면 안내문에서 `/orch:setup` 권유

**충돌 처리**:
- 이미 다른 살아있는 pane이 orch로 등록된 경우 에러 — 그쪽 정리 후 재시도
- 같은 pane이 이미 등록돼 있으면 idempotent (그대로 OK)
- stale 등록(pane 죽음)은 자동 정리 후 재등록

출력 후 다음 단계 안내(`/orch:setup` 또는 `/orch:issue-up`)를 그대로 사용자에게 전달.
