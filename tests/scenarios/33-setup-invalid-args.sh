#!/usr/bin/env bash
# setup.sh — 잘못된 인자 값 거부 검증.

set -uo pipefail

ws="$SANDBOX/setup-invalid"
mkdir -p "$ws/repo-a"
git -C "$ws/repo-a" init -q
echo "x" > "$ws/repo-a/a.txt"
git -C "$ws/repo-a" add . && git -C "$ws/repo-a" -c user.email=a@b -c user.name=t commit -qm init

fail=0
for bad in '--issue-tracker yolo' '--issue-tracker jira' '--git-host weird' '--notify maybe'; do
    if ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/config/setup.sh" $bad >/dev/null 2>&1; then
        echo "FAIL: '$bad' 거부되지 않음"
        fail=1
    fi
    rm -rf "$ws/.orch"
done

[ "$fail" -eq 0 ] || exit 1
echo "OK setup-invalid-args"
