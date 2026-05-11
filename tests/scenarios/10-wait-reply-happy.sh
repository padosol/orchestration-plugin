#!/usr/bin/env bash
# wait-reply.sh — inbox 에 이미 [reply:Q1] 메시지 있을 때 즉시 exit 0 + 본문 출력.

set -euo pipefail

ws="$SANDBOX/wait-reply-happy"
mkdir -p "$ws/.orch/runs/mp-99/inbox"
cat > "$ws/.orch/runs/mp-99/inbox/test.md" <<'EOF'

---
from: mp-99
to: mp-99/test
ts: 2026-05-11T12:00:00Z
id: msg-001
---
[reply:Q1]
GO. 진행하세요.
EOF

out="$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=mp-99/test \
    ORCH_WAIT_REPLY_INTERVAL=1 \
    ORCH_WAIT_REPLY_TIMEOUT=5 \
    bash "$PLUGIN_ROOT/scripts/wait-reply.sh" Q1 2>&1
)"

echo "$out"

grep -qF "msg_id=msg-001" <<<"$out" || { echo "FAIL: msg_id not in output"; exit 1; }
grep -qF "GO. 진행하세요." <<<"$out" || { echo "FAIL: body not in output"; exit 1; }
grep -qF "qid=Q1" <<<"$out" || { echo "FAIL: qid label not in output"; exit 1; }

echo "OK wait-reply-happy"
