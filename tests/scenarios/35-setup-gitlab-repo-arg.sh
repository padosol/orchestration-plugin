#!/usr/bin/env bash
# setup.sh — GitLab issue tracker 도 --github-repo group/project 를 settings 에 보존한다.

set -euo pipefail

ws="$SANDBOX/setup-gitlab-repo-arg"
mkdir -p "$ws/repo-a"
git -C "$ws/repo-a" init -q
git -C "$ws/repo-a" checkout -q -b main
echo "x" > "$ws/repo-a/a.txt"
git -C "$ws/repo-a" add .
git -C "$ws/repo-a" -c user.email=a@b -c user.name=t commit -qm init

ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/config/setup.sh" \
    --issue-tracker gitlab --github-repo group/project --git-host gitlab --notify off >/dev/null

python3 - "$ws/.orch/settings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data.get("issue_tracker") == "gitlab", data
assert data.get("github_issue_repo") == "group/project", data
PY

ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/config/setup.sh" \
    --update --github-repo other/project >/dev/null

python3 - "$ws/.orch/settings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data.get("issue_tracker") == "gitlab", data
assert data.get("github_issue_repo") == "other/project", data
PY

echo "OK setup-gitlab-repo-arg"
