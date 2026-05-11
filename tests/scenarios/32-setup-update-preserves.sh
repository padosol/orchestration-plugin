#!/usr/bin/env bash
# setup.sh --update — 인자 없이 호출하면 issue_tracker / git_host / notify 모두 기존 값 보존.

set -euo pipefail

ws="$SANDBOX/setup-update-preserves"
mkdir -p "$ws/repo-a"
git -C "$ws/repo-a" init -q
git -C "$ws/repo-a" checkout -q -b main
echo "x" > "$ws/repo-a/a.txt"
git -C "$ws/repo-a" add . && git -C "$ws/repo-a" -c user.email=a@b -c user.name=t commit -qm init

ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/setup.sh" \
    --issue-tracker jira --git-host gitlab --notify on >/dev/null

# 두 번째 호출 — 인자 없이 update.
ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/setup.sh" --update >/dev/null

python3 - "$ws/.orch/settings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data.get("issue_tracker") == "jira", data
assert data.get("git_host") == "gitlab", data
assert data.get("notify", {}).get("slack_enabled") is True, data
PY

echo "OK setup-update-preserves"
