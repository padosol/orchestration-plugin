#!/usr/bin/env bash
# Regression guard: leader-spawn.sh 의 PM / developer first_msg 는
# SKILL 통합 이후 (a) explicit skill trigger + SKILL.md fallback,
# (b) role 별 hard guard (PM direction-check 차단 / developer escalate 차단)
# 만 검사. wait-reply.sh 사용 패턴 상세는 SKILL/orch-protocols.md 가드로 이동.

set -euo pipefail

src="$PLUGIN_ROOT/scripts/leader-spawn.sh"
[ -f "$src" ] || { echo "FAIL: $src not found"; exit 1; }

content="$(cat "$src")"

required_phrases=(
    # PM role — skill trigger + fallback path
    "orch-pm"
    "skills/orch-pm/SKILL.md"
    # PM hard guard — direction-check
    "direction-check"
    # PM hard guard — finalize/commit/push 금지 (사용자 컨펌 없이)
    "사용자 컨펌 없이"

    # developer role — skill trigger + fallback path
    "orch-developer-worker"
    "skills/orch-developer-worker/SKILL.md"
    # developer hard guard — 추측 진행 금지 / leader escalate
    "추측 진행"
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
