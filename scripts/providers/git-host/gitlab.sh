#!/usr/bin/env bash
# GitLab git-host provider. Sourced by scripts/core/lib.sh; do not execute directly.

orch_git_host_provider_require_cli() {
    command -v glab >/dev/null 2>&1 || { echo "ERROR: glab CLI 필요" >&2; return 2; }
}

orch_git_host_provider_pr_state_raw() {
    local pr="$1" project_path="${2:-.}"
    command -v glab >/dev/null 2>&1 || return 2
    # glab mr view 는 --output json 옵션이 없음 (glab 1.36+). REST API 직접 호출.
    cd "$project_path" 2>/dev/null && glab api "projects/:fullpath/merge_requests/$pr" 2>/dev/null | jq -r '.state // ""' 2>/dev/null || true
}

orch_git_host_provider_pr_merged_by_branch() {
    local branch="$1" project_path="${2:-.}" encoded_branch count
    command -v glab >/dev/null 2>&1 || return 2
    # branch 에 #, +, @, . 등 자연 키가 포함될 수 있으므로 URL-encode 필수.
    encoded_branch="$(printf '%s' "$branch" | jq -sRr @uri 2>/dev/null || printf '%s' "$branch")"
    count="$(cd "$project_path" 2>/dev/null && glab api "projects/:fullpath/merge_requests?state=merged&source_branch=$encoded_branch&per_page=1" 2>/dev/null | jq 'length' 2>/dev/null || true)"
    [ "${count:-0}" -gt 0 ]
}

orch_git_host_provider_pr_create_cmd() {
    printf 'glab mr create --target-branch "$base" --title "$title" --description "$body"'
}

orch_git_host_provider_pr_view_json_cmd() {
    printf 'glab api "projects/:fullpath/merge_requests/$pr" | jq "{title, body: .description, headRefName: .source_branch, baseRefName: .target_branch}"'
}

orch_git_host_provider_pr_diff_cmd() {
    printf 'glab mr diff "$pr"'
}

orch_git_host_provider_pr_comment_from_file_cmd() {
    printf 'glab mr note "$pr" --message "$(cat "$body_file")"'
}

orch_git_host_provider_pr_checks_watch_cmd() {
    printf 'glab ci status --live'
}

orch_git_host_provider_pr_run_log_failed_cmd() {
    printf 'glab api "projects/:fullpath/pipelines/$pipeline_id/jobs?scope[]=failed" | jq -r ".[] | .id" | head -1 | xargs -I{} glab api "projects/:fullpath/jobs/{}/trace" | head -200'
}
