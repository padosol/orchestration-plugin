#!/usr/bin/env bash
# Regression guard: issue-up.sh leader first_msg 는 SKILL 통합 이후
# (a) 동적 컨텍스트 변수, (b) explicit skill trigger + SKILL.md fallback,
# (c) hard guard (GO 전 spawn 금지 / leader 직접 사용자 확인) 만 검사.
# Phase 1 템플릿 본문, wait-reply 패턴 상세 등은 SKILL.md 검사 (별도 가드) 로 이동.

set -euo pipefail

src="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
[ -f "$src" ] || { echo "FAIL: $src not found"; exit 1; }

required_phrases=(
    # explicit skill trigger
    "orch-leader"
    # fallback Read 안내 (Skill 도구 로드 실패 시 SKILL.md 1회 Read)
    "skills/orch-leader/SKILL.md"
    # hard guard — leader 직접 사용자 확인
    "AskUserQuestion"
    # hard guard — 사용자 GO 받기 전 PM 포함 워커 spawn 금지
    "PM 포함 어떤 워커도 spawn 금지"
    # hard guard — 사용자 컨펌 라벨
    "[plan-confirm] GO"
    # hard guard — 복잡 이슈 Round 2 GO (approved_task_graph 승인) 전 developer/reviewer/integration spawn 금지
    "Round 2 GO"
    "approved_task_graph"
    # hard guard — PR workflow step 순서 invariant (review LGTM 전 wait_merge 금지)
    "review LGTM 전 wait_merge"
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
