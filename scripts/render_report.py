#!/usr/bin/env python3
"""render_report.py — orch MP 회고 JSON 을 결정적 HTML 로 렌더.

orch 가 /orch:report <mp> 의 raw markdown 데이터를 해석해 구조화된 JSON 으로
요약하면, 이 스크립트가 항상 동일한 HTML 골격 + CSS 로 렌더해 매번 양식이
달라지는 문제를 없앤다.

사용:
    render_report.py <input.json> <output.html>
    cat report.json | render_report.py - <output.html>
    render_report.py <input.json> -          # html 을 stdout 으로

JSON 스키마 (필수: mp_id, scope_dir / 나머지 optional, 누락 시 섹션 비워서 표시):

{
  "mp_id":        "MP-9",
  "scope_dir":    "/path/to/.orch/archive/mp-9-2026-05-06",
  "generated_at": "2026-05-07T07:30:00Z",

  "summary": {
    "issue_title": "이슈 한 줄",
    "worker_count": 2,
    "duration": "약 47분",
    "result_line": "PR #84 머지됨",
    "narrative": "한 문장 한국어 요약"
  },

  "changes": {
    "workers": [
      {"id": "MP-9/server",
       "branch": "feature/MP-9-...",
       "diff_stat": "5 files changed, +123 -8",
       "highlights": ["변경 한 줄", "변경 한 줄"]}
    ],
    "pr_url": "https://github.com/.../pull/84"
  },

  "as_is_to_be": [
    {"as_is": "...", "to_be": "..."}
  ],

  "test_results": {"narrative": "..."},

  "token_analysis": {
    "by_model": [
      {"model": "claude-opus-4-7",
       "messages": 1574, "input": 218506, "output": 1388300,
       "cache_read": 155774764, "cache_creation": 3902583,
       "cost_usd": 414.23}
    ],
    "total_cost_usd": 414.23,
    "tool_distribution": [{"tool": "Read", "count": 234}],
    "large_tool_results_top5": [{"target": "src/foo.go", "size": 32000, "note": "..."}],
    "observations": ["Read 가 같은 파일 반복", "..."]
  },

  "handoff": {"errors_count": 0, "narrative": "발견된 마찰 없음"},

  "follow_ups": [
    {"category": "skipped|bug|refactor|docs", "title": "...", "detail": "..."}
  ],

  "errors_check": {
    "narrative": "이번 사이클 에러 N건 / 반복 패턴 K개 / 자동 이슈 X건 생성",
    "patterns": [
      {"script": "send.sh", "exit_code": 1, "count": 3,
       "first_line": "ERROR: ...", "suggested_fix": "..."}
    ],
    "auto_issue": {"id": "PAD-XX", "url": "https://linear.app/..."}
  },

  "ai_ready_check": {
    "narrative": "stale 항목 자동 검사 결과 X — 영향 없음",
    "stale_items": [{"file": "CLAUDE.md", "lines": "12-20", "reason": "..."}],
    "auto_issue": {"id": "PAD-XX", "url": "https://linear.app/..."}
  }
}
"""
from __future__ import annotations

import html
import json
import sys
from typing import Any

CSS = """
:root {
  --fg: #1f2328;
  --fg-muted: #57606a;
  --bg: #ffffff;
  --bg-soft: #f6f8fa;
  --border: #d0d7de;
  --accent: #0969da;
  --warn: #9a6700;
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 32px 24px; max-width: 920px;
  margin-left: auto; margin-right: auto;
  font-family: system-ui, -apple-system, "Segoe UI", "Helvetica Neue", sans-serif;
  color: var(--fg); background: var(--bg);
  line-height: 1.55; font-size: 15px;
}
h1 { font-size: 26px; margin: 0 0 4px; }
h2 { font-size: 18px; margin: 0 0 12px; }
h3 { font-size: 15px; margin: 16px 0 6px; color: var(--fg-muted); font-weight: 600; }
.meta { color: var(--fg-muted); font-size: 13px; margin-bottom: 24px; }
.meta code { font-size: 12px; }
.section {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 18px 22px;
  margin-bottom: 16px;
}
.section.empty { color: var(--fg-muted); font-style: italic; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px;
       background: var(--bg-soft); padding: 1px 5px; border-radius: 4px; }
pre  { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px;
       background: var(--bg-soft); padding: 10px 12px; border-radius: 6px; overflow-x: auto;
       margin: 6px 0; }
table { border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 13px; }
th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid var(--border); }
th { font-weight: 600; background: var(--bg-soft); }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
ul { margin: 6px 0; padding-left: 22px; }
li { margin: 2px 0; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
.kv { display: grid; grid-template-columns: 120px 1fr; gap: 4px 14px; margin: 6px 0; }
.kv dt { color: var(--fg-muted); font-weight: 500; }
.kv dd { margin: 0; }
.badge {
  display: inline-block; padding: 1px 8px; border-radius: 999px;
  background: var(--bg-soft); border: 1px solid var(--border);
  font-size: 12px; color: var(--fg-muted); margin-right: 4px;
}
.badge.bug      { color: #b22; border-color: #f3c0c0; }
.badge.refactor { color: #555; }
.badge.skipped  { color: var(--warn); border-color: #e8d27a; }
.badge.docs     { color: var(--accent); border-color: #b6daff; }
.muted { color: var(--fg-muted); }
.worker { border-left: 3px solid var(--border); padding: 4px 0 4px 12px; margin: 10px 0; }
.worker .id { font-weight: 600; }
.asis-tobe { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 8px 0; }
.asis-tobe .col { background: var(--bg-soft); border-radius: 6px; padding: 10px 12px; }
.asis-tobe .col h4 { margin: 0 0 4px; font-size: 12px; color: var(--fg-muted); text-transform: uppercase; letter-spacing: 0.5px; }
""".strip()


def esc(s: Any) -> str:
    return html.escape("" if s is None else str(s), quote=True)


def fmt_int(n: Any) -> str:
    try:
        return f"{int(n):,}"
    except (TypeError, ValueError):
        return esc(n)


def fmt_money(n: Any) -> str:
    try:
        return f"${float(n):.4f}"
    except (TypeError, ValueError):
        return "—"


def section(title: str, body_html: str, empty: bool = False) -> str:
    cls = "section empty" if empty else "section"
    return f'<section class="{cls}"><h2>{esc(title)}</h2>{body_html}</section>'


def render_summary(d: dict | None) -> str:
    if not d:
        return section("요약", "<p>요약 정보 없음.</p>", empty=True)
    rows = []
    if d.get("issue_title"):    rows.append(("이슈", esc(d["issue_title"])))
    if d.get("worker_count") is not None: rows.append(("산하 워커", esc(d["worker_count"])))
    if d.get("duration"):       rows.append(("경과 시간", esc(d["duration"])))
    if d.get("result_line"):    rows.append(("결과", esc(d["result_line"])))
    kv = "<dl class=\"kv\">" + "".join(f"<dt>{k}</dt><dd>{v}</dd>" for k, v in rows) + "</dl>"
    narrative = f"<p>{esc(d['narrative'])}</p>" if d.get("narrative") else ""
    return section("요약", narrative + kv)


def render_changes(d: dict | None) -> str:
    if not d or not d.get("workers"):
        return section("변경 내용", "<p>변경 데이터 없음.</p>", empty=True)
    parts = []
    for w in d["workers"]:
        wid = esc(w.get("id", "?"))
        branch = esc(w.get("branch", ""))
        diff = esc(w.get("diff_stat", ""))
        highlights = w.get("highlights") or []
        hl = "".join(f"<li>{esc(h)}</li>" for h in highlights)
        parts.append(
            f'<div class="worker">'
            f'<div class="id">{wid}</div>'
            + (f'<div class="muted">{branch}</div>' if branch else "")
            + (f'<div><code>{diff}</code></div>' if diff else "")
            + (f'<ul>{hl}</ul>' if hl else "")
            + '</div>'
        )
    pr_url = d.get("pr_url")
    pr_html = ""
    if pr_url:
        pr_html = f'<p>PR: <a href="{esc(pr_url)}" target="_blank" rel="noreferrer">{esc(pr_url)}</a></p>'
    return section("변경 내용", "".join(parts) + pr_html)


def render_as_is_to_be(items: list | None) -> str:
    if not items:
        return section("as-is / to-be", "<p>비교할 변경 없음.</p>", empty=True)
    rows = []
    for it in items:
        rows.append(
            '<div class="asis-tobe">'
            f'<div class="col"><h4>as-is</h4>{esc(it.get("as_is", ""))}</div>'
            f'<div class="col"><h4>to-be</h4>{esc(it.get("to_be", ""))}</div>'
            '</div>'
        )
    return section("as-is / to-be", "".join(rows))


def render_test_results(d: dict | None) -> str:
    if not d or not d.get("narrative"):
        return section("테스트 결과", "<p>워커 자가보고 없음.</p>", empty=True)
    return section("테스트 결과", f"<p>{esc(d['narrative'])}</p>")


def render_token_analysis(d: dict | None) -> str:
    if not d:
        return section("토큰·시간 분석", "<p>토큰 데이터 없음.</p>", empty=True)
    parts = []

    by_model = d.get("by_model") or []
    if by_model:
        head = ('<table><thead><tr>'
                '<th>Model</th><th class="num">Msgs</th><th class="num">Input</th>'
                '<th class="num">Output</th><th class="num">Cache Read</th>'
                '<th class="num">Cache Write</th><th class="num">Cost (USD)</th>'
                '</tr></thead><tbody>')
        rows = []
        for m in by_model:
            rows.append(
                '<tr>'
                f'<td><code>{esc(m.get("model"))}</code></td>'
                f'<td class="num">{fmt_int(m.get("messages"))}</td>'
                f'<td class="num">{fmt_int(m.get("input"))}</td>'
                f'<td class="num">{fmt_int(m.get("output"))}</td>'
                f'<td class="num">{fmt_int(m.get("cache_read"))}</td>'
                f'<td class="num">{fmt_int(m.get("cache_creation"))}</td>'
                f'<td class="num">{fmt_money(m.get("cost_usd"))}</td>'
                '</tr>'
            )
        total_cost = d.get("total_cost_usd")
        total_row = ""
        if total_cost is not None:
            total_row = (
                f'<tr><td colspan="6" class="num"><b>Total</b></td>'
                f'<td class="num"><b>{fmt_money(total_cost)}</b></td></tr>'
            )
        parts.append(head + "".join(rows) + total_row + "</tbody></table>")

    tool_dist = d.get("tool_distribution") or []
    if tool_dist:
        parts.append("<h3>도구 호출 분포</h3>")
        head = '<table><thead><tr><th>Tool</th><th class="num">Count</th></tr></thead><tbody>'
        rows = "".join(
            f'<tr><td><code>{esc(t.get("tool"))}</code></td><td class="num">{fmt_int(t.get("count"))}</td></tr>'
            for t in tool_dist
        )
        parts.append(head + rows + "</tbody></table>")

    big = d.get("large_tool_results_top5") or []
    if big:
        parts.append("<h3>큰 tool_result top-5</h3>")
        head = ('<table><thead><tr><th>Target</th><th class="num">Size (bytes)</th>'
                '<th>비고</th></tr></thead><tbody>')
        rows = "".join(
            f'<tr><td><code>{esc(b.get("target"))}</code></td>'
            f'<td class="num">{fmt_int(b.get("size"))}</td>'
            f'<td>{esc(b.get("note", ""))}</td></tr>'
            for b in big
        )
        parts.append(head + rows + "</tbody></table>")

    obs = d.get("observations") or []
    if obs:
        parts.append("<h3>관찰</h3><ul>" + "".join(f"<li>{esc(o)}</li>" for o in obs) + "</ul>")

    body = "".join(parts) if parts else "<p>토큰 분석 비어있음.</p>"
    return section("토큰·시간 분석", body, empty=not parts)


def render_handoff(d: dict | None) -> str:
    if not d:
        return section("핸드오프 페인포인트", "<p>발견된 마찰 없음.</p>", empty=True)
    parts = []
    if d.get("errors_count") is not None:
        parts.append(f'<p>에러 로그 항목: <b>{fmt_int(d["errors_count"])}건</b></p>')
    if d.get("narrative"):
        parts.append(f"<p>{esc(d['narrative'])}</p>")
    if not parts:
        return section("핸드오프 페인포인트", "<p>발견된 마찰 없음.</p>", empty=True)
    return section("핸드오프 페인포인트", "".join(parts))


def render_follow_ups(items: list | None) -> str:
    if not items:
        return section("후속 이슈 메모", "<p>후속 항목 없음.</p>", empty=True)
    rows = []
    for it in items:
        cat = (it.get("category") or "").lower()
        valid = {"skipped", "bug", "refactor", "docs"}
        badge_cls = cat if cat in valid else ""
        badge = f'<span class="badge {badge_cls}">{esc(cat or "note")}</span>'
        title = esc(it.get("title", ""))
        detail = esc(it.get("detail", ""))
        rows.append(f'<li>{badge}<b>{title}</b>{(" — " + detail) if detail else ""}</li>')
    return section("후속 이슈 메모", "<ul>" + "".join(rows) + "</ul>")


def render_errors_check(d: dict | None) -> str:
    if not d:
        return section("자가진단 — errors.jsonl 영향 검사", "<p>검사 정보 없음.</p>", empty=True)
    parts = []
    if d.get("narrative"):
        parts.append(f"<p>{esc(d['narrative'])}</p>")
    patterns = d.get("patterns") or []
    if patterns:
        parts.append("<h3>반복 패턴 + 개선 액션</h3>")
        head = ('<table><thead><tr><th>script</th><th class="num">rc</th>'
                '<th class="num">count</th><th>stderr 첫 줄</th><th>fix 액션</th>'
                '</tr></thead><tbody>')
        rows = "".join(
            f'<tr><td><code>{esc(p.get("script"))}</code></td>'
            f'<td class="num">{esc(p.get("exit_code"))}</td>'
            f'<td class="num">{fmt_int(p.get("count"))}</td>'
            f'<td>{esc(p.get("first_line", ""))}</td>'
            f'<td>{esc(p.get("suggested_fix", ""))}</td></tr>'
            for p in patterns
        )
        parts.append(head + rows + "</tbody></table>")
    issue = d.get("auto_issue")
    if issue:
        url = issue.get("url", "")
        iid = issue.get("id", "")
        link = (f'<a href="{esc(url)}" target="_blank" rel="noreferrer">{esc(iid)}</a>'
                if url else esc(iid))
        parts.append(f"<p>자동 생성 이슈: {link}</p>")
    return section("자가진단 — errors.jsonl 영향 검사",
                   "".join(parts) if parts else "<p>검사 결과 없음.</p>",
                   empty=not parts)


def render_ai_ready(d: dict | None) -> str:
    if not d:
        return section("AI-Ready 영향 검사", "<p>검사 정보 없음.</p>", empty=True)
    parts = []
    if d.get("narrative"):
        parts.append(f"<p>{esc(d['narrative'])}</p>")
    stale = d.get("stale_items") or []
    if stale:
        parts.append("<h3>stale 후보</h3>")
        head = ('<table><thead><tr><th>파일</th><th>위치</th><th>사유</th>'
                '</tr></thead><tbody>')
        rows = "".join(
            f'<tr><td><code>{esc(s.get("file"))}</code></td>'
            f'<td><code>{esc(s.get("lines"))}</code></td>'
            f'<td>{esc(s.get("reason", ""))}</td></tr>'
            for s in stale
        )
        parts.append(head + rows + "</tbody></table>")
    issue = d.get("auto_issue")
    if issue:
        url = issue.get("url", "")
        iid = issue.get("id", "")
        link = (f'<a href="{esc(url)}" target="_blank" rel="noreferrer">{esc(iid)}</a>'
                if url else esc(iid))
        parts.append(f"<p>자동 생성 이슈: {link}</p>")
    return section("AI-Ready 영향 검사", "".join(parts) if parts else "<p>검사 결과 없음.</p>",
                   empty=not parts)


def render_html(data: dict) -> str:
    mp_id = data.get("mp_id") or "(unknown)"
    scope_dir = data.get("scope_dir") or ""
    generated_at = data.get("generated_at") or ""

    body = "".join([
        render_summary(data.get("summary")),
        render_changes(data.get("changes")),
        render_as_is_to_be(data.get("as_is_to_be")),
        render_test_results(data.get("test_results")),
        render_token_analysis(data.get("token_analysis")),
        render_handoff(data.get("handoff")),
        render_follow_ups(data.get("follow_ups")),
        render_errors_check(data.get("errors_check")),
        render_ai_ready(data.get("ai_ready_check")),
    ])

    meta_bits = []
    if scope_dir:    meta_bits.append(f'scope: <code>{esc(scope_dir)}</code>')
    if generated_at: meta_bits.append(f'생성: <code>{esc(generated_at)}</code>')
    meta = ' · '.join(meta_bits)

    return (
        f'<!doctype html>\n<html lang="ko">\n<head>'
        f'<meta charset="utf-8">'
        f'<meta name="viewport" content="width=device-width, initial-scale=1">'
        f'<title>{esc(mp_id)} 회고</title>'
        f'<style>{CSS}</style>'
        f'</head>\n<body>'
        f'<h1>{esc(mp_id)} 회고</h1>'
        f'<div class="meta">{meta}</div>'
        f'{body}'
        f'</body>\n</html>\n'
    )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("사용법: render_report.py <input.json|-> <output.html|->", file=sys.stderr)
        return 2

    in_path, out_path = argv[1], argv[2]

    if in_path == "-":
        raw = sys.stdin.read()
    else:
        with open(in_path, "r", encoding="utf-8") as f:
            raw = f.read()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"ERROR: 입력 JSON 파싱 실패 — {e}", file=sys.stderr)
        return 3

    if not isinstance(data, dict):
        print("ERROR: 최상위는 JSON 객체여야 합니다.", file=sys.stderr)
        return 3

    if not data.get("mp_id"):
        print("ERROR: 'mp_id' 필드 필수.", file=sys.stderr)
        return 3

    out = render_html(data)
    if out_path == "-":
        sys.stdout.write(out)
    else:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
