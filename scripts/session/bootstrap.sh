#!/usr/bin/env bash
# 어디서든 한 명령으로 워크스페이스 진입.
#   bash <plugin>/scripts/session/bootstrap.sh [<workspace-path>]
# - workspace-path 없으면 현재 디렉토리.
# - tmux 세션 이름 = workspace 디렉토리 basename.
# - 새 세션이면 claude 실행 + /orch:up 자동 입력. 기존 세션이면 attach.

set -euo pipefail

target="${1:-$PWD}"
if [ ! -d "$target" ]; then
    echo "ERROR: 디렉토리 없음: $target" >&2
    exit 2
fi
target="$(cd "$target" && pwd)"

if ! command -v tmux >/dev/null 2>&1; then
    echo "ERROR: tmux 미설치" >&2
    exit 2
fi

session="$(basename "$target")"

if tmux has-session -t "$session" 2>/dev/null; then
    echo "INFO: 기존 세션 '$session' attach (cwd=$target)"
    exec tmux attach -t "$session"
fi

echo "INFO: 새 세션 '$session' 생성 (cwd=$target)"
tmux new-session -d -s "$session" -c "$target"
tmux send-keys -t "$session" 'claude' Enter
sleep 4
tmux send-keys -t "$session" '/orch:up' Enter

exec tmux attach -t "$session"
