#!/usr/bin/env bash
# Regression guard: 작업 타입 모호 시 leader 가 직접 AskUserQuestion 을 호출하지 않고
# orch 경유 ([type-clarify:<qid>] 송신 → orch 가 AskUserQuestion → [type-decision:<qid>] 회신) 로
# 라우팅되는지 검증. SKILL 통합 후 절차 본문은 orch-leader SKILL.md 로 이동했으므로
# first_msg 에는 hard guard, SKILL 본문에는 자세한 절차로 분리해 검사.

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issue-up.sh"
skill_leader="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"
doc="$PLUGIN_ROOT/commands/check-inbox.md"

[ -f "$src_up" ]       || { echo "FAIL: $src_up 없음" >&2; exit 1; }
[ -f "$skill_leader" ] || { echo "FAIL: $skill_leader 없음" >&2; exit 1; }
[ -f "$doc" ]          || { echo "FAIL: $doc 없음" >&2; exit 1; }

# 1. first_msg hard guard — [type-clarify:<qid>] 라벨이 leader 의 명시 트리거
if ! grep -qF '[type-clarify:' "$src_up"; then
    echo "FAIL: issue-up.sh first_msg 에 '[type-clarify:<qid>' 송신 라벨 안내 없음 (correlation id hard guard)" >&2
    exit 1
fi

# 2. first_msg hard guard — leader 가 직접 AskUserQuestion 호출 금지
if ! grep -qF 'leader 가 직접 AskUserQuestion 호출 금지' "$src_up"; then
    echo "FAIL: issue-up.sh first_msg 에 'leader 가 직접 AskUserQuestion 호출 금지' hard guard 누락" >&2
    exit 1
fi

# 3. orch (check-inbox.md) 가 [type-clarify:<qid>] 처리 절차를 가져야
if ! grep -qF '[type-clarify:' "$doc"; then
    echo "FAIL: check-inbox.md 에 '[type-clarify:<qid>]' 라벨 처리 절차 없음" >&2
    exit 1
fi

# 4. orch 가 회신할 때 쓰는 [type-decision:<qid>] 라벨이 양쪽에 일관되게 등장
#    (first_msg 의 hard guard + check-inbox 절차 + orch-leader SKILL 본문)
for f in "$src_up" "$doc" "$skill_leader"; do
    if ! grep -qF '[type-decision:' "$f"; then
        echo "FAIL: $f 에 '[type-decision:<qid>]' 회신 라벨 안내 없음" >&2
        exit 1
    fi
done

# 5. orch 가 type-clarify 처리 시 AskUserQuestion TUI 를 강제하는 문구
section="$(awk '/^## 특수 라벨 처리 — `\[type-clarify/,/^---$/' "$doc")"
if [ -z "$section" ]; then
    echo "FAIL: check-inbox.md 에 type-clarify 처리 섹션이 잡히지 않음" >&2
    exit 1
fi
if ! grep -qF 'AskUserQuestion' <<<"$section"; then
    echo "FAIL: type-clarify 처리 섹션에 AskUserQuestion TUI 강제 문구 없음" >&2
    exit 1
fi

# 6. correlation id (qid) 가 송신·수신 양쪽에서 같은 값을 박아야 한다는 정책 문구
if ! grep -q '같은 qid' "$doc"; then
    echo "FAIL: check-inbox.md 에 'qid 일치' 정책 안내 없음 — 라운드 답 섞임 위험" >&2
    exit 1
fi

# 7. leader 의 wait-reply 차단 패턴 — first_msg 에는 hard guard 만, 절차는 SKILL 본문에.
#    SKILL 본문에 [reply:<qid>] 매칭 + wait-reply.sh 사용 절차가 있어야 함.
if ! grep -qF '[reply:' "$skill_leader"; then
    echo "FAIL: orch-leader SKILL 에 '[reply:<qid>]' 매칭 안내 없음 — wait-reply 차단 대기 패턴 미사용" >&2
    exit 1
fi
if ! grep -qF 'wait-reply.sh' "$skill_leader"; then
    echo "FAIL: orch-leader SKILL 에 'wait-reply.sh' 차단 대기 패턴 안내 없음" >&2
    exit 1
fi

echo "OK type-clarify-routed-via-orch"
