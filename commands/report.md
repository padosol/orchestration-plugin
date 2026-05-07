---
description: MP 운영 데이터 덤프 + 결정적 템플릿으로 REPORT.html 작성
argument-hint: <mp-id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*), Bash(python3:*), Write
---

다음 명령으로 데이터 덤프를 받습니다.

!`${CLAUDE_PLUGIN_ROOT}/scripts/report.sh $ARGUMENTS`

**역할**: 위 출력은 해당 MP 의 운영 흐름·코드 변경·토큰 사용량·도구 분포·에러·메시지 카운트가 담긴 **원본 데이터** 입니다. orch 가 이를 해석해 회고 REPORT.html 을 작성합니다.

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

6. **AI-Ready 영향 검사 — 후속 Linear 이슈 자동 생성** (REPORT.html 직후 자동 수행):

   변경 파일 목록을 보고 CLAUDE.md / 핵심 docs 가 stale 해질 후보를 식별 → 발견 시 후속 Linear 이슈 자동 생성. 매번 ai-ready-audit 100점 루브릭을 돌리는 게 아니라, **이번 변경분에 한정한 가벼운 영향 검사**.

   절차:
   1. **변경 파일 목록** — 위 데이터의 워커별 diff stat 에서 변경된 파일 경로 모두 모음.
   2. **영향 후보 식별** — 다음 중 하나라도 해당하면 "docs 갱신 후보" 로 마크:
      - 새 모듈/패키지/디렉토리 추가
      - public API (controller, service interface, port) 신규/제거/시그니처 변경
      - DB 스키마 / migration 추가
      - 핵심 dependency 추가 또는 메이저 버전 변경
      - Build/CI 설정 변경 (gradle, package.json scripts, github workflow)
      - 기존 CLAUDE.md / AGENTS.md / docs/ 에서 변경 파일이 mention 됨
   3. **stale 여부 직접 확인** — 후보 파일을 mention 하는 CLAUDE.md/`*.md` 를 grep 한 뒤 본문이 변경 이후에도 정확한지 Read 로 검증. 부정확/누락 발견 시 stale 위치 (file:line) 명시.
   4. **stale 발견 시 후속 Linear 이슈 자동 생성** — `mcp__linear-server__save_issue`:
      - title: `[docs] MP-N 변경에 따른 CLAUDE.md / docs 갱신`
      - description: 구체 stale 위치 + 갱신 방법 (commit / PR 링크 인용)
      - team: 본 MP 와 동일한 team
      - parent: 본 MP issue
      - priority: 3 (Medium) 또는 4 (Low)
      - labels: `docs`, `ai-ready` (팀에 라벨이 존재할 때만)

      stale 미발견 시 이슈 생성 안 함.
   5. **JSON 의 `ai_ready_check` 필드에 결과 반영** 후 4번 단계 다시 실행해 REPORT.html 갱신:
      - 자동 생성된 이슈가 있으면 `auto_issue: {id, url}` 채움
      - stale 위치는 `stale_items` 배열로
      - narrative 한 줄 ("stale 항목 자동 검사 결과 X — 영향 없음" 또는 "X건 발견, 자동 이슈 생성")

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
- 6번 (AI-Ready 영향 검사 + 후속 이슈) 도 사용자 컨펌 없이 자동 수행 (사용자가 폐기 결정한 경우만 SKIP — 인박스 메시지에 그 신호가 보이면 SKIP).

**주의**:
- ❌ HTML / CSS 직접 작성 — 매번 양식 달라짐 (결정적 템플릿 렌더러가 따로 있음)
  ✅ JSON 만 만들고 render_report.py 에 위임. 양식은 스크립트에 고정
- ❌ 단순 복붙 — 데이터 그대로 붙이기
  ✅ 데이터를 **해석**해 사용자 관점 narrative 로 풀어쓰기 (특히 summary.narrative, as_is_to_be, observations)
- ❌ 토큰 분석에서 Read 가 같은 파일 반복 / 도구 호출 쏠림 발견했는데 침묵
  ✅ token_analysis.observations 에 명시적으로 짚기
- ❌ 핸드오프 페인포인트가 없을 때 빈 문자열
  ✅ narrative 에 "발견된 마찰 없음" 명시 (또는 handoff 객체 자체를 누락 — 둘 다 같은 표시)
