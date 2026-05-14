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

# 이미 orch 등록 상태 처리
if orch_worker_exists "orch"; then
    existing_pane="$(orch_worker_field orch pane_id 2>/dev/null || true)"
    if [ "$existing_pane" = "$TMUX_PANE" ]; then
        echo "OK orch 이미 이 pane에 등록됨"
        exit 0
    fi
    if [ -n "$existing_pane" ] && orch_pane_alive "$existing_pane"; then
        echo "ERROR: 다른 pane이 이미 orch로 등록됨 (pane_id=$existing_pane)" >&2
        echo "  덮어쓰려면 그 pane에서 작업 마무리 후 .orch/workers/orch.json 직접 삭제, 다시 /orch:up" >&2
        exit 2
    fi
    # stale entry 정리
    orch_worker_unregister "orch"
fi

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')"
cwd="${PWD:-$(pwd)}"

orch_worker_register "orch" "orch" "$window_id" "$TMUX_PANE" "$cwd"

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
