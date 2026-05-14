#!/usr/bin/env bash
# issue-up.sh / review-spawn.sh — 지원 트래커 (linear / github / gitlab) 모두
# 자동 fetch 분기를 가지는지 회귀 가드.
#
# linear: mcp__linear-server__get_issue
# github: gh issue view
# gitlab: glab issue view

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
src_rev="$PLUGIN_ROOT/scripts/issues/review-spawn.sh"
provider_dir="$PLUGIN_ROOT/scripts/providers/issue-tracker"
[ -f "$src_up" ] || { echo "FAIL: $src_up 없음"; exit 1; }
[ -f "$src_rev" ] || { echo "FAIL: $src_rev 없음"; exit 1; }

check_branch_in() {
    local file="$1" case_label="$2" fetch_cmd="$3"
    if ! grep -q "${fetch_cmd}" "$file"; then
        echo "FAIL: $file 에 '${fetch_cmd}' 호출 없음" >&2; exit 1
    fi
}

# issue-up.sh / review-spawn.sh 는 issue-tracker provider helper 만 호출
grep -q 'orch_issue_fetch_step' "$src_up" || { echo "FAIL: issue-up.sh 가 orch_issue_fetch_step 호출 누락" >&2; exit 1; }
grep -q 'orch_issue_lookup_line' "$src_rev" || { echo "FAIL: review-spawn.sh 가 orch_issue_lookup_line 호출 누락" >&2; exit 1; }

# provider — 지원 트래커 모두 자동 fetch
check_branch_in "$provider_dir/linear.sh" "linear" "mcp__linear-server__get_issue"
check_branch_in "$provider_dir/github.sh" "github" "gh issue view"
check_branch_in "$provider_dir/gitlab.sh" "gitlab" "glab issue view"

# Jira 지원 제거: stale jira branch / 합쳐진 'jira|gitlab' 잔존 금지
for f in "$src_up" "$src_rev" "$provider_dir"/*.sh; do
    if grep -q 'jira)' "$f" || grep -q 'jira issue' "$f"; then
        echo "FAIL: $f 에 제거된 jira 트래커 분기 잔존" >&2; exit 1
    fi
    if grep -q 'jira|gitlab' "$f"; then
        echo "FAIL: $f 에 합쳐진 'jira|gitlab' case 잔존" >&2; exit 1
    fi
done

echo "OK issue-up-gitlab-fetch"
