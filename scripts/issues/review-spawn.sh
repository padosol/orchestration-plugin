#!/usr/bin/env bash
# /orch:review-spawn <project-alias> <pr-num>
# leader (<issue_id>) 가 호출. PR 리뷰 전용 워커를 깨끗한 컨텍스트로 띄운다.
# reviewer 는 코드 수정 권한 없음 — first_msg 의 <pr_view_json_cmd>/<pr_diff_cmd> 로 변경분 검토 후 호스트 PR/MR 코멘트 (<pr_comment_from_file_cmd>) + leader 답신, 자기 종료. gh/glab 호환은 first_msg 변수가 spawn 시점에 결정.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 2 ]; then
    cat >&2 <<EOF
사용법: /orch:review-spawn <project-alias> <pr-num>
  project-alias: settings.json 의 projects 키 (예: server, ui, repo)
  pr-num: GitHub PR 번호 (숫자)
EOF
    exit 2
fi

project="$1"
pr="$2"

case "$pr" in
    ''|*[!0-9]*) echo "ERROR: pr-num은 숫자여야 함 ('$pr')" >&2; exit 2 ;;
esac

orch_settings_require || exit 2

self="$(orch_detect_self 2>/dev/null || true)"
self_kind="$(orch_wid_kind "${self:-}")"
if [ "$self_kind" != "leader" ]; then
    echo "ERROR: /orch:review-spawn 은 leader (<issue_id>) pane 에서만 호출 가능 (현재: ${self:-unknown})" >&2
    exit 2
fi

mp_id="$self"

if ! orch_settings_project_exists "$project"; then
    echo "ERROR: settings.json에 프로젝트 '$project' 없음" >&2
    echo "  사용 가능: $(orch_settings_projects | tr '\n' ' ')" >&2
    exit 2
fi

worker_id="${mp_id}/review-${project}"
if orch_worker_exists "$worker_id"; then
    echo "ERROR: $worker_id 이미 떠 있음 (PR #$pr 리뷰 진행 중)" >&2
    exit 2
fi

project_path="$(orch_settings_project_field "$project" path)"
[ -d "$project_path" ] || { echo "ERROR: project path '$project_path' 없음" >&2; exit 2; }

# leader 윈도우 찾기 (issue-up 이 만든 issue_id 이름 윈도우 = 워커들이 합류한 윈도우)
mp_window="$(tmux list-windows -t "$ORCH_TMUX_SESSION" -F '#{window_id} #W' 2>/dev/null \
    | awk -v n="$mp_id" '$2==n {print $1}' | head -n1)"

if [ -z "$mp_window" ]; then
    echo "ERROR: '$mp_id' 윈도우 없음 — leader 가 새 윈도우에 살고 있어야 함" >&2
    exit 2
fi

reviewer_pane="$(orch_split_in_window "$mp_window" "$project_path")"
if [ -z "$reviewer_pane" ]; then
    echo "ERROR: reviewer pane 생성 실패" >&2
    exit 2
fi

orch_worker_register "$worker_id" "worker" "$mp_window" "$reviewer_pane" "$project_path" "$project"

tmux send-keys -t "$reviewer_pane" "export ORCH_WORKER_ID=${worker_id} ORCH_BIN_DIR=${LIB_DIR} && claude" Enter
sleep 4

desc="$(orch_settings_project_field "$project" description)"
stack="$(orch_settings_project_field "$project" tech_stack)"
# 표시·트래커 호출용 키 (issue-up.sh 와 동일 규칙):
#   issue_display = issue_id 그대로
issue_display="$mp_id"
tracker="$(orch_settings_issue_tracker)"
gh_repo="$(orch_settings_github_issue_repo 2>/dev/null || true)"
plugin_root_review="$(dirname "$LIB_DIR")"
guidelines_path="${plugin_root_review}/references/coding-guidelines.md"
workflows_dir_review="${plugin_root_review}/references/workflows"

# leader 가 issue-up 시점에 .orch/runs/<mp_id>/type 으로 작업 타입 (feature|bug|refactor) 기록.
# reviewer 도 같은 가이드의 'Review 체크리스트' 절을 평가 잣대로 사용.
scope_dir_review="$(orch_scope_dir "$mp_id" 2>/dev/null || true)"
issue_type=""
if [ -n "$scope_dir_review" ] && [ -f "${scope_dir_review}/type" ]; then
    # 대소문자·공백 정규화 — leader 가 "Feature" / "BUG " 적어도 매칭되도록.
    issue_type="$(head -1 "${scope_dir_review}/type" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)"
fi
case "$issue_type" in
    feature|bug|refactor)
        workflow_review_line="추가로 ${workflows_dir_review}/${issue_type}.md 1회 Read — 'Review 체크리스트' 절을 ${issue_type} 작업 평가의 우선 기준으로 사용 (위의 일반 항목보다 ${issue_type} 특화 항목 우선)."
        ;;
    *)
        workflow_review_line="작업 타입 미기록 (.orch/runs/${mp_id}/type 없음 또는 알 수 없는 값) — 일반 5항목 체크리스트만 적용."
        ;;
esac

issue_lookup_line="$(orch_issue_lookup_line "$tracker" "$issue_display" "$gh_repo")"

protocols_path_review="${plugin_root_review}/references/orch-protocols.md"

# host-aware PR/MR 검토 명령 fragment. git_host 미설정이면 빈 안내.
pr_view_json_cmd="$(orch_pr_view_json_cmd 2>/dev/null || true)"
pr_diff_cmd="$(orch_pr_diff_cmd 2>/dev/null || true)"
pr_comment_from_file_cmd="$(orch_pr_comment_from_file_cmd 2>/dev/null || true)"
if [ -n "$pr_view_json_cmd" ]; then
    pr_host_block_review="- pr_view_json_cmd:        $pr_view_json_cmd
- pr_diff_cmd:             $pr_diff_cmd
- pr_comment_from_file_cmd: $pr_comment_from_file_cmd"
else
    pr_host_block_review="- (git_host 미설정 — PR view/diff/comment 가 불가. settings.json 의 git_host 를 github|gitlab 으로 채우고 다시 spawn)"
fi

first_msg="너는 ${worker_id} reviewer 다 (PR #${pr} 단발성). ${stack} 코드의 정확성 / 회귀 위험 / 사이드이펙트 / 단순성 / 가독성을 판단한다.

[컨텍스트 — spawn 시 주입]
- 이슈 ${issue_display} / PR #${pr} / $project ($project_path)
- tech: $stack / 설명: $desc
- leader: ${mp_id}
- ${workflow_review_line}
- ${issue_lookup_line}
${pr_host_block_review}

[필수 — 첫 마디로 Skill 로딩]
1) Skill 도구 invoke: **orch-reviewer**. 페르소나·체크리스트·두 채널 답신·verdict 형식·worker-shutdown 절차 전체가 본 SKILL 에 담겨 있다.
2) Skill 로드 실패 시 fallback: \`Read ${plugin_root_review}/skills/orch-reviewer/SKILL.md\` 1회. 본문 그대로 따른다.
3) 공통 운영 규약 단일 source: \`Read ${protocols_path_review}\` 1회 (hub-and-spoke / PR 4단계 / shutdown).
4) 시작 시 \`Read ${guidelines_path}\` 1회 — 4원칙을 평가 잣대로 사용 (특히 Surgical / Simplicity / Goal-Driven).

[Hard Guards — 본 first_msg 만으로도 절대 어기지 말 것]
1. **읽기 전용 — 코드 수정·커밋·push 금지.** Edit / Write / git commit / git push 호출 금지. 지적은 코멘트로만.
2. **답신은 두 채널 같은 본문 의무** — 호스트 PR (\`<pr_comment_from_file_cmd>\`) + leader (${mp_id}) inbox (\`send.sh\`). 채널마다 다른 본문 보내지 말 것.
3. **verdict 형식 고정**: 본문 첫 줄 \`[review PR #${pr}] <LGTM | needs-changes>\`.
4. **본 PR 변경분 범위 안에서만 평가** — PR 밖 리팩터 권고는 후속 이슈 메모로 leader 에 알리되 본 PR 차단 사유로 쓰지 말 것.
5. **답신 직후 자기 종료 의무** — \`bash \\\$ORCH_BIN_DIR/issues/worker-shutdown.sh\` 한 번. \`exit\` 키 입력 금지. 한 reviewer 는 1회 검토.

[진입 액션]
- 위 1) Skill 도구 invoke (orch-reviewer) → 2) orch-protocols.md Read → 3) coding-guidelines.md Read → PR #${pr} 검토 → 두 채널 답신 → \`worker-shutdown.sh\`."

orch_send_keys_line "$reviewer_pane" "$first_msg" \
    || echo "WARN: reviewer first_msg 송신 실패 (pane=$reviewer_pane)" >&2

echo "OK reviewer=$worker_id pane=$reviewer_pane window=$mp_window"
echo "  PR: #$pr"
echo "  cwd: $project_path"
