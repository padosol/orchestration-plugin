#!/usr/bin/env bash
# setup.sh --update — legacy 0.11.0 이하 settings.json (root default_base_branch + nested override)
# 을 업그레이드하면 root 는 제거되고 nested 는 보존되는지 검증 (0.12.0).

set -euo pipefail

ws="$SANDBOX/setup-update-drops-root"
mkdir -p "$ws/repo-a/.orch"
git -C "$ws/repo-a" init -q
git -C "$ws/repo-a" checkout -q -b main
echo "x" > "$ws/repo-a/a.txt"
git -C "$ws/repo-a" add . && git -C "$ws/repo-a" -c user.email=a@b -c user.name=t commit -qm init
mkdir -p "$ws/.orch"

jq -n \
    --arg base "$ws" \
    --arg repo_path "$ws/repo-a" \
    '{
      version: 1,
      base_dir: $base,
      default_base_branch: "develop",
      issue_tracker: "linear",
      team: "Core",
      custom_flag: true,
      providers: { issue_tracker: { custom: "keep" } },
      projects: {
        "repo-a": {
          path: $repo_path,
          kind: "shared-library",
          default_base_branch: "main",
          description: "legacy entry"
        }
      }
    }' > "$ws/.orch/settings.json"

ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/config/setup.sh" --update >/dev/null

python3 - "$ws/.orch/settings.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert "default_base_branch" not in data, f"root default_base_branch 잔존: {data!r}"
assert data["projects"]["repo-a"].get("default_base_branch") == "main", data["projects"]["repo-a"]
assert data["projects"]["repo-a"].get("description") == "legacy entry", "description 손실됨"
# 신규 필드는 디폴트로 채워져야 함
assert data.get("git_host") == "none", data
assert data.get("notify", {}).get("slack_enabled") is False, data
assert data.get("issue_tracker") == "linear", data
assert data.get("team") == "Core", data
assert data.get("custom_flag") is True, data
assert data.get("providers", {}).get("issue_tracker", {}).get("custom") == "keep", data
PY

echo "OK setup-update-drops-root-base"
