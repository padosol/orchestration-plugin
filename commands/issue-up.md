---
description: 이슈 팀리더(leader) pane을 띄운다 — orch 전용
argument-hint: <issue-id> [--force] [--no-issue]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/issue-up.sh:*)
---

다음 명령으로 leader를 띄우세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/issue-up.sh $ARGUMENTS`

**v2 변경**: repo 인자 없음. leader가 settings.json 보고 어느 프로젝트(들)에서 작업할지 결정.

**사용 규칙**:
- **orch 전용 명령** — 다른 워커에서 호출하면 거부됨
- `issue-id`: 트래커의 키 그대로 사용 (`[A-Za-z0-9_-]+`, 대소문자 보존). 예: Linear `MP-13` / Jira `PROJ-456` / GitHub `142` / 자유 `issue42`. 이슈가 없으면 사용자가 임의로 골라도 OK (식별자 용도로만 쓰임). `orch` 는 reserved.
- 같은 leader가 이미 있으면 에러. cascade 재생성은 끝에 `--force`
- leader pane은 **`<issue_id>` 이름의 새 tmux 윈도우** 로 생성됨 (orch 윈도우 split 아님). 같은 윈도우 안에 leader 가 자기 산하 워커 pane 들을 split 으로 띄워 (`/orch:leader-spawn` / `/orch:review-spawn` 이 자동 tiled) leader+worker 가 한 화면에 모인다.
- leader는 settings.json 의 `issue_tracker` 값에 따라 컨텍스트를 가져오고 작업 계획을 orch에 보고
  - `linear` → Linear MCP 로 이슈 fetch
  - `github` → `gh issue view` 로 fetch (settings.github_issue_repo 기준). issue-id 가 **전체 숫자** 가 아니면 (예: `feature-x`, `feature-2026`) 조기 차단 — `--no-issue` 로 우회하거나 다른 트래커 사용.
  - `gitlab` → `glab issue view` 로 fetch
  - `jira` → `jira issue view` 로 fetch
  - `none` → orch 에 spec 직접 요청
- **`--no-issue`**: 워크스페이스가 `linear`/`github` 트래커 모드여도 이번 호출만 fetch 스킵 (이슈 없음 → leader 가 orch 에 spec 직접 요청). 다음 호출부터는 워크스페이스 설정 그대로 적용. 사용 케이스: 이슈 만들기 번거로운 작은 작업, 이슈 미발행 상태에서 try-out, 사용자가 spec 만 구두 전달.

**PM (orch) 행동 규약 — 사용자 결정 후 즉시 invoke**:

- 사용자와 spec/계획을 컨펌한 직후 `issue-up`, `send`, `issue-down`, `report` 같은 슬래시 명령은 **orch 가 Skill 도구로 직접 invoke** 한다.
- ❌ "이 명령을 입력해주세요" 같이 사용자에게 떠넘기지 말 것. orch 의 역할은 사용자 결정을 받아 직접 실행하고 결과를 보고하는 것.
- 사용자 ↔ orch 토론 → 결정 → orch → leader 전송 구조를 유지. 사용자가 워커에 직접 명령을 내리는 흐름이 되지 않도록 한다.
- 예외: 사용자가 명시적으로 "직접 입력하겠다" 라고 했거나, 인터랙티브 외부 인증 (예: `gcloud auth login`) 같은 경우만 사용자에게 떠넘김.

**MP 마무리 — 책무 분리 (leader vs orch)**:

마무리 단계는 leader / orch 책무가 다음과 같이 갈린다. orch 가 leader 책무를 가로채지 말 것 — REPORT 중복 호출 / 후속 이슈 자동 등록 등이 사고의 원인.

**leader 책무** (phase 의 마지막 단계로 자체 수행):
- PR 머지 확인 후 `/orch:report <issue_id>` 호출 → REPORT-data.md + REPORT.html 생성
- errors.jsonl / AI-Ready 영향 검사 → **후속 이슈 후보** 도출 (REPORT.html `errors_check.patterns` / `ai_ready_check.stale_items` 기록)
- 후속 이슈 후보를 orch 인박스로 송신 (`[follow-up-candidates <issue_id>]` 라벨)
- `/orch:issue-down <issue_id>` 호출 → cascade shutdown

**orch 책무** (issue-down 알림 / follow-up-candidates 메시지 수신 시):
- 트래커 Done 업데이트 (linear → save_issue / github → gh issue close / gitlab → glab issue close / none → SKIP)
- REPORT.html 경로를 사용자에게 한 줄로 안내
- follow-up-candidates 본문을 사용자와 검토 → 등록 결정 난 항목만 트래커에 등록 (사용자 정책: "팀리더가 제공한 이슈를 사용자와 검토해서 추가")

**금지**:
- ❌ orch 가 `/orch:report` 자동 호출 — REPORT 는 leader phase 마지막 단계. 사용자 명시 요청 또는 REPORT.html 누락 hint 가 보일 때 수동 복구만 OK.
- ❌ orch 가 후속 이슈 자동 등록 — 항상 사용자 검토 후. leader 보낸 후보 메시지를 무비판 등록 금지.
- ❌ "PR 생성 task / 이슈 업데이트 task / REPORT task" 식 분할 — 한 작업이 여러 task 를 거치며 컨텍스트 분산.

**leader 안에서 다음 작업**:
- `/orch:leader-spawn <project>` 로 산하 워커 생성
- `/orch:send <issue_id>/<project> '...'` 로 워커에 지시
- `/orch:send orch '...'` 로 orch(=사용자에 전달용)에 진행 보고
- `/orch:issue-down <issue_id>` 로 cascade shutdown

**leader 작업 규약 — 워커 worktree 강제**:

- ❌ leader 가 자기 cwd 에서 직접 코드 수정 / 빌드 / 커밋 절대 금지.
- ✅ 모든 코드 작업은 **반드시 `/orch:leader-spawn <project>` 로 워커 spawn 후 워커가 worktree 안에서 처리**.
- 이유: leader cwd 는 본 repo 메인 워킹 트리이거나 사용자 작업 트리. leader 가 직접 변경하면 (1) 사용자 진행 중 변경과 충돌 (2) 브랜치 격리 안 됨 (3) PR 라이프사이클이 깨짐.
- 워커가 1명이면 충분한 단순 작업이라도 leader-spawn 으로 워커 spawn 해서 격리 워크트리에서 진행.
- spec 본문에 "worktree path 안에서 작업" 을 항상 명시.
