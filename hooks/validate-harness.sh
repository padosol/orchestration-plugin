#!/usr/bin/env bash
# SessionStart hook — orch settings.json 의 필수 키 누락을 사용자에게 systemMessage 배너로 알림.
#
# 설계 메모:
#   - hookSpecificOutput.additionalContext 도 같이 출력해 봤으나 (PAD-56) Claude 가 능동 행동을
#     trigger 하지 않음. 실제 보강은 `/orch:setup --update` 의 Claude-side 절차가 담당 (PAD-57).
#   - 따라서 이 hook 은 **알림 전용** — 사용자가 fix 명령을 알아채도록 systemMessage 만 출력.
#   - 누락 없음 → silent. 비-orch 환경 → no-op.

set -u

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    exit 0
fi

LIB_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
[ -f "$LIB_PATH" ] || exit 0
# shellcheck source=/dev/null
source "$LIB_PATH"

orch_settings_exists || exit 0

missing="$(jq -r '
    .projects // {} | to_entries[]
    | select((.value.default_base_branch // "") == "")
    | .key
' "$ORCH_SETTINGS" 2>/dev/null)"

[ -n "$missing" ] || exit 0

aliases=()
while IFS= read -r alias; do
    [ -n "$alias" ] || continue
    aliases+=("$alias")
done <<<"$missing"

banner="🔧 orch settings.json: default_base_branch 누락 alias [${aliases[*]}] — '/orch:setup --update' 실행해 채우세요."

BANNER="$banner" python3 <<'PY'
import json, os
print(json.dumps({"systemMessage": os.environ["BANNER"]}, ensure_ascii=False))
PY

exit 0
