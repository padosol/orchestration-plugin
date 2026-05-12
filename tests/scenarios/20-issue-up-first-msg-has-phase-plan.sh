#!/usr/bin/env bash
# Regression guard: issue-up.sh leader first_msg 는 SKILL 통합 이후
# (a) 동적 컨텍스트 변수, (b) explicit skill trigger + SKILL.md fallback,
# (c) hard guard (GO 전 spawn 금지 / type-clarify qid / phase-plan 라벨) 만 검사.
# Phase 1 템플릿 본문, wait-reply 패턴 상세 등은 SKILL.md 검사 (별도 가드) 로 이동.

set -euo pipefail

src="$PLUGIN_ROOT/scripts/issue-up.sh"
[ -f "$src" ] || { echo "FAIL: $src not found"; exit 1; }

required_phrases=(
    # explicit skill trigger
    "orch-leader"
    # fallback Read 안내 (Skill 도구 로드 실패 시 SKILL.md 1회 Read)
    "skills/orch-leader/SKILL.md"
    # hard guard 라벨 (orch 에 phase plan 송신 트리거)
    "[phase-plan"
    # hard guard — 사용자 GO 받기 전 PM 포함 워커 spawn 금지
    "PM 포함 어떤 워커도 spawn 금지"
    # hard guard — orch 컨펌 라벨
    "[plan-confirm] GO"
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
