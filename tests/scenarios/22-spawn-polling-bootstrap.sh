#!/usr/bin/env bash
# Regression guard: spawn 3종이 first_msg 직접 push 를 폐기하고 포인터 inbox 적재 +
# SessionStart hook → start skill 부트스트랩으로 전환됐는지 소스 계약 검사.

set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

# 1. spawn 3종: first_msg 는 orch_append_message 로 적재, orch_send_keys_line 직접 push 없음,
#    claude 기동은 적재 이후, sleep 4 제거.
for s in issues/issue-up.sh issues/leader-spawn.sh issues/review-spawn.sh; do
    src="$PLUGIN_ROOT/scripts/$s"
    [ -f "$src" ] || fail "$s 없음"
    c="$(cat "$src")"

    grep -qF 'orch_append_message' <<<"$c" || fail "$s: orch_append_message 미사용 (spawn-context inbox 적재 안 함)"
    grep -qF 'orch_send_keys_line' <<<"$c" && fail "$s: orch_send_keys_line 잔존 (first_msg 직접 push 폐기 위반)"

    # claude 기동 send-keys 가 orch_append_message 보다 뒤에 있어야 함 (context 적재 후 기동)
    ap_line="$(grep -n 'orch_append_message' <<<"$c" | head -1 | cut -d: -f1)"
    cl_line="$(grep -n 'send-keys .*&& claude' <<<"$c" | head -1 | cut -d: -f1)"
    [ -n "$ap_line" ] && [ -n "$cl_line" ] || fail "$s: append/claude 라인 식별 실패"
    [ "$ap_line" -lt "$cl_line" ] || fail "$s: claude 기동이 spawn-context 적재보다 앞섬 (race)"

    grep -qE '^[[:space:]]*sleep 4[[:space:]]*$' <<<"$c" && fail "$s: sleep 4 잔존 (불필요한 기동 대기)"
done

# 2. session-start.sh: leader/worker 는 start skill invoke 지시, orch 는 아님.
hook="$PLUGIN_ROOT/hooks/session-start.sh"
hc="$(cat "$hook")"
grep -qF 'orch-leader-start' <<<"$hc" || fail "session-start.sh: orch-leader-start 미지정"
grep -qF 'orch-worker-start' <<<"$hc" || fail "session-start.sh: orch-worker-start 미지정"
grep -qF 'Skill 도구로' <<<"$hc" || fail "session-start.sh: start skill invoke 지시문 누락"

# 3. start skill 2종 존재 + 페르소나/진입 계약.
ls="$PLUGIN_ROOT/skills/orch-leader-start/SKILL.md"
ws="$PLUGIN_ROOT/skills/orch-worker-start/SKILL.md"
[ -f "$ls" ] || fail "skills/orch-leader-start/SKILL.md 없음"
[ -f "$ws" ] || fail "skills/orch-worker-start/SKILL.md 없음"

lc="$(cat "$ls")"; wc="$(cat "$ws")"
grep -qF 'name: orch-leader-start' <<<"$lc" || fail "orch-leader-start frontmatter name 누락"
grep -qF 'name: orch-worker-start' <<<"$wc" || fail "orch-worker-start frontmatter name 누락"
grep -qF 'orch-leader' <<<"$lc" || fail "orch-leader-start 가 orch-leader 페르소나 참조 안 함"
grep -qF 'check-inbox' <<<"$lc" || fail "orch-leader-start 가 inbox 드레인 안 함"
for p in orch-pm orch-reviewer orch-developer-worker; do
    grep -qF "$p" <<<"$wc" || fail "orch-worker-start 가 $p 페르소나 분기 누락"
done
grep -qF 'check-inbox' <<<"$wc" || fail "orch-worker-start 가 inbox 드레인 안 함"

echo "OK spawn-polling-bootstrap"
