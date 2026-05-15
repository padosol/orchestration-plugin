# orch — Claude Code 멀티-워커 오케스트레이션

**한 명의 이슈 관리자 (orch) + 여러 명의 팀리더 (leader) + 그 산하 프로젝트 워커들** 을 tmux pane / git worktree / 파일 메일박스 위에 얹어 한 사람이 동시에 굴리도록 만든 Claude Code 플러그인.

```
사용자 ─┬─ orch (issue manager / dispatcher)
        ├─ issue-13 (leader) ─┬─ issue-13/repo-a   → PR #142
        │                     ├─ issue-13/repo-b   → PR #143
        │                     └─ issue-13/repo-c   → PR #144
        └─ issue-42 (leader) ─┬─ issue-42/repo-a   → PR #97
                              └─ issue-42/repo-b   → PR #166
```

각 leader / worker 는 자기 worktree + 자기 Claude 세션을 가진다. leader 식별자(`<issue_id>`)는 사용자가 `/orch:issue-up` 에 넘긴 이슈 키 그대로 — 트래커 무관 (대소문자 보존, shell-위험 문자·`/`·`..` 만 차단). 모든 메시지는 hub-and-spoke — 워커끼리 직접 통신 차단, 항상 leader 경유.

---

## 무엇을 풀어주는가

- **컨텍스트 분리** — 큰 이슈를 한 Claude 세션에 통째로 넣으면 컨텍스트 압박으로 품질이 떨어진다. orch 가 분해해 워커별로 깨끗한 컨텍스트를 준다.
- **병렬 작업** — 여러 repo 에 걸친 이슈를 워커가 독립적으로 동시 진행.
- **PR 라이프사이클 자동화** — PR 생성 → CI 통과 대기 → 깨끗한 컨텍스트의 reviewer 자동 spawn → LGTM 라우팅 → 머지 대기 → 자동 cascade shutdown + worktree 정리 + REPORT.html.
- **사람 알림** — 동시다발로 끝나는 워커들 사이에서 "지금 뭐 봐야 하지?" 가 안 되도록 Slack 알림 (이벤트 6 카테고리, 즉시 발송).

---

## 빠른 시작

처음 한 번 (1, 2) 셋업, 이후 매 워크스페이스마다 (3, 4) 진행.

### 1. 플러그인 설치 (1회)

```
/plugin marketplace add padosol/padosol-marketplace
/plugin install orch
```

scope 는 **project** 권장 (워크스페이스 `.claude/settings.json` 에 등록 → 해당 워크스페이스에서만 활성화).

### 2. tmux 설치

```bash
sudo apt install tmux        # Debian/Ubuntu
brew install tmux            # macOS
```

orch / leader / worker 가 각각 별도 pane 에서 Claude 세션을 들고 동시에 동작하기 때문에 필요.

### 3. tmux 세션 시작 + orch 초기화

신규 세션 (워크스페이스 첫 진입):

```bash
cd ~/path/to/workspace
tmux new -s "$(basename "$PWD")"   # 세션 이름 = 디렉토리 basename 권장
claude                              # tmux pane 안에서 Claude 실행
```

Claude pane 안에서 워크스페이스당 한 번씩:

```
/orch:up      # 현재 pane 을 orch 로 등록
/orch:setup   # .orch/settings.json 자동 생성 — 트래커 / git host / Slack 3종 메타를 AskUserQuestion TUI 로 묻는다
```

기존 세션 재진입:

```bash
tmux attach -t <session-name>
```

### 4. 첫 이슈 위임

큰 이슈가 떴을 때:

```
/orch:issue-up issue-13              # 트래커 이슈 키 (Linear / GitHub / GitLab / 자유 식별자)
/orch:issue-up issue-99 --no-issue   # 트래커 설정 무관 ad-hoc 작업, leader 가 orch 에 spec 직접 요청
```

→ leader pane 이 떠서 트래커별로 이슈 컨텍스트를 가져옴 → leader 가 사용자에게 phase plan 을 직접 컨펌 → leader 가 워커 spawn → 워커 PR → reviewer → 머지 → `/orch:issue-down <id>` 으로 정리 + REPORT.html.

---

## Slash 명령 한눈에

| 명령 | 호출자 | 용도 |
|---|---|---|
| `/orch:setup` | 사용자 (orch) | `.orch/settings.json` 자동 생성 |
| `/orch:up` | 사용자 (orch) | 현재 pane 을 orch 로 등록 (1회) |
| `/orch:down` | 사용자 | tmux 세션 통째 종료 |
| `/orch:issue-up <id>` | orch | `<id>` leader 띄움 |
| `/orch:issue-down <id>` | orch / leader | cascade shutdown + 정리 + REPORT |
| `/orch:leader-spawn <project> [type] [--role pm\|dev]` | leader | 산하 프로젝트 워커 spawn (`--role pm` 으로 PM 워커, 미지정 시 developer) |
| `/orch:review-spawn <project> <pr>` | leader | PR 리뷰 전용 워커 (단발성) |
| `/orch:send <target> <msg>` | 누구나 | hub-and-spoke 메시지 |
| `/orch:check-inbox [id]` | 누구나 | 자기 인박스 처리 |
| `/orch:poll-inbox [...]` | leader / worker | 파일 inbox 에 메시지가 올 때까지 폴링 |
| `/orch:status` | 누구나 | 전체 위계 + inbox 상태 |
| `/orch:peek <wid>` | 사용자 | 워커 pane 마지막 30줄 — 응답 없는 워커 진단 |
| `/orch:errors [...]` | 사용자 | 통합 에러 로그 |
| `/orch:report <id>` | leader / 사용자 | REPORT-data.md → REPORT.html 렌더 |
| `/orch:validate-settings` | 사용자 | settings.json ↔ 실제 repo 정합성 검사 |
| `/orch:validate-plugin` | 사용자 | 플러그인 자체 위생 검증 |
| `/orch:prioritize` | 사용자 | 트래커 미완료 이슈 → 루브릭 점수 → Top N |
| `/orch:usage-stats` | 사용자 | jsonl 분석 → 슬래시/스크립트/스킬/서브에이전트 사용량 |

---

## 핵심 개념

### 2-tier hub-and-spoke

- **orch** — 이슈 관리 / leader spawn / 후속 후보 등록 검토를 맡는 dispatcher.
- **leader (`<issue_id>`)** — 한 이슈의 책임자. 사용자와 직접 소통하고 산하 프로젝트 워커들을 spawn / 라우팅 / shutdown.
- **worker (`<issue_id>/<project>`)** — 한 repo 의 작업자. 자기 worktree + 자기 PR 라이프사이클 책임.

워커끼리 직접 통신 안 됨. `/orch:send` 가 라우팅 가드로 막는다. 다른 프로젝트와 의존 생기면 leader 가 라우팅하거나 orch 로 escalate. leader ↔ worker 메시지는 파일 inbox 에 기록되고 수신자가 `/orch:poll-inbox` 또는 `/orch:check-inbox` 로 읽는다. tmux `send-keys` 는 세션 spawn / peek / shutdown 쪽에 남고, 메시지 전달의 기본 경로가 아니다.

### worker_id 표기

issue_id 는 사용자가 `/orch:issue-up` 에 넘긴 키 그대로 (대소문자 보존, `orch` 는 reserved). sanitize 는 deny-list: 공백·제어문자 / shell metacharacters (`;|&$\` \\`) / redirect·quoting·grouping (`<>!(){}[]"'`) / path traversal (`..`) / slash 차단. 자연 키 (`#`, `.`, `+`, `@`, `~`, `-`, `_`, alnum) 통과.

```
orch                  ← PM
MP-13                 ← leader (Linear 키)
142                   ← leader (GitHub Issue 번호)
my-issue#42           ← leader (GitLab 자연 키)
MP-13/repo-a          ← MP-13 산하 repo-a 워커
```

트래커에 해당 이슈가 없으면 leader 가 search 로 후보 N 건을 모아 사용자에게 직접 질문한다 (fuzzy fallback, SKILL `orch-leader §1.1`).

### PR 라이프사이클 (4 단계)

#### 1. CI 통과 — 워커 자기 책임

- 워커가 worktree 안에서 작업 → `safe-commit` → `git push` → `gh pr create`.
- `gh pr checks <pr> --watch --required` 로 블록 대기.
- 실패: `gh run view <run-id> --log-failed | head -200` 로 진단. 자기 영역이면 직접 fix → 재push → 재watch. 다른 워커 영역이면 leader 에 escalate.
- 통과: leader 에 `PR #N ready for review + URL` 답신.

#### 2. 코드 리뷰 — 깨끗한 컨텍스트의 reviewer

- leader 가 `/orch:review-spawn <project> <pr>` 호출 → reviewer 워커 spawn.
- reviewer 는 **읽기 전용**. `gh pr diff`, `gh pr view`, base repo grep / Read 만으로 검토.
- 답신 두 채널 의무:
  - **GitHub PR 코멘트** (`gh pr comment`) — 사용자가 PR 페이지에서 검토 자료 확인.
  - **leader inbox** (`send.sh`) — orch 라우팅용.
- LGTM 또는 needs-changes 답신 후 reviewer 자기 종료.
- needs-changes: 워커가 수정 → push → `re-review please` → leader 가 새 reviewer spawn.

#### 3. 머지 대기 — 사용자 결정

- 워커가 LGTM 받으면 즉시 `wait-merge.sh` 진입 (30s 폴링).
- 머지 결정은 **항상 사용자**. plugin 은 자동 머지 안 함.
- exit 0 (MERGED): 워커가 leader 에 보고.
- exit 1 (CLOSED): leader 에 보고 후 대기 — 사용자 의도 확인 필요.

#### 4. Cascade shutdown — leader 자기 종료

- 모든 산하 워커 종료 확인 후 `/orch:issue-down`.
- 자동 정리:
  - 머지된 worktree prune + 로컬 브랜치 삭제 + base 브랜치 fetch
  - 미머지 worktree 보존
  - 산하 워커 registry → `workers-archive/`
  - `REPORT-data.md` → archive 보존
  - leader pane kill

---

## 작업 타입 — 워크플로우 분기

이슈가 feature 인지 bug 인지 refactor 인지에 따라 phase 구조와 review 잣대가 다르다. leader 는 phase plan 직전 **작업 타입 1회 결정** → 그 타입의 가이드 (`references/workflows/<type>.md`) 를 phase 골격 + reviewer 체크리스트로 사용.

| 타입 | 핵심 질문 | 강조 |
|---|---|---|
| **feature** | "무엇이 가능해져야 하는가?" | 요구사항 / 인터페이스 / 테스트 / 엣지 케이스 |
| **bug** | "왜 기대와 다르게 동작하는가?" | **재현 → 회귀 테스트 → 최소 변경**. 증상 가리기 금지 |
| **refactor** | "동작은 그대로, 구조를 더 낫게?" | **characterization test 로 외부 동작 고정 → 작은 단위 변경**. 기능 변경 섞기 금지 |

판별 절차 (leader 1회 수행):

1. spec 의 label / title prefix 로 자동 추론.
2. 모호하면 leader 가 직접 **AskUserQuestion** TUI 3택으로 사용자에게 확인한다 (feature / bug / refactor). orch 에 `[type-clarify]` 를 보내거나 사용자 응답을 `wait-reply.sh` 로 기다리지 않는다.
3. 결정 직후 `.orch/runs/<id>/type` 에 한 줄 기록.
4. 해당 가이드의 'Phase 템플릿' 을 phase plan 골격으로 사용.

reviewer 도 같은 가이드 따름 — `review-spawn` 이 `.orch/runs/<id>/type` 을 읽어 reviewer spawn-context 에 가이드 경로 주입.

---

## 워커 페르소나 — Skill 기반

leader / developer worker / PM / reviewer 의 페르소나·절차는 `skills/orch-<role>/SKILL.md` 단일 source 로 분리돼 있다. spawn 스크립트는 동적 컨텍스트 변수 (worker_id / project / branch / stack 등) + Skill 도구 트리거 + hard guard (GO 전 spawn 금지 / leader 직접 사용자 확인 / PM direction-check / reviewer read-only / shutdown 의무) 를 담은 **spawn-context 메시지를 워커 inbox 에 적재** (tmux push 폐기). claude 기동 시 SessionStart hook 이 `orch-leader-start`/`orch-worker-start` 진입 skill 을 invoke → 그 skill 이 inbox 를 드레인해 spawn-context 를 수령하고 본문 절차는 SKILL 로딩으로 가져온다.

- `skills/orch-leader/SKILL.md` — leader 셋업 / 타입 판별 / Phase Plan / 라우팅 / cascade shutdown
- `skills/orch-developer-worker/SKILL.md` — developer HOLD 체크포인트 / 차단 질문 / PR 4단계 / worker-shutdown
- `skills/orch-pm/SKILL.md` — PM direction-check + wait-reply / 산출물 PR / 사용자 컨펌 의무
- `skills/orch-reviewer/SKILL.md` — read-only 검토 / 두 채널 답신 / verdict 형식

공통 운영 규약 (leader-worker hub-and-spoke / 파일 inbox 폴링 / 사용자 직접 확인 / wait-reply qid / HOLD 체크포인트 / PR 4단계 / shutdown) 은 `references/orch-protocols.md` 단일 source. SKILL 4종이 이 문서를 가리키기만 하므로 규약 갱신은 한 곳에서.

작업 타입 가이드 (`references/workflows/{feature,bug,refactor}.md`) 와 4원칙 (`references/coding-guidelines.md`) 도 그대로 단일 source — SKILL 은 언제 읽고 어떻게 적용할지만 지시.

복잡 이슈용 design-first 흐름은 [Design-first Task Graph](#design-first-task-graph-멀티-repo--복잡-이슈) 절 참고. PM 페르소나 (`skills/orch-pm/SKILL.md`) 와 task graph 계약 (`references/workflows/task-graph-contract.md`) / schema / template 가 그 흐름의 단일 source.

---

## Phase Plan — 순차 실행 강제 (단순 이슈)

단순 이슈 (단일 repo / 명확 AC / 작은 fix·refactor) 의 기본 흐름. 멀티 repo / API·DB·migration 변경 / 비기능 리스크가 있는 복잡 이슈는 아래 [Design-first Task Graph](#design-first-task-graph-멀티-repo--복잡-이슈) 로 분기.

비-blocking 으로 여러 워커가 동시 진행되면 산출물 의존이 있는데도 순서가 꼬인다. **leader 가 phase plan 을 사용자 컨펌 받고 phase 단위 순차 실행**.

- **소유**: leader. PM 워커는 설계 영역 (분석·아키텍처·스펙·API·DB 모델) 만 책임 — 산출물을 leader 가 받아 phase 분해.
- **저장**: `.orch/runs/<issue_id>/phases.md`.
- **흐름**: leader 가 spec 받자마자 phases.md 작성 → 사용자에게 전문을 보여주고 **leader 가 AskUserQuestion TUI 로 직접 컨펌** (GO / 수정 / 취소) → leader 가 라벨에 따라 분기.
- **단순 이슈도 phase 1개로** — 일관성 + 흐름 추적 용이.
- **금지**: phase plan 사용자 GO 받기 전 워커 spawn / 다중 phase 동시 진행.

### 컨펌 응답 라벨 (leader 내부 처리)

| 사용자 TUI 답 | leader 가 적용할 라벨 | leader 동작 |
|---|---|---|
| GO | `[plan-confirm] GO` | Phase 1 워커 spawn |
| 수정 | `[plan-revise] <notes>` | phases.md 갱신 → 다시 사용자 직접 컨펌 |
| 취소 | `[plan-cancel] <사유>` | `/orch:issue-down` cascade kill |

자유서술 답 (`응 ㅇㅋ`, `한 군데만 빼고`) 은 GO / 수정 / 취소 판별이 모호하므로 leader 는 **반드시 AskUserQuestion** 사용.

---

## Design-first Task Graph (멀티 repo / 복잡 이슈)

phase 직렬 흐름은 멀티 repo 병렬 개발에서 답답하고, API contract / DB migration / 권한 변경 같은 설계가 앞서야 하는 이슈는 phase plan 단계에서 의존이 충분히 드러나지 않는다. 이런 이슈는 **PM 설계 산출물 → leader 가 task graph 로 승인 → depends_on 기반 병렬 실행** 흐름을 쓴다.

### 단계

- **Phase 0 — Design**: 6 종 artifact (`problem_frame` / `architecture_decision` / `implementation_brief` / `risk_register` / `open_decisions` / `proposed_task_graph`) 작성. 분기:
  - **복잡 이슈**: 사용자 **Round 1 GO** → PM 워커 spawn → 산출물 PR → 사용자 **Round 2 GO** → `approved_task_graph` 확정.
  - **단순 이슈**: leader 가 lightweight design 으로 직접 작성 (risk_register / open_decisions 는 빈 배열 허용) → 1 라운드 GO 가 곧 `approved_task_graph` 승인.
- **Phase 1 — Execution**: leader 가 `approved_task_graph` 의 ready task (의존성 만족) 를 병렬 spawn. 각 task 는 `workflow_template` (예: `developer_pr_v1` 14 step) step 순서 강제.
- **Phase 2 — Report / Cleanup**: task 결과 수집 → REPORT → `issue-down`.

### 적용 분기

사용자 가독용 요약. 실행 canonical 은 `skills/orch-leader/SKILL.md` §3.5.1.

| 신호 | 분류 | PM session |
|---|---|---|
| project ≥ 2 개 (멀티 repo) | 복잡 | **필수** |
| API contract / DB model / migration / auth / 권한 / 외부 연동 변경 | 복잡 | **권장** |
| 비기능 리스크 (성능 / 보안 / 호환성) 또는 acceptance criteria 모호 | 복잡 | **권장** |
| 위 조건 모두 해당 안 됨 | 단순 | **생략 — leader lightweight design** (위 Phase Plan 절) |

### Step 순서 invariant

해당 step 이 있는 workflow 기준 (developer 등 PR 구현 workflow). reviewer 처럼 단발성 workflow 는 자기 template 기준 (respond → shutdown).

- `ci` done 전 `ready_for_review` 금지
- `review` LGTM 전 `wait_merge` 금지
- `wait_merge` done 전 `shutdown` 금지

워커 보고가 invariant 위반이면 leader 즉시 HOLD.

### 계약 / 스키마 / 템플릿 단일 source

- `references/workflows/design-first-task-graph.md` — 전체 흐름 / 예시 (단순 / 멀티 repo)
- `references/workflows/task-graph-contract.md` — Task / TaskGraph / WorkflowTemplate 계약
- `references/schemas/task-graph.schema.json` + `task-template.schema.json` — Draft 2020-12 strict
- `references/workflows/task-templates/*.json` — `developer_pr_v1` / `pm_design_v1` / `reviewer_pr_v1` 는 stable, `integration_check_v1` 은 placeholder (stable 화 전 spawn 금지)

---

## Worker → Leader 차단 질문 (`wait-reply.sh`)

워커가 결정 필요한 질문을 leader 에 보낸 뒤 답을 못 받았는데 다른 마디로 진행하면 추측 작업이 PR 까지 가서 회수 불가. 워커는 질문 송신 직후 `wait-reply.sh` 로 **차단 대기**.

```bash
qid="q-$(date +%s)-$RANDOM"
bash -c "$ORCH_BIN_DIR/messages/send.sh <leader_id> <<ORCH_MSG
[question:$qid]
A vs B 결정 필요. 추천: A (이유 ...).
ORCH_MSG"
bash $ORCH_BIN_DIR/messages/wait-reply.sh $qid     # 차단. 답 도착할 때까지 다음 마디 X.
# wait-reply 가 stdout 으로 답 본문 + msg_id 출력.
bash $ORCH_BIN_DIR/messages/inbox-archive.sh <msg_id>
```

- **마커 규약**: 워커 질문 `[question:<q-id>]`, leader 답 `[reply:<q-id>]` — 둘 다 본문에 포함.
- **leader 응답 의무**: `[question:...]` 마커는 워커가 wait-reply 로 막힌 상태. 답 미루지 말고 우선 처리. 사용자 차원이면 leader 가 직접 확인해 같은 qid 로 답한다.
- **timeout**: 기본 1h (`ORCH_WAIT_REPLY_TIMEOUT`). 도달 시 exit 2 → 워커가 leader 에 재prompt 후 재대기.
- **wait-reply 안 쓰는 케이스**: 단발성 FYI / ack / 진행 보고 — `**[답신 불필요]**` 마커 활용.

---

## 사이클 종료 후 자가진단 → 개선 루프

회고는 일회성 보고가 아니라 **다음 사이클의 입력**. 페인포인트가 plugin 자체 개선 이슈로 들어와 워커 가이드 / 라이프사이클 / 라우팅을 점진적으로 다듬는다.

```
leader phase 마지막 ──→ /orch:report ──→ REPORT-data.md + REPORT.html
                              │                    │
                              │                    └─→ orch 인박스 [follow-up-candidates]
                              ↓                              │
                       /orch:issue-down                      ↓
                              │                  사용자 검토 → 트래커 등록
                              ↓
                         archive 정리 (안전망 report.sh)
```

#### 1. leader 호출 + 안전망 데이터 덤프

leader 가 cascade shutdown 직전 마지막 phase 로 `/orch:report <issue_id>` 실행 → `scope_dir/REPORT-data.md` + `scope_dir/REPORT.html`. `issue-down` 이 scope_dir 을 archive 로 이동.

`issue-down` 자체도 archive 직전 `report.sh` 한 번 더 실행 — leader 가 REPORT-data.md 단계를 빠뜨려도 안전망 (idempotent). REPORT.html 누락 시 사용자가 archive 의 REPORT-data.md 보고 `/orch:report` 수동 복구.

REPORT-data.md 내용:

- 워커별 토큰 사용량 (sidecar jsonl 파싱)
- 도구 호출 분포 (Read / Edit / Bash / 슬래시 빈도)
- 메시지 흐름 (orch ↔ leader ↔ worker 타임라인)
- 에러 로그 (`errors.jsonl`)

#### 2. HTML 렌더

`render_report.py` 가 결정적 HTML 렌더. 골격:

- 회고 메타 (시간 / 워커 수 / PR 수)
- 워커별 토큰·도구 통계
- **핸드오프 페인포인트** — 메시지 누락·지연, 권한 차단, 컨텍스트 사고, escalation 횟수
- **Follow-up 개선 액션** (errors_check + ai_ready_check 후보 포함)

#### 3. 후속 이슈 후보 → orch 검토 → 트래커 등록

leader 가 REPORT 안에서 errors_check / ai_ready_check 후보 도출 → `[follow-up-candidates <issue_id>]` 라벨로 orch 인박스 송신. **leader 직접 등록 X — 자동 등록 사고 방지**.

orch 가 사용자에게 보여주고 등록 여부 검토. 결정된 항목만 트래커 등록 (linear → `save_issue` / github → `gh issue create` / gitlab → `glab issue create` / none → SKIP).

#### 4. plugin 개선 → 다음 사이클 적용

- 이슈 fix PR → 머지 → `plugin.json` + `marketplace.json` version bump
- 클라이언트: `/plugin marketplace update padosol` + `/plugin update orch@padosol`
- 다음 issue-up 부터 워커 spawn-context / reviewer 가이드 / 정리 로직 갱신 반영

---

## Slack 알림 (선택)

| 이모지 | 카테고리 | 트리거 |
|---|---|---|
| 🤔 | `mp_select` | `issue-up` 직후 — leader 떴음, plan 컨펌 곧 도착 |
| 🟡 | `pr_open` | 워커 → leader 메시지에 `PR #N ready for review` 매치 |
| 🟢 | `pr_ready` | reviewer 가 `worker-shutdown` 직전 (머지 가능) |
| ❓ | `worker_question` | 워커 → orch 메시지 송신 |
| ✅ | `mp_done` | `issue-down` 종료 |
| 🔴 | `error` | `errors.jsonl` 새 entry |

**활성화 조건** (둘 다 만족):

1. `.orch/settings.json` 에 `notify.slack_enabled: true`
2. webhook URL 이 환경변수 (`ORCH_SLACK_WEBHOOK`) 또는 `${ORCH_ROOT}/notify.local.json` (gitignore 필수) 에 설정

기본값 `false` — 셋업 안 한 사용자는 알림 안 발생.

**셋업**:

1. Slack 채널에 *Incoming Webhooks* → URL 발급.
2. `.orch/settings.json`:
   ```json
   { "notify": { "slack_enabled": true } }
   ```
3. webhook URL — 셸 rc 에:
   ```bash
   export ORCH_SLACK_WEBHOOK='https://hooks.slack.com/services/.../.../...'
   ```
4. tmux 세션 재시작.
5. 동작 확인:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/notify/notify-slack.sh" mp_done MP-test "동작 확인"
   ```

**비활성화**: `slack_enabled: false` (영구) / `export ORCH_NOTIFY_ENABLED=0` (셸 단위).

**주의**: 실패는 silent. webhook URL 은 secret — settings.json 에 박지 말 것 (커밋 누출 위험).

---

## 디스크 레이아웃

워크스페이스 루트의 `.orch/`:

```
.orch/
├── settings.json                  # 프로젝트 메타데이터
├── inbox/<id>/                    # orch / leader 인박스 (포인터 <ts>-<id>.json + payloads/<id>.md)
├── archive/<id>-YYYY-MM-DD.md     # 처리 완료 메시지
├── archive/<scope>-YYYY-MM-DD/    # issue-down 시 scope dir 통째 archive
├── workers/<id>.json              # orch / leader registry
├── errors.jsonl                   # top-level 에러 로그
└── runs/<scope>/                  # 진행 중 이슈들 (wrapper)
    └── MP-13/
        ├── inbox/<role>/               # 포인터 <ts>-<id>.json + payloads/<id>.md
        ├── archive/<role>-YYYY-MM-DD.md
        ├── workers/<role>.json         # 살아있는 워커
        ├── workers-archive/<role>.json # 종료된 워커 (sidecar 분석 보존)
        ├── worktrees/<project>/        # git worktree
        ├── leader-archive.md
        └── errors.jsonl
```

- `runs/` wrapper 로 동시 진행 이슈가 많아져도 `.orch/` 루트가 정돈됨.
- **inbox 0 bytes = 정상**: `inbox-archive.sh` 가 처리된 메시지를 archive 로 옮기고 truncate. 흔적은 archive 에서 확인.

---

## 설정 (.orch/settings.json)

```json
{
  "version": 1,
  "base_dir": "/abs/workspace",
  "issue_tracker": "linear",
  "github_issue_repo": "owner/repo",
  "git_host": "github",
  "notify": { "slack_enabled": false },
  "projects": {
    "repo-a": {
      "path": "/abs/path/to/repo-a",
      "kind": "<framework>",
      "description": "<도메인 X API 책임 한 줄>",
      "tech_stack": ["<언어>", "<프레임워크>"],
      "default_base_branch": "develop"
    }
  }
}
```

- `github_issue_repo` 는 기존 호환 이름이다. `issue_tracker=github` 에서는 `owner/repo`, `issue_tracker=gitlab` 에서는 `group/project` 를 저장한다.
- `default_base_branch` 는 **프로젝트별 키**. 누락 시 `/orch:setup` 의 후속 절차가 AskUserQuestion 으로 채움. 비어 있으면 `develop` 폴백.
- `/orch:setup` 이 `git symbolic-ref refs/remotes/origin/HEAD` 로 자동 감지.
- `/orch:validate-settings` 로 description / tech_stack 이 실제 repo 와 어긋나는지 점검.

### 이슈 트래커 / git 호스트 / 알림 선택

`/orch:setup` 시 3 종을 한 번에 묻는다 (`AskUserQuestion` TUI). 변경: `/orch:setup --update --issue-tracker <new>` / `--git-host <new>` / `--notify on|off`. `--update` 에서 생략한 값은 기존 settings.json 값이 보존된다.

**Issue tracker (`issue_tracker`)**:

| 값 | leader 가 하는 일 | 추가 셋업 |
|---|---|---|
| `linear` | `mcp__linear-server__get_issue <id>` 로 컨텍스트 fetch. issue-down 시 orch 가 Done 업데이트. follow-up 후보는 orch 검토 후 `save_issue` 로 sub-issue 등록. | Linear MCP 서버 등록 (`~/.claude.json` 의 mcpServers). |
| `github` | `gh issue view N --repo <github_issue_repo>` 로 fetch. issue-down 시 `gh issue close`. follow-up 은 orch 검토 후 `gh issue create`. | `github_issue_repo` 필수. `gh auth login`. |
| `gitlab` | `glab issue view <id> --repo <github_issue_repo>` 로 fetch (`github_issue_repo` 에 group/project 저장). glab 미설치/미인증 시 leader 가 orch 에 spec 요청으로 fallback. | `glab auth login` 권장. `/orch:setup --issue-tracker gitlab --github-repo group/project`. |
| `none` | 트래커 호출 없음. leader 가 orch 에 spec 직접 요청. follow-up 후보는 REPORT.html 에만 기록 (트래커 등록 SKIP). | 없음. 가장 가벼움. |

**한 번만 이슈 없이 띄우기**: `--no-issue` 플래그. 워크스페이스가 `linear` / `github` 모드여도 이번 호출만 fetch 스킵.

**Git host (`git_host`)**:

| 값 | 동작 |
|---|---|
| `github` | `gh` 기반 PR 라이프사이클 (open-pr / await-merge / post-review). |
| `gitlab` | `glab` 기반 MR 라이프사이클. `scripts/providers/git-host/` provider 가 gh ↔ glab 차이를 흡수 — 표준 state (OPEN/MERGED/CLOSED) JSON. |
| `none` | git 호스트 미사용 (로컬 전용 / self-hosted). PR 자동화 비활성. |

**Notify (`notify.slack_enabled`)**: `on` 으로 켜면 위 [Slack 알림](#slack-알림-선택) 6 카테고리 활성화.
