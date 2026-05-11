#!/usr/bin/env bash
# PAD-61: REPORT 작성 책임 = leader. orch 자동 호출 금지. 후속 이슈는 leader 가
# 후보만 도출 → orch 인박스로 송신 → orch 가 사용자 검토 후 등록.
#
# 검증:
# - commands/issue-up.md: 마무리 책무 분리 절 + leader/orch 책무 + orch 자동 호출 금지
# - commands/issue-down.md: REPORT 는 leader phase 마지막 + orch 자동 호출 금지
# - commands/report.md: 호출 주체 절 + errors_check / ai_ready_check 후보 송신 (자동 등록 X)
# - commands/check-inbox.md: [follow-up-candidates] 라벨 처리 절차
# - scripts/issue-up.sh first_msg: PR-4 종료 단계에 follow-up-candidates 송신 단계
# - scripts/issue-down.sh: REPORT.html 존재/부재 분기 어휘 명확
# - references/workflows/{feature,bug,refactor}.md: 마무리 phase 추가

set -euo pipefail

up_md="$PLUGIN_ROOT/commands/issue-up.md"
down_md="$PLUGIN_ROOT/commands/issue-down.md"
report_md="$PLUGIN_ROOT/commands/report.md"
inbox_md="$PLUGIN_ROOT/commands/check-inbox.md"
up_sh="$PLUGIN_ROOT/scripts/issue-up.sh"
down_sh="$PLUGIN_ROOT/scripts/issue-down.sh"
wf_feature="$PLUGIN_ROOT/references/workflows/feature.md"
wf_bug="$PLUGIN_ROOT/references/workflows/bug.md"
wf_refactor="$PLUGIN_ROOT/references/workflows/refactor.md"

for f in "$up_md" "$down_md" "$report_md" "$inbox_md" "$up_sh" "$down_sh" \
         "$wf_feature" "$wf_bug" "$wf_refactor"; do
    [ -f "$f" ] || { echo "FAIL: $f 없음" >&2; exit 1; }
done

# 1. commands/issue-up.md — 책무 분리 절
for token in '책무 분리' 'leader 책무' 'orch 책무' 'follow-up-candidates' 'orch 가 `/orch:report` 자동 호출'; do
    if ! grep -qF "$token" "$up_md"; then
        echo "FAIL: issue-up.md 에 '${token}' 없음" >&2; exit 1
    fi
done

# 2. commands/issue-down.md — leader 책임 + orch 자동 호출 금지
for token in 'leader 가 phase 마지막 단계' 'orch 자동 호출 금지'; do
    if ! grep -qF "$token" "$down_md"; then
        echo "FAIL: issue-down.md 에 '${token}' 없음" >&2; exit 1
    fi
done
# 0.15.x 옛 어휘는 제거됐어야 함
if grep -qF 'REPORT.html 자동 작성 요청' "$down_md"; then
    echo "FAIL: issue-down.md 에 옛 어휘 'REPORT.html 자동 작성 요청' 잔존" >&2; exit 1
fi

# 3. commands/report.md — 호출 주체 절 + errors_check/ai_ready_check 후보 송신
for token in '호출 주체' 'leader 가 호출' 'follow-up-candidates' '직접 트래커 등록' 'orch 가 사용자와' 'orch 인박스로 후보 송신'; do
    if ! grep -qF "$token" "$report_md"; then
        echo "FAIL: report.md 에 '${token}' 없음" >&2; exit 1
    fi
done
# 옛 "자동 호출" 절 제목과 옛 "후속 이슈 자동 생성" 어휘는 사라졌어야 함
if grep -qE '^\*\*자동 호출\*\*:' "$report_md"; then
    echo "FAIL: report.md 의 옛 '**자동 호출**:' 헤더 잔존" >&2; exit 1
fi
if grep -qF '후속 이슈 자동 생성' "$report_md"; then
    echo "FAIL: report.md 에 옛 '후속 이슈 자동 생성' 어휘 잔존" >&2; exit 1
fi

# 4. commands/check-inbox.md — follow-up-candidates 라벨 처리 절차
for token in '[follow-up-candidates' '등록 결정' 'errors_check' 'ai_ready_check' '사용자 정책'; do
    if ! grep -qF "$token" "$inbox_md"; then
        echo "FAIL: check-inbox.md 에 '${token}' 없음" >&2; exit 1
    fi
done

# 5. scripts/issue-up.sh first_msg — PR-4 종료 단계에 follow-up-candidates 송신
for token in 'follow-up-candidates' 'errors_check'; do
    if ! grep -qF "$token" "$up_sh"; then
        echo "FAIL: issue-up.sh first_msg 에 '${token}' 없음" >&2; exit 1
    fi
done

# 6. scripts/issue-down.sh — REPORT.html 존재/부재 분기 명확
if ! grep -qF 'REPORT.html 누락' "$down_sh"; then
    echo "FAIL: issue-down.sh 에 'REPORT.html 누락' 분기 안내 없음" >&2; exit 1
fi
if ! grep -qF 'orch 자동 호출 X' "$down_sh"; then
    echo "FAIL: issue-down.sh inbox 메시지에 'orch 자동 호출 X' 명시 없음" >&2; exit 1
fi

# 7. references/workflows/*.md 마지막 phase — '마무리' + /orch:report + /orch:issue-down
for wf in "$wf_feature" "$wf_bug" "$wf_refactor"; do
    for token in '마무리' '/orch:report' '/orch:issue-down' 'follow-up-candidates'; do
        if ! grep -qF "$token" "$wf"; then
            echo "FAIL: $(basename "$wf") 에 '${token}' 없음" >&2; exit 1
        fi
    done
done

echo "OK report-owner-leader"
