---
description: Claude Code 모든 세션 jsonl 을 스캔해 슬래시 / 스크립트 / 스킬 / 서브에이전트 사용량 집계 — dead code 후보 식별
argument-hint: [--since ISO] [--until ISO] [--plugin prefix] [--top N] [--format md|json]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/usage-stats.py:*)
---

다음 명령으로 사용량 통계를 출력하세요.

!`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/usage-stats.py $ARGUMENTS`

**데이터 소스**: `~/.claude/projects/*/*.jsonl` — Claude Code 가 모든 세션의 user message + tool_use 를 자동 기록.

**집계 카테고리**:
1. **Slash commands** — user message 의 `<command-name>/X</command-name>` 태그 카운트 (사용자가 직접 타이핑한 슬래시).
2. **Bash scripts** — Bash tool_use 의 `command` 안에 등장한 `*.sh` 파일명. plugin 스크립트가 슬래시/스킬 안에서 호출돼도 잡힘.
3. **Skills** — Skill tool_use `input.skill`. Claude 가 자율적으로 스킬 호출한 횟수.
4. **Subagent types** — Agent tool_use `input.subagent_type`.

**옵션**:
- `--since 2026-05-01` / `--until 2026-05-31` — ISO 시점 필터
- `--plugin orch:` — 해당 prefix 슬래시/스킬만 (Bash 스크립트는 prefix 필터 X)
- `--top 30` — 카테고리별 상위 N (기본 20)
- `--format json` — JSON 출력 (다른 도구가 소비할 때)
- `--zero <listfile>` — 등록된 entity 목록 파일 (한 줄당 이름) 과 대조해 카운트 0 항목 별도 보고
- `--zero-category commands|scripts|skills|agents` — `--zero` 대조 카테고리 (기본 commands)

**Dead code 후보 찾는 워크플로**:
```bash
# 1. 현재 등록된 .sh 파일 목록 생성
find ${CLAUDE_PLUGIN_ROOT}/scripts ${CLAUDE_PLUGIN_ROOT}/hooks -name '*.sh' -type f 2>/dev/null \
    | sed "s#^${CLAUDE_PLUGIN_ROOT}/##" > /tmp/orch-sh.txt

# 2. 카운트 0 인 파일 식별
/orch:usage-stats --zero /tmp/orch-sh.txt --zero-category scripts

# 3. 슬래시도 같은 식으로
ls ${CLAUDE_PLUGIN_ROOT}/commands/*.md | xargs -n1 basename | sed 's/\.md$//' | sed 's|^|/orch:|' > /tmp/orch-cmds.txt
/orch:usage-stats --plugin orch: --zero /tmp/orch-cmds.txt
```

**주의**: 카운트 0 ≠ 즉시 삭제 OK. user-facing 슬래시는 사용자가 알아야 하는 entry-point 라 한 번도 안 불렸어도 의미 있을 수 있음. Bash 스크립트가 다른 스크립트 안에서만 호출되는 core/lib 형 (`scripts/core/lib.sh`, `inbox-parse.py`) 는 다른 카운트로 추론. 최종 삭제 결정 전 grep 으로 cross-reference 권장.
