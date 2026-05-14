---
description: leader가 산하 워커 pane을 띄움 (worktree + tmux + claude). --role 로 developer / PM 선택.
argument-hint: <project-alias> [feat|fix|refactor|chore|docs] [--role pm|dev]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/issues/leader-spawn.sh:*)
---

다음 명령으로 산하 워커를 띄우세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/issues/leader-spawn.sh $ARGUMENTS`

**역할 (--role)**:
- `dev` (기본): 구현 담당 developer. `worker_id = <issue_id>/<project>`. 프로젝트당 하나.
- `pm`: 분석·시스템 아키텍처·프로젝트 계획·기술 문서·API 스펙·데이터 모델 담당. `worker_id = <issue_id>/pm` (한 이슈 당 단일). **분석 직후 mandatory `[direction-check]` — 사용자 컨펌 전 산출물 finalize 금지.** 산출물은 `docs/spec/<issue_id>/` 등 워크트리에 commit → PR. 코드 직접 구현은 developer 담당.

**제약**:
- **leader 전용 명령**. orch나 다른 워커에서 호출하면 거부.
- `project-alias`는 `.orch/settings.json` 의 `projects` 키 (예: `server`, `ui`, `repo`). PM 도 worktree host 로 한 프로젝트 지정 — 다른 프로젝트 코드 참조는 `git -C <abs>` / `Read <abs>` 로.
- `type`: 브랜치 prefix. 기본 dev=`feat`, pm=`docs`. 가능: `feat|fix|refactor|chore|docs|test`.
- 같은 worker_id 가 이미 떠 있으면 에러 (PM 은 한 이슈 당 단일이라 두 번째 호출 차단됨).

**복잡 이슈 워크플로 (PM → developer)**:
1. 분석/스펙/API/데이터모델 필요하면 phase plan 에 **Phase 0: 분석/설계** 로 명시. **`[plan-confirm] GO` 받기 전 PM 포함 어떤 워커도 spawn 금지.**
2. GO 후 그 phase 시작 시점에 PM spawn: `/orch:leader-spawn <project> --role pm`
3. PM 이 `[direction-check]` + `[question:<qid>]` 송신 → leader 가 본문 그대로 사용자에게 보여주고 직접 `AskUserQuestion`
4. 사용자 답신을 같은 `[reply:<qid>]` 마커로 PM 에 forward
5. PM 산출물 finalize → PR 머지 후 다음 phase 시작 시점에 developer spawn → 구현

**worktree 격리 — 강제**:
이 명령은 항상 격리 worktree 를 생성하고 그 안에서 워커를 띄운다. leader 가 자기 cwd 에서 직접 코드 작업하지 말 것 — 작업은 무조건 워커 spawn 으로 위임.

**동작**:
1. settings.json 에서 project path 조회
2. `git -C <project_path> worktree add <worktree_path> -b <branch> origin/<base_branch>`
   - dev: branch `<type>/<issue_id>`, path `.../worktrees/<issue_id>/<project>/<type>`
   - pm:  branch `<type>/<issue_id>-pm`, path `.../worktrees/<issue_id>/<project>/pm`
3. tmux: `<issue_id>` 윈도우가 있으면 split, 없으면 새로 생성
4. 워커 pane에서 `claude` 실행 (ORCH_WORKER_ID 환경변수 셋)
5. 첫 메시지 자동 주입 — 동적 컨텍스트 + Skill 도구 트리거 (`orch-pm` / `orch-developer-worker`) + hard guard. 페르소나·절차 본문은 해당 SKILL.md 와 `references/orch-protocols.md` 단일 source 에서 로드.
6. 등록: `.orch/runs/<issue_id>/workers/<role>.json` (`<role>` = project alias 또는 `pm`)

이후 leader는 `/orch:send <issue_id>/<role> '<지시>'` 로 워커에 작업 분배 (`<role>` 은 PM 이면 `pm`, developer 면 project alias).
