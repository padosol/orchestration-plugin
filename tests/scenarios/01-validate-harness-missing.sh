#!/usr/bin/env bash
# validate-harness SessionStart hook — 누락된 default_base_branch alias 를 보고.
# 기대 출력 (둘 다 있어야 함):
#   - hookSpecificOutput.additionalContext : Claude 컨텍스트 주입용 instruction
#   - systemMessage                        : UI 배너용 짧은 요약
# exit 0.

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

# additionalContext — Claude 가 instruction 으로 받는 키
hso = data.get("hookSpecificOutput") or {}
ctx = hso.get("additionalContext", "")
assert ctx, f"hookSpecificOutput.additionalContext 비어 있음: {data!r}"
assert hso.get("hookEventName") == "SessionStart", f"hookEventName 누락/오타: {hso!r}"
assert "repo-b" in ctx, f"repo-b not in additionalContext: {ctx!r}"
assert "repo-c" in ctx, f"repo-c not in additionalContext: {ctx!r}"
assert "repo-a" not in ctx, f"repo-a should NOT be flagged: {ctx!r}"
assert "AskUserQuestion" in ctx, f"instruction 에 AskUserQuestion 가이드 누락: {ctx!r}"

# systemMessage — UI 배너 (선택이지만 있어야 함)
banner = data.get("systemMessage", "")
assert banner, f"systemMessage 비어 있음: {data!r}"
assert "repo-b" in banner and "repo-c" in banner, f"banner 에 alias 누락: {banner!r}"
PY

echo "OK validate-harness-missing"
