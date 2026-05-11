---
description: leader가 산하 워커 pane을 띄움 (worktree + tmux + claude). --role 로 developer / PM 선택.
argument-hint: <project-alias> [feat|fix|refactor|chore|docs] [--role pm|dev]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/leader-spawn.sh:*)
---

다음 명령으로 산하 워커를 띄우세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/leader-spawn.sh $ARGUMENTS`

**역할 (--role)**:
- `dev` (기본): 구현 담당 developer. `worker_id = mp-NN/<project>`. 프로젝트당 하나.
- `pm`: 분석·시스템 아키텍처·프로젝트 계획·기술 문서·API 스펙·데이터 모델 담당. `worker_id = mp-NN/pm` (한 MP 당 단일). **분석 직후 mandatory `[direction-check]` — 사용자 컨펌 전 산출물 finalize 금지.** 산출물은 docs/spec/MP-NN/ 등 워크트리에 commit → PR. 코드 직접 구현은 developer 담당.

**제약**:
- **leader 전용 명령**. orch나 다른 워커에서 호출하면 거부.
- `project-alias`는 `.orch/settings.json` 의 `projects` 키 (예: `server`, `ui`, `repo`). PM 도 worktree host 로 한 프로젝트 지정 — 다른 프로젝트 코드 참조는 `git -C <abs>` / `Read <abs>` 로.
- `type`: 브랜치 prefix. 기본 dev=`feat`, pm=`docs`. 가능: `feat|fix|refactor|chore|docs|test`.
- 같은 worker_id 가 이미 떠 있으면 에러 (PM 은 한 MP 당 단일이라 두 번째 호출 차단됨).

**복잡 MP 워크플로 (PM → developer)**:
1. 분석/스펙/API/데이터모델 필요한 MP 는 PM 먼저: `/orch:leader-spawn <project> --role pm`
2. PM 이 `[direction-check]` 송신 → leader 가 본문 그대로 `/orch:send orch` 로 forward
3. 사용자 답신 (orch → leader inbox) 을 PM 으로 forward
4. PM 산출물 finalize → PR 머지 후 developer spawn → 구현

**worktree 격리 — 강제**:
이 명령은 항상 격리 worktree 를 생성하고 그 안에서 워커를 띄운다. leader 가 자기 cwd 에서 직접 코드 작업하지 말 것 — 작업은 무조건 워커 spawn 으로 위임.

**동작**:
1. settings.json 에서 project path 조회
2. `git -C <project_path> worktree add <worktree_path> -b <branch> origin/<base_branch>`
   - dev: branch `<type>/MP-NN`, path `.../worktrees/MP-NN/<project>/<type>`
   - pm:  branch `<type>/MP-NN-pm`, path `.../worktrees/MP-NN/<project>/pm`
3. tmux: `<mp_id>` 윈도우가 있으면 split, 없으면 새로 생성
4. 워커 pane에서 `claude` 실행 (ORCH_WORKER_ID 환경변수 셋)
5. 첫 메시지 자동 주입 (역할별 페르소나 + 라우팅 규칙)
6. 등록: `.orch/<mp_id>/workers/<role>.json` (`<role>` = project alias 또는 `pm`)

이후 leader는 `/orch:send <mp_id>/<role> '<지시>'` 로 워커에 작업 분배 (`<role>` 은 PM 이면 `pm`, developer 면 project alias).
