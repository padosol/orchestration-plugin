#!/usr/bin/env bash
# Regression guard: spawn 3종이 first_msg 직접 push 를 폐기하고 포인터 inbox 적재로
# 전환됐는지 + SessionStart hook 이 inbox 첫 메시지(spawn-context)를 셸에서 직접
# 드레인해 plain stdout 으로 주입하고 archive 하는지 (start skill indirection 없음).

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

    ap_line="$(grep -n 'orch_append_message' <<<"$c" | head -1 | cut -d: -f1)"
    cl_line="$(grep -n 'send-keys .*&& claude' <<<"$c" | head -1 | cut -d: -f1)"
    [ -n "$ap_line" ] && [ -n "$cl_line" ] || fail "$s: append/claude 라인 식별 실패"
    [ "$ap_line" -lt "$cl_line" ] || fail "$s: claude 기동이 spawn-context 적재보다 앞섬 (race)"

    grep -qE '^[[:space:]]*sleep 4[[:space:]]*$' <<<"$c" && fail "$s: sleep 4 잔존 (불필요한 기동 대기)"
done

# 2. session-start.sh: 폐기된 메커니즘 잔재 없음.
hook="$PLUGIN_ROOT/hooks/session-start.sh"
hc="$(cat "$hook")"
grep -qF 'orch_inbox_path' <<<"$hc" && fail "session-start.sh: 삭제된 orch_inbox_path 참조"
grep -qF 'systemMessage' <<<"$hc" && fail "session-start.sh: systemMessage 채널 잔존 (모델 미수신)"
grep -qF 'hookSpecificOutput' <<<"$hc" && fail "session-start.sh: JSON 래퍼 잔존 (plain stdout 으로 전환됨)"
grep -qE 'orch-(leader|worker)-start' <<<"$hc" && fail "session-start.sh: 폐기된 start skill 참조 잔존"

# 3. start skill 2종은 제거됨.
[ -e "$PLUGIN_ROOT/skills/orch-leader-start" ] && fail "skills/orch-leader-start 미삭제"
[ -e "$PLUGIN_ROOT/skills/orch-worker-start" ] && fail "skills/orch-worker-start 미삭제"

# 4. hook 실제 실행 — leader inbox 에 spawn-context 적재 후:
#    (a) plain stdout(JSON 아님)에 본문 그대로 주입, (b) 실행 후 단건 archive 로 inbox 비움.
ib="$SANDBOX/spawn-boot-inbox"
rm -rf "$ib"
MARK="SPAWN-CTX-MARK-$$"
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ORCH_INBOX="$ib" bash -c "
source '$PLUGIN_ROOT/scripts/core/lib.sh'
orch_append_message orch MP-BOOT '너는 MP-BOOT 팀리더다. $MARK 본문 지시.' >/dev/null
" || fail "spawn-context 적재 실패"

out="$(ORCH_WORKER_ID=MP-BOOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ORCH_INBOX="$ib" \
    bash "$hook" </dev/null 2>/dev/null)" || fail "session-start.sh 실행 실패 (spawn-context 있음)"

[ -n "$out" ] || fail "spawn-context 있는데 stdout 비어 있음"
case "$(printf '%s' "$out" | head -c1)" in
    '{') fail "stdout 이 JSON — plain stdout 이어야 함" ;;
esac
grep -qF "$MARK" <<<"$out" || fail "stdout 에 spawn-context 본문 미주입"

cnt="$(ORCH_WORKER_ID=MP-BOOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ORCH_INBOX="$ib" bash -c "
source '$PLUGIN_ROOT/scripts/core/lib.sh'
orch_inbox_count MP-BOOT")"
[ "$cnt" = "0" ] || fail "전달 후 spawn-context 가 archive 안 됨 (inbox count=$cnt)"

# 5. 드레인 후 재fire(빈 inbox): 재부트스트랩 없이 역할 안내만, 여전히 plain stdout.
out2="$(ORCH_WORKER_ID=MP-BOOT CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ORCH_INBOX="$ib" \
    bash "$hook" </dev/null 2>/dev/null)" || fail "session-start.sh 재실행 실패 (빈 inbox)"
grep -qF "$MARK" <<<"$out2" && fail "빈 inbox 인데 옛 spawn-context 재주입됨"
grep -qF 'MP-BOOT' <<<"$out2" || fail "재fire 역할 안내에 worker_id 없음"

# 6. orch(PM): spawn-context 없이 역할 안내만, plain stdout.
outo="$(ORCH_WORKER_ID=orch CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ORCH_INBOX="$ib" \
    bash "$hook" </dev/null 2>/dev/null)" || fail "session-start.sh 실행 실패 (orch)"
case "$(printf '%s' "$outo" | head -c1)" in
    '{') fail "orch stdout 이 JSON — plain 이어야 함" ;;
esac
grep -qF 'orchestrator(PM)' <<<"$outo" || fail "orch 역할 안내 누락"

echo "OK spawn-polling-bootstrap"
