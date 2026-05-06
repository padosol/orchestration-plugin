---
description: leader가 산하 프로젝트 워커 pane을 띄움 (worktree + tmux + claude)
argument-hint: <project-alias> [feat|fix|refactor|chore|docs]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/leader-spawn.sh:*)
---

다음 명령으로 산하 워커를 띄우세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/leader-spawn.sh $ARGUMENTS`

**제약**:
- **leader 전용 명령**입니다. orch나 다른 워커에서 호출하면 거부됩니다.
- `project-alias`는 `.orch/settings.json` 의 `projects` 키 (예: `server`, `ui`, `repo`).
- `type`은 브랜치 prefix — 기본 `feat`. 가능: `feat|fix|refactor|chore|docs|test`.
- 같은 프로젝트 워커가 이미 떠 있으면 에러.

**worktree 격리 — 강제**:
이 명령은 항상 격리 worktree (`.orch/<mp_id>/worktrees/<project>`) 를 생성하고 그 안에서 워커를 띄운다. leader 가 자기 cwd 에서 직접 코드 작업하지 말 것 — 작업은 무조건 워커 spawn 으로 위임.

**동작**:
1. settings.json 에서 project path 조회
2. `git -C <project_path> worktree add .orch/<mp_id>/worktrees/<project> -b <type>/MP-NN origin/<base_branch>` 로 worktree 생성
3. tmux: `<mp_id>` 윈도우가 있으면 split, 없으면 새로 생성
4. 워커 pane에서 `claude` 실행 (ORCH_WORKER_ID=mp-NN/project)
5. 첫 메시지 자동 주입 (프로젝트 컨텍스트 + 라우팅 규칙)
6. `.orch/<mp_id>/workers/<project>.json` 등록

이후 leader는 `/orch:send <mp_id>/<project> '<지시>'` 로 워커에 작업 분배.
