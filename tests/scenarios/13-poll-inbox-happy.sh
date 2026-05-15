#!/usr/bin/env bash
# poll-inbox.sh — inbox 에 이미 메시지가 있으면 가장 오래된 msg_id 본문을 즉시 출력 (FIFO). (포인터 모델)

set -euo pipefail

ws="$SANDBOX/poll-inbox-happy"
ib="$ws/.orch/runs/mp-99/inbox/test"
mkdir -p "$ib/payloads"

mkmsg() { # $1=seq $2=id $3=body
    printf '%s' "$3" > "$ib/payloads/$2.md"
    jq -nc --arg from mp-99 --arg to mp-99/test --arg ts 2026-05-11T12:00:00Z \
        --arg id "$2" --arg payload "$ib/payloads/$2.md" \
        '{from:$from,to:$to,ts:$ts,id:$id,payload:$payload}' \
        > "$ib/$(printf '%020d' "$1")-$2.json"
}

mkmsg 1 msg-001 '첫 번째 작업 지시.'
mkmsg 2 msg-002 '두 번째 메시지.'

out="$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=mp-99/test \
    bash "$PLUGIN_ROOT/scripts/messages/poll-inbox.sh" --timeout 2 --interval 1 2>&1
)"

echo "$out"

grep -qF "msg_id=msg-001" <<<"$out" || { echo "FAIL: 가장 오래된 msg_id (FIFO) 를 출력해야 함"; exit 1; }
grep -qF "첫 번째 작업 지시." <<<"$out" || { echo "FAIL: 가장 오래된 메시지 본문 누락"; exit 1; }
grep -qF "inbox-archive.sh msg-001" <<<"$out" || { echo "FAIL: archive 안내 누락"; exit 1; }

echo "OK poll-inbox-happy"
