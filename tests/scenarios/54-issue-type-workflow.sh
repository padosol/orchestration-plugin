#!/usr/bin/env bash
# 타입별 워크플로우 (feature/bug/refactor) 회귀 가드.
#
# - references/workflows/{feature,bug,refactor}.md 세 파일 존재
# - 각 파일에 'Phase 템플릿' + 'Review 체크리스트' 절 존재
# - issue-up.sh 가 리더에게 작업 타입 판별 + 가이드 read + .orch/runs/<id>/type 기록을 지시
# - review-spawn.sh 가 .orch/runs/<id>/type 을 읽고 reviewer 에게 가이드 적용을 지시

set -euo pipefail

workflows_dir="$PLUGIN_ROOT/references/workflows"
for t in feature bug refactor; do
    f="${workflows_dir}/${t}.md"
    [ -f "$f" ] || { echo "FAIL: ${f} 없음" >&2; exit 1; }
    if ! grep -q '## Phase 템플릿' "$f"; then
        echo "FAIL: ${f} 에 'Phase 템플릿' 섹션 없음" >&2; exit 1
    fi
    if ! grep -q '## Review 체크리스트' "$f"; then
        echo "FAIL: ${f} 에 'Review 체크리스트' 섹션 없음" >&2; exit 1
    fi
done

src_up="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
src_rev="$PLUGIN_ROOT/scripts/issues/review-spawn.sh"
skill_leader="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"
[ -f "$skill_leader" ] || { echo "FAIL: $skill_leader 없음" >&2; exit 1; }

# SKILL 통합 후: first_msg = workflows_dir 변수 주입 + AskUserQuestion hard guard.
# 절차 본문 ('작업 타입 판별' / 'runs/<mp_id>/type' 기록) 은 orch-leader SKILL 에서 검사.
grep -q 'references/workflows' "$src_up" || { echo "FAIL: issue-up.sh 가 references/workflows 경로를 가이드로 안 줌" >&2; exit 1; }
grep -q 'AskUserQuestion' "$src_up" || { echo "FAIL: issue-up.sh 에 AskUserQuestion hard guard 안내 없음" >&2; exit 1; }

grep -q '작업 타입 판별' "$skill_leader" || { echo "FAIL: orch-leader SKILL 에 '작업 타입 판별' 섹션 없음" >&2; exit 1; }
grep -q "runs/<mp_id>/type" "$skill_leader" || { echo "FAIL: orch-leader SKILL 에 .orch/runs/<id>/type 기록 안내 없음" >&2; exit 1; }
grep -q 'references/workflows' "$skill_leader" || { echo "FAIL: orch-leader SKILL 이 references/workflows 경로를 가이드로 안 줌" >&2; exit 1; }

# review-spawn.sh — type 파일 read + 가이드 안내
grep -q "scope_dir_review" "$src_rev" || { echo "FAIL: review-spawn.sh 에 scope_dir/type 읽기 로직 없음" >&2; exit 1; }
grep -q 'workflow_review_line' "$src_rev" || { echo "FAIL: review-spawn.sh 에 workflow_review_line 주입 없음" >&2; exit 1; }
grep -q 'references/workflows' "$src_rev" || { echo "FAIL: review-spawn.sh 가 references/workflows 경로 안 줌" >&2; exit 1; }

# 세 타입 모두 case 에 등장해야 — 미기록 fallback 만 있고 정상 분기 누락된 회귀 차단
for t in feature bug refactor; do
    if ! grep -q "${t}" "$src_rev"; then
        echo "FAIL: review-spawn.sh 에 타입 '${t}' 분기 안 보임" >&2; exit 1
    fi
done

echo "OK issue-type-workflow"
