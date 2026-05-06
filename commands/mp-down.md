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
- **base 머지 검사 정확도를 위해 project_path 별로 `git pull --ff-only origin <base>` 1회**
- 머지 확인: `gh pr list --state merged --head <branch>` (squash/rebase merge 까지) → fallback: `git branch -r --merged origin/<base>`
- 머지됨 + clean → `git worktree remove` + `git branch -d <branch>`
- 미머지 / dirty / 검출 실패 → 보존, 위치 출력
- `--no-cleanup` 플래그로 비활성화 (사용자 검토용)

**REPORT 자동 작성 (default ON)**:
- mp-down 시 archive 직전에 `report.sh` 가 실행 → `<archive_dir>/REPORT-data.md` 생성
- mp-down 이 orch 인박스에 종료 보고 + **REPORT.html 자동 작성 요청** 메시지 발송
- orch 가 인박스 처리할 때 `/orch:report <mp-id>` 실행 → `<archive_dir>/REPORT.html` 작성

**옵션**:
- `--no-cleanup` — worktree 정리를 건너뜀. 다 손으로 검토하고 싶을 때.
- `--no-report` — REPORT-data.md 덤프를 건너뜀.

**안전장치**:
- `git branch -d` (소문자) 만 사용 — unmerged 브랜치 자동 거부
- worktree 에 미커밋·미추적 변경 있으면 보존
- gh / git 양쪽 모두 머지 확인 못 하면 보존

출력에 안내 메시지가 있으면 그대로 사용자에게 보여주세요.
