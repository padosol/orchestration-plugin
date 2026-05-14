#!/usr/bin/env bash
# Regression guard: git_host 추상화 Phase 2 — PR/MR 명령 fragment 헬퍼 (orch_pr_create_cmd /
# view_json / diff / comment_from_file / checks_watch / run_log_failed) 가 lib.sh 에 존재하고
# github + gitlab 두 case 가지는지 + spawn script 가 first_msg 에 <pr_*_cmd> 변수 주입하는지
# + developer/orch-pm/orch-reviewer SKILL 및 orch-protocols.md 가 변수 참조 (직접 'gh pr'
# 명령 표기 제거) 인지 정적 검증.

set -euo pipefail

lib="$PLUGIN_ROOT/scripts/lib.sh"
leader_spawn="$PLUGIN_ROOT/scripts/leader-spawn.sh"
review_spawn="$PLUGIN_ROOT/scripts/review-spawn.sh"
dev_skill="$PLUGIN_ROOT/skills/orch-developer-worker/SKILL.md"
pm_skill="$PLUGIN_ROOT/skills/orch-pm/SKILL.md"
rv_skill="$PLUGIN_ROOT/skills/orch-reviewer/SKILL.md"
protocols="$PLUGIN_ROOT/references/orch-protocols.md"

for f in "$lib" "$leader_spawn" "$review_spawn" "$dev_skill" "$pm_skill" "$rv_skill" "$protocols"; do
    [ -f "$f" ] || { echo "FAIL: $f 없음" >&2; exit 1; }
done

# 1. lib.sh 의 6 헬퍼 정의 + 본문에 github + gitlab 두 case
extract_fn() {
    awk -v fn="$2" '
        $0 ~ "^"fn"\\(\\)" { capture = 1 }
        capture { print }
        capture && /^}$/ { capture = 0 }
    ' "$1"
}

for fn in orch_pr_create_cmd orch_pr_view_json_cmd orch_pr_diff_cmd orch_pr_comment_from_file_cmd orch_pr_checks_watch_cmd orch_pr_run_log_failed_cmd; do
    if ! grep -qE "^${fn}\(\)" "$lib"; then
        echo "FAIL: lib.sh 에 ${fn}() 정의 누락" >&2; exit 1
    fi
    body="$(extract_fn "$lib" "$fn")"
    if ! grep -qE '^\s*github\)' <<<"$body"; then
        echo "FAIL: ${fn} 본문에 github) case 누락" >&2; exit 1
    fi
    if ! grep -qE '^\s*gitlab\)' <<<"$body"; then
        echo "FAIL: ${fn} 본문에 gitlab) case 누락" >&2; exit 1
    fi
done

# 2. orch_pr_view_json_cmd 가 host 간 정규화 키 (title/body/headRefName/baseRefName) cover.
#    gitlab 분기는 glab api REST 우회 + jq 로 description→body / source_branch→headRefName /
#    target_branch→baseRefName 매핑.
#    (files 키는 제거 — reviewer 는 별도 <pr_diff_cmd> 로 변경분 확인. glab mr view 의
#    --output json 미지원 + changes 키는 별도 endpoint 라 단순화.)
view_body="$(extract_fn "$lib" "orch_pr_view_json_cmd")"
for token in title body headRefName baseRefName description source_branch target_branch; do
    if ! grep -qF "$token" <<<"$view_body"; then
        echo "FAIL: orch_pr_view_json_cmd 가 host 정규화 키워드 '${token}' 누락" >&2; exit 1
    fi
done
if ! grep -q 'glab api' <<<"$view_body"; then
    echo "FAIL: orch_pr_view_json_cmd 의 gitlab 분기에 'glab api' 호출 누락 (glab mr view 는 --output json 미지원)" >&2
    exit 1
fi

# 2b. orch_pr_checks_watch_cmd 의 gitlab 분기는 --live (glab 1.36+ 에서 --wait 미지원).
watch_body="$(extract_fn "$lib" "orch_pr_checks_watch_cmd")"
watch_gitlab="$(awk '/^\s*gitlab\)/,/;;/' <<<"$watch_body")"
if grep -q -- '--wait' <<<"$watch_gitlab"; then
    echo "FAIL: orch_pr_checks_watch_cmd gitlab 분기에 stale '--wait' 잔존 (glab 1.36+ 는 '--live')" >&2
    exit 1
fi
if ! grep -q -- '--live' <<<"$watch_gitlab"; then
    echo "FAIL: orch_pr_checks_watch_cmd gitlab 분기에 '--live' 옵션 누락" >&2; exit 1
fi

# 2c. orch_pr_run_log_failed_cmd 의 gitlab 분기는 glab api (glab ci view 는 TUI 라 automation 불가).
log_body="$(extract_fn "$lib" "orch_pr_run_log_failed_cmd")"
log_gitlab="$(awk '/^\s*gitlab\)/,/;;/' <<<"$log_body")"
if grep -qE 'glab ci view.*--trace' <<<"$log_gitlab"; then
    echo "FAIL: orch_pr_run_log_failed_cmd gitlab 분기에 stale 'glab ci view --trace' 잔존 (TUI / 미지원 flag)" >&2
    exit 1
fi
if ! grep -q 'glab api' <<<"$log_gitlab"; then
    echo "FAIL: orch_pr_run_log_failed_cmd gitlab 분기에 'glab api' REST 호출 누락" >&2; exit 1
fi

# 3. leader-spawn.sh / review-spawn.sh 가 host 헬퍼 호출 + pr_host_block 변수 주입
if ! grep -q 'orch_pr_create_cmd' "$leader_spawn"; then
    echo "FAIL: leader-spawn.sh 가 orch_pr_create_cmd 호출 누락" >&2; exit 1
fi
if ! grep -q 'orch_pr_checks_watch_cmd' "$leader_spawn"; then
    echo "FAIL: leader-spawn.sh 가 orch_pr_checks_watch_cmd 호출 누락" >&2; exit 1
fi
if ! grep -q 'pr_host_block' "$leader_spawn"; then
    echo "FAIL: leader-spawn.sh 가 pr_host_block 변수 주입 누락" >&2; exit 1
fi
if ! grep -q 'orch_pr_view_json_cmd' "$review_spawn"; then
    echo "FAIL: review-spawn.sh 가 orch_pr_view_json_cmd 호출 누락" >&2; exit 1
fi
if ! grep -q 'orch_pr_comment_from_file_cmd' "$review_spawn"; then
    echo "FAIL: review-spawn.sh 가 orch_pr_comment_from_file_cmd 호출 누락" >&2; exit 1
fi
if ! grep -q 'pr_host_block_review' "$review_spawn"; then
    echo "FAIL: review-spawn.sh 가 pr_host_block_review 변수 주입 누락" >&2; exit 1
fi

# 4. SKILL 본문 / orch-protocols.md 가 <pr_*_cmd> 변수 참조 + gh pr 직결 표기 제거.
#    developer SKILL §6 / §0.5 표
if ! grep -q '<pr_create_cmd>' "$dev_skill"; then
    echo "FAIL: developer SKILL 에 <pr_create_cmd> 참조 누락" >&2; exit 1
fi
if ! grep -q '<pr_checks_watch_cmd>' "$dev_skill"; then
    echo "FAIL: developer SKILL 에 <pr_checks_watch_cmd> 참조 누락" >&2; exit 1
fi
if grep -qE '`gh pr (create|checks)' "$dev_skill"; then
    echo "FAIL: developer SKILL 에 stale 한 'gh pr create/checks' 직결 표기 잔존" >&2; exit 1
fi

# pm SKILL §5 산출물 PR
if ! grep -q '<pr_create_cmd>' "$pm_skill"; then
    echo "FAIL: orch-pm SKILL 에 <pr_create_cmd> 참조 누락" >&2; exit 1
fi
if grep -qE '`gh pr (create|checks)' "$pm_skill"; then
    echo "FAIL: orch-pm SKILL 에 stale 한 'gh pr create/checks' 직결 표기 잔존" >&2; exit 1
fi

# reviewer SKILL §3 정보 도구 + §4 송신
for var in '<pr_view_json_cmd>' '<pr_diff_cmd>' '<pr_comment_from_file_cmd>'; do
    if ! grep -qF "$var" "$rv_skill"; then
        echo "FAIL: reviewer SKILL 에 ${var} 참조 누락" >&2; exit 1
    fi
done
if grep -qE '`gh pr (view|diff|comment|checks)' "$rv_skill"; then
    echo "FAIL: reviewer SKILL 에 stale 한 'gh pr view/diff/comment/checks' 직결 표기 잔존" >&2; exit 1
fi

# orch-protocols.md §4 CI sample 도 <pr_*_cmd> 변수 참조 (gh pr create 직결 fence block 표기 제거)
for var in '<pr_create_cmd>' '<pr_checks_watch_cmd>' '<pr_run_log_failed_cmd>'; do
    if ! grep -qF "$var" "$protocols"; then
        echo "FAIL: orch-protocols.md 에 ${var} 참조 누락" >&2; exit 1
    fi
done

# orch-protocols.md 의 stale invalid GitLab 명령 잔존 금지 (glab 1.36+ 미지원 flag).
# helper 본문은 이미 --live / glab api 로 갱신됐는데 shared protocol 문서가 invalid command 를
# 가르치면 워커가 stale 명령 그대로 실행 → fail.
if grep -qE 'glab ci status[^A-Za-z]+--wait' "$protocols"; then
    echo "FAIL: orch-protocols.md 에 stale 한 'glab ci status --wait' 잔존 (glab 1.36+ 미지원, --live 사용)" >&2
    exit 1
fi
if grep -qE 'glab ci view [^|]*--trace' "$protocols"; then
    echo "FAIL: orch-protocols.md 에 stale 한 'glab ci view ... --trace' 잔존 (TUI / 미지원, glab api .../trace 사용)" >&2
    exit 1
fi

echo "OK git-host-pr-cmd-helpers"
