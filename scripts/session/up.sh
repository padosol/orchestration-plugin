#!/usr/bin/env bash
# /orch:up — 현재 pane을 orch worker(PM)로 등록.
# tmux 세션 / role 워커 윈도우는 더 이상 자동 생성하지 않는다.
# 사용자가 프로젝트 base_dir 에서 claude 를 실행한 뒤 한 번 호출.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

if [ -z "${TMUX_PANE:-}" ]; then
    echo "ERROR: tmux 안에서 실행해야 합니다 (TMUX_PANE 미설정)" >&2
    exit 2
fi

mkdir -p "$ORCH_INBOX" "$ORCH_ARCHIVE" "$ORCH_WORKERS"

# Identity 는 경로 (.orch/settings.json 의 위치) — 현재 이 경로에서 띄워진 claude 가 곧 orch.
# orch.json 은 informational 레지스트리일 뿐 (delivery 가 polling 으로 일원화돼서 pane_id
# 가 메시지 라우팅 책무를 잃었음). 따라서 /orch:up 은 멱등 overwrite — 기존 등록이 있어도
# 새 pane 정보로 덮어쓴다. 충돌 검사 없음.
prior_pane=""
if orch_worker_exists "orch"; then
    prior_pane="$(orch_worker_field orch pane_id 2>/dev/null || true)"
fi

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')"
cwd="${PWD:-$(pwd)}"

orch_worker_register "orch" "orch" "$window_id" "$TMUX_PANE" "$cwd"

if [ -n "$prior_pane" ] && [ "$prior_pane" != "$TMUX_PANE" ]; then
    echo "INFO: 기존 orch 등록 갱신 (pane $prior_pane → $TMUX_PANE)"
fi

cat <<EOF
OK orch pane 등록 완료
  pane_id:   $TMUX_PANE
  window_id: $window_id
  cwd:       $cwd

EOF

if ! orch_settings_exists; then
    cat <<EOF
다음 단계:
  1. /orch:setup 으로 .orch/settings.json 생성 후 description 보강
  2. /orch:issue-up <issue-id> 로 첫 leader 시작 (예: MP-13 / PROJ-456 / 142)
EOF
else
    echo "다음 단계: /orch:issue-up <issue-id> 로 leader 시작 (예: MP-13 / PROJ-456 / 142)"
fi
