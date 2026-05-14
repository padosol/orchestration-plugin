#!/usr/bin/env bash
# GitHub issue-tracker provider. Sourced by scripts/core/lib.sh; do not execute directly.

orch_issue_tracker_provider_fetch_step() {
    local issue_display="$1" gh_repo="${2:-}" issue_num
    issue_num="$issue_display"
    if [ -n "$gh_repo" ]; then
        printf "1. \`gh issue view '%s' --repo '%s' --json title,body,labels,milestone\` (description / acceptance criteria). 실패(이슈 없음 / 숫자 키 아님) 시 SKILL §1 fuzzy fallback — \`gh issue list --repo '%s' --search '%s'\` 로 후보 → leader 가 사용자에게 직접 질문." "$issue_num" "$gh_repo" "$gh_repo" "$issue_display"
    else
        printf "1. \`gh issue view '%s' --json title,body,labels,milestone\` (현재 cwd 의 repo 기준 — settings.json 의 github_issue_repo 미설정). 실패 시 SKILL §1 fuzzy fallback — \`gh issue list --search '%s'\` 로 후보 → leader 가 사용자에게 직접 질문." "$issue_num" "$issue_display"
    fi
}

orch_issue_tracker_provider_lookup_line() {
    local issue_display="$1" gh_repo="${2:-}" issue_num_gh=""
    if [[ "$issue_display" =~ ^[0-9]+$ ]]; then
        issue_num_gh="$issue_display"
    fi
    if [ -z "$issue_num_gh" ]; then
        printf -- "- 이슈 컨텍스트: GitHub Issues 인데 '%s' 가 전체 숫자 id 가 아님 — PR description / leader 가 보낸 spec 으로만 판단 (자유 id 의 부분 숫자를 GitHub issue 번호로 오인하지 않도록 lookup 생략)" "$issue_display"
    elif [ -n "$gh_repo" ]; then
        printf -- '- 이슈 컨텍스트: gh issue view %s --repo %s' "$issue_num_gh" "$gh_repo"
    else
        printf -- '- 이슈 컨텍스트: gh issue view %s (현재 repo 기준)' "$issue_num_gh"
    fi
}
