#!/usr/bin/env bash
# Regression guard: leader 가 읽는 보조 문서들 (references/workflows/*.md, README.md)
# 이 핵심 정책과 충돌하지 않아야 한다.
#
# 핵심 정책:
#   (a) 사용자 [plan-confirm] GO 전에는 PM 포함 어떤 워커도 spawn 금지.
#       PM 이 필요하면 phase plan 의 'Phase 0: 분석/설계' 또는 첫 phase 로 명시 후 GO 받고 spawn.
#   (b) 작업 타입 모호 시 leader 가 직접 AskUserQuestion 호출 금지 — orch 경유:
#       [type-clarify:<qid>] 송신 → orch AskUserQuestion → [type-decision:<qid>] 회신.
#
# leader first_msg (scripts/issue-up.sh) 가 이미 워크플로우 .md / README 를 읽도록
# 안내하므로, 그 문서들에 옛 충돌 문구가 남아 있으면 사용자 GO 전 PM spawn / leader
# 직접 AskUserQuestion 같은 재발이 일어난다.

set -euo pipefail

workflows_dir="$PLUGIN_ROOT/references/workflows"
readme="$PLUGIN_ROOT/README.md"

[ -d "$workflows_dir" ] || { echo "FAIL: $workflows_dir 없음" >&2; exit 1; }
[ -f "$readme" ] || { echo "FAIL: $readme 없음" >&2; exit 1; }

forbid_in_file() {
    local file="$1" pattern="$2" reason="$3"
    if grep -qE "$pattern" "$file"; then
        echo "FAIL: $file 에 정책 충돌 문구 잔존 (${reason})" >&2
        grep -nE "$pattern" "$file" >&2 || true
        exit 1
    fi
}

# 1. 워크플로우 문서 — 'PM 워커 spawn 해 ... 부터 받고 사용자 컨펌' 식의 GO 전 PM spawn 권유 금지
for f in "$workflows_dir"/{feature,bug,refactor}.md; do
    [ -f "$f" ] || { echo "FAIL: $f 없음" >&2; exit 1; }
    forbid_in_file "$f" 'PM 워커 spawn 해 .* 받고 사용자 컨펌' "GO 전 PM spawn 권유 — 새 정책과 충돌"
    forbid_in_file "$f" '큰 기능이면 PM 워커 spawn' "GO 전 PM spawn 권유 — 새 정책과 충돌"
done

# 2. feature.md 는 PM 필요 시 'Phase 0' / '분석/설계' 흐름을 명시해야 (긍정 가드)
fmd="$workflows_dir/feature.md"
if ! grep -qE 'Phase 0.*분석/설계|분석/설계.*Phase 0|\[plan-confirm\] GO' "$fmd"; then
    echo "FAIL: $fmd 에 'Phase 0 분석/설계 → GO 후 PM spawn' 흐름 안내 없음" >&2
    exit 1
fi
if ! grep -q 'GO 전 PM 포함 어떤 워커도 spawn 금지' "$fmd"; then
    echo "FAIL: $fmd 에 'GO 전 PM 포함 어떤 워커도 spawn 금지' 명시 없음" >&2
    exit 1
fi

# 3. 워크플로우 문서 — leader 가 직접 AskUserQuestion 호출하라는 권유 금지.
#    'leader 직접 AskUserQuestion' 또는 '여기서 AskUserQuestion' 같은 표현은 모호하므로
#    AskUserQuestion 이 나오면 같은 줄·근처에 'orch escalate' / 'orch 경유' / '호출 금지'
#    같은 안전 토큰이 있어야 한다.
for f in "$workflows_dir"/{feature,bug,refactor}.md; do
    while IFS= read -r line; do
        if grep -qE 'orch (escalate|경유)|호출 금지|leader 직접 .*금지' <<<"$line"; then
            continue
        fi
        echo "FAIL: $f 의 AskUserQuestion 언급이 'orch 경유' / '직접 호출 금지' 안전 토큰 없이 등장:" >&2
        echo "  > $line" >&2
        exit 1
    done < <(grep -n AskUserQuestion "$f" || true)
done

# 4. README 의 타입 판별 절차 — orch 경유 표현으로 정정됐는지
if ! grep -q 'type-clarify:' "$readme"; then
    echo "FAIL: README.md 에 '[type-clarify:<qid>]' 흐름 안내 없음 — 옛 'AskUserQuestion 직접' 문구일 가능성" >&2
    exit 1
fi
if ! grep -q 'type-decision:' "$readme"; then
    echo "FAIL: README.md 에 '[type-decision:<qid>]' 회신 라벨 안내 없음" >&2
    exit 1
fi
if ! grep -q '직접 .*AskUserQuestion.*위반\|leader 가 직접 .*AskUserQuestion' "$readme"; then
    echo "FAIL: README.md 에 'leader 직접 AskUserQuestion = 허브 위반' 명시 없음" >&2
    exit 1
fi

echo "OK docs-pm-spawn-policy-consistency"
