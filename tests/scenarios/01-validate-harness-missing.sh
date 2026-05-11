#!/usr/bin/env bash
# validate-harness SessionStart hook — 누락된 default_base_branch alias 를 systemMessage JSON 으로 보고.
# 기대: stdout 에 {"systemMessage":"..."} JSON, 본문에 누락 alias 목록 포함, exit 0.

set -euo pipefail

ws="$SANDBOX/validate-harness-missing"
mkdir -p "$ws/.orch"
cat > "$ws/.orch/settings.json" <<'JSON'
{
  "version": 1,
  "base_dir": "/dummy",
  "default_base_branch": "develop",
  "issue_tracker": "none",
  "projects": {
    "repo-a": {
      "path": "/abs/repo-a",
      "default_base_branch": "main"
    },
    "repo-b": {
      "path": "/abs/repo-b"
    },
    "repo-c": {
      "path": "/abs/repo-c"
    }
  }
}
JSON

out="$(cd "$ws" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/hooks/validate-harness.sh")"

echo "$out"

python3 - "$out" <<'PY'
import json, sys
raw = sys.argv[1]
data = json.loads(raw)
msg = data["systemMessage"]
assert "repo-b" in msg, f"repo-b not in systemMessage: {msg!r}"
assert "repo-c" in msg, f"repo-c not in systemMessage: {msg!r}"
assert "repo-a" not in msg, f"repo-a should NOT be flagged (has override): {msg!r}"
PY

echo "OK validate-harness-missing"
