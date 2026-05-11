#!/usr/bin/env bash
# Regression guard: leader-spawn.sh worker / PM first_msg 안에 wait-reply 차단 패턴이 포함되어 있는지.

set -euo pipefail

src="$PLUGIN_ROOT/scripts/leader-spawn.sh"
[ -f "$src" ] || { echo "FAIL: $src not found"; exit 1; }

content="$(cat "$src")"

required_phrases=(
    "wait-reply.sh"
    "[question:"
    "[reply:"
    "차단"
    "Direction Check"
)

missing=()
for phrase in "${required_phrases[@]}"; do
    if ! grep -qF "$phrase" <<<"$content"; then
        missing+=("$phrase")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: leader-spawn.sh first_msg 에 다음 필수 문구 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

echo "OK leader-spawn-first-msg-has-wait-reply"
