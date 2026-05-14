#!/usr/bin/env bash
# Linear issue-tracker provider. Sourced by scripts/core/lib.sh; do not execute directly.

orch_issue_tracker_provider_fetch_step() {
    local issue_display="$1"
    printf '1. mcp__linear-server__get_issue %s (description / acceptance criteria). 실패(이슈 없음) 시 SKILL §1 fuzzy fallback — list_issues 로 후보 search → leader 가 사용자에게 직접 질문.' "$issue_display"
}

orch_issue_tracker_provider_lookup_line() {
    local issue_display="$1"
    printf -- '- 이슈 컨텍스트: mcp__linear-server__get_issue %s' "$issue_display"
}
