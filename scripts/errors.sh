#!/usr/bin/env bash
# /orch:errors [--tail N] [--analyze] [--mp <id>] [--worker <wid>] [--script <name>] [--clear [--mp <id>]]
# scope-aware errors.jsonl 조회.
#   기본: top-level + 모든 mp-*/errors.jsonl (live + archive) 통합
#   --mp <id>: 그 MP scope 만

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

tail_n=20
do_clear=0
do_analyze=0
filter_worker=""
filter_script=""
filter_mp=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tail) shift; tail_n="${1:?--tail requires N}" ;;
        --clear) do_clear=1 ;;
        --analyze) do_analyze=1 ;;
        --mp) shift; filter_mp="${1:?--mp requires mp-id}" ;;
        --worker) shift; filter_worker="${1:?--worker requires worker_id}" ;;
        --script) shift; filter_script="${1:?--script requires script name}" ;;
        -h|--help)
            cat <<EOF
사용법: /orch:errors [옵션]
  --tail N        마지막 N건만 (기본 20)
  --analyze       script×rc 빈도, worker×script 매트릭스, stderr 그룹 통계
  --mp <id>       특정 MP scope 만 (mp-9 등). 안 주면 top-level + 모든 MP 통합
  --worker <wid>  특정 worker_id 만 필터
  --script <name> 특정 스크립트 만 필터
  --clear         로그 파일 비우기 (확인 프롬프트 후). --mp 와 같이 쓰면 그 MP 만, 아니면 top-level 만.
EOF
            exit 0 ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

# --mp 정규화
if [ -n "$filter_mp" ]; then
    filter_mp="$(orch_normalize_issue_id "$filter_mp" 2>/dev/null || true)"
    if [ -z "$filter_mp" ]; then
        echo "ERROR: --mp 인자 정규화 실패" >&2
        exit 2
    fi
fi

# 데이터 소스 결정
if [ -n "$filter_mp" ]; then
    # 그 MP 의 errors.jsonl (live 또는 archive). PAD-3: runs/ 와 legacy 양쪽.
    candidates=(
        "$(orch_scope_dir "$filter_mp" 2>/dev/null)/errors.jsonl"
        "$ORCH_RUNS_DIR/$filter_mp/errors.jsonl"
        "$ORCH_ROOT/$filter_mp/errors.jsonl"
    )
    # archive 들도 포함 (날짜별)
    while IFS= read -r f; do
        candidates+=("$f")
    done < <(find "$ORCH_ARCHIVE" -maxdepth 2 -path "*/${filter_mp}-*/errors.jsonl" 2>/dev/null)
    sources=()
    for c in "${candidates[@]}"; do
        [ -f "$c" ] && sources+=("$c")
    done
    if [ "${#sources[@]}" -eq 0 ]; then
        echo "에러 로그 없음 (mp=$filter_mp)"
        exit 0
    fi
    raw_input="$(cat "${sources[@]}")"
else
    raw_input="$(orch_collect_all_errors)"
fi

# --clear: top-level 또는 mp scope 비우기
if [ "$do_clear" -eq 1 ]; then
    if [ -n "$filter_mp" ]; then
        target="$(orch_scope_dir "$filter_mp" 2>/dev/null)/errors.jsonl"
    else
        target="$ORCH_ERRORS_LOG"
    fi
    if [ ! -s "$target" ]; then
        echo "이미 비어있음: $target"; exit 0
    fi
    line_count="$(wc -l <"$target")"
    read -r -p "$target ($line_count 건) 비울까요? [y/N] " ans
    case "$ans" in
        y|Y|yes) : >"$target"; echo "비움 완료" ;;
        *) echo "취소" ;;
    esac
    exit 0
fi

if [ -z "$raw_input" ]; then
    echo "에러 로그 비어있음"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq 가 필요합니다" >&2
    exit 2
fi

total="$(printf '%s\n' "$raw_input" | grep -c . || true)"

if [ "$do_analyze" -eq 1 ]; then
    label="전체"
    [ -n "$filter_mp" ] && label="$filter_mp"
    printf '── orch errors --analyze ── (%s, 전체 %d건)\n\n' "$label" "$total"
    [ "$total" -eq 0 ] && exit 0

    printf '[script × exit_code 빈도]\n'
    printf '%s\n' "$raw_input" | jq -s -r '
        group_by([.script, .exit_code])
        | map([.[0].script, (.[0].exit_code|tostring), length])
        | sort_by(-.[2])
        | .[] | @tsv
    ' | awk -F'\t' 'BEGIN{printf "  %-16s %-5s %s\n","script","rc","count"} {printf "  %-16s %-5s %s\n",$1,$2,$3}'
    printf '\n'

    printf '[worker × script 매트릭스]\n'
    printf '%s\n' "$raw_input" | jq -s -r '
        group_by([.worker_id, .script])
        | map([.[0].worker_id, .[0].script, length, (max_by(.ts).ts)])
        | sort_by(-.[2])
        | .[] | @tsv
    ' | awk -F'\t' 'BEGIN{printf "  %-22s %-16s %-6s %s\n","worker_id","script","count","last_ts"} {printf "  %-22s %-16s %-6s %s\n",$1,$2,$3,$4}'
    printf '\n'

    printf '[stderr 첫 줄 그룹별 빈도 — top 10]\n'
    printf '%s\n' "$raw_input" | jq -s -r '
        map(. + {first_line: (.stderr | split("\n") | .[0] // "")})
        | group_by(.first_line)
        | map([length, .[0].first_line])
        | sort_by(-.[0])
        | .[0:10]
        | .[] | @tsv
    ' | awk -F'\t' 'BEGIN{printf "  %-6s %s\n","count","first-line"} {fl=$2; if(length(fl)>96) fl=substr(fl,1,93)"..."; printf "  %-6s %s\n",$1,fl}'
    printf '\n'

    printf '[최빈 top-3 stderr 전문]\n'
    printf '%s\n' "$raw_input" | jq -s -r '
        map(. + {first_line: (.stderr | split("\n") | .[0] // "")})
        | group_by(.first_line)
        | map({
            count: length,
            first_ts: (min_by(.ts).ts),
            last_ts: (max_by(.ts).ts),
            sample_wid: .[0].worker_id,
            sample_script: .[0].script,
            sample_rc: (.[0].exit_code|tostring),
            sample_stderr: .[0].stderr
          })
        | sort_by(-.count)
        | .[0:3]
        | to_entries[]
        | "── #\(.key + 1) (\(.value.count)회 · \(.value.sample_wid)/\(.value.sample_script) rc=\(.value.sample_rc))\n   첫 발생: \(.value.first_ts)\n   마지막:  \(.value.last_ts)\n   샘플 stderr:\n\(.value.sample_stderr | split("\n") | map("     " + .) | join("\n"))"
    '
    exit 0
fi

# 필터 조건 jq 표현식 조립
filter_expr='.'
[ -n "$filter_worker" ] && filter_expr="${filter_expr} | select(.worker_id == \"$filter_worker\")"
[ -n "$filter_script" ] && filter_expr="${filter_expr} | select(.script == \"$filter_script\")"

matched="$(printf '%s\n' "$raw_input" | jq -c "$filter_expr" 2>/dev/null | tail -n "$tail_n")"

if [ -z "$matched" ]; then
    echo "조건에 맞는 로그 없음 (전체 $total 건)"
    exit 0
fi

shown_count="$(printf '%s\n' "$matched" | grep -c . || true)"
label="전체"
[ -n "$filter_mp" ] && label="$filter_mp"
printf '── orch errors ── (%s, 전체 %d건 중 %d건 표시)\n\n' "$label" "$total" "$shown_count"

printf '%s\n' "$matched" | while IFS= read -r line; do
    ts="$(printf '%s' "$line" | jq -r '.ts // "?"')"
    wid="$(printf '%s' "$line" | jq -r '.worker_id // "?"')"
    src="$(printf '%s' "$line" | jq -r '.script // "?"')"
    rc="$(printf '%s' "$line" | jq -r '.exit_code // "?"')"
    err="$(printf '%s' "$line" | jq -r '.stderr // ""')"
    err_first="$(printf '%s' "$err" | head -n 3)"
    err_lines="$(printf '%s' "$err" | grep -c . || true)"

    printf '[%s] %s · %s (rc=%s)\n' "$ts" "$wid" "$src" "$rc"
    printf '%s\n' "$err_first" | sed 's/^/    /'
    if [ "$err_lines" -gt 3 ]; then
        printf '    ... (총 %d줄)\n' "$err_lines"
    fi
    printf '\n'
done
