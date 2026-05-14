---
description: MP-XXX leader cascade shutdown (산하 워커 + scope dir archive + 머지 브랜치 자동 정리)
argument-hint: <issue-id> [--no-cleanup]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/issue-down.sh:*)
---

다음 명령으로 cascade shutdown을 실행하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/issue-down.sh $ARGUMENTS`

**호출자별 동작**:
- **orch가 호출**: leader pane에 `/orch:issue-down <id>` 자동 전달 → leader가 cleanup 수행. leader pane이 이미 죽었으면 직접 정리.
- **leader가 호출**: 산하 워커 pane 모두 kill + 머지된 worktree 자동 정리(+pull) + `.orch/<mp-id>/` 를 archive로 이동 + 마지막에 mp-id tmux 윈도우 통째 kill (**leader 자기 pane 까지 자동 종료** — 사용자가 닫지 않음).

**worktree 자동 정리 (default ON)**:
- 산하 워커마다 그 worktree 의 현재 브랜치를 검사
- 각 워커는 자기 프로젝트의 `default_base_branch` override 우선, 없으면 글로벌 default 로 검사
- **base 머지 검사 정확도 + 사용자 수동 pull 면제**: project 마다 1회
  - main working tree 가 이미 base 체크아웃 중 → `git pull --ff-only origin <base>`
  - 다른 브랜치에 있음 → `git fetch origin <base>:<base>` 로 working tree 안 건드리고 local <base> ref 만 ff
- 머지 확인: 호스트 PR/MR (github: `gh pr list --state merged --head <branch>` / gitlab: `glab mr list --state merged --source-branch <branch>`, lib.sh `orch_pr_merged_by_branch` 가 settings.json 의 `git_host` 보고 분기) → fallback: `git branch -r --merged origin/<base>`
- 머지됨 → `git worktree remove --force` + `git branch -d <branch>` (squash-merge 인식 거부 시 `-D` 폴백)
- 미머지 / 검출 실패 → 보존, 위치 출력
- 루프 종료 후 방문한 project 마다 `git worktree prune` 1회 — dangling 메타 보강
- `--no-cleanup` 플래그로 비활성화 (사용자 검토용)

**leader registry 비어 있는 fallback**:
- orch 가 호출했지만 leader 등록이 사라진 / leader pane 이 이미 죽은 경우
- settings 의 모든 project 에 `git worktree prune` 1회 (안전, 메타데이터만)
- mp_id 패턴 일치 로컬 브랜치 후보를 머지 상태와 함께 출력 — **자동 삭제 안 함, 명령 제안만**

**REPORT — leader 가 phase 마지막 단계로 직접 작성**:
- leader 가 cascade shutdown 직전 자기 phase 마지막 단계로 `/orch:report <issue_id>` 호출 → `<scope_dir>/REPORT-data.md` + `<scope_dir>/REPORT.html` 생성 (issue-down 이 scope_dir 을 archive 로 옮기면서 함께 이동).
- issue-down.sh 는 안전망으로 archive 직전에 `report.sh` 를 한 번 더 실행 — REPORT-data.md 만 누락 방지용 (이미 있으면 idempotent overwrite).
- REPORT.html 은 leader 가 만들지 않으면 누락. inbox 메시지에 누락 hint 가 보이면 사용자가 `/orch:report <issue_id>` 로 archive 의 REPORT-data.md 를 재료로 수동 복구.

**orch 자동 호출 금지** — issue-down 알림 처리 시 orch 가 `/orch:report` 자동 호출하지 말 것. REPORT 는 leader 책임이고 orch 자동 호출은 중복 작업의 원인. 사용자 명시 요청 또는 누락 hint 가 있을 때만 호출.

**옵션**:
- `--no-cleanup` — worktree 정리를 건너뜀. 다 손으로 검토하고 싶을 때.
- `--no-report` — REPORT-data.md 덤프를 건너뜀.

**안전장치**:
- 머지 확인된 경우만 `branch -D` 폴백 — 호스트 PR/MR (`gh pr list --state merged` / `glab mr list --state merged`) 또는 `git branch -r --merged` 통과 못 한 브랜치는 절대 force 삭제 안 함
- worktree 에 미커밋·미추적 변경: 머지 확인 시 `--force` 로 정리 (PR 이미 머지됐으니 untracked 는 빌드 산출물), 미확인 시 보존
- fallback 경로의 orphan 브랜치 후보는 출력만 — 사용자 직접 실행
- 호스트 CLI (gh/glab) / git 양쪽 모두 머지 확인 못 하면 보존

출력에 안내 메시지가 있으면 그대로 사용자에게 보여주세요.

**잔재 수동 정리**: 자동 정리 후에도 worktree / 로컬 브랜치가 남아 있으면 `git worktree prune` + `git branch -D <branch>` 로 수동 보수.
