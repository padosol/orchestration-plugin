#!/usr/bin/env bash
# Regression guard: references/orch-protocols.md 가 모든 워커 SKILL 의 공통 운영 규약
# (HOLD 체크포인트 / wait-reply qid / hub-and-spoke / PR 4단계 / shutdown) 단일 source
# 역할을 유지해야 한다. SKILL 들은 이 문서를 가리키기만 함.

set -euo pipefail

doc="$PLUGIN_ROOT/references/orch-protocols.md"
[ -f "$doc" ] || { echo "FAIL: $doc 없음" >&2; exit 1; }

required=(
    "HOLD"
    "wait-reply.sh"
    "[question:"
    "[reply:"
    "hub-and-spoke"
    "/orch:send"
    "PR 4단계"
    "wait-merge.sh"
    "worker-shutdown.sh"
    "/compact"
)
missing=()
for phrase in "${required[@]}"; do
    if ! grep -qF "$phrase" "$doc"; then
        missing+=("$phrase")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: orch-protocols.md 단일 source 에 다음 항목 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

# qid 생성 패턴 — q-$(date +%s)-$RANDOM
if ! grep -qE 'q-\$\(date' "$doc"; then
    echo "FAIL: orch-protocols.md 에 qid 생성 패턴 (q-\$(date +%s)-\$RANDOM) 안내 없음" >&2
    exit 1
fi

# PR 4단계가 4개 단계 모두 명시 (CI / 리뷰 / 머지 대기 / 자기 종료)
for stage in "CI" "리뷰" "머지 대기" "종료"; do
    if ! grep -qF "$stage" "$doc"; then
        echo "FAIL: orch-protocols.md 의 PR 4단계 중 '$stage' 단계 누락" >&2
        exit 1
    fi
done

echo "OK orch-protocols-single-source"
