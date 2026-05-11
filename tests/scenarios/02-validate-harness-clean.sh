#!/usr/bin/env bash
# validate-harness — 모든 alias 가 default_base_branch 보유 → silent exit 0 (stdout 비어야 함).

set -euo pipefail

ws="$SANDBOX/validate-harness-clean"
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
      "path": "/abs/repo-b",
      "default_base_branch": "develop"
    }
  }
}
JSON

out="$(cd "$ws" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/hooks/validate-harness.sh")"

if [ -n "$out" ]; then
    echo "FAIL: 모든 alias 보유했는데 stdout 출력 발생:"
    echo "$out"
    exit 1
fi

echo "OK validate-harness-clean (silent exit 0)"
