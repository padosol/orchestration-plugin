#!/usr/bin/env bash
# orch_normalize_issue_id / orch_wid_kind — 트래커별 다양한 키 형식이 leader_id 로 통과되는지.
# 0.13.0~: mp-NN 강제 변환 폐지, [A-Za-z0-9_-]+ 대소문자 보존.

set -euo pipefail

cd "$SANDBOX"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib.sh"

assert_eq() {
    local label="$1" got="$2" want="$3"
    if [ "$got" != "$want" ]; then
        echo "FAIL $label: got='$got' want='$want'" >&2
        exit 1
    fi
}

# normalize: 트래커별 키 그대로 통과
assert_eq "norm MP-13"      "$(orch_normalize_issue_id MP-13)"     "MP-13"
assert_eq "norm mp-13"      "$(orch_normalize_issue_id mp-13)"     "mp-13"
assert_eq "norm PROJ-456"   "$(orch_normalize_issue_id PROJ-456)"  "PROJ-456"
assert_eq "norm 142"        "$(orch_normalize_issue_id 142)"       "142"
assert_eq "norm issue_42"   "$(orch_normalize_issue_id issue_42)"  "issue_42"
assert_eq "norm gh-99"      "$(orch_normalize_issue_id gh-99)"     "gh-99"

# normalize reject: orch / 슬래시 / # / 빈
for bad in "orch" "a/b" "#142" "" "MP 13" "MP@13"; do
    if orch_normalize_issue_id "$bad" >/dev/null 2>&1; then
        echo "FAIL normalize accepted bad input: '$bad'" >&2
        exit 1
    fi
done

# wid_kind 분기
assert_eq "kind orch"          "$(orch_wid_kind orch)"            "orch"
assert_eq "kind MP-13"         "$(orch_wid_kind MP-13)"           "leader"
assert_eq "kind PROJ-456"      "$(orch_wid_kind PROJ-456)"        "leader"
assert_eq "kind 142"           "$(orch_wid_kind 142)"             "leader"
assert_eq "kind issue42"       "$(orch_wid_kind issue42)"         "leader"
assert_eq "kind MP-13/server"  "$(orch_wid_kind MP-13/server)"    "worker"
assert_eq "kind 142/api"       "$(orch_wid_kind 142/api)"         "worker"
assert_eq "kind a#b"           "$(orch_wid_kind 'a#b')"           "invalid"
assert_eq "kind a/b/c"         "$(orch_wid_kind a/b/c)"           "invalid"

# wid_scope
assert_eq "scope MP-13"            "$(orch_wid_scope MP-13)"            "MP-13"
assert_eq "scope MP-13/server"     "$(orch_wid_scope MP-13/server)"     "MP-13"
assert_eq "scope PROJ-456/ui"      "$(orch_wid_scope PROJ-456/ui)"      "PROJ-456"
assert_eq "scope orch"             "$(orch_wid_scope orch)"             ""

echo "OK identifier-tracker-keys"
