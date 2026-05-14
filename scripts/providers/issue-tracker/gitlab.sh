#!/usr/bin/env bash
# GitLab issue-tracker provider. Sourced by scripts/core/lib.sh; do not execute directly.

orch_issue_tracker_gitlab_issue_num() {
    printf '%s' "$1" | grep -Eo '[0-9]+' | head -1 || true
}

orch_issue_tracker_provider_fetch_step() {
    local issue_display="$1" gh_repo="${2:-}" gl_issue_num
    gl_issue_num="$(orch_issue_tracker_gitlab_issue_num "$issue_display")"
    if [ -n "$gh_repo" ]; then
        # github_issue_repo 가 gitlab 환경에서는 group/project 로 재해석됨.
        printf "1. \`glab issue view '%s' --repo '%s'\` (text — title / labels / milestone). 실패(이슈 없음 / 미인증) 시 SKILL §1 fuzzy fallback — \`glab issue list --repo '%s' --search '%s'\` 로 후보 → leader 가 사용자에게 직접 질문. glab 미설치 시 사용자에게 spec 직접 확인." "${gl_issue_num:-$issue_display}" "$gh_repo" "$gh_repo" "$issue_display"
    else
        printf "1. \`glab issue view '%s'\` (현재 cwd 의 project 기준 — settings.json 의 github_issue_repo 미설정). 실패 시 SKILL §1 fuzzy fallback — \`glab issue list --search '%s'\` 로 후보 → leader 가 사용자에게 직접 질문. glab 미설치 시 사용자에게 spec 직접 확인." "${gl_issue_num:-$issue_display}" "$issue_display"
    fi
}

orch_issue_tracker_provider_lookup_line() {
    local issue_display="$1" gh_repo="${2:-}" gl_issue_num
    gl_issue_num="$(orch_issue_tracker_gitlab_issue_num "$issue_display")"
    if [ -n "$gh_repo" ]; then
        printf -- '- 이슈 컨텍스트: glab issue view %s --repo %s (glab 미설치/미인증 시 PR description 으로 판단)' "${gl_issue_num:-$issue_display}" "$gh_repo"
    else
        printf -- '- 이슈 컨텍스트: glab issue view %s (현재 project 기준; glab 미설치/미인증 시 PR description 으로 판단)' "${gl_issue_num:-$issue_display}"
    fi
}
