#!/usr/bin/env bash
# wait-reply.sh — 빈 inbox + 짧은 timeout → exit 2, stderr 에 timeout 메시지.

set -uo pipefail

ws="$SANDBOX/wait-reply-timeout"
mkdir -p "$ws/.orch/runs/mp-99/inbox"
: > "$ws/.orch/runs/mp-99/inbox/test.md"

set +e
out=$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=mp-99/test \
    ORCH_WAIT_REPLY_INTERVAL=1 \
    ORCH_WAIT_REPLY_TIMEOUT=2 \
    bash "$PLUGIN_ROOT/scripts/messages/wait-reply.sh" Q1 2>&1
)
code=$?
set -e

echo "$out"
echo "exit_code=$code"

[ "$code" -eq 2 ] || { echo "FAIL: 기대 exit 2 received $code"; exit 1; }
grep -qF "timeout" <<<"$out" || { echo "FAIL: timeout 메시지 누락"; exit 1; }

echo "OK wait-reply-timeout"
