#!/usr/bin/env bash
# Regression guard: PM worker (worker_id=<issue>/pm) 의 worktree 가 어느 settings.projects
# 키 아래 만들어졌는지 registry 의 project 필드에 명시 보존되어야 cleanup 이 정확하다.
#
# 옛 버그: orch_cleanup_merged_worktrees 가 role 토큰 ('pm') 을 project alias 로 가정 →
# settings.projects.pm 이 없으면 PM worktree 정리 SKIP. registry 에 project 필드를 두면
# cleanup 이 그 alias 로 정확히 project_path / default_base_branch 를 찾는다.

set -euo pipefail

LIB="$PLUGIN_ROOT/scripts/lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB 없음" >&2; exit 1; }

cd "$SANDBOX"
# shellcheck source=/dev/null
source "$LIB"

# 격리된 ORCH 경로 — 실제 사용자 ~/.orch 건드리지 않게
export ORCH_DIR="$SANDBOX/.orch"
export ORCH_WORKERS="$ORCH_DIR/workers"
export ORCH_RUNS_DIR="$ORCH_DIR/runs"
export ORCH_INBOX="$ORCH_DIR/inbox"
export ORCH_ARCHIVE="$ORCH_DIR/archive"
mkdir -p "$ORCH_WORKERS" "$ORCH_RUNS_DIR" "$ORCH_INBOX" "$ORCH_ARCHIVE"
mkdir -p "$ORCH_RUNS_DIR/MP-99/workers"

# orch_worker_register 가 새 시그니처 (6번째 인자 project_alias) 를 가지는지
# 정적 검사 — leader-spawn / review-spawn 양쪽이 project 를 넘기는지.
src_lead="$PLUGIN_ROOT/scripts/leader-spawn.sh"
src_rev="$PLUGIN_ROOT/scripts/review-spawn.sh"
for caller in "$src_lead" "$src_rev"; do
    if ! grep -qE 'orch_worker_register .* "\$project"' "$caller"; then
        echo "FAIL: $caller 가 orch_worker_register 6번째 인자로 project alias 안 넘김" >&2
        exit 1
    fi
done

# orch_worker_register 본문이 jq -n --arg 로 JSON 을 만드는지 (heredoc 직접 합성 금지)
if ! grep -q 'jq -n ' "$LIB"; then
    echo "FAIL: lib.sh 에 orch_worker_register 의 jq -n 사용 흔적 없음 — heredoc JSON 합성으로 회귀 가능" >&2
    exit 1
fi

# 동적: PM worker 등록 → registry 가 project 필드를 정확히 가지는지
mp_id="MP-99"
worker_id="${mp_id}/pm"
worktree_path="$SANDBOX/work/proj-a/${mp_id}/pm"
mkdir -p "$worktree_path"

# Sandbox 안 cwd 에 특수문자 (따옴표) 섞인 경로도 jq -n 으로 안전한지 부수 검증
weird_cwd="$SANDBOX/work/proj-a/odd \"name\" with \\back"
mkdir -p "$weird_cwd"

orch_worker_register "$worker_id" "worker" "@1" "%1" "$worktree_path" "proj-a"

reg_path="$(orch_worker_path "$worker_id")"
[ -f "$reg_path" ] || { echo "FAIL: registry json 생성 안 됨 ($reg_path)" >&2; exit 1; }

got_project="$(jq -r '.project // empty' "$reg_path")"
if [ "$got_project" != "proj-a" ]; then
    echo "FAIL: PM worker registry 의 project 필드 누락/오류 (got='$got_project' want='proj-a')" >&2
    exit 1
fi

# 특수문자 cwd 도 jq -n 으로 안전하게 escape 되는지
weird_wid="${mp_id}/odd-cwd"
weird_dir="$ORCH_RUNS_DIR/${mp_id}/workers"
mkdir -p "$weird_dir"
orch_worker_register "$weird_wid" "worker" "@2" "%2" "$weird_cwd" "proj-a"
weird_reg="$(orch_worker_path "$weird_wid")"
got_cwd="$(jq -r '.cwd' "$weird_reg")"
if [ "$got_cwd" != "$weird_cwd" ]; then
    echo "FAIL: 특수문자 cwd 가 JSON 으로 round-trip 안 됨" >&2
    echo "  want: $weird_cwd" >&2
    echo "  got:  $got_cwd" >&2
    exit 1
fi

# orch_cleanup_merged_worktrees 가 project 필드를 우선 참조하는지 정적 검사
if ! grep -q 'orch_worker_field "\$sub_wid" project' "$LIB"; then
    echo "FAIL: orch_cleanup_merged_worktrees 가 registry project 필드 참조 안 함 — PM cleanup 정확도 회귀" >&2
    exit 1
fi

# 폴백 안내 주석 (구버전 호환 — role 을 alias 로) 존재
if ! grep -q '구버전 호환' "$LIB"; then
    echo "FAIL: cleanup 폴백 호환 주석 없음 — 의도 불명확" >&2
    exit 1
fi

echo "OK pm-worker-cleanup-metadata"
