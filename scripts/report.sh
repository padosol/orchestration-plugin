#!/usr/bin/env bash
# /orch:report <mp-id>
# MP 운영 데이터를 모아 markdown 으로 stdout 에 출력. orch 가 이걸 읽어 REPORT.md 작성.
# 활성 scope (.orch/runs/<mp_id>/ 또는 legacy .orch/<mp_id>/) 또는 가장 최근 archive
# (.orch/archive/<mp_id>-YYYY-MM-DD/) 중 하나를 자동 선택.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    echo "사용법: /orch:report <mp-id>" >&2
    exit 2
fi

raw_id="$1"
mp_id="$(orch_normalize_issue_id "$raw_id" || true)"
[ -z "$mp_id" ] && { echo "ERROR: issue-id '$raw_id' 정규화 실패" >&2; exit 2; }

# scope 위치 결정
scope_dir=""
scope_kind=""
live_scope="$(orch_scope_dir "$mp_id" 2>/dev/null || true)"
if [ -n "$live_scope" ] && [ -d "$live_scope" ]; then
    scope_dir="$live_scope"
    scope_kind="live"
else
    # 가장 최근 archive 찾기 (디렉토리만, .md 파일 제외)
    latest="$(find "$ORCH_ARCHIVE" -maxdepth 1 -type d -name "${mp_id}-*" 2>/dev/null | sort | tail -n1)"
    if [ -n "$latest" ] && [ -d "$latest" ]; then
        scope_dir="$latest"
        scope_kind="archive"
    fi
fi

if [ -z "$scope_dir" ]; then
    echo "ERROR: $mp_id 의 scope 디렉토리 못 찾음 (live 또는 archive)" >&2
    exit 2
fi

encode_cwd() {
    local c="$1"
    c="${c//\//-}"
    c="${c//./-}"
    printf '%s' "$c"
}

# 토큰·도구 분석 — 한 jsonl 또는 디렉토리의 모든 jsonl 합산.
# 인자: cwd  [started_iso]
# started_iso 가 주어지면 그 시각 이후 record 만 집계 — 같은 cwd 에 여러 워커 세션이 섞여
# 있는 경우 (특히 reviewer 가 lol-server 같은 베이스 cwd 를 공유) 토큰 분리에 사용.
analyze_jsonls() {
    local cwd="$1" since="${2:-}"
    local enc dir
    enc="$(encode_cwd "$cwd")"
    dir="$HOME/.claude/projects/$enc"

    local args=("$dir")
    if [ -n "$since" ]; then
        args+=(--since "$since")
    fi
    python3 "${LIB_DIR}/analyze-jsonls.py" "${args[@]}"
}

worker_section() {
    local sub_wid="$1" registry="$2"
    local role
    role="${sub_wid##*/}"

    printf '\n### %s\n\n' "$sub_wid"
    if [ ! -f "$registry" ]; then
        printf '_(registry 파일 없음: %s)_\n' "$registry"
        return 0
    fi

    local cwd started_at pane_id window_id
    cwd="$(jq -r '.cwd // ""' "$registry")"
    started_at="$(jq -r '.started_at // ""' "$registry")"
    pane_id="$(jq -r '.pane_id // ""' "$registry")"
    window_id="$(jq -r '.window_id // ""' "$registry")"

    printf -- '- registry: %s\n' "$registry"
    printf -- '- cwd: %s\n' "$cwd"
    printf -- '- pane/window: %s / %s\n' "$pane_id" "$window_id"
    printf -- '- started_at: %s\n' "$started_at"

    # worktree 상태
    if [ -d "$cwd" ]; then
        local branch base diff_stat git_log
        branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
        base="$(orch_settings_global default_base_branch 2>/dev/null || echo develop)"
        printf -- '- worktree: 살아있음\n'
        printf -- '- branch: %s (base: origin/%s)\n' "$branch" "$base"
        printf -- '- diff stat (origin/%s..HEAD):\n' "$base"
        diff_stat="$(git -C "$cwd" diff "origin/$base..HEAD" --stat 2>/dev/null | sed 's/^/    /' || true)"
        if [ -n "$diff_stat" ]; then printf '%s\n' "$diff_stat"; else printf '    _(diff 비어있거나 base ref 없음)_\n'; fi
        printf -- '- commits (origin/%s..HEAD):\n' "$base"
        git_log="$(git -C "$cwd" log "origin/$base..HEAD" --oneline 2>/dev/null | sed 's/^/    /' || true)"
        if [ -n "$git_log" ]; then printf '%s\n' "$git_log"; else printf '    _(no commits)_\n'; fi
    else
        printf -- '- worktree: 삭제됨 또는 archive 안에 (%s)\n' "$cwd"
    fi

    printf '\n#### 토큰·도구 분석 (cwd 기준 jsonl 스캔, since=worker started_at)\n\n'
    analyze_jsonls "$cwd" "$started_at"
}

# ─── 출력 시작 ─────────────────────────────────────────────────────

cat <<EOF
# ${mp_id} 운영 데이터 덤프

이 문서는 \`/orch:report\` 가 모은 **원본 데이터** 입니다. orch 가 이를 읽어 \`${scope_dir}/REPORT.html\` 에 한국어 회고를 단순 inline-css 시각화로 작성하세요.

## 메타

- mp_id: ${mp_id}
- scope: \`${scope_dir}\` (${scope_kind})
- 생성 시각: $(date -Iseconds)
EOF

# leader registry (live 면 ORCH_WORKERS, archive 면 거의 없음)
leader_json="$ORCH_WORKERS/$mp_id.json"
if [ -f "$leader_json" ]; then
    started="$(jq -r '.started_at // ""' "$leader_json")"
    pane="$(jq -r '.pane_id // ""' "$leader_json")"
    win="$(jq -r '.window_id // ""' "$leader_json")"
    printf -- '- leader registry: live (started %s, pane %s, window %s)\n' "$started" "$pane" "$win"
else
    printf -- '- leader registry: 없음 (이미 archive)\n'
fi

# 산하 워커 리스트
printf '\n## 산하 워커\n\n'
sub_workers=()
if [ "$scope_kind" = "live" ]; then
    while IFS= read -r w; do
        [ -n "$w" ] && sub_workers+=("$w")
    done < <(orch_active_sub_workers "$mp_id")
fi

# archive 의 workers 도 스캔 (또는 live 라도 보충).
# workers/ = 살아있는 워커 등록, workers-archive/ = self-shutdown 후 보존된 워커.
workers_dir="$scope_dir/workers"
workers_archive_dir="$scope_dir/workers-archive"
for d in "$workers_dir" "$workers_archive_dir"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.json; do
        [ -f "$f" ] || continue
        role="$(basename "$f" .json)"
        wid="$mp_id/$role"
        # 중복 제거
        already=0
        for sw in "${sub_workers[@]+"${sub_workers[@]}"}"; do
            [ "$sw" = "$wid" ] && already=1 && break
        done
        [ "$already" -eq 0 ] && sub_workers+=("$wid")
    done
done

if [ "${#sub_workers[@]}" -eq 0 ]; then
    printf '_(산하 워커 등록 없음)_\n'
else
    printf '%s\n' "${sub_workers[@]}" | sed 's/^/- /'
fi

# 워커별 상세
printf '\n## 워커별 상세\n'
for sub_wid in "${sub_workers[@]+"${sub_workers[@]}"}"; do
    role="${sub_wid##*/}"
    # registry 위치: 살아있는 워커는 <scope>/workers/, 종료된 워커는 <scope>/workers-archive/.
    # archive 모드에선 둘 다 archive_dir 안에서 찾는다 (scope_dir 통째로 mv 됐기 때문).
    if [ -f "$workers_dir/$role.json" ]; then
        reg="$workers_dir/$role.json"
    elif [ -f "$workers_archive_dir/$role.json" ]; then
        reg="$workers_archive_dir/$role.json"
    else
        reg="$workers_dir/$role.json"
    fi
    worker_section "$sub_wid" "$reg"
done

# 인박스/아카이브 메시지
printf '\n## 인박스 / 아카이브 메시지 흐름\n\n'
inbox_dir="$scope_dir/inbox"
archive_msg_dir="$scope_dir/archive"

count_msgs() {
    local f="$1"
    if [ ! -f "$f" ]; then echo 0; return; fi
    local n
    n="$(grep -c '^---$' "$f" 2>/dev/null || true)"
    [ -z "$n" ] && n=0
    echo $((n / 2))
}

if [ -d "$inbox_dir" ]; then
    for f in "$inbox_dir"/*.md; do
        [ -f "$f" ] || continue
        role="$(basename "$f" .md)"
        n="$(count_msgs "$f")"
        printf -- '- inbox/%s.md: 미처리 %s건\n' "$role" "$n"
    done
fi
if [ -d "$archive_msg_dir" ]; then
    for f in "$archive_msg_dir"/*.md; do
        [ -f "$f" ] || continue
        role="$(basename "$f" .md)"
        n="$(count_msgs "$f")"
        printf -- '- archive/%s: 처리완료 %s건\n' "$(basename "$f")" "$n"
    done
fi

# orch / leader top-level 인박스/아카이브 (mp-NN 키)
printf '\n### top-level 메시지 (orch ↔ leader)\n\n'
for f in "$ORCH_INBOX/$mp_id.md" "$ORCH_ARCHIVE/$mp_id-"*.md; do
    [ -f "$f" ] || continue
    n="$(count_msgs "$f")"
    printf -- '- %s: %s건\n' "$f" "$n"
done

# 에러 (이 MP scope 의 errors.jsonl)
printf '\n## 에러 로그 (이 MP scope)\n\n'
scope_errors="$scope_dir/errors.jsonl"
if [ ! -s "$scope_errors" ]; then
    # legacy fallback — 옛 mp 는 top-level errors.jsonl 에 worker_id 로 filter
    if [ -s "$ORCH_ERRORS_LOG" ]; then
        legacy_count="$(jq -s --arg mp "$mp_id" '[.[] | select(.worker_id == $mp or (.worker_id | startswith($mp + "/")))] | length' "$ORCH_ERRORS_LOG" 2>/dev/null || echo 0)"
        if [ "$legacy_count" != "0" ]; then
            printf -- '- legacy top-level errors.jsonl 에서 %s건 발견:\n\n' "$legacy_count"
            jq -r --arg mp "$mp_id" '
                select(.worker_id == $mp or (.worker_id | startswith($mp + "/")))
                | "[\(.ts)] \(.worker_id) · \(.script) (rc=\(.exit_code))\n  \((.stderr // "") | split("\n")[0:3] | map("    " + .) | join("\n"))"
            ' "$ORCH_ERRORS_LOG"
        else
            printf '_(scope errors.jsonl 없음, top-level 에서도 이 MP 관련 entry 없음)_\n'
        fi
    else
        printf '_(scope errors.jsonl 없음)_\n'
    fi
else
    err_count="$(grep -c . "$scope_errors" 2>/dev/null || echo 0)"
    printf -- '- %s 에서 %s건\n\n' "$scope_errors" "$err_count"
    jq -r '
        "[\(.ts)] \(.worker_id) · \(.script) (rc=\(.exit_code))\n  \((.stderr // "") | split("\n")[0:3] | map("    " + .) | join("\n"))"
    ' "$scope_errors"
fi

# PR 드래프트 / 부산물
printf '\n## 부산물 (pr-drafts, reports 등)\n\n'
for sub in pr-drafts reports; do
    d="$scope_dir/$sub"
    if [ -d "$d" ]; then
        printf -- '- %s/:\n' "$sub"
        ls -1 "$d" 2>/dev/null | sed 's/^/    /'
    fi
done

cat <<EOF

---

## 이 데이터를 REPORT.html 로 변환하는 절차 (orch 만 수행)

위 원본을 **해석**해 7개 섹션의 한국어 회고로 요약하되, HTML 을 직접 작성하지 말 것. 매번 양식이 달라지는 문제를 막기 위해 결정적 템플릿 렌더러가 따로 있음.

**흐름**:

1. 위 raw 데이터를 해석해 **JSON** 으로 정리 (스키마는 \`render_report.py\` 상단 docstring 참조 / 필수 필드는 \`mp_id\` 만, 나머지는 optional). 7개 섹션 콘텐츠를 다음 키에 매핑:
   - summary / changes / as_is_to_be / test_results / token_analysis / handoff / follow_ups / ai_ready_check
2. JSON 을 임시 파일에 저장 (예: \`/tmp/orch-report-${mp_id}.json\`).
3. 렌더러 호출:

   \`\`\`bash
   python3 \${CLAUDE_PLUGIN_ROOT}/scripts/render_report.py \\
     /tmp/orch-report-${mp_id}.json \\
     ${scope_dir}/REPORT.html
   \`\`\`

   HTML 골격·CSS·섹션 순서는 스크립트가 고정. orch 의 작업은 콘텐츠 JSON 까지.

4. 사용자에게 \`${scope_dir}/REPORT.html\` 경로 + 한 줄 요약 보고.

**해석 시 유의**:
- 단순 복붙 X — 데이터를 사용자 관점 narrative 로 풀어쓰기 (특히 summary.narrative / as_is_to_be / observations)
- 토큰 분포에서 Read 가 같은 파일 반복 / 도구 쏠림 보이면 \`token_analysis.observations\` 에 명시적으로 짚기
- 워커 자가보고 인용은 archive 메시지 / pr-drafts / reports 에서 발췌
- 핸드오프 페인포인트는 errors.jsonl + 메시지 흐름의 재질문 빈도로 추정. 없으면 \`handoff.narrative\` 에 "발견된 마찰 없음"

**🚫 cwd 보호 (절대 규칙)**:
- ❌ orch 메인 pane Bash 로 \`cd <repo>\` — pane cwd 가 워크스페이스 루트에서 벗어나면 이후 \`.orch/...\` 상대 경로 / 메일박스 모두 깨짐
- ✅ 다른 repo 정보 → \`git -C <abs-path> ...\` (cd 없이) 또는 단일 파일 \`Read <abs-path>\`

**📦 컨텍스트·비용 보호 (효율 규칙) — 위치 인지로 분기**:
- 위 raw data 에 변경 파일 경로 / commits / diff stat / errors stderr / archive 메시지 다 포함됨. **추가 호출은 위치를 아는지로 분기**:
  - 위치 명확 + 단일/소수 파일 → 메인이 직접 \`Read <abs>\` / \`git -C <abs> ...\` / \`grep <pat> <abs>\` (round-trip 낭비 X)
  - 위치 미상 → \`Agent(subagent_type=Explore)\` 단발
  - 큰 작업 (다파일 grep / 여러 docs 검증) → \`Agent(subagent_type=general-purpose)\` 단발 위임
- ❌ raw data 에 이미 file:line 이 있는데 또 Agent 시켜 다시 찾게 함 — Explore 비용 낭비
- ❌ 단발 Read 한 번이면 끝나는 일을 Agent 위임 — round-trip 낭비
- ✅ orch 메인은 /tmp JSON 작성 / render_report.py 호출 / Linear save_issue / inbox-archive / 위 효율 규칙의 단일 Read·grep·git -C 까지 직접

\`/orch:prioritize\` 의 list/get 위임은 본문 누적이 큰 케이스라 Agent. 이 단계도 같은 기준으로 — 작으면 직접, 크면 Agent.
EOF
