#!/usr/bin/env bash
# setup.sh — fresh run 에서 새 메타데이터 필드 (issue_tracker / git_host / notify.slack_enabled) 가
# settings.json 에 들어가고 root default_base_branch 는 들어가지 않는지 검증 (0.12.0).

set -euo pipefail

ws="$SANDBOX/setup-fresh-new-fields"
mkdir -p "$ws/repo-a" "$ws/repo-b"
git -C "$ws/repo-a" init -q
git -C "$ws/repo-a" checkout -q -b main
echo '{"dependencies":{"next":"14"}}' > "$ws/repo-a/package.json"
git -C "$ws/repo-a" add . && git -C "$ws/repo-a" -c user.email=a@b -c user.name=t commit -qm init
git -C "$ws/repo-b" init -q
git -C "$ws/repo-b" checkout -q -b develop
echo "Hello" > "$ws/repo-b/README.md"
git -C "$ws/repo-b" add . && git -C "$ws/repo-b" -c user.email=a@b -c user.name=t commit -qm init

ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/setup.sh" \
    --issue-tracker jira --git-host gitlab --notify on >/dev/null

python3 - "$ws/.orch/settings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert "default_base_branch" not in data, f"root default_base_branch 잔존: {data!r}"
assert data.get("issue_tracker") == "jira", data
assert data.get("git_host") == "gitlab", data
assert data.get("notify", {}).get("slack_enabled") is True, data
assert "projects" in data and len(data["projects"]) == 2, data
PY

echo "OK setup-fresh-new-fields"
