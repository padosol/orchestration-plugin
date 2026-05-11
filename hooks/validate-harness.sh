#!/usr/bin/env bash
# SessionStart hook — orch 워크스페이스의 settings.json 이 orch 하네스가 요구하는
# 필수 키를 갖추고 있는지 검증. 누락 시 안내 + exit 1 로 세션 차단.
#
# 동작 조건:
#   - ORCH_ROOT/.orch/settings.json 이 발견되어야 함 (없으면 no-op — 비 orch 환경)
#
# 현재 체크:
#   1. projects.<alias>.default_base_branch — **프로젝트마다 명시 필수**.
#      프로젝트마다 base 가 다르기 때문에 글로벌 fallback 에 의존하지 않는다.
#      await-merge cleanup target / leader-spawn worktree base 결정의 진실의 원천.
#
# 지속 확장 예정: issue_tracker / base_dir 정확성 / projects.<alias>.path 실재 등.
# 새 체크 추가 시 require_* 함수를 한 개 추가하고 main 흐름에서 호출.

set -u

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    exit 0
fi

LIB_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
[ -f "$LIB_PATH" ] || exit 0
# shellcheck source=/dev/null
source "$LIB_PATH"

# orch settings 가 없으면 비 orch 환경 — 검증 skip.
orch_settings_exists || exit 0

errors=()

require_project_base_branches() {
    local missing
    # projects.* 중 default_base_branch 가 null/빈 alias 만 추출.
    missing="$(jq -r '
        .projects // {} | to_entries[]
        | select((.value.default_base_branch // "") == "")
        | .key
    ' "$ORCH_SETTINGS" 2>/dev/null)"

    [ -n "$missing" ] || return 0

    errors+=("projects.<alias>.default_base_branch 누락 (프로젝트마다 명시 필수) — ${ORCH_SETTINGS}")
    while IFS= read -r alias; do
        [ -n "$alias" ] || continue
        errors+=("  - ${alias}")
    done <<<"$missing"
    errors+=(
        "  → 추가 방법: 각 alias 객체에 \"default_base_branch\": \"main\" (또는 그 프로젝트 워크플로우에 맞게) 필드를 추가하세요."
        "  → 영향: await-merge cleanup 대상 / leader-spawn worktree base 결정 불가."
    )
}

require_project_base_branches

if [ "${#errors[@]}" -gt 0 ]; then
    {
        echo "ERROR: orch 하네스 설정 검증 실패"
        for line in "${errors[@]}"; do
            echo "$line"
        done
        echo
        echo "수정 후 세션을 다시 시작하세요."
    } >&2
    exit 1
fi

exit 0
