#!/usr/bin/env bash
# SessionStart hook — orch 워크스페이스의 settings.json 이 orch 하네스가 요구하는
# 필수 키를 갖추고 있는지 검증. 누락 발견 시 stdout 에 systemMessage JSON 을 출력해
# Claude 가 첫 응답에서 AskUserQuestion 으로 누락 값을 받아 settings.json 을 Edit 하도록 유도.
#
# 흐름:
#   - 누락 없음 → silent exit 0
#   - 누락 있음 → systemMessage(JSON) 출력 + exit 0
#                  · Claude 가 그 인스트럭션을 받아 AskUserQuestion + Edit 으로 처리
#                  · hook 은 차단(exit 1)하지 않는다 — 사용자가 Claude 응답을 받기 위해서는
#                    세션이 진행되어야 하기 때문. 인스트럭션이 "다른 작업 전 선행" 톤이라
#                    Claude 가 자동으로 우선순위를 잡는다.
#
# 비 orch 환경 (settings.json 없음) → no-op.

set -u

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    exit 0
fi

LIB_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
[ -f "$LIB_PATH" ] || exit 0
# shellcheck source=/dev/null
source "$LIB_PATH"

orch_settings_exists || exit 0

escape_json() {
    # 최소한의 JSON 문자열 이스케이프 (\\ → \\\\, " → \", 개행 → \n, 탭 → \t)
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1], end="")' 2>/dev/null \
        || printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# 누락 항목 누적. 각 require_* 는 누락 alias / 키 / 경로 등을 errors 배열에 push.
errors=()

require_project_base_branches() {
    local missing
    missing="$(jq -r '
        .projects // {} | to_entries[]
        | select((.value.default_base_branch // "") == "")
        | .key
    ' "$ORCH_SETTINGS" 2>/dev/null)"

    [ -n "$missing" ] || return 0

    local aliases=()
    while IFS= read -r alias; do
        [ -n "$alias" ] || continue
        aliases+=("$alias")
    done <<<"$missing"

    errors+=("missing.default_base_branch:${aliases[*]}")
}

require_project_base_branches

if [ "${#errors[@]}" -eq 0 ]; then
    exit 0
fi

# 누락 alias 들을 사람이 읽기 쉬운 + Claude 가 파싱하기 쉬운 형식으로 정리.
missing_aliases=""
for err in "${errors[@]}"; do
    case "$err" in
        missing.default_base_branch:*)
            missing_aliases="${err#missing.default_base_branch:}"
            ;;
    esac
done

# systemMessage 본문 — Claude 가 따라야 하는 인스트럭션.
msg="orch 하네스 설정 검증: ${ORCH_SETTINGS} 의 다음 alias 들에 default_base_branch 가 누락되었습니다 → [${missing_aliases}]. "
msg+="다른 작업을 시작하기 전에 **AskUserQuestion 도구로 각 alias 의 base branch 를 사용자에게 묻고** (옵션 예: 'main', 'develop', '기타 직접 입력') "
msg+="응답을 받아 ${ORCH_SETTINGS} 의 해당 alias 객체에 \"default_base_branch\": \"<값>\" 필드를 Edit 으로 추가하세요. "
msg+="모든 alias 가 채워진 뒤 사용자에게 '설정 완료, 작업 진행해도 됩니다' 라고 안내하고 원래 요청을 처리합니다. "
msg+="이 안내는 settings.json 검증 hook 이 자동 생성한 것이며 사용자가 직접 요청하지 않았어도 우선 처리해야 합니다."

# JSON output
printf '{"systemMessage":"%s"}\n' "$(printf '%s' "$msg" | escape_json)"
exit 0
