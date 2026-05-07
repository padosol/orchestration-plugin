---
description: MP-XXX 팀리더(leader) pane을 띄운다 — orch 전용
argument-hint: <issue-id> [--force]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/issue-up.sh:*)
---

다음 명령으로 leader를 띄우세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/issue-up.sh $ARGUMENTS`

**v2 변경**: repo 인자 없음. leader가 settings.json 보고 어느 프로젝트(들)에서 작업할지 결정.

**사용 규칙**:
- **orch 전용 명령** — 다른 워커에서 호출하면 거부됨
- `issue-id`: `MP-13` / `mp-13` / `13` 모두 허용 (내부적으로 `mp-13`)
- 같은 leader가 이미 있으면 에러. cascade 재생성은 끝에 `--force`
- leader pane은 호출자(orch) 윈도우를 split해 생성됨 (자동 타일링)
- leader는 settings.json 의 `issue_tracker` 값에 따라 컨텍스트를 가져오고 작업 계획을 orch에 보고
  - `linear` → Linear MCP 로 이슈 fetch
  - `github` → `gh issue view` 로 fetch (settings.github_issue_repo 기준)
  - `none` → orch 에 spec 직접 요청

**PM (orch) 행동 규약 — 사용자 결정 후 즉시 invoke**:

- 사용자와 spec/계획을 컨펌한 직후 `issue-up`, `send`, `issue-down`, `report` 같은 슬래시 명령은 **orch 가 Skill 도구로 직접 invoke** 한다.
- ❌ "이 명령을 입력해주세요" 같이 사용자에게 떠넘기지 말 것. orch 의 역할은 사용자 결정을 받아 직접 실행하고 결과를 보고하는 것.
- 사용자 ↔ orch 토론 → 결정 → orch → leader 전송 구조를 유지. 사용자가 워커에 직접 명령을 내리는 흐름이 되지 않도록 한다.
- 예외: 사용자가 명시적으로 "직접 입력하겠다" 라고 했거나, 인터랙티브 외부 인증 (예: `gcloud auth login`) 같은 경우만 사용자에게 떠넘김.

**PM task 분리 금지 — 마무리는 단일 task**:

MP 마무리 단계 (PR 머지 / 이슈 트래커 Done 표시 / REPORT 트리거) 는 **orch 측에서 분리 task 로 만들지 말 것**. 셋은 한 묶음:
- PR 머지 자체는 워커 PR 라이프사이클이 처리 (워커 first_msg 4단계)
- 머지 완료 → leader 가 issue-down → issue-down 알림이 orch 인박스에 들어옴 → orch 는 그 알림 1건 처리 흐름에서 트래커 Done 업데이트 (linear → save_issue, github → gh issue close, none → SKIP) + REPORT 까지 한 turn 에 처리
- "PR 생성 task / 이슈 업데이트 task" 식으로 쪼개면 한 작업이 여러 task 를 거치며 컨텍스트가 분산됨. **단일 task = 단일 작업** 원칙.

**leader 안에서 다음 작업**:
- `/orch:leader-spawn <project>` 로 산하 워커 생성
- `/orch:send <mp-id>/<project> '...'` 로 워커에 지시
- `/orch:send orch '...'` 로 orch(=사용자에 전달용)에 진행 보고
- `/orch:issue-down <mp-id>` 로 cascade shutdown

**leader 작업 규약 — 워커 worktree 강제**:

- ❌ leader 가 자기 cwd 에서 직접 코드 수정 / 빌드 / 커밋 절대 금지.
- ✅ 모든 코드 작업은 **반드시 `/orch:leader-spawn <project>` 로 워커 spawn 후 워커가 worktree 안에서 처리**.
- 이유: leader cwd 는 본 repo 메인 워킹 트리이거나 사용자 작업 트리. leader 가 직접 변경하면 (1) 사용자 진행 중 변경과 충돌 (2) 브랜치 격리 안 됨 (3) PR 라이프사이클이 깨짐.
- 워커가 1명이면 충분한 단순 작업이라도 leader-spawn 으로 워커 spawn 해서 격리 워크트리에서 진행.
- spec 본문에 "worktree path 안에서 작업" 을 항상 명시.
