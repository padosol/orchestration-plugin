---
description: MP 운영 데이터 덤프 (토큰·도구·diff·메시지·에러) — 회고 REPORT.html 작성용 입력
argument-hint: <mp-id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*), Write
---

다음 명령으로 데이터 덤프를 받습니다.

!`${CLAUDE_PLUGIN_ROOT}/scripts/report.sh $ARGUMENTS`

**역할**: 위 출력은 해당 MP 의 운영 흐름·코드 변경·토큰 사용량·도구 분포·에러·메시지 카운트가 담긴 **원본 데이터** 입니다. orch 가 이를 해석해 회고 REPORT.html 을 작성합니다.

**다음 단계 (orch 만 수행)**:

1. 위 데이터를 해석해 한국어 단일 파일 HTML 회고 작성
2. 다음 7개 섹션 포함:
   - **요약** — 이슈 무엇이었나, 산하 워커 / 경과 시간 / 결과 한 줄
   - **변경 내용** — 워커별 diff stat 보고 핵심 변경만 한 줄씩 (10줄 이내). 구현 상세는 PR description 참고 안내
   - **as-is / to-be** — 코드 변경(diff stat + commit 메시지)을 보고 "원래 어땠는데 → 어떻게 바뀌었나" 를 사용자 시점으로 요약
   - **테스트 결과** — pr-drafts/reports 또는 archive 메시지에서 워커 자가 보고 인용. 없으면 "워커 자가보고 없음" 명시
   - **토큰·시간 분석** — 위 토큰 합계 표 그대로 / 도구 호출 분포에서 비대칭(Read 가 같은 파일 반복 등) 의심 / 큰 tool_result top-5 위치 평가
   - **핸드오프 페인포인트** — errors.jsonl 패턴 + 메시지 흐름의 재질문 빈도. 없으면 "발견된 마찰 없음"
   - **후속 이슈 메모** — SKIP 된 케이스 (E2E, 다른 영역) + 발견된 버그/리팩터 후보

3. **HTML 형식 요구사항** (오프라인 열람 가능 단일 파일):
   - `<!doctype html>` + `<meta charset="utf-8">` + `<title>${mp_id} 회고</title>` + 인라인 `<style>` 만 (외부 CDN / CSS / JS / 폰트 로드 금지)
   - 폰트: `system-ui, -apple-system, "Segoe UI", sans-serif`. 코드/숫자 블록은 monospace.
   - 섹션마다 카드 스타일 — 흰 배경 / 연한 1px 보더 / 8-12px rounded / padding 16-24px
   - 본문은 무채색 (회색 계열). 강조는 한두 곳만 색상 (e.g., 머지 PR 번호 강조).
   - 토큰 합계 / 도구 분포 / 큰 tool_result 는 `<table>` 또는 CSS grid 정렬. 표 헤더 굵게.
   - PR / commit / 파일 경로는 `<code>` 모노스페이스.
   - 외부 링크(PR URL 등)는 `<a target="_blank" rel="noreferrer">` 로 새 탭 열기.

4. **저장 경로**: 데이터 메타의 `scope_dir` + `/REPORT.html`
   - 예: `/home/padosol/lol/.orch/archive/mp-9-2026-05-06/REPORT.html`

5. `Write` 도구로 작성 후, 사용자에게 경로와 한 줄 요약만 전달

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
   5. **REPORT.html 의 "후속 이슈 메모" 섹션에 결과 반영**:
      - 자동 생성된 이슈가 있으면 "docs 갱신 자동 이슈: MP-XX [URL]" 명시
      - 없으면 "docs/CLAUDE.md 영향 없음 — stale 항목 자동 검사 결과 X" 명시

**자동 호출**:
- `mp-down` 이 종료 보고 메시지에 "REPORT.html 자동 작성 요청" 을 명시함. orch 가 인박스 처리할 때 그 메시지를 보면 별도 사용자 지시 없이 `/orch:report <mp-id>` 실행해 작성하면 됨.
- 6번 (AI-Ready 영향 검사 + 후속 이슈) 도 사용자 컨펌 없이 자동 수행 (사용자가 폐기 결정한 경우만 SKIP — 인박스 메시지에 그 신호가 보이면 SKIP).

**주의**:
- 단순 복붙 X — 데이터를 **해석**해 사용자 관점 narrative 로 풀어쓰기
- 토큰 분석에서 Read 가 같은 파일 반복 / 도구 호출이 한 종류에 쏠림 같은 패턴이 보이면 명시적으로 짚기
- 핸드오프 페인포인트는 errors.jsonl + 메시지 흐름의 재질문 빈도로 추정 (없으면 "발견 안 됨")
- pr-drafts 가 있으면 PR 결과·리뷰 코멘트 흐름도 살펴서 테스트 결과 / 페인포인트에 반영
