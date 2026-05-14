---
description: MP 운영 데이터 덤프 + 결정적 템플릿으로 REPORT.html 작성
argument-hint: <mp-id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect/report.sh:*), Bash(python3:*), Write
---

다음 명령으로 데이터 덤프를 받습니다.

!`${CLAUDE_PLUGIN_ROOT}/scripts/inspect/report.sh $ARGUMENTS`

**역할**: 위 출력은 해당 MP 의 운영 흐름·코드 변경·토큰 사용량·도구 분포·에러·메시지 카운트가 담긴 **원본 데이터** 입니다. orch 가 이를 해석해 회고 REPORT.html 을 작성합니다.

**🚫 cwd 보호 (절대 규칙)**:

호출자 pane (orch 메인 또는 leader) 의 cwd 는 절대 변경하지 않는다 — orch 는 워크스페이스 루트 (`/orch:up` 등록 위치) 에, leader 는 자기 등록 cwd 에 고정.

- ❌ `cd <repo>` / `cd <subproject>` — 한 번이라도 실행하면 이후 `.orch/...` 상대 경로 / 메일박스 모두 깨짐
- ✅ 다른 repo 정보 필요 → `git -C <abs-path> ...` (cd 없이) 또는 단일 파일 Read (절대경로)
- ✅ scope_dir / archive_dir / REPORT.html 등은 raw 데이터의 절대경로 그대로 사용 — 호출자가 orch 든 leader 든 동일

**📦 컨텍스트·비용 보호 (효율 규칙) — 위치 인지로 분기**:

raw 데이터 (위 report.sh 출력) 에 이미 변경 파일 경로 / commits / diff stat / errors stderr / archive 메시지 다 들어있다. **추가 호출은 위치를 아는지에 따라 다르게 결정**:

- **위치 명확 + 단일/소수 파일** → orch 메인이 직접 호출 OK
  - 단일 파일 `Read <abs-path>` (워크스페이스 루트 밖이어도 무관 — Read 는 cwd 영향 없음)
  - 단발 `git -C <abs-path> log/diff/show ...` (cd 아님)
  - 절대경로 `grep <pattern> <abs-path>` (단일 파일 또는 한 디렉토리)
- **위치 미상 (어느 파일에 있는지 모름)** → `Agent(subagent_type=Explore)` 단발 호출 — 메인은 결과(file:line + 한 줄 사유) 만 받음
- **큰 컨텍스트 작업** (다파일 grep / 여러 docs stale 검증 / 워크스페이스 전체 탐색) → `Agent(subagent_type=general-purpose)` 단발 위임 — 한 호출에 묶어 결과 JSON만 회수

**금지 (낭비)**:
- ❌ raw data 에 이미 file:line 이 있는 정보를 또 Agent 시켜 다시 찾게 함 — Explore 비용 낭비
- ❌ 단발 Read 한 번 하면 끝나는 일을 Agent 위임 — round-trip 낭비
- ❌ 메인 Bash 로 `cd <repo>` — pane cwd 오염

**orch 메인이 직접 하는 작업** (cwd 무관 / 컨텍스트 부담 작음):
- `/tmp/orch-report-<mp-id>.json` 작성 (Write)
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render_report.py` 호출 (절대경로)
- Linear `mcp__linear-server__save_issue` (MCP, cwd 무관)
- `inbox-archive.sh <id>` (절대경로)
- 위 효율 규칙에 해당하는 단일/단발 Read·grep·git -C

`/orch:prioritize` 의 list/get 위임은 본문이 길어 메인 컨텍스트 누적이 큰 케이스라 Agent. 이 단계도 같은 기준으로 판단 — 작으면 직접, 크면 Agent.

**다음 단계 (orch 만 수행)**:

1. 위 데이터를 해석해 **구조화된 JSON 객체**로 요약 (HTML 직접 작성 금지 — 양식 드리프트 방지)
2. JSON 은 다음 8개 섹션 콘텐츠를 담음 (스키마는 아래 "JSON 스키마" 참조):
   - **요약** — 이슈 무엇이었나, 산하 워커 / 경과 시간 / 결과 한 줄
   - **변경 내용** — 워커별 diff stat 보고 핵심 변경만 한 줄씩 (10줄 이내)
   - **as-is / to-be** — 코드 변경(diff stat + commit 메시지)을 보고 "원래 어땠는데 → 어떻게 바뀌었나" 사용자 시점 요약
   - **테스트 결과** — pr-drafts/reports 또는 archive 메시지의 워커 자가보고 인용. 없으면 narrative 비움 → "워커 자가보고 없음" 자동 표시
   - **토큰·시간 분석** — 모델별 토큰 합계 + 도구 분포 + 큰 tool_result top-5 + 관찰 (Read 반복 / 도구 쏠림 의심)
   - **토큰 효율 분석** — 도구별 누적 byte / 파일별 read 빈도 / 워커별 cost 점유 / 낭비 hint. 부적절한 토큰 사용 패턴 식별 후 후속 개선 액션 도출 (다음 사이클에서 절감 효과 측정)
   - **핸드오프 페인포인트** — errors.jsonl 패턴 + 메시지 흐름의 재질문 빈도. 없으면 "발견된 마찰 없음"
   - **후속 이슈 메모** — SKIP 된 케이스 + 발견된 버그/리팩터 후보

3. JSON 을 임시 파일에 저장 (예: `/tmp/orch-report-<mp-id>.json`)

4. 렌더러 호출 — HTML 골격 / CSS / 섹션 순서가 고정되어 매번 동일한 양식이 보장됨:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render_report.py \
     /tmp/orch-report-<mp-id>.json \
     <scope_dir>/REPORT.html
   ```

   `<scope_dir>` 는 위 데이터 메타의 `scope_dir` 값 그대로 사용. 예: `<workspace>/.orch/archive/mp-9-2026-05-06/REPORT.html`

5. 사용자에게 경로와 한 줄 요약만 전달

6. **토큰 효율 분석 — token_efficiency 필드 작성** (REPORT.html 직후 자동 수행):

   부적절하게 낭비되는 토큰을 매 사이클마다 식별 → 후속 개선 액션 도출. 별도 grep 불필요 — raw 데이터의 워커별 jsonl 분석 섹션에 이미 도구별 누적 byte / 파일별 read / 낭비 hint 가 들어있다.

   **데이터 매핑 (raw markdown → token_efficiency JSON)**:

   1. **`tool_size`** — raw 의 "도구별 tool_result 누적 byte top-10" 섹션을 그대로 매핑. share 는 0.0~1.0 float
   2. **`file_reads`** — raw 의 "파일별 누적 read top-5" 섹션을 그대로 매핑. count ≥ 3 인 항목은 자동으로 high 색상 카드로 렌더됨
   3. **`worker_share`** — 워커마다 by_model cost 합계로 환산해 전체 대비 share 계산. ≥ 0.70 인 워커는 자동으로 high (warn 색) 카드로 렌더됨
   4. **`waste_hints`** — raw 의 "낭비 패턴 hint" 섹션 + 메인이 워커 분석으로 보강 (예: "MP-9/server 워커가 비용의 72% 점유")
   5. **`narrative`** — "도구·파일·워커 3축 분석. 낭비 hint N건" 한 줄

   **JSON 직접 호출이 더 정확하면**: `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-jsonls.py <jsonl-dir> --json` (또는 워커 분리 시 `--since <started_at>` 추가). markdown 재해석보다 정확한 share/bytes 숫자 회수.

   **자동 이슈 생성 안 함** — errors_check 와 달리 토큰 낭비 패턴은 매 사이클 거의 항상 발생하므로 자동 이슈는 노이즈. 패턴만 REPORT.html 에 기록하고 사용자가 직접 후속 결정 (예: 같은 파일 5+ 회 read → 캐싱 메모 추가, 단일 도구 80%+ → 해당 도구 SKILL 점검).

7. **자가진단 — errors.jsonl 영향 검사 + 개선 액션** (REPORT.html 직후 자동 수행, AI-Ready 검사보다 먼저):

   이번 사이클 동안 누적된 에러를 **개선 루프에 반영**하는 단계. 패턴을 식별하고 액션을 도출해 후속 이슈 **후보** 로 정리 — 실제 트래커 등록은 orch 가 사용자와 검토 후 결정 (사용자 정책: "팀리더가 제공한 이슈를 사용자와 검토해서 추가").

   **이슈 등록 주체**:
   - leader 는 **후보 도출 + REPORT.html 기록 + orch 인박스 송신** 까지만. 직접 `save_issue` / `gh issue create` / `glab issue create` 호출 금지.
   - orch 가 `[follow-up-candidates <issue_id>]` 메시지 받아 사용자와 검토 → 등록 결정 항목만 트래커에 등록.

   **위임 규칙 (위치 인지로 분기)**: scope errors.jsonl 의 stderr 는 raw data 에 이미 다 들어있다 — 별도 grep 불필요. entry 가 많아 stderr 본문 누적이 부담스러울 때만 **Agent (general-purpose)** 한 번에 묶어 위임. entry 적거나 stderr 짧으면 메인에서 직접 그룹화·해석 OK.

   절차:
   1. **scope errors.jsonl 스캔** — raw 데이터의 "에러 로그 (이 MP scope)" 섹션 entry 모두. 비어 있으면 narrative "이번 사이클 에러 0건 — 개선할 패턴 없음" 으로 마무리하고 후보 송신 SKIP.
   2. **패턴 식별** — `(script, exit_code, stderr 첫 줄)` 로 그룹화. 다음 중 하나라도 해당하면 후보:
      - 같은 그룹 2회 이상 (반복 마찰)
      - 단발이라도 root cause 가 스크립트 / 슬래시 / first_msg / 라우팅 가이드 결함으로 추정 가능 (예: 워커가 `/orch:send` 를 특수문자 그대로 호출해 깨진 케이스 → first_msg 의 heredoc 안내 누락)
   3. **개선 액션 도출** — 각 후보 패턴마다 한 줄 fix 제안 (어디를 어떻게 — 스크립트 함수명 / first_msg 절 / 슬래시 옵션 등 구체적으로).
   4. **JSON 의 `errors_check` 필드에 결과 기록** (자동 트래커 등록 안 함):
      - `narrative`: "이번 사이클 에러 N건 / 반복 패턴 K개 / 등록 후보 K개 — orch 검토 대기" 또는 "에러 0건 — 개선할 패턴 없음"
      - `patterns`: `[{script, exit_code, count, first_line, suggested_fix}]`
      - `auto_issue` 필드는 비워둔다 — orch 가 사용자와 등록 결정 후 채울 수도, 안 채울 수도 있음 (선택). leader 가 채우지 않음.
   5. **orch 인박스로 후보 송신** (패턴 ≥ 1건일 때만) — `[follow-up-candidates <issue_id>]` 라벨 + `errors_check` 카테고리:
      ```
      bash -c "$ORCH_BIN_DIR/messages/send.sh orch <<'ORCH_MSG'
      [follow-up-candidates <issue_id>] errors_check
      - send.sh / rc=2 / 3회 / 'ERROR: ...' → first_msg 의 heredoc 절 보강
      - notify-slack.sh / rc=1 / 1회 / 'curl: …' → 토큰 검증 옵션 추가
      (등록 여부는 사용자 검토 — orch 가 후보 보여주고 결정)
      ORCH_MSG"
      ```
      orch 가 사용자에게 후보 목록을 보여주고 등록 여부를 받음. 등록 트래커는 settings.json 의 `issue_tracker` 분기 (linear → save_issue / github → gh issue create / gitlab → glab issue create / none → SKIP).
   6. **렌더러 재호출** — `errors_check` 채워진 JSON 으로 REPORT.html 갱신.

   **금지**:
   - ❌ leader 가 직접 `save_issue` / `gh issue create` / `glab issue create` 호출 — 사용자 검토 단계 우회
   - ❌ errors.jsonl 0건이 아닌데 patterns 비워둔 채 narrative "에러 N건" 한 줄로 종결 — 매번 사용자가 직접 패턴 분석해야 함
   - ❌ 후속 이슈 후보 본문에 stderr 전체 dump — 첫 줄 + 그룹 횟수 + fix 액션 까지만 (raw 는 errors.jsonl 에 있음)

8. **AI-Ready 영향 검사 — 후속 이슈 후보 도출** (REPORT.html 직후 자동 수행):

   변경 파일 목록을 보고 CLAUDE.md / 핵심 docs 가 stale 해질 후보를 식별 → 발견 시 **후속 이슈 후보** 정리 (자동 트래커 등록 X — orch 검토 후 등록). 매번 ai-ready-audit 100점 루브릭을 돌리는 게 아니라, **이번 변경분에 한정한 가벼운 영향 검사**.

   **이슈 등록 주체** (errors_check 와 동일 원칙): leader 가 후보 도출 + REPORT.html 기록 + orch 인박스 송신까지만. orch 가 사용자와 검토 후 등록.

   **위임 규칙 (위치 인지로 분기)**:
   - 변경 파일 경로는 raw data 에 이미 절대경로 명시 — 직접 사용. 추가 탐색 불필요.
   - docs 위치 명확 (CLAUDE.md / AGENTS.md / docs/ 같은 표준 경로) + 변경 파일 ≤ 3개 → 메인이 직접 `grep -l` (절대경로) 한 번 + `Read` 한 번씩 검증. round-trip 낭비 X.
   - **변경 파일 ≥ 5개 또는 docs 후보 ≥ 3개** → `Agent(subagent_type=general-purpose)` 단발 위임으로 묶어 한 번에 stale 위치 (file:line + 사유) JSON 만 회수.
   - **docs 위치 미상** (특이한 위치에 mention 가능성) → `Agent(subagent_type=Explore)` 한 번. 메인은 결과만.

   **Agent 프롬프트 템플릿 (위임할 때만 사용)**:
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
   3. **stale 여부 확인** — 위 "위임 규칙" 에 따라 분기. 작은 케이스는 메인이 직접 `grep -l <pattern> <abs-path>` + `Read` 한 번씩, 큰 케이스만 Agent 단발 위임. 둘 다 결과는 (file:line + 한 줄 사유) JSON 형태로 정리해 다음 단계에서 issue body 에 포함.
   4. **stale 발견 시 후속 이슈 후보 정리** (자동 트래커 등록 X):
      - REPORT.html 의 `ai_ready_check.stale_items` 에 stale 위치 + 사유 기록.
      - **orch 인박스로 후보 송신** (stale ≥ 1건일 때만) — `[follow-up-candidates <issue_id>]` 라벨 + `ai_ready_check` 카테고리:
        ```
        bash -c "$ORCH_BIN_DIR/messages/send.sh orch <<'ORCH_MSG'
        [follow-up-candidates <issue_id>] ai_ready_check
        - CLAUDE.md:12-20 / "API endpoint 목록" 절 / src/api/v2/foo.go 신규로 누락
        - docs/architecture.md:34 / "auth flow" 절 / 토큰 저장 위치 변경됨
        (등록 여부는 사용자 검토 — orch 가 후보 보여주고 결정)
        ORCH_MSG"
        ```
        orch 가 사용자와 검토 → 등록 결정 항목만 트래커에 등록 (linear → save_issue / github → gh issue create / gitlab → glab issue create / none → SKIP).

      stale 미발견 시 송신 SKIP.
   5. **JSON 의 `ai_ready_check` 필드에 결과 반영** 후 렌더러 재호출:
      - `auto_issue` 필드는 leader 가 채우지 않음 (orch 가 등록한 경우 사후 채울 수도, 안 채울 수도).
      - stale 위치는 `stale_items` 배열로
      - narrative 한 줄 ("stale 항목 0건 — 영향 없음" 또는 "X건 발견 — orch 검토 대기" 또는 "X건 발견, 트래커 미사용으로 직접 처리 필요")

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

  "token_efficiency": {
    "narrative": "도구·파일·워커 3축 분석. 낭비 hint N건",
    "tool_size": [
      {"name": "Grep", "bytes": 55015, "share": 0.70}
    ],
    "file_reads": [
      {"path": "/proj/src/foo.py", "count": 3, "bytes": 24006}
    ],
    "worker_share": [
      {"worker_id": "MP-9/server", "share": 0.72, "cost_usd": 295.40}
    ],
    "waste_hints": [
      "같은 파일 3회 read — 캐싱 미활용 의심"
    ]
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

**호출 주체**:
- **정상 흐름 — leader 가 호출**: cascade shutdown 직전 자기 phase 마지막 단계로 `/orch:report <issue_id>` 실행. 이 시점에 본 절차 (1~8단계 + 후속 이슈 후보 송신) 전부 수행.
- **orch 가 호출하는 두 케이스만**:
  1. 사용자가 `/orch:report <issue_id>` 명시 호출 — archive 의 REPORT-data.md 다시 보거나 후속 후보 재검토.
  2. issue-down 알림에 "REPORT.html 누락" hint — orch 가 자동 호출하는 게 아니라 사용자에게 수동 복구 권유.
- orch 가 issue-down 알림 받았다고 자동으로 `/orch:report` 호출하지 않는다 — REPORT 는 leader 책임, 중복 호출은 사고의 원인.
- 6번 (token_efficiency) / 7번 (errors.jsonl 자가진단) / 8번 (AI-Ready 영향 검사) 은 본 호출 안에서 사용자 컨펌 없이 자동 수행. **7/8번은 후속 이슈 후보 도출 + orch 인박스 송신까지** (leader 가 직접 트래커 등록하지 않음), 6번은 REPORT.html 에 패턴 기록만. 셋 다 같은 REPORT.html 1회 갱신으로 마무리.

**주의**:
- ❌ HTML / CSS 직접 작성 — 매번 양식 달라짐 (결정적 템플릿 렌더러가 따로 있음)
  ✅ JSON 만 만들고 render_report.py 에 위임. 양식은 스크립트에 고정
- ❌ 단순 복붙 — 데이터 그대로 붙이기
  ✅ 데이터를 **해석**해 사용자 관점 narrative 로 풀어쓰기 (특히 summary.narrative, as_is_to_be, observations)
- ❌ 토큰 분석에서 Read 가 같은 파일 반복 / 도구 호출 쏠림 발견했는데 침묵
  ✅ token_analysis.observations 에 명시적으로 짚기
- ❌ 핸드오프 페인포인트가 없을 때 빈 문자열
  ✅ narrative 에 "발견된 마찰 없음" 명시 (또는 handoff 객체 자체를 누락 — 둘 다 같은 표시)
