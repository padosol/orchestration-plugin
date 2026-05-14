#!/usr/bin/env bash
# Regression guard: git_host 추상화 헬퍼 (orch_require_git_host_cli / orch_pr_state /
# orch_pr_merged_by_branch) 가 lib.sh 에 존재하고, github + gitlab 두 case 분기를
# 가지는지 + 호출처 (wait-merge.sh / orch_branch_merged) 가 직접 gh/glab 안 부르고
# 헬퍼만 호출하는지 정적 검증.

set -euo pipefail

lib="$PLUGIN_ROOT/scripts/lib.sh"
wait_merge="$PLUGIN_ROOT/scripts/wait-merge.sh"

[ -f "$lib" ]        || { echo "FAIL: $lib 없음" >&2; exit 1; }
[ -f "$wait_merge" ] || { echo "FAIL: $wait_merge 없음" >&2; exit 1; }

# 1. 헬퍼 함수 3종 정의 존재
for fn in orch_require_git_host_cli orch_pr_state orch_pr_merged_by_branch; do
    if ! grep -qE "^${fn}\(\)" "$lib"; then
        echo "FAIL: lib.sh 에 ${fn}() 함수 정의 누락" >&2
        exit 1
    fi
done

# 2. 각 헬퍼 함수 본문에 github + gitlab 두 분기가 있어야 한다.
#    함수 본문 = 함수 시작 라인 ~ 다음 토픽 함수 시작 직전. awk 로 한 함수만 추출.
extract_fn() {
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        $0 ~ "^"fn"\\(\\)" { capture = 1 }
        capture { print }
        capture && /^}$/ { capture = 0 }
    ' "$file"
}

for fn in orch_require_git_host_cli orch_pr_state orch_pr_merged_by_branch; do
    body="$(extract_fn "$lib" "$fn")"
    if [ -z "$body" ]; then
        echo "FAIL: ${fn} 본문 추출 실패" >&2; exit 1
    fi
    if ! grep -qE '^\s*github\)' <<<"$body"; then
        echo "FAIL: ${fn} 본문에 github) case 분기 누락" >&2; exit 1
    fi
    if ! grep -qE '^\s*gitlab\)' <<<"$body"; then
        echo "FAIL: ${fn} 본문에 gitlab) case 분기 누락" >&2; exit 1
    fi
done

# 3. orch_pr_state 정규화: gh/glab 양쪽의 state 값을 정규화된 키워드로 매핑.
state_body="$(extract_fn "$lib" "orch_pr_state")"
for raw in merged closed open opened; do
    if ! grep -qE "${raw}[^a-z]" <<<"$state_body"; then
        echo "FAIL: orch_pr_state 가 raw state '${raw}' 매핑 누락 (gh 의 MERGED/CLOSED/OPEN + glab 의 opened/closed/merged 모두 cover 필요)" >&2
        exit 1
    fi
done

# 4. orch_pr_merged_by_branch: gh 와 glab 의 인자 명이 다름 — gh '--head', glab '--source-branch'.
merged_body="$(extract_fn "$lib" "orch_pr_merged_by_branch")"
if ! grep -q -- '--head' <<<"$merged_body"; then
    echo "FAIL: orch_pr_merged_by_branch 의 github 분기에 '--head' 인자 누락" >&2; exit 1
fi
if ! grep -q -- '--source-branch' <<<"$merged_body"; then
    echo "FAIL: orch_pr_merged_by_branch 의 gitlab 분기에 '--source-branch' 인자 누락" >&2; exit 1
fi

# 5. wait-merge.sh 가 직접 gh / glab 호출하지 않고 헬퍼만 사용
if grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]' "$wait_merge"; then
    echo "FAIL: wait-merge.sh 가 여전히 'gh pr ...' 직접 호출 — orch_pr_state 헬퍼로 통과해야 함" >&2
    exit 1
fi
if grep -qE '(^|[[:space:]])glab[[:space:]]+mr[[:space:]]' "$wait_merge"; then
    echo "FAIL: wait-merge.sh 가 'glab mr ...' 직접 호출 — orch_pr_state 헬퍼로 통과해야 함" >&2
    exit 1
fi
if ! grep -q 'orch_require_git_host_cli' "$wait_merge"; then
    echo "FAIL: wait-merge.sh 가 orch_require_git_host_cli 호출 누락" >&2; exit 1
fi
if ! grep -q 'orch_pr_state' "$wait_merge"; then
    echo "FAIL: wait-merge.sh 가 orch_pr_state 호출 누락" >&2; exit 1
fi

# 6. orch_branch_merged 가 host 직결 호출 제거하고 orch_pr_merged_by_branch 사용
branch_merged_body="$(extract_fn "$lib" "orch_branch_merged")"
if grep -qE 'gh[[:space:]]+pr[[:space:]]+list' <<<"$branch_merged_body"; then
    echo "FAIL: orch_branch_merged 가 여전히 'gh pr list' 직접 호출 — orch_pr_merged_by_branch 로 통과해야 함" >&2
    exit 1
fi
if ! grep -q 'orch_pr_merged_by_branch' <<<"$branch_merged_body"; then
    echo "FAIL: orch_branch_merged 가 orch_pr_merged_by_branch 호출 누락" >&2; exit 1
fi

# 7. 동적: settings.json (sandbox) 의 git_host 별 분기 동작 — host 누락 시 require 가 fail
#    (CLI 자체는 sandbox 에 있을 수도/없을 수도 있으므로 require 의 host 분기만 확인).
cd "$SANDBOX"
# shellcheck source=/dev/null
source "$lib"

# git_host 가 'none' 인 settings 에서는 require 가 fail (return 2)
git_host_none_settings='{"base_dir":"'"$SANDBOX"'","projects":[],"issue_tracker":"none","git_host":"none","slack":{"webhook":"","mention":""}}'
mkdir -p "$ORCH_ROOT"
printf '%s' "$git_host_none_settings" > "$ORCH_SETTINGS"
rc=0
orch_require_git_host_cli >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "FAIL: git_host=none 인데 orch_require_git_host_cli 가 통과 (실패해야 함)" >&2
    exit 1
fi

echo "OK git-host-helpers"
