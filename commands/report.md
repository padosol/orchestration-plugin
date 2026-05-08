---
description: MP 운영 데이터 덤프 + 결정적 템플릿으로 REPORT.html 작성
argument-hint: <mp-id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*), Bash(python3:*), Write
---

다음 명령으로 데이터 덤프를 받습니다.

!`${CLAUDE_PLUGIN_ROOT}/scripts/report.sh $ARGUMENTS`

**역할**: 위 출력은 해당 MP 의 운영 흐름·코드 변경·토큰 사용량·도구 분포·에러·메시지 카운트가 담긴 **원본 데이터** 입니다. orch 가 이를 해석해 회고 REPORT.html 을 작성합니다.

**🚫 cwd 보호 + 컨텍스트 보호 — 절대 규칙**:

orch 메인 pane 의 cwd 는 워크스페이스 루트 (예: `/home/padosol/lol`) 에 고정. 본 절차 내내 다음 위반 금지:

- ❌ `cd <repo>` 또는 `cd <subproject>` — 한 번이라도 실행하면 이후 `.orch/...` 상대 경로 / 메일박스 모두 깨짐
- ❌ orch 메인 Bash 로 직접 `git log`, `git diff`, `gh pr view`, 워크스페이스 docs grep/Read — 결과가 메인 컨텍스트에 누적돼 토큰 압박 (특히 step 6/7 의 영향 검사는 변경 파일 다수 + docs 다수 grep)

**대신 다음 패턴 사용**:

- 추가 git 정보 필요 → `git -C <abs-path> ...` (cd 없이) 또는 **Agent (subagent_type=general-purpose 또는 Explore) 로 위임**
- 변경 파일 grep / docs Read / 외부 repo 탐색 → 모두 Agent 로 위임. 메인은 Agent 결과 (요약 markdown) 만 받음
- 위임 시 프롬프트에 절대경로 + 어떤 정보를 어떤 형식으로 회수할지 명시 (예: "리스트 + file:line 만 회수, 본문 인용 X")

**orch 메인 pane 이 직접 하는 작업 (cwd 무관 / 컨텍스트 부담 작음) 만**:

- `/tmp/orch-report-<mp-id>.json` 작성 (Write)
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render_report.py` 호출 (절대경로)
- Linear `mcp__linear-server__save_issue` (MCP, cwd 무관)
- `inbox-archive.sh <id>` (절대경로)

`/orch:prioritize` 가 list/get 호출을 Agent 로 위임하는 것과 같은 이유 — 메인은 결과만 받아 의사결정.

**다음 단계 (orch 만 수행)**:

1. 위 데이터를 해석해 **구조화된 JSON 객체**로 요약 (HTML 직접 작성 금지 — 양식 드리프트 방지)
2. JSON 은 다음 7개 섹션 콘텐츠를 담음 (스키마는 아래 "JSON 스키마" 참조):
   - **요약** — 이슈 무엇이었나, 산하 워커 / 경과 시간 / 결과 한 줄
   - **변경 내용** — 워커별 diff stat 보고 핵심 변경만 한 줄씩 (10줄 이내)
   - **as-is / to-be** — 코드 변경(diff stat + commit 메시지)을 보고 "원래 어땠는데 → 어떻게 바뀌었나" 사용자 시점 요약
   - **테스트 결과** — pr-drafts/reports 또는 archive 메시지의 워커 자가보고 인용. 없으면 narrative 비움 → "워커 자가보고 없음" 자동 표시
   - **토큰·시간 분석** — 모델별 토큰 합계 + 도구 분포 + 큰 tool_result top-5 + 관찰 (Read 반복 / 도구 쏠림 의심)
   - **핸드오프 페인포인트** — errors.jsonl 패턴 + 메시지 흐름의 재질문 빈도. 없으면 "발견된 마찰 없음"
   - **후속 이슈 메모** — SKIP 된 케이스 + 발견된 버그/리팩터 후보

3. JSON 을 임시 파일에 저장 (예: `/tmp/orch-report-<mp-id>.json`)

4. 렌더러 호출 — HTML 골격 / CSS / 섹션 순서가 고정되어 매번 동일한 양식이 보장됨:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render_report.py \
     /tmp/orch-report-<mp-id>.json \
     <scope_dir>/REPORT.html
   ```

   `<scope_dir>` 는 위 데이터 메타의 `scope_dir` 값 그대로 사용. 예: `/home/padosol/lol/.orch/archive/mp-9-2026-05-06/REPORT.html`

5. 사용자에게 경로와 한 줄 요약만 전달

6. **자가진단 — errors.jsonl 영향 검사 + 개선 액션** (REPORT.html 직후 자동 수행, AI-Ready 검사보다 먼저):

   이번 사이클 동안 누적된 에러를 **개선 루프에 실제로 반영**하는 단계. 단순히 `handoff.narrative` 에 "에러 N건" 한 줄로 끝내지 말고, 패턴을 식별하고 액션을 도출해 후속 이슈로 박아라 — 그래야 다음 사이클에서 같은 함정을 안 밟는다.

   **위임 규칙**: scope errors.jsonl entry 가 5건 이상이거나 stderr 가 길면 패턴 분석을 **Agent (general-purpose) 로 위임** — 메인은 patterns + suggested_fix 요약만 받음. entry 가 적으면 메인에서 직접 그룹화 OK.

   절차:
   1. **scope errors.jsonl 스캔** — 위 raw 데이터의 "에러 로그 (이 MP scope)" 섹션 entry 모두. 비어 있으면 narrative "이번 사이클 에러 0건 — 개선할 패턴 없음" 으로 마무리하고 후속 이슈 SKIP.
   2. **패턴 식별** — `(script, exit_code, stderr 첫 줄)` 로 그룹화. 다음 중 하나라도 해당하면 후보:
      - 같은 그룹 2회 이상 (반복 마찰)
      - 단발이라도 root cause 가 스크립트 / 슬래시 / first_msg / 라우팅 가이드 결함으로 추정 가능 (예: 워커가 `/orch:send` 를 특수문자 그대로 호출해 깨진 케이스 → first_msg 의 heredoc 안내 누락)
   3. **개선 액션 도출** — 각 후보 패턴마다 한 줄 fix 제안 (어디를 어떻게 — 스크립트 함수명 / first_msg 절 / 슬래시 옵션 등 구체적으로).
   4. **후속 이슈 자동 생성** — settings.json 의 `issue_tracker` 분기 (AI-Ready 검사와 동일 패턴):
      - `linear` → `mcp__linear-server__save_issue`:
        - title: `[orch-fix] MP-N 사이클 errors.jsonl 패턴 개선`
        - description: 패턴별 (script · rc · 횟수 · stderr 첫 줄) + 도출된 fix 액션 + 본 MP 링크
        - team: 본 MP 와 동일한 team
        - parent: 본 MP issue
        - priority: 3 (Medium)
        - labels: `bug`, `orch-fix` (팀에 라벨이 존재할 때만)
      - `github` → `gh issue create --repo <github_issue_repo> --title '...' --body '...' --label bug`
        - title / body 형식 동일. parent 링크는 body 에 텍스트로 (`Related: #N`).
      - `none` → 이슈 자동 생성 SKIP. 패턴만 REPORT.html 의 `errors_check.patterns` 에 기록.
   5. **JSON 의 `errors_check` 필드에 결과 반영** 후 4번 단계(렌더러 호출) 다시 실행해 REPORT.html 갱신:
      - `narrative`: "이번 사이클 에러 N건 / 반복 패턴 K개 / 자동 이슈 X건 생성" 또는 "에러 0건 — 개선할 패턴 없음"
      - `patterns`: `[{script, exit_code, count, first_line, suggested_fix}]`
      - `auto_issue`: `{id, url}` (생성됐을 때만, 트래커 linear/github)

   **금지**:
   - ❌ errors.jsonl 0건이 아닌데 patterns 비워둔 채 narrative "에러 N건" 한 줄로 종결 — 매번 사용자가 직접 패턴 분석해야 함
   - ❌ 후속 이슈 본문에 stderr 전체 dump — 첫 줄 + 그룹 횟수 + fix 액션 까지만 (raw 는 errors.jsonl 에 이미 있음)

7. **AI-Ready 영향 검사 — 후속 이슈 자동 생성** (REPORT.html 직후 자동 수행):

   변경 파일 목록을 보고 CLAUDE.md / 핵심 docs 가 stale 해질 후보를 식별 → 발견 시 후속 이슈 자동 생성. 매번 ai-ready-audit 100점 루브릭을 돌리는 게 아니라, **이번 변경분에 한정한 가벼운 영향 검사**.

   **위임 규칙 (필수)**: 본 단계의 grep / Read / git fetch 는 **모두 Agent (subagent_type=Explore 또는 general-purpose) 로 위임**. 변경 파일 5개 이상 또는 grep 대상 docs 3개 이상이면 단일 Agent 호출로 묶어 한 번에 stale 위치 (file:line + 사유) 만 회수. orch 메인이 직접 grep/Read 하면 본 이슈(PAD-36) 의 cwd 오염 / 컨텍스트 누적 재발.

   **Agent 프롬프트 예시 (그대로 차용)**:
   ```
   변경 파일 N개: [절대경로 리스트]
   각 파일을 mention 하는 다음 docs 안에서 stale 위치 식별:
   - <repo>/CLAUDE.md
   - <repo>/AGENTS.md
   - <repo>/docs/**/*.md
   회수 형식: [{file: "path", lines: "12-20", reason: "한 줄"}] JSON. 본문 인용 금지.
   ```

   절차:
   1. **변경 파일 목록** — 위 데이터의 워커별 diff stat 에서 변경된 파일 경로 모두 모음.
   2. **영향 후보 식별** — 다음 중 하나라도 해당하면 "docs 갱신 후보" 로 마크:
      - 새 모듈/패키지/디렉토리 추가
      - public API (controller, service interface, port) 신규/제거/시그니처 변경
      - DB 스키마 / migration 추가
      - 핵심 dependency 추가 또는 메이저 버전 변경
      - Build/CI 설정 변경 (gradle, package.json scripts, github workflow)
      - 기존 CLAUDE.md / AGENTS.md / docs/ 에서 변경 파일이 mention 됨
   3. **stale 여부 확인 — Agent 위임** — 후보 파일을 mention 하는 CLAUDE.md/`*.md` grep + 본문 정확성 Read 검증을 Agent 한 번에 위임 (위 "Agent 프롬프트 예시" 그대로 사용). orch 메인은 결과 JSON 만 받음. **메인 pane Bash 로 grep/Read 직접 호출 금지**.
   4. **stale 발견 시 후속 이슈 자동 생성** — settings.json 의 `issue_tracker` 값에 따라 분기:
      - `linear` → `mcp__linear-server__save_issue`:
        - title: `[docs] MP-N 변경에 따른 CLAUDE.md / docs 갱신`
        - description: 구체 stale 위치 + 갱신 방법 (commit / PR 링크 인용)
        - team: 본 MP 와 동일한 team
        - parent: 본 MP issue
        - priority: 3 (Medium) 또는 4 (Low)
        - labels: `docs`, `ai-ready` (팀에 라벨이 존재할 때만)
      - `github` → `gh issue create --repo <github_issue_repo> --title '...' --body '...' --label docs`
        - title / body 형식 동일. parent 링크는 body 에 텍스트로 (`Related: #N`).
      - `none` → 이슈 자동 생성 SKIP. stale 위치만 REPORT.html 의 `ai_ready_check.stale_items` 에 기록 — 사용자가 직접 후속 처리.

      stale 미발견 시 이슈 생성 안 함.
   5. **JSON 의 `ai_ready_check` 필드에 결과 반영** 후 4번 단계 다시 실행해 REPORT.html 갱신:
      - 자동 생성된 이슈가 있으면 `auto_issue: {id, url}` 채움 (트래커 linear/github 일 때만)
      - stale 위치는 `stale_items` 배열로
      - narrative 한 줄 ("stale 항목 자동 검사 결과 X — 영향 없음" 또는 "X건 발견, 자동 이슈 생성" 또는 "X건 발견, 트래커 미사용으로 직접 처리 필요")

## JSON 스키마

`render_report.py --help` (또는 스크립트 상단 docstring) 에 정식 스키마가 있음. 핵심:

```json
{
  "mp_id":        "MP-9",
  "scope_dir":    "/home/.../mp-9-2026-05-06",
  "generated_at": "2026-05-07T07:30:00Z",

  "summary": {
    "issue_title": "...", "worker_count": 2, "duration": "약 47분",
    "result_line": "PR #84 머지됨", "narrative": "한 문장 요약"
  },

  "changes": {
    "workers": [
      {"id": "MP-9/server", "branch": "feature/...", "diff_stat": "5 files, +123 -8",
       "highlights": ["변경 한 줄"]}
    ],
    "pr_url": "https://github.com/.../pull/84"
  },

  "as_is_to_be": [{"as_is": "...", "to_be": "..."}],

  "test_results": {"narrative": "..."},

  "token_analysis": {
    "by_model": [
      {"model": "claude-opus-4-7", "messages": 412, "input": 53210, "output": 188400,
       "cache_read": 33000000, "cache_creation": 880000, "cost_usd": 73.42}
    ],
    "total_cost_usd": 73.42,
    "tool_distribution": [{"tool": "Read", "count": 134}],
    "large_tool_results_top5": [{"target": "src/x.go", "size": 41200, "note": "..."}],
    "observations": ["Read 반복 의심"]
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
    "narrative": "...",
    "stale_items": [{"file": "CLAUDE.md", "lines": "12-20", "reason": "..."}],
    "auto_issue": {"id": "PAD-XX", "url": "https://linear.app/..."}
  }
}
```

필수 필드: `mp_id`. 나머지는 모두 optional — 누락된 섹션은 "X 없음" 으로 자동 표시.

**자동 호출**:
- `issue-down` 이 종료 보고 메시지에 "REPORT.html 자동 작성 요청" 을 명시함. orch 가 인박스 처리할 때 그 메시지를 보면 별도 사용자 지시 없이 `/orch:report <mp-id>` 실행해 작성.
- 6번 (errors.jsonl 자가진단) / 7번 (AI-Ready 영향 검사) 도 사용자 컨펌 없이 자동 수행. 둘 다 후속 이슈 생성까지 끝내고 REPORT.html 갱신 1회로 마무리 (사용자가 폐기 결정한 경우만 SKIP — 인박스 메시지에 그 신호가 보이면 SKIP).

**주의**:
- ❌ HTML / CSS 직접 작성 — 매번 양식 달라짐 (결정적 템플릿 렌더러가 따로 있음)
  ✅ JSON 만 만들고 render_report.py 에 위임. 양식은 스크립트에 고정
- ❌ 단순 복붙 — 데이터 그대로 붙이기
  ✅ 데이터를 **해석**해 사용자 관점 narrative 로 풀어쓰기 (특히 summary.narrative, as_is_to_be, observations)
- ❌ 토큰 분석에서 Read 가 같은 파일 반복 / 도구 호출 쏠림 발견했는데 침묵
  ✅ token_analysis.observations 에 명시적으로 짚기
- ❌ 핸드오프 페인포인트가 없을 때 빈 문자열
  ✅ narrative 에 "발견된 마찰 없음" 명시 (또는 handoff 객체 자체를 누락 — 둘 다 같은 표시)
