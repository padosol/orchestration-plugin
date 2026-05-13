#!/usr/bin/env bash
# Regression guard: developer_pr_v1.json 의 step 순서 invariant 유지.
# 시나리오 67 은 SKILL 본문 (개념/keyword) guard, 본 시나리오는 실제 template
# 파일의 실행 순서를 구조적으로 검증한다 — 책임 분리.

set -euo pipefail

tmpl="$PLUGIN_ROOT/references/workflows/task-templates/developer_pr_v1.json"
[ -f "$tmpl" ] || { echo "FAIL: $tmpl 없음" >&2; exit 1; }

python3 - "$tmpl" <<'PY'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    tmpl = json.load(f)

if tmpl.get("name") != "developer_pr_v1":
    print(f"FAIL: name expected 'developer_pr_v1', got {tmpl.get('name')!r}")
    sys.exit(1)
if tmpl.get("status") != "stable":
    print(f"FAIL: status expected 'stable', got {tmpl.get('status')!r}")
    sys.exit(1)

steps = tmpl.get("steps") or []
ids = [s.get("id") for s in steps]
idx = {sid: i for i, sid in enumerate(ids)}

# 1. 핵심 순서 invariant — PR 4단계 + HOLD + brief_validation 흐름
ordered = [
    "receive_instruction",
    "analyze",
    "hold_before_edit",
    "brief_validation",
    "implement",
    "test",
    "commit",
    "hold_before_push",
    "push_and_pr",
    "ci",
    "ready_for_review",
    "review",
    "wait_merge",
    "shutdown",
]
missing = [sid for sid in ordered if sid not in idx]
if missing:
    print(f"FAIL: developer_pr_v1.json 에 다음 step 누락: {missing}")
    sys.exit(1)

# 2. 순서 invariant — 인접 pair 가 단조 증가
for a, b in zip(ordered, ordered[1:]):
    if idx[a] >= idx[b]:
        print(f"FAIL: step 순서 위반 — '{a}' (idx={idx[a]}) 는 '{b}' (idx={idx[b]}) 보다 먼저 와야 함")
        sys.exit(1)

# 3. brief_validation 속성 invariant (review 이후 non-blocking 의미 합의)
bv = next((s for s in steps if s.get("id") == "brief_validation"), None)
if bv is None:
    print("FAIL: brief_validation step 사라짐")
    sys.exit(1)
if bv.get("blocking") is not False:
    print(f"FAIL: brief_validation.blocking 은 false 여야 함 (현재: {bv.get('blocking')!r})")
    sys.exit(1)
if bv.get("required") is not True:
    print(f"FAIL: brief_validation.required 는 true 여야 함 (현재: {bv.get('required')!r})")
    sys.exit(1)

# 4. PR 핵심 단계는 blocking=true / required=true
critical_blocking = [
    "receive_instruction", "analyze", "hold_before_edit",
    "implement", "test", "commit", "hold_before_push",
    "push_and_pr", "ci", "ready_for_review", "review",
    "wait_merge", "shutdown",
]
for sid in critical_blocking:
    s = next((x for x in steps if x.get("id") == sid), None)
    if s is None:
        print(f"FAIL: critical step '{sid}' 사라짐")
        sys.exit(1)
    if s.get("blocking") is not True:
        print(f"FAIL: step '{sid}'.blocking 은 true 여야 함 (현재: {s.get('blocking')!r})")
        sys.exit(1)
    if s.get("required") is not True:
        print(f"FAIL: step '{sid}'.required 는 true 여야 함 (현재: {s.get('required')!r})")
        sys.exit(1)

# 5. owner 분리 — review 만 reviewer 소유, 첫 step 은 leader, 나머지는 developer
expected_owner = {
    "receive_instruction": "leader",
    "review": "reviewer",
}
for s in steps:
    sid = s.get("id")
    want = expected_owner.get(sid, "developer")
    got = s.get("owner")
    if got != want:
        print(f"FAIL: step '{sid}'.owner expected '{want}', got '{got}'")
        sys.exit(1)

print("OK developer-pr-v1-step-order")
PY
