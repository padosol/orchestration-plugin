#!/usr/bin/env bash
# /orch:down — orch tmux 세션을 통째로 종료. inbox/archive는 보존.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

force=0
for arg in "$@"; do
    case "$arg" in
        --force|-f) force=1 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

if ! tmux has-session -t "$ORCH_TMUX_SESSION" 2>/dev/null; then
    echo "Session $ORCH_TMUX_SESSION not running."
    exit 0
fi

if [ "$force" -eq 0 ]; then
    read -r -p "Kill tmux session '$ORCH_TMUX_SESSION'? Claude 세션이 종료됩니다. [y/N] " ans
    case "$ans" in
        y|Y|yes) ;;
        *) echo "취소"; exit 0 ;;
    esac
fi

tmux kill-session -t "$ORCH_TMUX_SESSION"
echo "세션 종료됨. 메일박스($ORCH_ROOT)는 유지됩니다."
