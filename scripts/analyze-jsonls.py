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
    """since/until 은 ISO 문자열. 내부에서 datetime 으로 변환해 비교."""
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
    tool_results = []  # (size, tool_use_id)
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

                    elif typ == "user":
                        msg = obj.get("message") or {}
                        content = msg.get("content")
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get("type") == "tool_result":
                                    payload = block.get("content")
                                    size = len(json.dumps(payload, ensure_ascii=False))
                                    tu_id = block.get("tool_use_id") or "(no-id)"
                                    tool_results.append((size, tu_id))
        except (OSError, IOError) as e:
            print(f"warn: 읽기 실패 {path}: {e}", file=sys.stderr)
            continue

    if skipped_lines:
        print(f"warn: invalid JSON 줄 {skipped_lines}개 skip", file=sys.stderr)

    return totals, tool_counts, tool_results, timestamps


def render(jsonl_paths, totals, tool_counts, tool_results, timestamps, dir_path):
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

    print("- 큰 tool_result top-5 (응답 크기 byte; 낭비 의심):")
    if not tool_results:
        print("    _(tool_result 없음)_")
    else:
        tool_results.sort(reverse=True)
        for size, tu_id in tool_results[:5]:
            print(f"    {size:<9} {tu_id}")

    print("- 세션 시간 범위:")
    if not timestamps:
        print("    (timestamp 미상)")
    else:
        timestamps.sort()
        print(f"    first: {timestamps[0]}")
        print(f"    last:  {timestamps[-1]}")


def main():
    if len(sys.argv) < 2:
        print("사용법: analyze-jsonls.py <jsonl-dir> [--since ISO] [--until ISO]", file=sys.stderr)
        sys.exit(2)
    dir_path = sys.argv[1]
    since = until = None
    args = sys.argv[2:]
    while args:
        if args[0] == "--since" and len(args) >= 2:
            since = args[1]
            args = args[2:]
        elif args[0] == "--until" and len(args) >= 2:
            until = args[1]
            args = args[2:]
        else:
            print(f"warn: 알 수 없는 인자 무시: {args[0]}", file=sys.stderr)
            args = args[1:]

    p = Path(dir_path)
    if not p.is_dir():
        print(f"_(jsonl 디렉토리 없음: {dir_path})_")
        sys.exit(0)

    jsonl_paths = sorted(p.glob("*.jsonl"))
    if not jsonl_paths:
        print(f"_(jsonl 파일 없음 in {dir_path})_")
        sys.exit(0)

    totals, tool_counts, tool_results, timestamps = aggregate(jsonl_paths, since, until)
    render(jsonl_paths, totals, tool_counts, tool_results, timestamps, dir_path)


if __name__ == "__main__":
    main()
