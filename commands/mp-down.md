---
description: MP-XXX leader cascade shutdown (산하 워커 + scope dir archive + 머지 브랜치 자동 정리)
argument-hint: <issue-id> [--no-cleanup]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/mp-down.sh:*)
---

다음 명령으로 cascade shutdown을 실행하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/mp-down.sh $ARGUMENTS`

**호출자별 동작**:
- **orch가 호출**: leader pane에 `/orch:mp-down <id>` 자동 전달 → leader가 cleanup 수행. leader pane이 이미 죽었으면 직접 정리.
- **leader가 호출**: 산하 워커 pane 모두 kill + 머지된 worktree 자동 정리(+pull) + `.orch/<mp-id>/` 를 archive로 이동 + 마지막에 mp-id tmux 윈도우 통째 kill (**leader 자기 pane 까지 자동 종료** — 사용자가 닫지 않음).

**worktree 자동 정리 (default ON)**:
- 산하 워커마다 그 worktree 의 현재 브랜치를 검사
- 각 워커는 자기 프로젝트의 `default_base_branch` (PAD-6 override 우선) 로 검사
- **base 머지 검사 정확도 + 사용자 수동 pull 면제 (PAD-12)**: project 마다 1회
  - main working tree 가 이미 base 체크아웃 중 → `git pull --ff-only origin <base>`
  - 다른 브랜치에 있음 → `git fetch origin <base>:<base>` 로 working tree 안 건드리고 local <base> ref 만 ff
- 머지 확인: `gh pr list --state merged --head <branch>` (squash/rebase merge 까지) → fallback: `git branch -r --merged origin/<base>`
- 머지됨 → `git worktree remove --force` + `git branch -d <branch>` (squash-merge 인식 거부 시 `-D` 폴백)
- 미머지 / 검출 실패 → 보존, 위치 출력
- 루프 종료 후 방문한 project 마다 `git worktree prune` 1회 — dangling 메타 보강
- `--no-cleanup` 플래그로 비활성화 (사용자 검토용)

**leader registry 비어 있는 fallback** (PAD-20):
- orch 가 호출했지만 leader 등록이 사라진 / leader pane 이 이미 죽은 경우
- settings 의 모든 project 에 `git worktree prune` 1회 (안전, 메타데이터만)
- mp_id 패턴 일치 로컬 브랜치 후보를 머지 상태와 함께 출력 — **자동 삭제 안 함, 명령 제안만**

**REPORT 자동 작성 (default ON)**:
- mp-down 시 archive 직전에 `report.sh` 가 실행 → `<archive_dir>/REPORT-data.md` 생성
- mp-down 이 orch 인박스에 종료 보고 + **REPORT.html 자동 작성 요청** 메시지 발송
- orch 가 인박스 처리할 때 `/orch:report <mp-id>` 실행 → `<archive_dir>/REPORT.html` 작성

**옵션**:
- `--no-cleanup` — worktree 정리를 건너뜀. 다 손으로 검토하고 싶을 때.
- `--no-report` — REPORT-data.md 덤프를 건너뜀.

**안전장치**:
- 머지 확인된 경우만 `branch -D` 폴백 — `gh pr list --state merged` 통과 못 한 브랜치는 절대 force 삭제 안 함
- worktree 에 미커밋·미추적 변경: 머지 확인 시 `--force` 로 정리 (PR 이미 머지됐으니 untracked 는 빌드 산출물), 미확인 시 보존
- fallback 경로의 orphan 브랜치 후보는 출력만 — 사용자 직접 실행
- gh / git 양쪽 모두 머지 확인 못 하면 보존

출력에 안내 메시지가 있으면 그대로 사용자에게 보여주세요.
