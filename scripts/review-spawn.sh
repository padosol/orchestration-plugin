#!/usr/bin/env bash
# /orch:review-spawn <project-alias> <pr-num>
# leader (mp-NN) 가 호출. PR 리뷰 전용 워커를 깨끗한 컨텍스트로 띄운다.
# reviewer 는 코드 수정 권한 없음 — gh pr diff/view 로 변경분 검토 후 leader 에 답신하고 자기 종료.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
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
    echo "ERROR: /orch:review-spawn 은 leader (mp-NN) pane 에서만 호출 가능 (현재: ${self:-unknown})" >&2
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

# mp-NN 윈도우 찾기 (mp-up 이 만든 leader 윈도우 = 워커들이 합류한 윈도우)
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

orch_worker_register "$worker_id" "worker" "$mp_window" "$reviewer_pane" "$project_path"

tmux send-keys -t "$reviewer_pane" "export ORCH_WORKER_ID=${worker_id} ORCH_BIN_DIR=${LIB_DIR} && claude" Enter
sleep 4

desc="$(orch_settings_project_field "$project" description)"
stack="$(orch_settings_project_field "$project" tech_stack)"
mp_upper="${mp_id^^}"

first_msg="너는 ${worker_id} reviewer 워커다 (PR #${pr} 리뷰 전용, 단발성).

[리뷰 컨텍스트]
- 이슈: ${mp_upper}
- PR: #${pr}
- 대상 프로젝트: $project ($project_path)
- tech_stack: $stack
- 설명: $desc

[권한]
- **읽기 전용**. 코드 수정 / 커밋 / push / PR 코멘트 직접 달기 금지.
- 너는 leader($mp_id) 에게 코멘트 텍스트만 답신하고, leader 가 작업 워커에게 전달한다.

[리뷰 체크리스트]
1. **코드 정확성** — diff 가 의도된 변경을 정확히 구현하는가? off-by-one / null / 분기 누락 없나?
2. **사이드이펙트** — 변경 범위가 의도 외 영역에 영향 안 주는가? 공용 유틸 / API 시그니처 변경 시 호출자 영향?
3. **테스트 커버리지** — 변경에 대응하는 테스트가 있나? 누락된 엣지 케이스?
4. **회귀 가능성** — 기존 기능 회귀 위험? 데이터 마이그레이션 / 호환성 우려?
5. **스타일·가독성** — 네이밍·구조·주석 — repo 컨벤션과 일치?

[정보 수집 도구]
- gh pr view ${pr} --json title,body,files,headRefName,baseRefName
- gh pr diff ${pr}
- gh pr checks ${pr}
- 필요하면 base 코드 탐색: $project_path 안에서 grep / Read

[Linear 컨텍스트가 필요하면]
- mcp__linear-server__get_issue ${mp_upper}

[답신 형식]
bash -c \"\$ORCH_BIN_DIR/send.sh $mp_id <<'ORCH_MSG'
[review PR #${pr}] <LGTM | needs-changes>

요약: <한 줄>

코멘트:
- <파일:line> <지적 + 권고>
- ...

(없으면 \\\"코멘트 없음\\\" 명시)
ORCH_MSG\"

[종료 — 필수]
- 답신 보낸 직후 다음 명령 한 번:
    bash \$ORCH_BIN_DIR/worker-shutdown.sh
- registry 해제 + tmux pane kill 한 번에. \`exit\` 키 입력은 Claude Code 가 떠 있어서 셸에 닿지 않으므로 사용 금지.
- 추가 라운드가 필요하면 leader 가 다시 /orch:review-spawn 으로 새 reviewer 띄울 것 — 한 reviewer 는 1회 검토만.

[중요]
- 리뷰는 **이번 PR 범위 안에서만**. 'PR 밖 리팩터 권고' 는 후속 이슈 메모로 분류해 leader 에 알리되 본 PR 차단 사유로 쓰지 말 것.
- 사소한 스타일은 LGTM 하되 코멘트로만 남기고 차단하지 않기.

준비되면 위 도구로 PR 검토하고 답신 후 worker-shutdown.sh 실행하라."

tmux send-keys -t "$reviewer_pane" "$first_msg"
sleep 0.3
tmux send-keys -t "$reviewer_pane" Enter

echo "OK reviewer=$worker_id pane=$reviewer_pane window=$mp_window"
echo "  PR: #$pr"
echo "  cwd: $project_path"
