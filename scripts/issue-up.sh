#!/usr/bin/env bash
# /orch:issue-up <issue-id> [--force]
# orch가 호출. MP-XX 팀리더 pane을 띄운다.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법: /orch:issue-up <issue-id> [--force] [--no-issue]
  issue-id 예: MP-13 / mp-13 / 13 (모두 mp-13으로 정규화)
  --force: 이미 떠 있는 leader가 있어도 cascade kill 후 재생성
  --no-issue: 트래커 설정 무시 (이번 한 번만). leader 가 orch 에 spec 직접 요청.
              사용 케이스: 이슈 만들기 번거로운 작은 작업 / 이슈 없이 try-out
EOF
    exit 2
fi

raw_id="$1"
shift || true
force=0
no_issue=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        --no-issue) no_issue=1 ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

mp_id="$(orch_normalize_issue_id "$raw_id" || true)"
if [ -z "$mp_id" ]; then
    echo "ERROR: issue-id '$raw_id' 정규화 실패. MP-NN 또는 NN 형식 사용." >&2
    exit 2
fi

orch_settings_require || exit 2

caller="$(orch_detect_self 2>/dev/null || true)"
if [ "$caller" != "orch" ]; then
    echo "ERROR: /orch:issue-up 은 orch에서만 호출 가능 (현재: ${caller:-unknown})" >&2
    echo "  orch pane이 등록 안 돼 있으면 먼저 /orch:up 실행" >&2
    exit 2
fi

if orch_worker_exists "$mp_id"; then
    if [ "$force" -eq 1 ]; then
        echo "INFO: 기존 $mp_id leader cascade kill"
        existing_pane="$(orch_worker_field "$mp_id" pane_id 2>/dev/null || true)"
        if [ -n "$existing_pane" ] && orch_pane_alive "$existing_pane"; then
            tmux kill-pane -t "$existing_pane" 2>/dev/null || true
        fi
        sub_window="$(tmux list-windows -t "$ORCH_TMUX_SESSION" -F '#{window_id} #W' 2>/dev/null \
            | awk -v n="$mp_id" '$2==n {print $1}' | head -n1)"
        if [ -n "$sub_window" ]; then
            tmux kill-window -t "$sub_window" 2>/dev/null || true
        fi
        rm -rf "$(orch_scope_dir "$mp_id")"
        orch_worker_unregister "$mp_id"
    else
        echo "ERROR: $mp_id 이미 등록됨. cascade 재생성하려면 --force" >&2
        exit 2
    fi
fi

# scope skeleton (runs/ wrapper 가 기본 위치)
mkdir -p "$ORCH_RUNS_DIR"
scope_dir="$(orch_scope_dir "$mp_id")"
mkdir -p "$scope_dir/inbox" "$scope_dir/archive" "$scope_dir/workers" "$scope_dir/worktrees"
mkdir -p "$ORCH_INBOX" "$ORCH_ARCHIVE" "$ORCH_WORKERS"

# leader pane (mp-NN 이름의 새 윈도우 — 이후 워커들도 이 윈도우에 합류)
ids="$(orch_new_window "$mp_id" "$scope_dir")"
read -r leader_window leader_pane <<<"$ids"
if [ -z "$leader_pane" ]; then
    echo "ERROR: leader pane 생성 실패" >&2
    exit 2
fi

orch_worker_register "$mp_id" "leader" "$leader_window" "$leader_pane" "$scope_dir"

tmux send-keys -t "$leader_pane" "export ORCH_WORKER_ID=$mp_id ORCH_BIN_DIR=$LIB_DIR && claude" Enter
sleep 4

projects_blob="$(orch_settings_projects | tr '\n' ' ')"
mp_upper="${mp_id^^}"
issue_num="${mp_id#mp-}"
tracker="$(orch_settings_issue_tracker)"
gh_repo="$(orch_settings_github_issue_repo 2>/dev/null || true)"

# --no-issue 가 켜지면 워크스페이스 트래커 설정과 무관하게 spec 요청 모드.
effective_tracker="$tracker"
if [ "$no_issue" -eq 1 ]; then
    effective_tracker="none"
fi

case "$effective_tracker" in
    linear)
        issue_fetch_step="1. mcp__linear-server__get_issue ${mp_upper} (description / acceptance criteria)"
        ;;
    github)
        if [ -n "$gh_repo" ]; then
            issue_fetch_step="1. \`gh issue view ${issue_num} --repo ${gh_repo} --json title,body,labels,milestone\` (description / acceptance criteria)"
        else
            issue_fetch_step="1. \`gh issue view ${issue_num} --json title,body,labels,milestone\` (현재 cwd 의 repo 기준 — settings.json 의 github_issue_repo 미설정이라 해당 repo 인지 확인 필요)"
        fi
        ;;
    none|*)
        if [ "$no_issue" -eq 1 ] && [ "$tracker" != "none" ]; then
            tracker_note="(이번 호출만 --no-issue — 워크스페이스 트래커 설정 ${tracker} 는 다음 호출부터 그대로 적용)"
        else
            tracker_note="(트래커 미사용 모드)"
        fi
        issue_fetch_step="1. 이슈 컨텍스트 없음 ${tracker_note}. 본인 inbox 의 spec 메시지 또는 orch 의 첫 지시 확인. spec 부재 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${mp_upper} spec 부탁 — 작업 범위·acceptance·관련 repo 알려달라.\\nORCH_MSG\` 로 요청."
        ;;
esac

first_msg="너는 ${mp_id} 팀리더(leader)다. 10년차 시니어 엔지니어링 매니저로서 사용자가 위임한 ${mp_upper} 을 책임지고 끝낸다 — spec 분해 / 산하 워커 spawn / 라우팅 / 통합 / shutdown. 의사결정은 코드·데이터 기반으로 하고, spec 이 모호하면 추측 진행 금지 — 사유 명시해 orch 에 escalate.

[셋업]
${issue_fetch_step}
2. cat .orch/settings.json — 사용 가능 프로젝트: ${projects_blob}
3. 어느 프로젝트(들)에서 작업할지 결정. 모호하면 후보 \`<path>/CLAUDE.md\` 확인. 그래도 불확실하면 orch 에 질문 — 잘못된 프로젝트에 spawn 금지.

[워커 spawn]
  /orch:leader-spawn <project> [type]   # type: feat | fix | refactor | chore | docs | test (기본 feat)

[메시지 — Hub-and-Spoke]
- 산하 지시: /orch:send ${mp_id}/<project> '<지시>'
- orch 보고: /orch:send orch '<요약>'
- 워커끼리 / 다른 MP / 다른 프로젝트 직접 통신 차단됨 — 의존 생기면 leader 라우팅 또는 orch escalate.
- **따옴표·줄바꿈·백틱 메시지는** Bash heredoc 필수:
    bash -c \"\$ORCH_BIN_DIR/send.sh <target> <<'ORCH_MSG'
    본문
    ORCH_MSG\"
  슬래시 /orch:send 는 \$ARGUMENTS 가 셸 파서 깨뜨려 특수문자 실패. \$ORCH_BIN_DIR 자동 export 됨.

[PR 4단계]
1. **CI**: 워커가 \`gh pr checks <pr> --watch --required\` 로 자기 책임. 통과하면 'PR #N ready for review + URL' 답신.
2. **리뷰**: ready 받으면 즉시 /orch:review-spawn <project> <pr>. reviewer 답신은 \`[review PR #N] LGTM\` 또는 \`needs-changes\` + 코멘트.
   - **needs-changes** → 답신 그대로 작업 워커에 라우팅 → 수정 후 're-review please' → 다시 review-spawn (라운드 N).
   - **LGTM** → 답신 그대로 작업 워커에 라우팅. 워커가 자동으로 wait-merge.sh 진입 (별도 '머지 대기' 지시 불필요).
   ⚠ LGTM 라우팅 후 워커가 wait-merge 안 들어가고 멈춰 있으면 \"\\\$ORCH_BIN_DIR/wait-merge.sh <pr> 실행\" 명시 트리거.
3. **머지 대기**: 워커 wait-merge.sh 30s 폴링. 사용자 머지 시 'PR #N merged' 답신 후 자동 종료. exit 1 / 2 면 워커 보고 → escalate.
4. **종료**: 모든 워커 종료 후 /orch:issue-down ${mp_id} → cascade kill + worktree 정리 + REPORT 자동 작성 + leader 자기 pane 종료.

[테스트·컨텍스트]
- 크로스-프로젝트 E2E SKIP — 후속 이슈 메모. 워커 작업 독립 가정.
- 컨텍스트 150k 넘으면 보고 직후 /compact (워커에도 같은 가이드 전달).

[금지]
- 리뷰 없이 머지 대기로 점프 금지 — 깨끗한 컨텍스트 reviewer 가 안전망.
- 워커 보고 없이 'PR 만들었으니 사용자가 머지' 식 종결 금지.

지금 1~3 진행하고 작업 계획을 /orch:send orch 로 보고하세요."

orch_send_keys_line "$leader_pane" "$first_msg" \
    || echo "WARN: leader first_msg 송신 실패 (pane=$leader_pane)" >&2

echo "OK leader=$mp_id pane=$leader_pane window=$leader_window"
echo "  scope_dir: $scope_dir"

# Slack 알림 — leader 가 막 떴고 plan 메시지를 곧 orch 로 송신할 예정.
"${LIB_DIR}/notify-slack.sh" mp_select "$mp_id" "leader 떴음 — 곧 plan 컨펌 메시지 도착" || true
