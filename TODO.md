# orch — 후속 작업 메모

작업 우선순위는 위에서 아래 순. 현재 활성 MP 가 끝난 뒤 잡는다.

> **상태 업데이트 (2026-05-06)**: 항목 1~6 모두 구현 완료.
> 1. ✅ check-inbox 단건 모드 (inbox.sh + inbox-archive.sh + inbox-parse.py + check-inbox.md)
> 2. ✅ mp-down 머지 브랜치 자동 cleanup (lib.sh helpers + mp-down.sh)
> 3. ✅ PR 생성 후 gh pr checks --watch 흐름 (leader-spawn.sh / mp-up.sh first_msg)
> 4. ✅ /orch:peek 가벼운 health check (peek.sh + peek.md)
> 5. ✅ /orch:report 유지보수 리포트 (report.sh + report.md, mp-down 통합)
> 6. ✅ /orch:errors --analyze (errors.sh)
> 7. orch pane ORCH_BIN_DIR — 보류 유지 (필요시 작업)

이력 보존 목적으로 원문 유지. 새 후속작업은 아래에 추가.

---

## 1. `/orch:check-inbox` — id 단위 단건 처리 모드 추가

### 문제
inbox 에 메시지가 여러 개 쌓인 상태로 `/orch:check-inbox` 를 부르면 모든 메시지가 한 번에 출력됨 → LLM 이 한 턴 안에서 전부 처리하려다 컨텍스트가 부풀고 처리 품질 저하. mp-9 운영 중 mp-9 leader 가 두 메시지를 한 턴에 묶어 응답한 사례에서 발견.

### 변경안
`/orch:check-inbox [id]` 형태로 인자를 받아, 인자가 있으면 해당 id 의 메시지 1건만 출력 후 처리.

대안 (조합 가능):
- (a) **단건 모드**: `/orch:check-inbox <id>` — 해당 id 만 출력. 처리 후 inbox.md 에서 그 블록만 archive 로 이동(현재는 파일 단위 archive 임).
- (b) **요약 모드**: `/orch:check-inbox` (인자 없음) → 전체 메시지 본문 대신 `id | from | ts | 첫줄` 표만 출력. 사용자/LLM 이 보고 `/orch:check-inbox <id>` 로 단건 처리.
- (c) **--next 모드**: `/orch:check-inbox --next` — 가장 오래된 1건만 출력 후 처리. 자동으로 한 건씩 진행.

권장: (b) + (a) 조합. 인자 없으면 요약, 인자 있으면 본문 + 처리.

### 영향 파일
- `scripts/inbox.sh` — id 인자 파싱 + 요약/단건 모드 분기. 현재는 통째 cat.
- `commands/check-inbox.md` — 새 인자 형식 안내 + LLM 행동 가이드 갱신 (요약 모드면 "단건씩 골라 처리하라").
- `scripts/inbox-archive.sh` — 단건 archive 지원 추가 (현재는 파일 통째 mv). 블록 단위 cut+append 필요.
- `scripts/lib.sh` — 메시지 블록을 id 로 찾는 헬퍼 (`orch_inbox_get_by_id <wid> <id>`), 블록 제거 헬퍼 (`orch_inbox_remove_by_id`).

### 잠재 함정
- inbox.md 의 메시지 블록 경계 (`---` front-matter) 를 파싱하다가 본문 안에 `---` 가 있으면 깨짐. 현재 `orch_append_message` 는 본문 그대로 넣으니 본문에 `---` 가 들어갈 수 있음. 파싱은 front-matter `id:` 라인 키로 블록 시작점을 찾고, 다음 블록의 front-matter 시작 또는 EOF 까지를 한 메시지로 보는 식이 안전.
- archive 가 파일 통째 mv → 블록 단위 추출+append 로 바뀌면 동시성 처리 (flock) 필요.

### 수용 기준
- `/orch:check-inbox` (인자 없음) — 전체 메시지 요약 표 출력 (각 줄: `id | from | ts | 첫줄 50자`)
- `/orch:check-inbox <id>` — 해당 id 메시지 본문 출력 + 처리 후 그 블록만 archive 이동
- 동일 inbox 에 메시지 N개 있을 때 N번 호출로 모두 처리 가능
- 잘못된 id 면 명확한 에러 + 사용 가능한 id 목록 제시
- inbox.md 본문에 `---` 가 들어 있어도 파싱 안 깨짐

---

## 2. `/orch:mp-down` — 머지된 브랜치 worktree 자동 정리 (default)

### 문제
mp-down 이 worktree 를 통째로 보존만 함 → 머지 끝난 브랜치도 디스크에 잔재. mp-9 종료 후에도 `lol-server`/`lol-ui` 워크트리가 그대로 남았음.

### 변경안
mp-down 이 산하 워커마다 다음 검사 후 분기:
- `git -C <project_path> branch -r --merged origin/<base>` 결과에 워커의 브랜치가 있으면 → `git -C <project_path> worktree remove <worktree_path>` + `git branch -d <branch>` (origin 푸시는 사용자 책임)
- 미머지면 → 보존, archive 안내문에 "수동 정리 필요" 명시

옵션:
- `--no-cleanup` 으로 자동 정리 끔 (기본은 cleanup ON)
- `--force-cleanup` 으로 미머지도 강제 정리 (위험, 확인 프롬프트 후)

### 영향 파일
- `scripts/mp-down.sh` — 워커별 cleanup 분기 추가
- `scripts/lib.sh` — `orch_branch_is_merged <project_path> <branch> <base>` 헬퍼
- `commands/mp-down.md` — 옵션 안내

### 잠재 함정
- worktree 디렉토리에 untracked 파일이 있으면 `worktree remove` 가 실패. `--force` 줄지, 사용자 확인 받을지 선택 필요. 권장: 일단 dry-run 결과 보여주고 확인.
- 사용자가 push 안 한 커밋이 있을 수 있음. branch -d (소문자) 는 unmerged면 거부 — 안전. -D (대문자) 절대 자동으로 쓰지 말 것.

### 수용 기준
- mp-down 시 머지된 브랜치 워크트리·로컬 브랜치 자동 정리
- 미머지는 보존 + archive 안내문에 명시
- untracked 파일 있는 worktree 는 사용자 확인 받음

---

## 3. PR 생성 후 CI 결과 폴링 (`gh pr checks --watch`)

### 문제
mp-9 await-merge 시 checkstyle 깨졌는데 leader/orch 가 감지 못함. PR 만들고 사용자에게 던져두고 끝.

### 변경안
leader first_msg 의 PR 흐름에 추가:
- `gh pr create` 직후 `gh pr checks <pr> --watch --required` 로 필수 체크 통과까지 대기
- 실패 시 실패한 워크플로우 로그 받아 해당 워커에 재배정
- 통과 시 orch 에 "merge ready" 보고

코드 변경 거의 없음 — leader-spawn.sh + mp-up.sh first_msg 에 흐름 명시만.

### 영향 파일
- `scripts/leader-spawn.sh` — 워커 first_msg 에 "PR 생성 후 자기 영역 체크 통과까지 watch" 추가
- `scripts/mp-up.sh` — leader first_msg 에 "워커 PR 통과 후 orch 보고" 추가

---

## 4. `/orch:peek <worker-id>` — 가벼운 health check

### 문제
워커가 응답 없을 때 leader/orch 가 살아있는지 알 방법은 `/orch:status` 의 alive flag 뿐. 실제 무엇을 하고 있는지(또는 멈췄는지) 모름.

### 변경안
leader 또는 orch 가 호출. 동작:
- `tmux capture-pane -pt <pane_id>` 마지막 30줄 출력
- `tmux display-message -p '#{pane_last_used}' -t <pane_id>` 으로 마지막 활동 시각 출력
- pane 죽었으면 명확히 표시

heartbeat 핑퐁(인박스 메시지로 ack 요구)은 LLM 토큰 낭비라 안 만듦.

### 영향 파일
- `scripts/peek.sh` (신규)
- `commands/peek.md` (신규)
- `scripts/lib.sh` — `orch_pane_capture <pane> <lines>` 헬퍼

---

## 5. `/orch:report <mp-id>` — 유지보수 리포트 자동 생성

### 문제
MP 종료 후 회고가 없음. 다음 MP 에서 같은 실수 반복. 토큰 낭비 / 핸드오프 페인 / 변경 내용이 사라짐.

### 변경안
mp-down 의 부산물(또는 별도 호출)로 `.orch/archive/<mp-id>-YYYY-MM-DD/REPORT.md` 자동 생성.

**섹션 구성** (한국어, GFM):
1. **요약** — 이슈 제목, 산하 워커 목록, 시작/종료 시각, 경과 시간
2. **변경 내용** — 워커별 worktree `git diff <base>..HEAD --stat` + 파일 단위 한 줄 요약
3. **as-is / to-be** — LLM 자동 요약 (잠시 후 설명)
4. **테스트 결과** — 워커 보고 인용 (workers/<id>.md 의 자가보고 필드)
5. **토큰·시간 분석**
   - 워커별 jsonl 파싱 (`~/.claude/projects/<proj>/<session>.jsonl`)
   - 턴별 input/output/cache_read 토큰 합계
   - 도구 호출 횟수 / 종류별 분포
   - 낭비 의심 구간 — 휴리스틱: 같은 파일 N번 read, tool_result > 50KB 인데 다음 턴 산출이 단순한 경우, 파일 read 후 같은 파일 edit 빈번
6. **핸드오프 페인포인트** — leader 자유서술 + orch 회고. LLM 자동 요약 (errors.jsonl 패턴 + leader inbox 의 재질문 빈도 등을 데이터로)
7. **후속 이슈 메모** — SKIP 한 E2E 케이스, 발견된 버그 등

**LLM 자동 요약 방식**:
- 리포트 생성 단계에서 사용자가 "/orch:report <mp-id>" 호출 시, orch 가 위 데이터를 prompt 로 받아 직접 작성. (별도 LLM API 호출 X — 호출자(claude) 자신이 LLM)
- 즉 `report.sh` 는 데이터(diff, jsonl 분석 결과, errors.jsonl 발췌)만 모아 stdout 으로 출력, orch 가 그걸 보고 REPORT.md 작성.

### 영향 파일
- `scripts/report.sh` (신규) — 데이터 수집 + 출력만
- `scripts/report-tokens.py` (신규, 옵션) — jsonl 파싱 (jq 만으론 복잡할 수 있음)
- `commands/report.md` (신규) — orch 에 "데이터를 받아 한국어 REPORT.md 작성" 가이드
- `scripts/mp-down.sh` — 종료 직전 자동 호출 옵션 (`--with-report`, default ON)

### 잠재 함정
- jsonl 파일 위치 — Claude Code 가 worker pane 별 session 을 어디 저장하는지 추적. 워커 시작 시 SessionStart hook 이 session_id 를 workers/<id>.json 에 박도록 hook 갱신 필요할 수도.
- 회고 prompt 가 너무 길면 orch 컨텍스트 부담 — 데이터 사이즈 제한 (top-N 만)

### 수용 기준
- `/orch:report mp-9` — REPORT.md 생성, 위 7개 섹션 포함
- 토큰 분석 표가 워커별로 채워짐
- mp-down 시 자동 생성 (default), `--no-report` 로 끔

---

## 6. `/orch:errors --analyze` — 에러 패턴 자동 요약

### 문제
errors.jsonl 이 쌓여도 사람이 직접 보고 패턴 찾아야 함. orch 가 자동으로 "send.sh: command not found 5건, mp-9/ui 에서만" 같은 표를 보여주면 좋음.

### 변경안
`/orch:errors --analyze` 모드 추가:
- script × exit_code 빈도 표
- stderr 첫 줄 기준 그룹핑 (해시 비슷)
- worker_id × script 매트릭스
- 최빈 에러 top-3 의 stderr 전문

LLM 호출 X — 휴리스틱·jq 만. 자동 fix 는 위험하니 표 제시까지.

### 영향 파일
- `scripts/errors.sh` — `--analyze` 분기 추가
- `commands/errors.md` — 사용 예 추가

---

## 7. orch pane 의 `$ORCH_BIN_DIR` (보류 — 우선순위 낮음)

### 문제
leader/worker 는 spawn 시 `ORCH_BIN_DIR` 자동 export 됨. orch pane 은 사용자가 자기 셸에서 직접 claude 실행한 거라 안 박혀 있음. orch 가 heredoc 으로 보낼 일 생기면 절대경로 직접 써야 함.

### 변경안 (옵션)
- `/orch:up` 출력 마지막에 `export ORCH_BIN_DIR=...` 한 줄 안내 → 사용자가 복붙
- 또는 hook (`session-start.sh`) 에서 systemMessage 로 안내
- 또는 그냥 commands/send.md 에 "orch 는 절대경로 사용" 명시

### 우선순위
낮음. orch 는 대부분 슬래시 명령으로 충분, heredoc 케이스가 드뭄.
