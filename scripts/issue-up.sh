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
  issue-id: 트래커의 키 그대로 (대소문자 보존). 거부 문자: 공백 / 제어문자 /
            shell metacharacters (;|&\$\`\\) / redirect·quoting·grouping (<>!(){}[]"') /
            path traversal (..) / slash (worker_id delimiter). 'orch' 는 reserved.
            예: MP-13 (Linear) / PROJ-456 (Jira) / 142 (GitHub) / my-issue#42 (GitLab) / issue42 (자유)
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
    echo "ERROR: issue-id '$raw_id' sanitize 실패." >&2
    echo "  거부 문자: 공백 / 제어문자 / shell meta(;|&\$\`\\) / redirect·quoting·grouping(<>!(){}[]\"') / .. / / ." >&2
    echo "  'orch' 는 reserved. GitLab cross-project ref(group/project#NN) 는 settings.json 의 github_issue_repo 에 project 박고 단일 키로 호출." >&2
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

# 트래커 결정 — fetch 자체는 leader 가 first_msg 의 issue_fetch_step 으로 수행.
# 트래커에 해당 이슈가 없으면 leader 가 search 로 후보 N 건을 가져와 orch 경유로
# 사용자 질문 → 답 받고 진행 (fuzzy fallback). 사전 차단은 sanitize 만, 트래커별
# id 형식 검증 (예: GitHub 전체 숫자) 은 leader fallback 에 위임.
tracker="$(orch_settings_issue_tracker)"
effective_tracker="$tracker"
if [ "$no_issue" -eq 1 ]; then
    effective_tracker="none"
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
#   issue_display = 사용자 입력 그대로 (sanitize 만 통과 — 예: MP-13, PROJ-456, 142, my-issue#42)
#   issue_num     = GitHub 분기에서 fetch 인자로 그대로 넘김 (사용자 입력 그대로 — fetch 실패는
#                   leader 의 fuzzy fallback 으로 처리). GitLab fallback 은 첫 [0-9]+ 시퀀스 추출
#                   (reference 안 받는 환경 대비) — pipefail 안전 || true.
issue_display="$mp_id"
gh_repo="$(orch_settings_github_issue_repo 2>/dev/null || true)"
plugin_root="$(dirname "$LIB_DIR")"
workflows_dir="${plugin_root}/references/workflows"

# 각 분기의 issue_fetch_step 은 (1) primary fetch 명령 + (2) fetch 실패 시 fuzzy fallback
# 진입 안내 한 줄로 구성. 상세 fuzzy 프로토콜 (search 명령 / orch 경유 사용자 질문 / wait-reply)
# 은 SKILL §1 "이슈 컨텍스트 fetch — fetch 실패 fallback" 절에 기록.
# sanitize 통과한 issue_display 도 leading '#' 같은 자연 키가 들어 있을 수 있으므로
# generated shell command 안에서는 항상 single-quote 로 감싼다 ('${issue_display}').
# orch_id_safe 가 ' 와 \\ 를 차단하므로 quote escape 위험은 없음.
case "$effective_tracker" in
    linear)
        issue_fetch_step="1. mcp__linear-server__get_issue ${issue_display} (description / acceptance criteria). 실패(이슈 없음) 시 SKILL §1 fuzzy fallback — list_issues 로 후보 search → orch 경유 사용자 질문."
        ;;
    github)
        issue_num="$mp_id"
        if [ -n "$gh_repo" ]; then
            issue_fetch_step="1. \`gh issue view '${issue_num}' --repo '${gh_repo}' --json title,body,labels,milestone\` (description / acceptance criteria). 실패(이슈 없음 / 숫자 키 아님) 시 SKILL §1 fuzzy fallback — \`gh issue list --repo '${gh_repo}' --search '${issue_display}'\` 로 후보 → orch 경유 사용자 질문."
        else
            issue_fetch_step="1. \`gh issue view '${issue_num}' --json title,body,labels,milestone\` (현재 cwd 의 repo 기준 — settings.json 의 github_issue_repo 미설정). 실패 시 SKILL §1 fuzzy fallback — \`gh issue list --search '${issue_display}'\` 로 후보 → orch 경유 사용자 질문."
        fi
        ;;
    gitlab)
        # glab 가 PROJ-12 같은 reference 를 직접 받기도 하고, 환경에 따라 숫자만 받기도 함 —
        # fallback 용 첫 숫자 시퀀스 추출. glab CLI 1.36+ 는 --output 옵션 없음 — text 출력만.
        gl_issue_num="$(printf '%s' "$mp_id" | grep -Eo '[0-9]+' | head -1 || true)"
        if [ -n "$gh_repo" ]; then
            # github_issue_repo 가 gitlab 환경에서는 group/project 로 재해석됨
            issue_fetch_step="1. \`glab issue view '${gl_issue_num:-$issue_display}' --repo '${gh_repo}'\` (text — title / labels / milestone). 실패(이슈 없음 / 미인증) 시 SKILL §1 fuzzy fallback — \`glab issue list --repo '${gh_repo}' --search '${issue_display}'\` 로 후보 → orch 경유 사용자 질문. glab 미설치 시 send.sh orch 로 spec 요청 fallback."
        else
            issue_fetch_step="1. \`glab issue view '${gl_issue_num:-$issue_display}'\` (현재 cwd 의 project 기준 — settings.json 의 github_issue_repo 미설정). 실패 시 SKILL §1 fuzzy fallback — \`glab issue list --search '${issue_display}'\` 로 후보 → orch 경유 사용자 질문. glab 미설치 시 send.sh orch 로 spec 요청 fallback."
        fi
        ;;
    jira)
        issue_fetch_step="1. \`jira issue view '${issue_display}' --plain\` (description / acceptance criteria). 실패(이슈 없음 / 미인증) 시 SKILL §1 fuzzy fallback — \`jira issue list --jql 'text ~ \"${issue_display}\"'\` 로 후보 → orch 경유 사용자 질문. jira-cli 미설치 시 send.sh orch 로 spec 요청 fallback."
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
1. **사용자 GO 전 PM 포함 어떤 워커도 spawn 금지.** 단순 이슈는 1 라운드 \`[plan-confirm] GO\` 후 spawn. 복잡 이슈는 Round 1 GO 로 PM 만 spawn 가능, **Round 2 GO (approved_task_graph 승인) 전 developer/reviewer/integration 워커 spawn 금지.** 상세 절차는 orch-leader SKILL §3.5.3.
2. **PR workflow step 순서 invariant 준수 (developer 등 wait_merge step 이 있는 PR 구현 workflow 기준)** — ci done 전 ready_for_review 금지 / review LGTM 전 wait_merge 금지 / wait_merge done 전 shutdown 금지. 워커 보고가 위반이면 leader 즉시 HOLD. 단발성 reviewer 처럼 wait_merge step 이 없는 workflow 는 자기 template 기준 (reviewer 는 respond → shutdown). 상세는 SKILL §3.5.5.
3. **작업 타입 모호 시 leader 가 직접 AskUserQuestion 호출 금지** (허브 위반). orch 에 \`[type-clarify:<qid> ${issue_display}]\` + \`[question:<qid>]\` 송신 후 \`bash \\\$ORCH_BIN_DIR/wait-reply.sh <qid>\` 로 차단 대기 → orch 가 같은 qid 박은 \`[type-decision:<qid>]\` + \`[reply:<qid>]\` 로 회신.
4. orch 에 phase plan 송신은 \`[phase-plan ${issue_display}]\` 라벨 의무 — orch 가 이 라벨로 컨펌 절차 트리거.
5. PM \`[direction-check]\` 본문 임의 요약·삭제 금지 — 원문 그대로 orch forward.
6. Worker \`[question:<qid>]\` 메시지는 우선 처리 — 워커가 wait-reply 로 막혀 있다. 답 미루지 말 것.

[진입 액션]
- 위 1) Skill 도구 invoke (orch-leader) → 2) orch-protocols.md Read → SKILL 본문의 절차대로 셋업·타입 판별·phase plan 작성 → \`[phase-plan ${issue_display}]\` 라벨로 orch 송신.
- \`[plan-confirm] GO\` 받기 전 워커 spawn 금지."

orch_send_keys_line "$leader_pane" "$first_msg" \
    || echo "WARN: leader first_msg 송신 실패 (pane=$leader_pane)" >&2

echo "OK leader=$mp_id pane=$leader_pane window=$leader_window"
echo "  scope_dir: $scope_dir"

# Slack 알림 — leader 가 막 떴고 plan 메시지를 곧 orch 로 송신할 예정.
"${LIB_DIR}/notify-slack.sh" mp_select "$mp_id" "leader 떴음 — 곧 plan 컨펌 메시지 도착" || true
