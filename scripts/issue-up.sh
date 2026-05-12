#!/usr/bin/env bash
# /orch:issue-up <issue-id> [--force]
# orch가 호출. 사용자가 넘긴 <issue-id> 로 팀리더 pane을 띄운다 — 트래커별 키 형식 그대로
# (Linear MP-13, Jira PROJ-456, GitHub 142, 자유 issue42 등).

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법: /orch:issue-up <issue-id> [--force] [--no-issue]
  issue-id: 트래커의 키 그대로 ([A-Za-z0-9_-]+, 대소문자 보존).
            예: MP-13 (Linear) / PROJ-456 (Jira) / 142 (GitHub) / issue42 (자유)
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

issue_id="$(orch_normalize_issue_id "$raw_id" || true)"
if [ -z "$issue_id" ]; then
    echo "ERROR: issue-id '$raw_id' 정규화 실패. [A-Za-z0-9_-]+ 만 허용 ('orch' 는 reserved)." >&2
    exit 2
fi
# 코드 호환을 위해 옛 변수명 mp_id 유지 (값은 issue_id 와 동일).
mp_id="$issue_id"

orch_settings_require || exit 2

caller="$(orch_detect_self 2>/dev/null || true)"
if [ "$caller" != "orch" ]; then
    echo "ERROR: /orch:issue-up 은 orch에서만 호출 가능 (현재: ${caller:-unknown})" >&2
    echo "  orch pane이 등록 안 돼 있으면 먼저 /orch:up 실행" >&2
    exit 2
fi

# 트래커 조기 검증 — side effects (--force kill / scope dir / leader pane spawn / claude 실행)
# 이전에 차단해야 실패 시 잔재 (.orch/runs/<id>, registry, tmux pane) 가 남지 않는다.
# GitHub Issues 는 issue id 전체가 숫자여야 함 — 'feature-2026' 같은 자유 id 의 첫 숫자
# 시퀀스를 GitHub issue #2026 으로 오인하면 잘못된 이슈 컨텍스트로 leader 가 작업.
tracker="$(orch_settings_issue_tracker)"
effective_tracker="$tracker"
if [ "$no_issue" -eq 1 ]; then
    effective_tracker="none"
fi
if [ "$effective_tracker" = "github" ]; then
    if [[ ! "$mp_id" =~ ^[0-9]+$ ]]; then
        echo "ERROR: issue-tracker=github 인데 '$mp_id' 가 전체 숫자 issue 번호가 아님." >&2
        echo "  GitHub Issues 는 숫자 키만 받음 (예: 142). 자유 식별자 (feature-x, MP-onboarding, feature-2026 등) 는" >&2
        echo "  --no-issue 로 이번 호출만 spec 요청 모드로 띄우거나, settings.json 의 issue_tracker 를 다른 값으로 바꿔서 호출." >&2
        exit 2
    fi
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

# leader pane (issue_id 이름의 새 윈도우 — 이후 워커들도 이 윈도우에 합류)
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
# 표시·트래커 호출용 키:
#   issue_display = 사용자 입력 그대로 (예: MP-13, PROJ-456, 142, issue42)
#   issue_num     = 트래커 fetch 에 넘기는 숫자 — GitHub 은 위에서 전체 숫자 검증을 통과했으므로
#                   $mp_id 가 그대로 곧 issue_num. GitLab fallback (reference 안 받는 환경) 용도로
#                   gitlab 분기에서만 첫 [0-9]+ 시퀀스 추출이 의미 있음 — pipefail 안전 || true.
issue_display="$mp_id"
gh_repo="$(orch_settings_github_issue_repo 2>/dev/null || true)"
plugin_root="$(dirname "$LIB_DIR")"
workflows_dir="${plugin_root}/references/workflows"

case "$effective_tracker" in
    linear)
        issue_fetch_step="1. mcp__linear-server__get_issue ${issue_display} (description / acceptance criteria)"
        ;;
    github)
        # 조기 검증 (orch_settings_require 직후) 에서 전체 숫자만 통과 — 여기 도달했다면 안전.
        issue_num="$mp_id"
        if [ -n "$gh_repo" ]; then
            issue_fetch_step="1. \`gh issue view ${issue_num} --repo ${gh_repo} --json title,body,labels,milestone\` (description / acceptance criteria)"
        else
            issue_fetch_step="1. \`gh issue view ${issue_num} --json title,body,labels,milestone\` (현재 cwd 의 repo 기준 — settings.json 의 github_issue_repo 미설정이라 해당 repo 인지 확인 필요)"
        fi
        ;;
    gitlab)
        # GitLab Issues 자동 fetch — glab CLI 경유. id 가 'PROJ-12' 같은 reference 면
        # glab 가 직접 받지만, 일부 환경/그룹에서는 숫자만 받음 — fallback 용 첫 숫자 시퀀스 추출.
        gl_issue_num="$(printf '%s' "$mp_id" | grep -Eo '[0-9]+' | head -1 || true)"
        if [ -n "$gh_repo" ]; then
            # github_issue_repo 가 gitlab 환경에서는 group/project 로 재해석됨
            issue_fetch_step="1. \`glab issue view ${gl_issue_num:-$issue_display} --repo ${gh_repo} --output json\` (description / labels / milestone). glab 미설치/미인증 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${issue_display} spec 부탁 — GitLab 이슈 본문/AC 붙여줘.\\nORCH_MSG\` 로 fallback."
        else
            issue_fetch_step="1. \`glab issue view ${gl_issue_num:-$issue_display} --output json\` (현재 cwd 의 project 기준 — settings.json 의 github_issue_repo 미설정이라 해당 project 인지 확인 필요). glab 미설치/미인증 시 send.sh orch 로 spec 요청 fallback."
        fi
        ;;
    jira)
        # Jira 자동 fetch — jira-cli (ankitpokhrel/jira-cli) 경유. 사이트 URL/토큰은
        # ~/.config/.jira/.config.yml 에 사전 등록되어 있어야 함.
        issue_fetch_step="1. \`jira issue view ${issue_display} --plain\` (description / acceptance criteria). jira-cli 미설치/미인증 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${issue_display} spec 부탁 — Jira 이슈 본문/AC 붙여줘.\\nORCH_MSG\` 로 fallback."
        ;;
    none|*)
        if [ "$no_issue" -eq 1 ] && [ "$tracker" != "none" ]; then
            tracker_note="(이번 호출만 --no-issue — 워크스페이스 트래커 설정 ${tracker} 는 다음 호출부터 그대로 적용)"
        else
            tracker_note="(트래커 미사용 모드)"
        fi
        issue_fetch_step="1. 이슈 컨텍스트 없음 ${tracker_note}. 본인 inbox 의 spec 메시지 또는 orch 의 첫 지시 확인. spec 부재 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${issue_display} spec 부탁 — 작업 범위·acceptance·관련 repo 알려달라.\\nORCH_MSG\` 로 요청."
        ;;
esac

first_msg="너는 ${mp_id} 팀리더(leader)다. 사용자가 위임한 ${issue_display} 을 책임지고 끝낸다.

[컨텍스트 — spawn 시 주입]
- issue: ${issue_display}
- 사용 가능 프로젝트: ${projects_blob}
- 이슈 fetch: ${issue_fetch_step}
- 타입 가이드 디렉토리: ${workflows_dir}
- plugin root: ${plugin_root}

[필수 — 첫 마디로 Skill 로딩]
1) Skill 도구 invoke: **orch-leader**. 페르소나·셋업·타입 판별·Phase Plan·라우팅·PR 4단계·종료 절차 전체가 본 SKILL 에 담겨 있다.
2) Skill 로드 실패 시 fallback: \`Read ${plugin_root}/skills/orch-leader/SKILL.md\` 1회. 본문 그대로 따른다.
3) 공통 운영 규약 단일 source: \`Read ${plugin_root}/references/orch-protocols.md\` 1회 (hub-and-spoke / wait-reply qid / HOLD / PR 4단계 / shutdown).

[Hard Guards — 본 first_msg 만으로도 절대 어기지 말 것]
1. **사용자 \`[plan-confirm] GO\` 받기 전 PM 포함 어떤 워커도 spawn 금지.** PM 이 필요하면 phase plan 에 'Phase 0: 분석/설계' (또는 첫 phase) 로 명시 후 GO 받고 그 phase 시작 시점에 spawn.
2. **작업 타입 모호 시 leader 가 직접 AskUserQuestion 호출 금지** (허브 위반). orch 에 \`[type-clarify:<qid> ${issue_display}]\` + \`[question:<qid>]\` 송신 후 \`bash \\\$ORCH_BIN_DIR/wait-reply.sh <qid>\` 로 차단 대기 → orch 가 같은 qid 박은 \`[type-decision:<qid>]\` + \`[reply:<qid>]\` 로 회신.
3. orch 에 phase plan 송신은 \`[phase-plan ${issue_display}]\` 라벨 의무 — orch 가 이 라벨로 컨펌 절차 트리거.
4. PM \`[direction-check]\` 본문 임의 요약·삭제 금지 — 원문 그대로 orch forward.
5. Worker \`[question:<qid>]\` 메시지는 우선 처리 — 워커가 wait-reply 로 막혀 있다. 답 미루지 말 것.

[진입 액션]
- 위 1) Skill 도구 invoke (orch-leader) → 2) orch-protocols.md Read → SKILL 본문의 절차대로 셋업·타입 판별·phase plan 작성 → \`[phase-plan ${issue_display}]\` 라벨로 orch 송신.
- \`[plan-confirm] GO\` 받기 전 워커 spawn 금지."

orch_send_keys_line "$leader_pane" "$first_msg" \
    || echo "WARN: leader first_msg 송신 실패 (pane=$leader_pane)" >&2

echo "OK leader=$mp_id pane=$leader_pane window=$leader_window"
echo "  scope_dir: $scope_dir"

# Slack 알림 — leader 가 막 떴고 plan 메시지를 곧 orch 로 송신할 예정.
"${LIB_DIR}/notify-slack.sh" mp_select "$mp_id" "leader 떴음 — 곧 plan 컨펌 메시지 도착" || true
