#!/usr/bin/env bash
# send.sh — leader ↔ worker 메시지는 tmux 알림 없이 파일 inbox 에만 queue.

set -euo pipefail

ws="$SANDBOX/send-leader-worker-file-delivery"
mkdir -p "$ws/.orch"

out="$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=mp-99 \
    bash "$PLUGIN_ROOT/scripts/messages/send.sh" mp-99/api '작업 시작하세요' 2>&1
)"

echo "$out"

grep -qF "file-queued delivery only" <<<"$out" || { echo "FAIL: 파일 queue 안내 누락"; exit 1; }
grep -qF "mp-99 → mp-99/api" <<<"$out" || { echo "FAIL: 송신 결과 누락"; exit 1; }
if grep -qi 'tmux' <<<"$out"; then
    echo "FAIL: leader→worker 기본 송신에서 tmux 알림을 시도하면 안 됨"
    exit 1
fi

inbox="$ws/.orch/runs/mp-99/inbox/api.md"
[ -f "$inbox" ] || { echo "FAIL: worker inbox 파일 미생성: $inbox"; exit 1; }
grep -qF "작업 시작하세요" "$inbox" || { echo "FAIL: inbox 본문 누락"; exit 1; }

echo "OK send-leader-worker-file-delivery"
