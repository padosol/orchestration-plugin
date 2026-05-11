#!/usr/bin/env bash
# Regression guard: issue-up.sh leader first_msg 안에 phase plan 관련 키워드가 빠지지 않게.
# first_msg 내용을 텍스트 검사로만 확인 (실제 tmux/claude spawn 없이).

set -euo pipefail

src="$PLUGIN_ROOT/scripts/issue-up.sh"
[ -f "$src" ] || { echo "FAIL: $src not found"; exit 1; }

required_phrases=(
    "[Phase Plan"
    "phases.md"
    "[phase-plan"
    "Phase 1"
    "phase plan 사용자 컨펌 전 워커 spawn 금지"
    "Worker→Leader 차단 질문"
)

content="$(cat "$src")"
missing=()
for phrase in "${required_phrases[@]}"; do
    if ! grep -qF "$phrase" <<<"$content"; then
        missing+=("$phrase")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: issue-up.sh first_msg 에 다음 필수 문구 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

echo "OK issue-up-first-msg-has-phase-plan"
