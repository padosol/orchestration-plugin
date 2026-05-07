#!/usr/bin/env bash
# orch v2 — 2-tier hub-and-spoke 공통 함수 라이브러리.
#
# 식별자(worker_id) 형태:
#   orch              → PM (사용자와 대화)
#   mp-NN             → MP-NN 팀리더
#   mp-NN/<project>   → MP-NN 산하 프로젝트 워커
#
# 디스크 레이아웃:
#   .orch/settings.json                            프로젝트 메타데이터
#   .orch/inbox/<id>.md                            orch / leader 인박스
#   .orch/archive/<id>-YYYY-MM-DD.md               orch / leader 메시지 archive
#   .orch/archive/<scope>-YYYY-MM-DD/              mp-down 시 scope dir 통째 archive
#   .orch/workers/<id>.json                        orch / leader 등록
#   .orch/runs/<scope>/inbox/<role>.md             leader 산하 워커 인박스
#   .orch/runs/<scope>/archive/<role>-YYYY-MM-DD.md
#   .orch/runs/<scope>/workers/<role>.json
#   .orch/runs/<scope>/worktrees/<project>/        git worktree
#   .orch/runs/<scope>/leader-archive.md           leader inbox archive (mp-down 시 함께 archive)
#   .orch/runs/<scope>/errors.jsonl                scope 별 에러 로그
#
# **PAD-3** 이후 신규 MP scope 는 `.orch/runs/<scope>/` 아래에 묶인다 — 동시 진행 MP 가
# 많아져도 .orch 루트가 어수선하지 않도록 wrapper 한 단계 추가. 변경 전에 만들어진 활성
# MP 는 `.orch/<scope>/` 평탄 위치에 그대로 있고, orch_scope_dir 가 양쪽을 본다 — 신규는
# runs/, legacy 는 평탄 path. 진행중인 MP 가 mp-down 으로 종료되면 자연스럽게 정리됨.
#
# **inbox 빈 파일 = 처리할 메시지 없음 (정상 상태).** inbox-archive.sh 가 처리된 메시지
# 를 archive/ 로 옮긴 뒤 inbox/<role>.md 를 truncate 한다. 처리 흔적은 archive 쪽 확인.

# ─── ORCH_ROOT 추론 ───────────────────────────────────────────────────
# 우선순위:
#   1) 환경변수 ORCH_ROOT 명시
#   2) PWD 부터 부모 traverse — .orch 디렉토리가 있는 첫 위치의 ${dir}/.orch
#   3) ${PWD}/.orch (setup 시 새로 생성될 위치)
# 후방호환: 기존 /home/padosol/lol/.orch 가 있고 위 추론이 실패해도 그대로 동작.
_orch_find_root() {
    if [ -n "${ORCH_ROOT:-}" ]; then
        printf '%s' "$ORCH_ROOT"
        return
    fi
    local d="${PWD:-$(pwd)}"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -d "$d/.orch" ]; then
            printf '%s/.orch' "$d"
            return
        fi
        d="$(dirname "$d")"
    done
    # 못 찾음 — 현재 디렉토리에 만들 예정
    printf '%s/.orch' "${PWD:-$(pwd)}"
}
ORCH_ROOT="$(_orch_find_root)"
ORCH_INBOX="${ORCH_ROOT}/inbox"
ORCH_ARCHIVE="${ORCH_ROOT}/archive"
ORCH_WORKERS="${ORCH_ROOT}/workers"
ORCH_SETTINGS="${ORCH_ROOT}/settings.json"
# errors.jsonl 은 caller scope 에 따라 결정 (orch_errors_log_path 참고).
# orch / unknown → ${ORCH_ROOT}/errors.jsonl
# mp-NN, mp-NN/role → ${ORCH_ROOT}/runs/<mp-NN>/errors.jsonl  (mp-down 이 scope dir 째 archive)
ORCH_ERRORS_LOG="${ORCH_ROOT}/errors.jsonl"  # legacy compat — 신규 코드는 orch_errors_log_path 사용
ORCH_RUNS_DIR="${ORCH_ROOT}/runs"

ORCH_LEADER_PATTERN='^mp-[0-9]+$'
ORCH_WORKER_PATTERN='^mp-[0-9]+/[a-zA-Z0-9_-]+$'

# tmux 세션 — 호출자가 살아있는 세션을 따라간다.
# fallback 우선순위: env ORCH_TMUX_SESSION > current tmux > base_dir basename > "orch"
if [ -z "${ORCH_TMUX_SESSION:-}" ]; then
    if [ -n "${TMUX:-}" ]; then
        ORCH_TMUX_SESSION="$(tmux display-message -p '#S' 2>/dev/null || true)"
    fi
    if [ -z "${ORCH_TMUX_SESSION:-}" ]; then
        # ORCH_ROOT 의 부모 디렉토리 basename 사용 — base_dir 을 세션명으로 자연 연결
        _orch_base="$(dirname "$ORCH_ROOT")"
        ORCH_TMUX_SESSION="${_orch_base##*/}"
        unset _orch_base
    fi
    [ -z "${ORCH_TMUX_SESSION:-}" ] && ORCH_TMUX_SESSION="orch"
fi

# ─── Worker ID 파싱 ───────────────────────────────────────────────────

# 출력: orch | leader | worker | invalid (항상 exit 0 — 호출자가 case로 분기)
orch_wid_kind() {
    local w="$1"
    if [ "$w" = "orch" ]; then printf 'orch'
    elif [[ "$w" =~ $ORCH_LEADER_PATTERN ]]; then printf 'leader'
    elif [[ "$w" =~ $ORCH_WORKER_PATTERN ]]; then printf 'worker'
    else printf 'invalid'
    fi
}

# scope: orch→empty, mp-NN→mp-NN, mp-NN/x→mp-NN
orch_wid_scope() {
    local w="$1" kind
    kind="$(orch_wid_kind "$w")"
    case "$kind" in
        leader|worker) printf '%s' "${w%%/*}" ;;
        *)             printf '' ;;
    esac
}

# role: worker만 의미있음 (mp-NN/server → server)
orch_wid_role() {
    local w="$1" kind
    kind="$(orch_wid_kind "$w")"
    case "$kind" in
        worker) printf '%s' "${w##*/}" ;;
        *)      printf '' ;;
    esac
}

orch_is_valid_worker_id() {
    [ "$(orch_wid_kind "$1")" != "invalid" ]
}

# 자기 worker_id 확인. 우선순위:
#   1) $ORCH_WORKER_ID (신규 표준)
#   2) $LOL_WORKER_ID  (후방호환 — 기존 워커 세션)
#   3) registry pane_id 역검색
# v1의 cwd 추론은 버그 원인이라 제거.
orch_detect_self() {
    local env_wid="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
    if [ -n "$env_wid" ] && orch_is_valid_worker_id "$env_wid"; then
        printf '%s' "$env_wid"
        return 0
    fi
    [ -n "${TMUX_PANE:-}" ] || return 1
    local f wid
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [ "$(jq -r '.pane_id // ""' "$f" 2>/dev/null)" = "$TMUX_PANE" ]; then
            wid="$(jq -r '.worker_id // ""' "$f" 2>/dev/null)"
            [ -n "$wid" ] && { printf '%s' "$wid"; return 0; }
        fi
    done < <(find "$ORCH_ROOT" -path "*/workers/*.json" 2>/dev/null)
    return 1
}

# 이슈 ID 정규화 (MP-13 / mp-13 / 13 → mp-13)
orch_normalize_issue_id() {
    local lower="${1,,}"
    if [[ "$lower" =~ ^mp-[0-9]+$ ]]; then
        printf '%s' "$lower"
    elif [[ "$lower" =~ ^[0-9]+$ ]]; then
        printf 'mp-%s' "$lower"
    else
        return 1
    fi
}

# ─── 경로 헬퍼 (scope-aware) ──────────────────────────────────────────

orch_inbox_path() {
    local w="$1" kind scope
    kind="$(orch_wid_kind "$w" 2>/dev/null || true)"
    case "$kind" in
        orch|leader)
            printf '%s/%s.md' "$ORCH_INBOX" "$w" ;;
        worker)
            scope="$(orch_scope_dir "${w%%/*}")" || return 1
            printf '%s/inbox/%s.md' "$scope" "${w##*/}" ;;
        *) return 1 ;;
    esac
}

orch_archive_path() {
    local w="$1" kind scope
    kind="$(orch_wid_kind "$w" 2>/dev/null || true)"
    case "$kind" in
        orch)
            # orch 는 어느 MP 와도 안 묶이므로 top-level 보존
            printf '%s/%s-%s.md' "$ORCH_ARCHIVE" "$w" "$(date +%Y-%m-%d)" ;;
        leader)
            # leader 메시지 archive 는 자기 scope dir 안에 — mp-down 이 scope 째 archive
            scope="$(orch_scope_dir "$w")" || return 1
            printf '%s/leader-archive.md' "$scope" ;;
        worker)
            scope="$(orch_scope_dir "${w%%/*}")" || return 1
            printf '%s/archive/%s-%s.md' "$scope" "${w##*/}" "$(date +%Y-%m-%d)" ;;
        *) return 1 ;;
    esac
}

orch_worker_path() {
    local w="$1" kind scope
    kind="$(orch_wid_kind "$w" 2>/dev/null || true)"
    case "$kind" in
        orch|leader)
            printf '%s/%s.json' "$ORCH_WORKERS" "$w" ;;
        worker)
            scope="$(orch_scope_dir "${w%%/*}")" || return 1
            printf '%s/workers/%s.json' "$scope" "${w##*/}" ;;
        *) return 1 ;;
    esac
}

# scope 디렉토리 (mp-13 sandbox 전체).
# PAD-3: `.orch/runs/<scope>/` 가 신규 위치. legacy `.orch/<scope>/` 도 fallback 으로 유지.
# 결정 순서:
#   1) runs/<scope> 디렉토리 존재 → runs path
#   2) legacy <scope> 디렉토리 존재 → legacy path (PAD-3 이전 활성 MP)
#   3) 둘 다 없음 → runs path (mp-up 이 mkdir 할 위치)
orch_scope_dir() {
    local s="$1"
    [[ "$s" =~ $ORCH_LEADER_PATTERN ]] || return 1
    local new_path="$ORCH_RUNS_DIR/$s"
    if [ -d "$new_path" ]; then
        printf '%s' "$new_path"; return 0
    fi
    local legacy_path="$ORCH_ROOT/$s"
    if [ -d "$legacy_path" ]; then
        printf '%s' "$legacy_path"; return 0
    fi
    printf '%s' "$new_path"
}

orch_scope_worktrees_dir() {
    local s="$1"
    local scope
    scope="$(orch_scope_dir "$s")" || return 1
    printf '%s/worktrees' "$scope"
}

# ─── settings.json 로더 (jq 의존) ─────────────────────────────────────

orch_settings_exists() {
    [ -f "$ORCH_SETTINGS" ]
}

orch_settings_require() {
    if ! orch_settings_exists; then
        echo "ERROR: $ORCH_SETTINGS 없음 — 먼저 /orch:setup 으로 생성하세요" >&2
        return 1
    fi
}

# 프로젝트 alias 목록
orch_settings_projects() {
    orch_settings_require || return 1
    jq -r '.projects | keys[]' "$ORCH_SETTINGS"
}

# 프로젝트 단일 필드 (path, kind, description, tech_stack)
orch_settings_project_field() {
    local project="$1" field="$2"
    orch_settings_require || return 1
    jq -r --arg p "$project" --arg f "$field" '
        if .projects[$p] == null then ""
        elif .projects[$p][$f] == null then ""
        elif (.projects[$p][$f] | type) == "array" then .projects[$p][$f] | join(", ")
        else .projects[$p][$f] | tostring end
    ' "$ORCH_SETTINGS"
}

orch_settings_global() {
    local field="$1"
    orch_settings_require || return 1
    jq -r --arg f "$field" '.[$f] // ""' "$ORCH_SETTINGS"
}

orch_settings_project_exists() {
    local project="$1"
    orch_settings_exists || return 1
    [ "$(jq -r --arg p "$project" '.projects[$p] // empty' "$ORCH_SETTINGS")" != "" ]
}

# 프로젝트의 기본 브랜치 결정 — projects.<alias>.default_base_branch > global default_base_branch > "develop".
# 모든 워크스페이스가 develop 플로우는 아니다 (예: lol-db-schema 는 main). 프로젝트별 override 가
# 핵심 안전장치 — 없으면 leader-spawn 이 origin/develop fetch 에서 silently fail 한 뒤 worktree
# add 가 'fatal: invalid reference: origin/develop' 로 죽는다 (PAD-6).
orch_settings_project_base_branch() {
    local project="$1"
    orch_settings_require || return 1
    local override global
    override="$(orch_settings_project_field "$project" default_base_branch 2>/dev/null || true)"
    if [ -n "$override" ]; then
        printf '%s' "$override"
        return 0
    fi
    global="$(orch_settings_global default_base_branch 2>/dev/null || true)"
    if [ -n "$global" ]; then
        printf '%s' "$global"
        return 0
    fi
    printf 'develop'
}

# ─── Worker registry ──────────────────────────────────────────────────

# 인자: worker_id, kind, window_id, pane_id, cwd
orch_worker_register() {
    local wid="$1" kind="$2" window_id="$3" pane_id="$4" cwd="$5"
    local path scope scope_json
    path="$(orch_worker_path "$wid")" || return 1
    mkdir -p "$(dirname "$path")"
    scope="$(orch_wid_scope "$wid")"
    if [ -n "$scope" ] && [ "$scope" != "$wid" ]; then
        scope_json="\"$scope\""
    else
        scope_json="null"
    fi
    cat >"$path" <<EOF
{
  "worker_id": "${wid}",
  "kind": "${kind}",
  "scope": ${scope_json},
  "window_id": "${window_id}",
  "pane_id": "${pane_id}",
  "cwd": "${cwd}",
  "started_at": "$(date -Iseconds)"
}
EOF
}

orch_worker_field() {
    local wid="$1" field="$2" path
    path="$(orch_worker_path "$wid")" || return 1
    [ -f "$path" ] || return 1
    jq -r --arg f "$field" '.[$f] // empty' "$path"
}

orch_worker_unregister() {
    local wid="$1" path
    path="$(orch_worker_path "$wid")" || return 0
    rm -f "$path"
}

orch_worker_exists() {
    local wid="$1" path
    path="$(orch_worker_path "$wid")" || return 1
    [ -f "$path" ]
}

# 살아있는 leader 목록
orch_active_leaders() {
    [ -d "$ORCH_WORKERS" ] || return 0
    local f
    for f in "$ORCH_WORKERS"/mp-*.json; do
        [ -f "$f" ] || continue
        basename "$f" .json
    done
}

# 특정 leader 산하 worker_id 목록 (mp-NN/role 형식)
orch_active_sub_workers() {
    local scope="$1"
    local scope_dir
    scope_dir="$(orch_scope_dir "$scope")" || return 0
    local dir="$scope_dir/workers"
    [ -d "$dir" ] || return 0
    local f
    for f in "$dir"/*.json; do
        [ -f "$f" ] || continue
        printf '%s/%s\n' "$scope" "$(basename "$f" .json)"
    done
}

orch_pane_alive() {
    local pane_id="$1"
    [ -n "$pane_id" ] || return 1
    tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane_id"
}

# ─── tmux pane 조작 ───────────────────────────────────────────────────

# 현재 pane이 속한 윈도우에 split. 출력: "<window_id> <pane_id>"
orch_split_in_current_window() {
    local cwd="$1"
    [ -n "${TMUX_PANE:-}" ] || { echo "ERROR: tmux 안에서 실행해야 합니다 (TMUX_PANE 미설정)" >&2; return 1; }
    local target_window pane_id window_id
    target_window="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}')"
    pane_id="$(tmux split-window -t "$target_window" -P -F '#{pane_id}' -c "$cwd")"
    window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}')"
    tmux select-layout -t "$target_window" tiled >/dev/null 2>&1
    printf '%s %s' "$window_id" "$pane_id"
}

# 새 윈도우 생성. 출력: "<window_id> <pane_id>"
orch_new_window() {
    local name="$1" cwd="$2"
    local pane_id window_id
    pane_id="$(tmux new-window -t "$ORCH_TMUX_SESSION" -n "$name" -c "$cwd" -P -F '#{pane_id}')"
    window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}')"
    printf '%s %s' "$window_id" "$pane_id"
}

# 기존 윈도우에 split. 출력: pane_id
orch_split_in_window() {
    local window_id="$1" cwd="$2"
    local pane_id
    pane_id="$(tmux split-window -t "$window_id" -P -F '#{pane_id}' -c "$cwd")"
    tmux select-layout -t "$window_id" tiled >/dev/null 2>&1
    printf '%s' "$pane_id"
}

# ─── 메시지 / 라우팅 ──────────────────────────────────────────────────

orch_gen_msg_id() {
    printf '%d-%s' "$(date +%s)" "$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 6)"
}

# inbox에 메시지 append (flock 보호). 출력: msg_id
orch_append_message() {
    local from="$1" to="$2" body="$3"
    local id ts target
    id="$(orch_gen_msg_id)"
    ts="$(date -Iseconds)"
    target="$(orch_inbox_path "$to")" || return 1
    mkdir -p "$(dirname "$target")"
    {
        flock -x 9
        printf '\n---\nfrom: %s\nto: %s\nts: %s\nid: %s\n---\n%s\n' \
            "$from" "$to" "$ts" "$id" "$body" >>"$target"
    } 9>"${target}.lock"
    printf '%s' "$id"
}

# 2-tier 라우팅 정책 검사. OK=0, 차단=1.
orch_route_check() {
    local from="$1" to="$2"
    if [ "$from" = "$to" ]; then
        echo "ERROR: '$from' 가 자기 자신에게 보낼 수 없음" >&2
        return 1
    fi
    local fk tk fs ts
    fk="$(orch_wid_kind "$from")"
    tk="$(orch_wid_kind "$to")"
    fs="$(orch_wid_scope "$from")"
    ts="$(orch_wid_scope "$to")"

    if [ "$fk" = "invalid" ]; then
        echo "ERROR: 보낸이 worker_id 형식 오류: '$from'" >&2; return 1
    fi
    if [ "$tk" = "invalid" ]; then
        echo "ERROR: 받는이 worker_id 형식 오류: '$to'" >&2; return 1
    fi

    case "${fk} ${tk}" in
        "orch leader"|"leader orch")
            return 0 ;;
        "leader worker")
            [ "$fs" = "$ts" ] && return 0
            echo "ERROR: cross-MP 통신 차단 ('$from' → '$to')" >&2; return 1 ;;
        "worker leader")
            [ "$fs" = "$ts" ] && return 0
            echo "ERROR: 다른 MP의 leader에 직접 송신 차단 ('$from' → '$to')" >&2; return 1 ;;
        "leader leader")
            echo "ERROR: cross-MP 통신 차단 — leader끼리 직접 송신 안 됨 ('$from' → '$to')" >&2
            return 1 ;;
        "worker worker")
            echo "ERROR: 워커끼리 직접 송신 차단 — leader('$fs') 경유 필요" >&2
            return 1 ;;
        "worker orch")
            echo "ERROR: 워커는 orch에 직접 보낼 수 없음 — leader('$fs') 경유 필요" >&2
            return 1 ;;
        "orch worker")
            echo "ERROR: orch는 워커에 직접 송신 불가 — leader('$ts') 에 위임" >&2
            return 1 ;;
        *)
            echo "ERROR: 알 수 없는 라우팅 ($fk → $tk)" >&2; return 1 ;;
    esac
}

# 타겟 worker pane에 /orch:check-inbox <msg_id> 알림 (단건 본문 모드 직진입)
# 인자: to=worker_id, msg_id=방금 append 된 메시지 id (옵셔널 — 없으면 요약 모드 fallback)
orch_notify() {
    local to="$1"
    local msg_id="${2:-}"
    if ! tmux has-session -t "$ORCH_TMUX_SESSION" 2>/dev/null; then
        echo "WARN: tmux 세션 '$ORCH_TMUX_SESSION' 없음 — 메시지는 inbox에 저장됐지만 실시간 알림 못 함" >&2
        return 0
    fi
    local pane_id
    pane_id="$(orch_worker_field "$to" pane_id 2>/dev/null || true)"
    if [ -z "$pane_id" ]; then
        echo "WARN: '$to' 워커가 등록 안 됨 — 메시지는 inbox에 저장됐지만 받을 사람 없음" >&2
        return 0
    fi
    if ! orch_pane_alive "$pane_id"; then
        echo "WARN: '$to' 워커의 pane($pane_id)이 죽었음 — registry 정리 후 메시지만 보존" >&2
        orch_worker_unregister "$to"
        return 0
    fi
    local cmd='/orch:check-inbox'
    [ -n "$msg_id" ] && cmd="${cmd} ${msg_id}"
    orch_send_keys_line "$pane_id" "$cmd" \
        || echo "WARN: '$to' (pane=$pane_id) 에 ${cmd} 전달 실패" >&2
}

# pane 에 한 줄 전송 (텍스트 + Enter). race / copy-mode 흡수 방지.
# 1) copy-mode 또는 status-line modal 이면 cancel — 없으면 노옵
# 2) 텍스트 송신 → 짧게 sleep → 별도 호출로 Enter
# 3) Enter 가 첫 호출에 흡수되는 사례 보고 잦아서 두 단계 분리는 의도적
# 반환: 0=텍스트·Enter 둘 다 성공, 1=둘 중 하나라도 실패
orch_send_keys_line() {
    local pane_id="$1" text="$2"
    [ -n "$pane_id" ] || return 1
    tmux send-keys -t "$pane_id" -X cancel 2>/dev/null || true
    sleep 0.1
    tmux send-keys -t "$pane_id" -- "$text" 2>/dev/null || return 1
    sleep 0.15
    tmux send-keys -t "$pane_id" Enter 2>/dev/null || return 1
    return 0
}

# ─── inbox 통계 ───────────────────────────────────────────────────────

orch_inbox_count() {
    local path n
    path="$(orch_inbox_path "$1" 2>/dev/null)" || { printf '0'; return; }
    if [ ! -s "$path" ]; then printf '0'; return; fi
    n="$(grep -c '^---$' "$path" 2>/dev/null || true)"
    printf '%d' "$(( n / 2 ))"
}

orch_inbox_mtime() {
    local path
    path="$(orch_inbox_path "$1" 2>/dev/null)" || { printf -- '-'; return; }
    if [ -s "$path" ]; then
        date -r "$path" '+%Y-%m-%d %H:%M:%S'
    else
        printf -- '-'
    fi
}

# ─── worktree cleanup ────────────────────────────────────────────────
# mp-down 시 산하 워커의 머지된 브랜치 worktree 만 자동 정리. 미머지·dirty 는 보존.

# orch_branch_merged <project_path> <branch> <base_branch>
# 머지 확인. gh PR(squash/rebase 포함) → git merge commit 순으로 검사. 0=merged, 1=not.
orch_branch_merged() {
    local project_path="$1" branch="$2" base="$3"
    [ -d "$project_path" ] || return 1

    if command -v gh >/dev/null 2>&1; then
        local merged_count
        merged_count="$(cd "$project_path" 2>/dev/null && gh pr list --state merged --head "$branch" --limit 1 --json number --jq 'length' 2>/dev/null || true)"
        if [ "${merged_count:-0}" -gt 0 ]; then
            return 0
        fi
    fi

    git -C "$project_path" fetch origin "$base" --quiet 2>/dev/null || true
    if git -C "$project_path" branch -r --merged "origin/$base" 2>/dev/null \
        | sed 's/^[[:space:]*]*//' | grep -qx "origin/${branch}"; then
        return 0
    fi
    return 1
}

# orch_worktree_cleanup <project_path> <worktree_path> <branch>
# 안전 삭제: dirty(미커밋·untracked) 면 SKIP, 로컬 브랜치는 git branch -d (소문자) 로 unmerged 보호.
orch_worktree_cleanup() {
    local project_path="$1" worktree_path="$2" branch="$3"

    if [ -d "$worktree_path" ]; then
        local dirty
        dirty="$(git -C "$worktree_path" status --porcelain 2>/dev/null)"
        if [ -n "$dirty" ]; then
            echo "    WARN: $worktree_path 에 미커밋/미추적 변경 있음 — 보존" >&2
            return 1
        fi
        if ! git -C "$project_path" worktree remove "$worktree_path" 2>/dev/null; then
            echo "    WARN: worktree remove 실패: $worktree_path" >&2
            return 1
        fi
    fi

    if git -C "$project_path" show-ref --verify --quiet "refs/heads/$branch"; then
        if ! git -C "$project_path" branch -d "$branch" 2>/dev/null; then
            echo "    WARN: 로컬 브랜치 '$branch' 삭제 거부 (-d 가 unmerged 보호) — 보존" >&2
            return 1
        fi
    fi
    return 0
}

# orch_cleanup_merged_worktrees <mp_id>
# mp 산하 워커 worktree 들 중 base 에 머지된 것만 정리. stdout 에 한 줄씩 결과 출력.
orch_cleanup_merged_worktrees() {
    local mp_id="$1"

    if ! orch_settings_exists; then
        echo "  cleanup skip: settings.json 없음"
        return 0
    fi

    local base_branch
    base_branch="$(orch_settings_global default_base_branch 2>/dev/null || true)"
    [ -n "$base_branch" ] || base_branch="develop"

    local sub_wid role worktree_path project_path branch any=0
    declare -A pulled_paths=()
    for sub_wid in $(orch_active_sub_workers "$mp_id"); do
        any=1
        role="${sub_wid##*/}"
        worktree_path="$(orch_worker_field "$sub_wid" cwd 2>/dev/null || true)"
        if [ -z "$worktree_path" ] || [ ! -d "$worktree_path" ]; then
            echo "  cleanup skip $sub_wid: worktree 경로 없음"
            continue
        fi

        project_path="$(orch_settings_project_field "$role" path 2>/dev/null || true)"
        if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
            echo "  cleanup skip $sub_wid: settings.json 의 project '$role' path 없음"
            continue
        fi

        # base 머지 검사 정확도를 위해 project_path 에서 base 를 최신화 (project당 1회)
        if [ -z "${pulled_paths[$project_path]+x}" ]; then
            git -C "$project_path" fetch origin "$base_branch" >/dev/null 2>&1 || true
            if git -C "$project_path" pull --ff-only origin "$base_branch" >/dev/null 2>&1; then
                echo "  pull OK $project_path (origin/$base_branch)"
            else
                echo "  pull skip $project_path (ff-only 불가 — dirty 또는 분기 — 머지 검사가 부정확할 수 있음)"
            fi
            pulled_paths[$project_path]=1
        fi

        branch="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
            echo "  cleanup skip $sub_wid: 현재 브랜치 미상"
            continue
        fi

        if orch_branch_merged "$project_path" "$branch" "$base_branch"; then
            if orch_worktree_cleanup "$project_path" "$worktree_path" "$branch"; then
                echo "  cleanup OK $sub_wid: $branch → $base_branch 머지 확인, worktree+local branch 정리"
            else
                echo "  cleanup partial $sub_wid: 머지됐지만 정리 도중 일부 실패 (위 WARN)"
            fi
        else
            echo "  cleanup keep $sub_wid: $branch 미머지 또는 검출 실패 — worktree 보존 ($worktree_path)"
        fi
    done
    [ "$any" -eq 0 ] && echo "  cleanup: 산하 워커 등록 없음 — skip"
    return 0
}

# ─── 에러 로깅 ─────────────────────────────────────────────────────────
# 어느 스크립트든 실패하면 한 줄 JSON 으로 추적용 로그 남긴다.
# scope-aware: orch / unknown 은 top-level errors.jsonl,
# mp-NN, mp-NN/role 은 .orch/<mp-NN>/errors.jsonl (mp-down 이 scope 째 archive 함).

# orch_errors_log_path [<wid>] — 호출자 worker_id 기반 errors.jsonl 경로 결정.
# 인자 없으면 ORCH_WORKER_ID(또는 LOL_WORKER_ID 후방호환) → orch_detect_self 순으로 추론.
orch_errors_log_path() {
    local wid="${1:-}"
    [ -z "$wid" ] && wid="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
    [ -z "$wid" ] && wid="$(orch_detect_self 2>/dev/null || true)"
    local scope scope_dir
    scope="$(orch_wid_scope "$wid" 2>/dev/null || true)"
    if [ -n "$scope" ]; then
        scope_dir="$(orch_scope_dir "$scope")" || { printf '%s/errors.jsonl' "$ORCH_ROOT"; return; }
        printf '%s/errors.jsonl' "$scope_dir"
    else
        printf '%s/errors.jsonl' "$ORCH_ROOT"
    fi
}

orch_log_error() {
    # 인자: <source-script> <exit_code> <stderr_text>
    local src="${1:-unknown}" rc="${2:-?}" stderr_text="${3:-}"
    local wid="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
    [ -z "$wid" ] && wid="$(orch_detect_self 2>/dev/null || true)"
    [ -z "$wid" ] && wid="unknown"

    local log_path
    log_path="$(orch_errors_log_path "$wid")"
    mkdir -p "$(dirname "$log_path")" 2>/dev/null || true
    local ts
    ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

    # stderr 너무 길면 자르고 (8KB), null 바이트 제거
    stderr_text="$(printf '%s' "$stderr_text" | tr -d '\0' | tail -c 8192)"

    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg ts "$ts" \
            --arg wid "$wid" \
            --arg src "$src" \
            --arg rc "$rc" \
            --arg err "$stderr_text" \
            '{ts:$ts, worker_id:$wid, script:$src, exit_code:($rc|tonumber? // $rc), stderr:$err}' \
            >> "$log_path" 2>/dev/null || true
    else
        local esc_err
        esc_err="$(printf '%s' "$stderr_text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')"
        printf '{"ts":"%s","worker_id":"%s","script":"%s","exit_code":%s,"stderr":"%s"}\n' \
            "$ts" "$wid" "$src" "$rc" "$esc_err" >> "$log_path" 2>/dev/null || true
    fi
}

# 모든 errors.jsonl 모으기 — top-level + 모든 mp-*/errors.jsonl (live + archive).
# stdout 으로 한 줄 JSON 들 출력. /orch:errors 가 사용.
# PAD-3 이후: 신규 위치 runs/mp-*/ 와 후방호환 평탄 mp-*/ 둘 다 스캔.
orch_collect_all_errors() {
    [ -f "$ORCH_ERRORS_LOG" ] && cat "$ORCH_ERRORS_LOG" 2>/dev/null
    local f
    for f in "$ORCH_RUNS_DIR"/mp-*/errors.jsonl; do
        [ -f "$f" ] && cat "$f" 2>/dev/null
    done
    for f in "$ORCH_ROOT"/mp-*/errors.jsonl; do
        [ -f "$f" ] && cat "$f" 2>/dev/null
    done
    for f in "$ORCH_ARCHIVE"/mp-*/errors.jsonl; do
        [ -f "$f" ] && cat "$f" 2>/dev/null
    done
    return 0
}

# orch_install_error_trap — 호출한 스크립트의 비0 종료를 자동으로 errors.jsonl 에 기록.
# 사용: 스크립트 상단에 source lib.sh 직후 orch_install_error_trap "$0"
# stderr 를 임시 파일에 미러링한 뒤 EXIT 시 비0 이면 그 내용을 로그한다.
orch_install_error_trap() {
    local src="${1:-$0}"
    local src_base
    src_base="$(basename "$src" .sh)"
    local stderr_buf
    stderr_buf="$(mktemp -t "orch-stderr-${src_base}-XXXXXX")" || return 0
    export __ORCH_STDERR_BUF="$stderr_buf"
    export __ORCH_SRC="$src_base"
    # tee 로 원래 stderr 와 임시 파일에 동시 기록
    exec 2> >(tee -a "$stderr_buf" >&2)
    trap '__rc=$?
        if [ "$__rc" -ne 0 ] && [ -n "${__ORCH_STDERR_BUF:-}" ]; then
            orch_log_error "${__ORCH_SRC:-unknown}" "$__rc" "$(cat "$__ORCH_STDERR_BUF" 2>/dev/null || true)"
        fi
        [ -n "${__ORCH_STDERR_BUF:-}" ] && rm -f "$__ORCH_STDERR_BUF" 2>/dev/null
        exit $__rc' EXIT
}
