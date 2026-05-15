---
description: 현재 pane을 orch(PM)로 등록 — 첫 진입 시 1회 실행
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/session/up.sh:*)
---

다음 명령으로 현재 pane을 orch worker(PM)로 등록하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/session/up.sh`

**역할**:
- 현재 tmux pane을 `orch` 라는 worker_id로 `.orch/workers/orch.json`에 등록
- 이 pane이 PM 역할을 맡고, 이후 `/orch:issue-up MP-XX`로 leader를 띄울 수 있게 됨
- v1과 달리 role 워커(server/ui/repo) 윈도우는 자동 생성하지 않음 — 워커는 leader가 spawn

**사전 조건**:
- tmux 세션 안에서 실행되어야 함 (`TMUX_PANE` 환경변수 필수)
- `.orch/settings.json`이 없으면 안내문에서 `/orch:setup` 권유

**등록 모델**:
- Identity 는 *경로* (`.orch/settings.json` 의 위치) — 이 경로에서 띄워진 claude 가 곧 orch
- `orch.json` 은 informational 레지스트리. 메시지 전달은 모두 파일 inbox + polling 으로 일원화돼서 pane_id 는 라우팅 책무가 없음 → `/orch:up` 은 **멱등 overwrite** (충돌 검사 없음)
- 기존 등록이 다른 pane 이면 silent 갱신 (INFO 한 줄). tmux 가 죽었다 살아도, pane 이 재발급돼도 그냥 덮어씀

출력 후 다음 단계 안내(`/orch:setup` 또는 `/orch:issue-up`)를 그대로 사용자에게 전달.
