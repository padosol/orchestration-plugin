#!/usr/bin/env bash
# issue-up.sh / review-spawn.sh — 네 트래커 (linear / github / gitlab / jira) 모두
# 자동 fetch 분기를 가지는지 회귀 가드.
#
# linear: mcp__linear-server__get_issue
# github: gh issue view
# gitlab: glab issue view
# jira:   jira issue view  (ankitpokhrel/jira-cli)

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issue-up.sh"
src_rev="$PLUGIN_ROOT/scripts/review-spawn.sh"
[ -f "$src_up" ] || { echo "FAIL: $src_up 없음"; exit 1; }
[ -f "$src_rev" ] || { echo "FAIL: $src_rev 없음"; exit 1; }

check_branch_in() {
    local file="$1" case_label="$2" fetch_cmd="$3"
    if ! grep -q "${case_label})" "$file"; then
        echo "FAIL: $file 에 '${case_label})' case 없음" >&2; exit 1
    fi
    if ! grep -q "${fetch_cmd}" "$file"; then
        echo "FAIL: $file 의 ${case_label} 분기에 '${fetch_cmd}' 호출 없음" >&2; exit 1
    fi
}

# issue-up.sh — 네 트래커 모두 자동 fetch
check_branch_in "$src_up" "linear" "mcp__linear-server__get_issue"
check_branch_in "$src_up" "github" "gh issue view"
check_branch_in "$src_up" "gitlab" "glab issue view"
check_branch_in "$src_up" "jira"   "jira issue view"

# review-spawn.sh — 동일
check_branch_in "$src_rev" "linear" "mcp__linear-server__get_issue"
check_branch_in "$src_rev" "github" "gh issue view"
check_branch_in "$src_rev" "gitlab" "glab issue view"
check_branch_in "$src_rev" "jira"   "jira issue view"

# 옛 합쳐진 'jira|gitlab' 잔존 금지 — 분리되어야 각자 다른 CLI 호출 가능
for f in "$src_up" "$src_rev"; do
    if grep -q 'jira|gitlab' "$f"; then
        echo "FAIL: $f 에 합쳐진 'jira|gitlab' case 잔존" >&2; exit 1
    fi
done

echo "OK issue-up-gitlab-fetch"
