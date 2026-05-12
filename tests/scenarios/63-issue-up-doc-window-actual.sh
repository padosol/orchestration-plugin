#!/usr/bin/env bash
# Regression guard: commands/issue-up.md 가 실제 scripts/issue-up.sh 동작 (새 tmux 윈도우 생성)
# 과 일치해야 한다. 옛 문서는 "호출자(orch) 윈도우를 split" 으로 잘못 적혀 있어 사용자
# 멘탈 모델과 어긋났다.

set -euo pipefail

doc="$PLUGIN_ROOT/commands/issue-up.md"
src="$PLUGIN_ROOT/scripts/issue-up.sh"

[ -f "$doc" ] || { echo "FAIL: $doc 없음" >&2; exit 1; }
[ -f "$src" ] || { echo "FAIL: $src 없음" >&2; exit 1; }

# 1. 실제 스크립트는 orch_new_window 로 새 윈도우 생성
if ! grep -q 'orch_new_window "\$mp_id"' "$src"; then
    echo "FAIL: scripts/issue-up.sh 가 orch_new_window 를 호출하지 않음 — 본 테스트의 전제 변경됨" >&2
    exit 1
fi

# 2. 문서가 '새 tmux 윈도우' 로 정정되어 있어야
if ! grep -q '새 tmux 윈도우' "$doc"; then
    echo "FAIL: commands/issue-up.md 에 '새 tmux 윈도우' 표현 없음" >&2
    exit 1
fi

# 3. 옛 잘못된 문구 ('호출자(orch) 윈도우를 split') 잔존 금지
if grep -q '호출자(orch) 윈도우를 split' "$doc"; then
    echo "FAIL: commands/issue-up.md 에 옛 'orch 윈도우 split' 문구 잔존 — 실제 동작과 불일치" >&2
    exit 1
fi

# 4. gitlab / jira 트래커 분기도 문서에 반영 (네 트래커 모두 자동 fetch 지원하므로)
for tracker in gitlab jira; do
    if ! grep -q "$tracker" "$doc"; then
        echo "FAIL: commands/issue-up.md 에 트래커 '${tracker}' 분기 안내 누락" >&2
        exit 1
    fi
done

echo "OK issue-up-doc-window-actual"
