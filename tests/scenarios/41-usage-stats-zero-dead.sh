#!/usr/bin/env bash
# usage-stats.py --zero — 등록 목록 대비 카운트 0 항목 식별.

set -euo pipefail

ws="$SANDBOX/usage-stats-zero"
mkdir -p "$ws/s1"
cat > "$ws/s1/log.jsonl" <<'JSONL'
{"type":"user","timestamp":"2026-05-01T00:00:00Z","sessionId":"s1","message":{"role":"user","content":[{"type":"text","text":"<command-name>/orch:check-inbox</command-name>"}]}}
{"type":"user","timestamp":"2026-05-01T00:01:00Z","sessionId":"s1","message":{"role":"user","content":[{"type":"text","text":"<command-name>/orch:up</command-name>"}]}}
JSONL

cat > "$ws/registered.txt" <<'EOF'
/orch:check-inbox
/orch:up
/orch:send
/orch:never-called
EOF

out=$(python3 "$PLUGIN_ROOT/scripts/usage-stats.py" --root "$ws" --zero "$ws/registered.txt")
echo "$out"

grep -qF "Dead 후보" <<<"$out" || { echo "FAIL: Dead 후보 섹션 누락"; exit 1; }
grep -qF "/orch:send" <<<"$out" || { echo "FAIL: /orch:send 가 dead 로 잡혀야 함"; exit 1; }
grep -qF "/orch:never-called" <<<"$out" || { echo "FAIL: /orch:never-called 가 dead 로 잡혀야 함"; exit 1; }
grep -qF "/orch:check-inbox" <<<"$out" && ! grep -qE "Dead.*check-inbox" <<<"$out" || true
# /orch:check-inbox 가 일반 카테고리 섹션엔 나타나도 Dead 섹션엔 없어야 한다.

echo "OK usage-stats-zero-dead"
