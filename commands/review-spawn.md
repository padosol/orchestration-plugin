---
description: leader가 PR 리뷰 전용 워커를 깨끗한 컨텍스트로 띄움 (단발성, 답신 후 자동 종료)
argument-hint: <project-alias> <pr-num>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/review-spawn.sh:*)
---

다음 명령으로 PR 리뷰 워커를 띄우세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/review-spawn.sh $ARGUMENTS`

**제약**:
- **leader 전용 명령**. orch / 작업 워커 / reviewer 자신에서 호출하면 거부.
- `project-alias`는 `.orch/settings.json` 의 `projects` 키 (예: `server`, `ui`).
- `pr-num`은 GitHub PR 번호.
- 같은 PR 리뷰가 이미 떠 있으면 에러 — 리뷰는 1회씩 진행.

**동작**:
1. worker_id = `${mp_id}/review-${project}` 등록
2. 같은 mp-NN 윈도우에 새 pane 추가 (cwd = project base path, **worktree 가 아님**)
3. claude 실행 + 첫 메시지 주입 — PR 번호 / 리뷰 체크리스트 / 답신 형식
4. reviewer 가 `gh pr diff/view` 로 PR 검토 후 leader 에 코멘트 답신, 직후 자기 pane 종료(`exit`)

**리뷰 라운드**:
- 한 reviewer 는 1회 검토만. 추가 라운드가 필요하면 leader 가 새로 `/orch:review-spawn` 호출.
- reviewer 답신 형식: `[review PR #N] <LGTM | needs-changes>` + 코멘트 리스트.

이후 leader 흐름:
- `LGTM` → 워커에 '머지 대기 시작' 지시 → 워커가 `wait-merge.sh <PR>` 호출
- `needs-changes` → 코멘트를 워커에 라우팅 → 워커 수정 후 're-review please' → 다시 `/orch:review-spawn`
