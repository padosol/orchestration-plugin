#!/usr/bin/env bash
# orch_id_safe / orch_normalize_issue_id / orch_wid_kind — sanitize 정책 회귀.
# 정책: positive regex 폐지, deny-list (공백·제어 / shell meta / quoting·grouping / .. / slash / 'orch' / 빈) 만 차단.

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

# normalize: 트래커별 키 + 자연 문자 (# . + @) 통과 (* ? ~ 는 deny)
assert_eq "norm MP-13"        "$(orch_normalize_issue_id MP-13)"        "MP-13"
assert_eq "norm mp-13"        "$(orch_normalize_issue_id mp-13)"        "mp-13"
assert_eq "norm PROJ-456"     "$(orch_normalize_issue_id PROJ-456)"     "PROJ-456"
assert_eq "norm 142"          "$(orch_normalize_issue_id 142)"          "142"
assert_eq "norm issue_42"     "$(orch_normalize_issue_id issue_42)"     "issue_42"
assert_eq "norm gh-99"        "$(orch_normalize_issue_id gh-99)"        "gh-99"
assert_eq "norm my-issue#42"  "$(orch_normalize_issue_id 'my-issue#42')" "my-issue#42"
assert_eq "norm v1.0.0"       "$(orch_normalize_issue_id 'v1.0.0')"     "v1.0.0"
assert_eq "norm feature+rc"   "$(orch_normalize_issue_id 'feature+rc')" "feature+rc"
assert_eq "norm user@home"    "$(orch_normalize_issue_id 'user@home')"  "user@home"
assert_eq "norm feature-2026" "$(orch_normalize_issue_id feature-2026)" "feature-2026"

# normalize reject: orch reserved / 빈 / slash / shell meta / quoting / grouping / control /
# .. / glob (*?) / tilde (~)
reject_cases=(
    "orch"
    ""
    "a/b"
    "a;b"
    "a|b"
    "a&b"
    'a$b'
    'a`b'
    'a\b'
    "a<b"
    "a>b"
    "a!b"
    "a(b)"
    "a{b}"
    "a[b]"
    'a"b'
    "a'b"
    "MP 13"
    ".."
    "a..b"
    "../etc"
    "a*b"
    "a?b"
    "MP-13*"
    "~home"
    "feat~rc"
)
for bad in "${reject_cases[@]}"; do
    if orch_normalize_issue_id "$bad" >/dev/null 2>&1; then
        echo "FAIL normalize accepted bad input: '$bad'" >&2
        exit 1
    fi
done

# 탭/개행 등 제어문자도 거부 (printf 로 명시)
for bad in "$(printf 'a\tb')" "$(printf 'a\nb')" "$(printf 'a\rb')" "$(printf 'a\x01b')"; do
    if orch_normalize_issue_id "$bad" >/dev/null 2>&1; then
        echo "FAIL normalize accepted control char input" >&2
        exit 1
    fi
done

# wid_kind 분기
assert_eq "kind orch"             "$(orch_wid_kind orch)"             "orch"
assert_eq "kind MP-13"            "$(orch_wid_kind MP-13)"            "leader"
assert_eq "kind PROJ-456"         "$(orch_wid_kind PROJ-456)"         "leader"
assert_eq "kind 142"              "$(orch_wid_kind 142)"              "leader"
assert_eq "kind issue42"          "$(orch_wid_kind issue42)"          "leader"
assert_eq "kind my-issue#42"      "$(orch_wid_kind 'my-issue#42')"    "leader"
assert_eq "kind MP-13/server"     "$(orch_wid_kind MP-13/server)"     "worker"
assert_eq "kind 142/api"          "$(orch_wid_kind 142/api)"          "worker"
assert_eq "kind my-issue#42/api"  "$(orch_wid_kind 'my-issue#42/api')" "worker"
assert_eq "kind a;b"              "$(orch_wid_kind 'a;b')"            "invalid"
assert_eq "kind a/b/c"            "$(orch_wid_kind a/b/c)"            "invalid"
assert_eq "kind ''"               "$(orch_wid_kind '')"               "invalid"
assert_eq "kind /leader"          "$(orch_wid_kind '/leader')"        "invalid"
assert_eq "kind leader/"          "$(orch_wid_kind 'leader/')"        "invalid"

# wid_scope
assert_eq "scope MP-13"           "$(orch_wid_scope MP-13)"           "MP-13"
assert_eq "scope MP-13/server"    "$(orch_wid_scope MP-13/server)"    "MP-13"
assert_eq "scope PROJ-456/ui"     "$(orch_wid_scope PROJ-456/ui)"     "PROJ-456"
assert_eq "scope my-issue#42/api" "$(orch_wid_scope 'my-issue#42/api')" "my-issue#42"
assert_eq "scope orch"            "$(orch_wid_scope orch)"            ""

echo "OK identifier-tracker-keys"
