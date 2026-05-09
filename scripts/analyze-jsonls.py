#!/usr/bin/env python3
"""analyze-jsonls.py — Claude Code jsonl 세션 로그 통합 분석.

report.sh 의 토큰·도구 분석 섹션 대체. jq -s 가 한 invalid 줄 만나면
전체 fail 하던 문제 해결.

사용:
    analyze-jsonls.py <jsonl-dir> [--since <ISO>] [--until <ISO>]

출력 (stdout, markdown bullet):
    - jsonl: N개 (<dir>)
    - 토큰 합계 (assistant 턴 기준):
        turns        : N
        input        : N
        output       : N
        cache_read   : N
        cache_write  : N
        total_in_eq  : N
    - 도구 호출 top-10 (이름별):
        <count> <tool>
    - 큰 tool_result top-5 (응답 크기 byte):
        <size> <tool_use_id>
    - 세션 시간 범위:
        first: <iso>
        last:  <iso>

invalid jsonl 줄은 조용히 skip (warning 만 stderr).
"""
import json
import os
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path


def parse_iso(s):
    """ISO 8601 문자열을 timezone-aware datetime 으로 (Z, +09:00, 마이크로초 모두 지원)."""
    if not s:
        return None
    s = s.strip()
    # 'Z' suffix → '+00:00' (Python 3.10 이하 fromisoformat 호환)
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def aggregate(jsonl_paths, since=None, until=None):
    """since/until 은 ISO 문자열. 내부에서 datetime 으로 변환해 비교.

    tool_use → tool_result 매칭은 tool_use_id 키로 single-pass + post-fix:
    assistant turn 의 tool_use 시점에 (name, file_path) 를 dict 에 저장하고,
    user turn 의 tool_result 는 즉시 누적하지 않고 임시 list 에 (size, tu_id)
    로 보관. 패스 끝난 뒤 매핑 lookup 으로 도구별/파일별 누적.

    줄 순서를 후처리로 분리하는 이유: Claude Code transcript 가 Edit/Read 같이
    server-side 가 빠르게 결과를 만드는 도구에서 tool_result 를 tool_use 보다
    먼저 flush 하는 케이스가 관찰됨 (timestamp 는 USE 가 빠른데 line 은 RES 가
    먼저). single-pass + 즉시 누적 방식이면 그 RES 가 unknown 으로 분류돼
    도구별 누적이 underreport.
    """
    since_dt = parse_iso(since) if since else None
    until_dt = parse_iso(until) if until else None

    totals = {
        "turns": 0,
        "input": 0,
        "output": 0,
        "cache_read": 0,
        "cache_write": 0,
    }
    tool_counts = Counter()
    tool_results = []  # (size, tool_use_id, name) — 매칭 후 채움
    tool_size_by_name = Counter()  # 도구별 누적 tool_result byte
    file_read_count = Counter()    # Read input.file_path → 호출 횟수
    file_read_bytes = Counter()    # Read input.file_path → 누적 byte
    tool_use_meta = {}  # tool_use_id → {"name": str, "file_path": str|None}
    pending_results = []  # (size, tu_id) — 패스 후 매핑 lookup
    timestamps = []
    skipped_lines = 0

    for path in jsonl_paths:
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        skipped_lines += 1
                        continue

                    # 시간 필터 — record 의 timestamp 가 since 이전이거나 until 이후면 skip
                    ts_raw = obj.get("timestamp")
                    if ts_raw and (since_dt or until_dt):
                        ts_dt = parse_iso(ts_raw)
                        if ts_dt is not None:
                            if since_dt and ts_dt < since_dt:
                                continue
                            if until_dt and ts_dt > until_dt:
                                continue
                    if ts_raw:
                        timestamps.append(ts_raw)

                    typ = obj.get("type")

                    if typ == "assistant":
                        msg = obj.get("message") or {}
                        usage = msg.get("usage")
                        if usage:
                            totals["turns"] += 1
                            totals["input"] += usage.get("input_tokens") or 0
                            totals["output"] += usage.get("output_tokens") or 0
                            totals["cache_read"] += usage.get("cache_read_input_tokens") or 0
                            totals["cache_write"] += usage.get("cache_creation_input_tokens") or 0
                        # tool_use 추출
                        content = msg.get("content")
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get("type") == "tool_use":
                                    name = block.get("name") or "(unknown)"
                                    tool_counts[name] += 1
                                    tu_id = block.get("id")
                                    inp = block.get("input") or {}
                                    fp = inp.get("file_path") if isinstance(inp, dict) else None
                                    if tu_id:
                                        tool_use_meta[tu_id] = {"name": name, "file_path": fp}

                    elif typ == "user":
                        msg = obj.get("message") or {}
                        content = msg.get("content")
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get("type") == "tool_result":
                                    payload = block.get("content")
                                    size = len(json.dumps(payload, ensure_ascii=False))
                                    tu_id = block.get("tool_use_id") or "(no-id)"
                                    pending_results.append((size, tu_id))
        except (OSError, IOError) as e:
            print(f"warn: 읽기 실패 {path}: {e}", file=sys.stderr)
            continue

    # post-fix 매칭 — tool_use 가 같은 file 안 어디에 있건 (line 순서 무관) 매칭됨
    for size, tu_id in pending_results:
        meta = tool_use_meta.get(tu_id) or {}
        name = meta.get("name") or "(unknown)"
        tool_results.append((size, tu_id, name))
        tool_size_by_name[name] += size
        fp = meta.get("file_path")
        if fp and name in ("Read", "NotebookRead"):
            file_read_count[fp] += 1
            file_read_bytes[fp] += size

    if skipped_lines:
        print(f"warn: invalid JSON 줄 {skipped_lines}개 skip", file=sys.stderr)

    return {
        "totals": totals,
        "tool_counts": tool_counts,
        "tool_results": tool_results,
        "tool_size_by_name": tool_size_by_name,
        "file_read_count": file_read_count,
        "file_read_bytes": file_read_bytes,
        "timestamps": timestamps,
    }


def derive_waste_hints(agg):
    """누적 데이터에서 낭비 패턴 식별. 각 hint 는 한 줄 narrative."""
    hints = []
    fc = agg["file_read_count"]
    fb = agg["file_read_bytes"]
    # 같은 파일 ≥ 3회 read
    repeat_files = [(p, c, fb[p]) for p, c in fc.items() if c >= 3]
    repeat_files.sort(key=lambda x: -x[2])
    for p, c, b in repeat_files[:3]:
        hints.append(f"같은 파일 {c}회 read · {b:,} byte 누적 — 캐싱 미활용 의심: {p}")

    # 단일 도구 ≥ 60% 점유 (tool_result byte 기준)
    sz = agg["tool_size_by_name"]
    total_sz = sum(sz.values())
    if total_sz > 0:
        for name, s in sz.most_common(1):
            share = s / total_sz
            if share >= 0.60:
                hints.append(
                    f"{name} 도구가 tool_result byte 의 {share*100:.0f}% 점유 — 다른 도구 활용/Agent 위임 검토"
                )

    # 매우 큰 단일 tool_result (≥ 50KB)
    big = sorted(agg["tool_results"], reverse=True)[:1]
    if big and big[0][0] >= 50_000:
        size, tu_id, name = big[0]
        hints.append(
            f"단일 {name} 결과가 {size:,} byte ({size//1024} KB) — 범위 좁히기/Agent 위임으로 분할 검토"
        )

    return hints


def render(jsonl_paths, agg, dir_path):
    totals = agg["totals"]
    tool_counts = agg["tool_counts"]
    tool_results = agg["tool_results"]
    tool_size_by_name = agg["tool_size_by_name"]
    file_read_count = agg["file_read_count"]
    file_read_bytes = agg["file_read_bytes"]
    timestamps = agg["timestamps"]

    print(f"- jsonl: {len(jsonl_paths)}개 ({dir_path})")
    print("- 토큰 합계 (assistant 턴 기준):")
    total_eq = totals["input"] + totals["cache_read"] + totals["cache_write"]
    print(f"    turns        : {totals['turns']}")
    print(f"    input        : {totals['input']}")
    print(f"    output       : {totals['output']}")
    print(f"    cache_read   : {totals['cache_read']}")
    print(f"    cache_write  : {totals['cache_write']}")
    print(f"    total_in_eq  : {total_eq}")

    print("- 도구 호출 top-10 (이름별):")
    if not tool_counts:
        print("    _(도구 호출 없음 또는 jsonl 파싱 실패)_")
    else:
        for name, count in tool_counts.most_common(10):
            print(f"    {count:<6} {name}")

    print("- 도구별 tool_result 누적 byte top-10 (input 컨텍스트 비중):")
    total_sz = sum(tool_size_by_name.values())
    if not tool_size_by_name:
        print("    _(tool_result 없음)_")
    else:
        for name, sz in tool_size_by_name.most_common(10):
            share = (sz / total_sz * 100) if total_sz else 0
            print(f"    {sz:<10,} ({share:5.1f}%) {name}")

    print("- 파일별 누적 read top-5 (캐싱 효율 신호):")
    if not file_read_count:
        print("    _(Read 호출 없음)_")
    else:
        ranked = sorted(file_read_count.items(), key=lambda kv: -file_read_bytes[kv[0]])[:5]
        for fp, cnt in ranked:
            b = file_read_bytes[fp]
            print(f"    {cnt}회 · {b:,} byte · {fp}")

    print("- 큰 tool_result top-5 (응답 크기 byte; 낭비 의심):")
    if not tool_results:
        print("    _(tool_result 없음)_")
    else:
        tool_results_sorted = sorted(tool_results, reverse=True)
        for size, tu_id, name in tool_results_sorted[:5]:
            print(f"    {size:<9} {name:<10} {tu_id}")

    hints = derive_waste_hints(agg)
    print("- 낭비 패턴 hint:")
    if not hints:
        print("    _(눈에 띄는 패턴 없음)_")
    else:
        for h in hints:
            print(f"    {h}")

    print("- 세션 시간 범위:")
    if not timestamps:
        print("    (timestamp 미상)")
    else:
        timestamps.sort()
        print(f"    first: {timestamps[0]}")
        print(f"    last:  {timestamps[-1]}")


def render_json(jsonl_paths, agg, dir_path):
    """orch:report SKILL 이 token_efficiency JSON 필드 매핑할 때 직접 사용."""
    totals = agg["totals"]
    tool_counts = agg["tool_counts"]
    tool_size_by_name = agg["tool_size_by_name"]
    file_read_count = agg["file_read_count"]
    file_read_bytes = agg["file_read_bytes"]
    timestamps = sorted(agg["timestamps"])
    total_sz = sum(tool_size_by_name.values())

    file_rank = sorted(file_read_count.items(), key=lambda kv: -file_read_bytes[kv[0]])
    out = {
        "jsonl_count": len(jsonl_paths),
        "dir_path": dir_path,
        "totals": totals,
        "tool_counts": dict(tool_counts.most_common()),
        "tool_size_by_name": [
            {"name": k, "bytes": v, "share": (v / total_sz) if total_sz else 0}
            for k, v in tool_size_by_name.most_common()
        ],
        "file_reads_top10": [
            {"path": fp, "count": cnt, "bytes": file_read_bytes[fp]}
            for fp, cnt in file_rank[:10]
        ],
        "waste_hints": derive_waste_hints(agg),
        "first_ts": timestamps[0] if timestamps else None,
        "last_ts": timestamps[-1] if timestamps else None,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


def main():
    if len(sys.argv) < 2:
        print(
            "사용법: analyze-jsonls.py <jsonl-dir> [--since ISO] [--until ISO] [--json]",
            file=sys.stderr,
        )
        sys.exit(2)
    dir_path = sys.argv[1]
    since = until = None
    json_out = False
    args = sys.argv[2:]
    while args:
        if args[0] == "--since" and len(args) >= 2:
            since = args[1]
            args = args[2:]
        elif args[0] == "--until" and len(args) >= 2:
            until = args[1]
            args = args[2:]
        elif args[0] == "--json":
            json_out = True
            args = args[1:]
        else:
            print(f"warn: 알 수 없는 인자 무시: {args[0]}", file=sys.stderr)
            args = args[1:]

    p = Path(dir_path)
    if not p.is_dir():
        if json_out:
            print(json.dumps({"error": f"디렉토리 없음: {dir_path}"}, ensure_ascii=False))
        else:
            print(f"_(jsonl 디렉토리 없음: {dir_path})_")
        sys.exit(0)

    jsonl_paths = sorted(p.glob("*.jsonl"))
    if not jsonl_paths:
        if json_out:
            print(json.dumps({"error": f"jsonl 파일 없음 in {dir_path}"}, ensure_ascii=False))
        else:
            print(f"_(jsonl 파일 없음 in {dir_path})_")
        sys.exit(0)

    agg = aggregate(jsonl_paths, since, until)
    if json_out:
        render_json(jsonl_paths, agg, dir_path)
    else:
        render(jsonl_paths, agg, dir_path)


if __name__ == "__main__":
    main()
