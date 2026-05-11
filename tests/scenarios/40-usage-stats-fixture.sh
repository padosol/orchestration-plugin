#!/usr/bin/env bash
# usage-stats.py — fixture jsonl 디렉토리에서 4 카테고리 카운트가 맞는지 검증.

set -euo pipefail

ws="$SANDBOX/usage-stats"
mkdir -p "$ws/sessionA"
mkdir -p "$ws/sessionB"

# Fixture: 슬래시 명령 + Bash 스크립트 호출 + Skill + Agent
cat > "$ws/sessionA/log.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-05-01T00:00:00Z","sessionId":"s1","message":{"role":"user","content":[{"type":"text","text":"<command-name>/orch:check-inbox</command-name>"}]}}
{"type":"user","timestamp":"2026-05-01T00:01:00Z","sessionId":"s1","message":{"role":"user","content":[{"type":"text","text":"<command-name>/orch:check-inbox</command-name>"}]}}
{"type":"user","timestamp":"2026-05-01T00:02:00Z","sessionId":"s1","message":{"role":"user","content":[{"type":"text","text":"<command-name>/orch:send</command-name>"}]}}
{"type":"assistant","timestamp":"2026-05-01T00:03:00Z","sessionId":"s1","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"$ORCH_BIN_DIR/send.sh leader hi"}}]}}
{"type":"assistant","timestamp":"2026-05-01T00:04:00Z","sessionId":"s1","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"orch:check-inbox"}}]}}
{"type":"assistant","timestamp":"2026-05-01T00:05:00Z","sessionId":"s1","message":{"role":"assistant","content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"Explore"}}]}}
JSONL

cat > "$ws/sessionB/log.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-05-02T00:00:00Z","sessionId":"s2","message":{"role":"user","content":[{"type":"text","text":"<command-name>/orch:check-inbox</command-name>"}]}}
{"type":"assistant","timestamp":"2026-05-02T00:01:00Z","sessionId":"s2","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"bash $ORCH_BIN_DIR/inbox-archive.sh msg-1"}}]}}
{"type":"assistant","timestamp":"2026-05-02T00:02:00Z","sessionId":"s2","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"$ORCH_BIN_DIR/send.sh leader bye"}}]}}
{"type":"assistant","timestamp":"2026-05-02T00:03:00Z","sessionId":"s2","message":{"role":"assistant","content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"Explore"}}]}}
JSONL

out=$(python3 "$PLUGIN_ROOT/scripts/usage-stats.py" --root "$ws" --format json)
echo "$out"

python3 - "$out" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["sessions"] == 2, f"sessions={data['sessions']}"
assert data["commands"].get("/orch:check-inbox") == 3, f"check-inbox count: {data['commands']!r}"
assert data["commands"].get("/orch:send") == 1, f"send count: {data['commands']!r}"
assert data["scripts"].get("send.sh") == 2, f"send.sh: {data['scripts']!r}"
assert data["scripts"].get("inbox-archive.sh") == 1, f"inbox-archive: {data['scripts']!r}"
assert data["skills"].get("orch:check-inbox") == 1, f"skill: {data['skills']!r}"
assert data["agents"].get("Explore") == 2, f"Explore: {data['agents']!r}"
PY

echo "OK usage-stats-fixture"
