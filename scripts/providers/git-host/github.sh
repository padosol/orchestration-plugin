#!/usr/bin/env bash
# GitHub git-host provider. Sourced by scripts/core/lib.sh; do not execute directly.

orch_git_host_provider_require_cli() {
    command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI 필요" >&2; return 2; }
}

orch_git_host_provider_pr_state_raw() {
    local pr="$1" project_path="${2:-.}"
    command -v gh >/dev/null 2>&1 || return 2
    cd "$project_path" 2>/dev/null && gh pr view "$pr" --json state -q .state 2>/dev/null || true
}

orch_git_host_provider_pr_merged_by_branch() {
    local branch="$1" project_path="${2:-.}" count
    command -v gh >/dev/null 2>&1 || return 2
    count="$(cd "$project_path" 2>/dev/null && gh pr list --state merged --head "$branch" --limit 1 --json number --jq 'length' 2>/dev/null || true)"
    [ "${count:-0}" -gt 0 ]
}

orch_git_host_provider_pr_create_cmd() {
    printf 'gh pr create --base "$base" --title "$title" --body "$body"'
}

orch_git_host_provider_pr_view_json_cmd() {
    printf 'gh pr view "$pr" --json title,body,headRefName,baseRefName'
}

orch_git_host_provider_pr_diff_cmd() {
    printf 'gh pr diff "$pr"'
}

orch_git_host_provider_pr_comment_from_file_cmd() {
    printf 'gh pr comment "$pr" --body-file "$body_file"'
}

orch_git_host_provider_pr_checks_watch_cmd() {
    printf 'gh pr checks "$pr" --watch --required'
}

orch_git_host_provider_pr_run_log_failed_cmd() {
    printf 'gh run view "$run_id" --log-failed | head -200'
}
