#!/usr/bin/env python3
"""usage-stats.py — Claude Code 모든 세션의 슬래시 / 스크립트 / 스킬 / 서브에이전트 사용량 집계.

`~/.claude/projects/*/*.jsonl` 를 스캔해 4 카테고리 카운트를 모은다. plugin 의 dead code
후보 (한 번도 안 불린 항목) 를 식별할 때 쓴다.

집계 대상:
1. slash commands — user message 안의 `<command-name>/X</command-name>` 태그
2. bash scripts   — assistant 의 Bash tool_use input.command 안에 등장한 `.sh` 파일명
3. skills         — assistant 의 Skill tool_use input.skill
4. subagents      — assistant 의 Agent tool_use input.subagent_type

사용:
    usage-stats.py [--root <dir>] [--since ISO] [--until ISO]
                   [--plugin <prefix>] [--format md|json]
                   [--top N] [--zero <listfile>]

--zero 옵션이 주어지면 해당 파일 (한 줄당 등록된 entity 이름) 을 읽어
실제 카운트가 0 인 항목만 별도 섹션으로 표시 — dead 후보 빠른 인지용.

stdin 비어있음. 잘못된 jsonl 줄은 warning 만 stderr 로 흘리고 skip.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Iterable

CMD_TAG_RE = re.compile(r"<command-name>([^<]+)</command-name>")
SH_RE = re.compile(r"/([A-Za-z0-9_-]+\.sh)\b")


def parse_iso(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        print(f"WARN: --since/--until 파싱 실패 '{value}'", file=sys.stderr)
        return None


def iter_jsonl(root: Path) -> Iterable[Path]:
    if not root.is_dir():
        return []
    return sorted(root.glob("*/*.jsonl"))


def msg_content_items(msg: dict) -> list:
    """assistant/user message 안의 content 를 항상 list 로 반환."""
    content = msg.get("content")
    if content is None:
        return []
    if isinstance(content, list):
        return content
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return []


def text_of(item: dict) -> str:
    if not isinstance(item, dict):
        return ""
    if item.get("type") == "text":
        return item.get("text") or ""
    return ""


def aggregate(
    jsonl_paths: Iterable[Path],
    since: datetime | None,
    until: datetime | None,
    plugin: str,
) -> dict:
    commands: Counter[str] = Counter()
    scripts: Counter[str] = Counter()
    skills: Counter[str] = Counter()
    agents: Counter[str] = Counter()
    sessions: set[str] = set()

    for path in jsonl_paths:
        try:
            fh = path.open("r", encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"WARN: open 실패 {path}: {exc}", file=sys.stderr)
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts_raw = rec.get("timestamp")
                if since or until:
                    ts = parse_iso(ts_raw) if ts_raw else None
                    if ts is None:
                        continue
                    if since and ts < since:
                        continue
                    if until and ts > until:
                        continue
                sid = rec.get("sessionId")
                if sid:
                    sessions.add(sid)
                msg = rec.get("message")
                if not isinstance(msg, dict):
                    continue
                rtype = rec.get("type")

                if rtype == "user":
                    for item in msg_content_items(msg):
                        text = text_of(item)
                        if not text:
                            continue
                        for m in CMD_TAG_RE.finditer(text):
                            name = m.group(1).strip()
                            if plugin and not name.lstrip("/").startswith(plugin):
                                continue
                            commands[name] += 1
                elif rtype == "assistant":
                    for item in msg_content_items(msg):
                        if not isinstance(item, dict) or item.get("type") != "tool_use":
                            continue
                        tool = item.get("name")
                        inp = item.get("input") or {}
                        if tool == "Bash":
                            cmd = inp.get("command") or ""
                            for m in SH_RE.finditer(cmd):
                                scripts[m.group(1)] += 1
                        elif tool == "Skill":
                            sk = inp.get("skill")
                            if sk:
                                if plugin and not sk.startswith(plugin):
                                    continue
                                skills[sk] += 1
                        elif tool == "Agent":
                            st = inp.get("subagent_type")
                            if st:
                                agents[st] += 1
    return {
        "commands": commands,
        "scripts": scripts,
        "skills": skills,
        "agents": agents,
        "sessions": len(sessions),
        "jsonl_count": sum(1 for _ in jsonl_paths) if isinstance(jsonl_paths, list) else None,
    }


def render_section(title: str, counter: Counter[str], top: int) -> list[str]:
    out = [f"### {title} ({sum(counter.values())} 회, {len(counter)} 종)"]
    if not counter:
        out.append("- (없음)")
        return out
    for name, n in counter.most_common(top):
        out.append(f"- {n:>6}  {name}")
    if len(counter) > top:
        out.append(f"- ... +{len(counter) - top} 더 (--top 으로 늘리기)")
    return out


def render_md(agg: dict, top: int) -> str:
    lines = [f"## 사용량 통계 (세션 {agg['sessions']}개)"]
    lines += render_section("Slash commands", agg["commands"], top)
    lines.append("")
    lines += render_section("Bash scripts (*.sh)", agg["scripts"], top)
    lines.append("")
    lines += render_section("Skills", agg["skills"], top)
    lines.append("")
    lines += render_section("Subagent types", agg["agents"], top)
    return "\n".join(lines)


def render_zero(agg: dict, registered: list[str], category: str) -> list[str]:
    counter = agg[category]
    zeros = [name for name in registered if name not in counter or counter[name] == 0]
    out = [f"### Dead 후보 — {category} 등록됐으나 카운트 0"]
    if not zeros:
        out.append("- (없음 — 모두 한 번은 호출됨)")
        return out
    for name in zeros:
        out.append(f"- {name}")
    return out


def main() -> int:
    p = argparse.ArgumentParser(description="Claude Code jsonl cross-session 사용량 집계")
    p.add_argument("--root", default=os.path.expanduser("~/.claude/projects"),
                   help="jsonl 루트 (기본 ~/.claude/projects)")
    p.add_argument("--since", default="", help="이 시점 이후 (ISO)")
    p.add_argument("--until", default="", help="이 시점 이전 (ISO)")
    p.add_argument("--plugin", default="",
                   help="이 prefix 로 시작하는 슬래시/스킬만 (예: 'orch:')")
    p.add_argument("--format", choices=["md", "json"], default="md")
    p.add_argument("--top", type=int, default=20, help="카테고리별 상위 N (기본 20)")
    p.add_argument("--zero", default="",
                   help="등록된 entity 목록 파일 (한 줄당 이름). 카운트 0 인 항목 별도 보고.")
    p.add_argument("--zero-category", default="commands",
                   choices=["commands", "scripts", "skills", "agents"],
                   help="--zero 대조 카테고리 (기본 commands)")
    args = p.parse_args()

    root = Path(args.root)
    jsonl_paths = list(iter_jsonl(root))
    if not jsonl_paths:
        print(f"WARN: jsonl 없음 ({root})", file=sys.stderr)

    agg = aggregate(
        jsonl_paths,
        parse_iso(args.since),
        parse_iso(args.until),
        args.plugin,
    )

    if args.format == "json":
        out = {k: dict(v) if hasattr(v, "items") else v for k, v in agg.items()}
        out["jsonl_paths"] = [str(p) for p in jsonl_paths]
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0

    md = render_md(agg, args.top)
    print(md)
    if args.zero:
        registered = [ln.strip() for ln in Path(args.zero).read_text().splitlines() if ln.strip()]
        print()
        print("\n".join(render_zero(agg, registered, args.zero_category)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
