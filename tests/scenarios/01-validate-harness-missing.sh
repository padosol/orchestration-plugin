#!/usr/bin/env bash
# validate-harness SessionStart hook — 누락된 default_base_branch alias 를 systemMessage 배너로 알림.
# additionalContext 시도는 폐기 (Claude 자율 행동 trigger 못 함 — PAD-57).
# 기대: systemMessage 에 alias 목록 + '/orch:setup --update' 안내. exit 0.

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

banner = data.get("systemMessage", "")
assert banner, f"systemMessage 비어 있음: {data!r}"
assert "repo-b" in banner and "repo-c" in banner, f"banner 에 alias 누락: {banner!r}"
assert "repo-a" not in banner, f"repo-a should NOT be flagged: {banner!r}"
assert "/orch:setup --update" in banner, f"fix 명령 안내 누락: {banner!r}"

# additionalContext 폐기 확인 — 있어도 무방하나 의도는 banner 전용.
hso = data.get("hookSpecificOutput")
if hso is not None:
    raise AssertionError(f"hookSpecificOutput 출력 잔존 (PAD-57 에서 폐기 결정): {hso!r}")
PY

echo "OK validate-harness-missing"
