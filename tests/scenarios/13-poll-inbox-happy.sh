#!/usr/bin/env bash
# poll-inbox.sh — inbox 에 이미 메시지가 있으면 가장 오래된 msg_id 본문을 즉시 출력 (FIFO).

set -euo pipefail

ws="$SANDBOX/poll-inbox-happy"
mkdir -p "$ws/.orch/runs/mp-99/inbox"
cat > "$ws/.orch/runs/mp-99/inbox/test.md" <<'EOF'

---
from: mp-99
to: mp-99/test
ts: 2026-05-11T12:00:00Z
id: msg-001
---
첫 번째 작업 지시.

---
from: mp-99
to: mp-99/test
ts: 2026-05-11T12:00:01Z
id: msg-002
---
두 번째 메시지.
EOF

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
