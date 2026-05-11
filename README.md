# orch — Claude Code 멀티-워커 오케스트레이션

**한 명의 PM (orch) + 여러 개의 팀리더 (leader) + 그 산하 프로젝트 워커들** 을 tmux pane / git worktree / 파일 메일박스 위에 얹어 한 사람이 동시에 굴리도록 만든 Claude Code 플러그인.

```
사용자 ─ orch ─┬─ MP-13 (leader) ─┬─ mp-13/repo-a  → PR #142
              │                   ├─ mp-13/repo-b  → PR #143
              │                   └─ mp-13/repo-c  → PR #144
              └─ MP-37 (leader) ─┬─ mp-37/repo-a  → PR #97
                                 └─ mp-37/repo-b  → PR #166
```

각 leader / worker 는 자기 worktree + 자기 Claude 세션을 가진다. orch 는 사용자에게서 받은 큰 이슈를 leader 에 위임하고, leader 는 산하 워커에 작업을 분배한다. 모든 메시지는 hub-and-spoke — 워커끼리 직접 통신은 차단되고 항상 leader 를 경유.

---

## 무엇을 풀어주는가

- **컨텍스트 분리**: 큰 이슈를 한 Claude 세션에 통째로 넣으면 컨텍스트 압박으로 품질이 떨어진다. orch 가 분해해서 워커 별로 깨끗한 컨텍스트를 준다.
- **병렬 작업**: 여러 repo (예: A, B, C) 에 걸친 이슈를 워커가 독립적으로 동시 진행.
- **PR 라이프사이클 자동화**: PR 생성 → CI 통과 대기 → 깨끗한 컨텍스트의 reviewer 워커 자동 spawn → LGTM 라우팅 → 머지 대기 → 자동 cascade shutdown + worktree 정리 + REPORT.html 자동 작성.
- **사람 알림**: 동시다발로 끝나는 워커들 사이에서 "지금 뭐 봐야 하지?" 가 안 되도록 Slack 알림 옵션 (이벤트 6 카테고리, 즉시 발송).

---

## 빠른 시작

처음 한 번 (1, 2) 셋업하면 매번은 (3, 4) 한 줄.

### 1. 설치 (1회)

```
/plugin marketplace add padosol/padosol-marketplace
/plugin install orch
```

scope 는 **project** 권장 (해당 워크스페이스의 `.claude/settings.json` 에 등록 → 그 워크스페이스에서만 활성화, 다른 곳에는 노이즈 없음).

### 2. 셸 함수 등록 (1회)

어디서든 `orch <workspace>` 한 명령으로 진입할 수 있도록 `.bashrc` / `.zshrc` 에 등록:

```bash
orch() {
    local script
    script="$(ls -d ~/.claude/plugins/cache/padosol/orch/*/scripts/bootstrap.sh 2>/dev/null | sort -V | tail -n1)"
    [ -z "$script" ] && { echo "orch plugin not installed (run /plugin install orch@padosol)" >&2; return 1; }
    bash "$script" "${1:-$PWD}"
}
```

`sort -V | tail -n1` — 가장 최신 semver 버전을 자동 선택. plugin version bump 와 무관하게 동작.

### 3. 워크스페이스 진입

```bash
orch ~/path/to/workspace   # 인자 없으면 cwd
```

- **신규 워크스페이스** — tmux 세션 (이름 = 디렉토리 basename) 생성 → `claude` 실행 → `/orch:up` 자동 입력. 첫 화면이 `/orch:setup` 안내로 끝남.
- **기존 워크스페이스** — 동일 이름 세션이 살아있으면 그대로 attach (등록 중복 안 함).

### 4. 첫 이슈 위임

신규 워크스페이스라면 orch pane 에서 한 번만:

```
/orch:setup
```

→ 산하 git repo 자동 발견해 `.orch/settings.json` 생성 (alias / path / kind / default_base_branch). 셋업 도중 **3 종 메타데이터** (이슈 트래커 / git 호스트 / Slack 알림) 를 `AskUserQuestion` TUI 로 묻는다 — 자세한 차이는 [이슈 트래커 / git 호스트 / 알림 선택](#이슈-트래커--git-호스트--알림-선택) 절 참조.

이후 orch 와 평소처럼 대화하다가 큰 이슈가 떴을 때:

```
/orch:issue-up MP-13              # Linear / 없음 모드
/orch:issue-up 142                # GitHub Issues 모드 (이슈 번호)
/orch:issue-up 99 --no-issue      # 이슈 없는 ad-hoc 작업 — 트래커 설정 무관, leader 가 orch 에 spec 직접 요청
```

→ leader pane 이 떠서 트래커별로 이슈 컨텍스트를 가져와 plan 을 orch 인박스로 보고 → 사용자 confirm → leader 가 `/orch:leader-spawn repo-a fix` 등으로 워커 spawn → 워커 PR → reviewer → 머지 → `/orch:issue-down MP-13` 으로 정리 + REPORT.html.

---

## Slash 명령 한눈에

| 명령 | 호출자 | 용도 |
|---|---|---|
| `/orch:setup` | 사용자 (orch) | `.orch/settings.json` 자동 생성 |
| `/orch:up` | 사용자 (orch) | 현재 pane 을 orch 로 등록 (1회) |
| `/orch:down` | 사용자 | tmux 세션 통째 종료 |
| `/orch:issue-up <id>` | orch | MP-NN leader 띄움 |
| `/orch:issue-down <id>` | orch / leader | MP cascade shutdown + 정리 + REPORT |
| `/orch:leader-spawn <project> [type]` | leader | 산하 프로젝트 워커 spawn |
| `/orch:review-spawn <project> <pr>` | leader | PR 리뷰 전용 워커 (단발성) |
| `/orch:send <target> <msg>` | 누구나 | hub-and-spoke 메시지 |
| `/orch:check-inbox [id]` | 누구나 | 자기 인박스 처리 |
| `/orch:status` | 누구나 | 전체 위계 + inbox 상태 |
| `/orch:peek <wid>` | 사용자 | 워커 pane 마지막 30줄 — 응답 없는 워커 진단 |
| `/orch:errors [...]` | 사용자 | 통합 에러 로그 |
| `/orch:report <id>` | 사용자 | REPORT-data.md → REPORT.html 렌더 |
| `/orch:validate-settings` | 사용자 | settings.json 과 실제 repo 정합성 검사 |
| `/orch:validate-plugin` | 사용자 | 플러그인 자체 위생 검증 (문법 + 종속어 검출) |
| `/orch:prioritize` | 사용자 | 트래커(Linear/GitHub) 미완료 이슈 → 루브릭 점수 → Top N 추천 |
| `/orch:usage-stats` | 사용자 | cross-session jsonl 분석 → 슬래시/스크립트/스킬/서브에이전트 사용량 (dead code 식별) |

---

## 핵심 개념

### 2-tier hub-and-spoke

- **orch** — 사용자와 대화하는 PM. 큰 이슈를 받아 leader 에 위임.
- **leader (mp-NN)** — 한 MP 의 책임자. 산하 프로젝트 워커들을 spawn / 라우팅 / shutdown.
- **worker (mp-NN/&lt;project&gt;)** — 한 repo 의 작업자. 자기 worktree + 자기 PR 라이프사이클 책임.

워커끼리는 직접 통신 안 됨. `/orch:send` 가 라우팅 가드로 막는다. 다른 프로젝트와 의존 생기면 leader 가 라우팅하거나 orch 로 escalate.

### worker_id 표기

```
orch              ← PM
mp-13             ← leader
mp-13/repo-a      ← MP-13 산하 repo-a 프로젝트 워커
```

### PR 라이프사이클 (4 단계)

#### 1. CI 통과 — 워커 자기 책임

- 워커가 worktree 안에서 작업 → `safe-commit` 으로 커밋 → `git push` → `gh pr create`.
- 이후 `gh pr checks <pr> --watch --required` 로 블록 대기.
- 실패: `gh run view <run-id> --log-failed | head -200` 로 진단. 자기 영역이면 직접 fix → 재push → 재watch. 다른 워커 영역이면 leader 에 escalate.
- 통과: leader 에 `PR #N ready for review + URL` 답신.

#### 2. 코드 리뷰 — 깨끗한 컨텍스트의 reviewer

- leader 가 `/orch:review-spawn <project> <pr>` 호출 → reviewer 워커가 새 pane 에 spawn.
- reviewer 는 **읽기 전용** (코드 수정·커밋·push 금지). `gh pr diff`, `gh pr view`, base repo grep / Read 만으로 변경분 검토.
- 평가 기준: 정확성 / 사이드이펙트 / 테스트 커버리지 / 회귀 / 스타일. 4원칙 가이드 (Think Before / Simplicity / Surgical / Goal-Driven) 를 잣대로 적용.
- **답신 두 채널 의무**:
  - **GitHub PR 코멘트** (`gh pr comment`) — 사용자가 머지 시 PR 페이지에서 검토 자료 확인.
  - **leader inbox** (`send.sh`) — orch 라우팅용.
- LGTM 또는 needs-changes 답신 후 reviewer 자기 종료 (한 reviewer = 1회 검토).
- needs-changes 받으면: 워커가 수정 → push → `re-review please` 답신 → leader 가 새 reviewer spawn.

#### 3. 머지 대기 — 사용자 결정

- 워커가 LGTM 받으면 즉시 `wait-merge.sh` 진입 (30s 폴링).
- 머지 결정은 **항상 사용자**. plugin 은 자동 머지 안 함.
- exit 0 (MERGED): 워커가 leader 에 `PR #N merged` 답신 후 다음 단계.
- exit 1 (CLOSED): leader 에 보고 후 대기 — 사용자 의도 확인 필요.

#### 4. Cascade shutdown — leader 자기 종료

- 모든 산하 워커 종료 확인 후 `/orch:issue-down`.
- 자동 정리:
  - 머지된 worktree prune + 로컬 브랜치 삭제 + base 브랜치 fetch
  - 미머지 worktree 보존 (수동 정리 가능)
  - 산하 워커 registry → `workers-archive/` 보존 (sidecar 토큰·도구 분석용)
  - `REPORT-data.md` 덤프 → archive 에 보존
  - leader 자기 pane 까지 통째 kill

---

## Phase Plan — 순차 실행 강제

비-blocking 으로 여러 워커가 동시에 진행되면 산출물 의존이 있는데도 병렬 실행되어 순서가 꼬이는 사고가 발생한다. 이를 막기 위해 **leader 가 phase plan 을 사용자 컨펌 받고 phase 단위 순차 실행** 한다.

- **소유**: leader (mp-NN). PM 워커는 설계 영역 (분석·아키텍처·스펙·API·DB 모델) 만 책임 — 그 산출물을 leader 가 받아 phase 분해.
- **저장**: `.orch/runs/<mp_id>/phases.md` (운영 메타, scope archive 에 함께 보존).
- **포맷 예시**:
  ```
  # MP-13 Phase Plan

  ## Phase 0: 설계 (PM)
  - 사용 워커: mp-13/pm docs
  - 산출물: docs/spec/MP-13/api.md PR
  - 완료 기준: PR merged

  ## Phase 1: server 구현
  - 사용 워커: mp-13/server feat
  - 산출물: API 엔드포인트 PR
  - 완료 기준: PR merged + 로컬 동기화
  - 의존: Phase 0

  ## Phase 2: ui 통합
  - 사용 워커: mp-13/ui feat
  - 의존: Phase 1
  ```
- **흐름**: leader 가 spec 받자마자 phases.md 작성 → orch 로 `[phase-plan MP-NN]` 송신 → 사용자 GO → Phase 1 만 spawn → 완료 보고 후 Phase 2 ...
- **단순 MP** 도 phase 1개로 표현 (Phase 1: 수정 + PR + 머지) — 일관성 확보 + 사용자가 흐름 따라가기 쉬움.
- **금지**: phase plan 사용자 GO 받기 전 워커 spawn / 다중 phase 동시 진행.

## Worker → Leader 차단 질문 (`wait-reply.sh`)

워커가 결정 필요한 질문을 leader 에 보낸 뒤 답을 못 받았는데 다른 마디로 진행하면 추측 작업이 PR 까지 가서 회수 불가능 비용. 이를 막기 위해 워커는 질문 송신 직후 `wait-reply.sh` 로 **차단 대기**.

```bash
qid="q-$(date +%s)-$RANDOM"
bash -c "$ORCH_BIN_DIR/send.sh mp-13 <<ORCH_MSG
[question:$qid]
A vs B 결정 필요. 추천: A (이유 ...).
ORCH_MSG"
bash $ORCH_BIN_DIR/wait-reply.sh $qid     # ← 차단. 답 도착할 때까지 다음 마디 X.
# wait-reply 가 stdout 으로 답 본문 + msg_id 출력.
# 처리 후: bash $ORCH_BIN_DIR/inbox-archive.sh <msg_id>
```

- **마커 규약**: 워커 질문 `[question:<q-id>]`, leader 답 `[reply:<q-id>]` — 둘 다 본문에 포함.
- **leader 응답 의무**: 워커가 `[question:...]` 마커 달면 wait-reply 로 막힌 상태. leader 는 답 미루지 말고 우선 처리. 결정이 사용자 차원이면 orch 로 forward 후 사용자 답을 같은 q-id 로 워커에 송신.
- **timeout**: 기본 1h (`ORCH_WAIT_REPLY_TIMEOUT`). 도달 시 exit 2 → 워커가 leader 에 한 번 더 prompt 후 재대기.
- **언제 wait-reply 안 쓰나**: 단발성 FYI / ack / 진행 보고는 비-blocking 그대로 (`[답신 불필요]` 마커 활용).

---

## 사이클 종료 후 자가진단 → 개선 루프

회고는 일회성 보고가 아니라 **다음 사이클의 입력**. 페인포인트가 plugin 자체 개선 이슈로 다시 들어와 워커 가이드 / 라이프사이클 / 라우팅을 점진적으로 다듬는다.

```
issue-down ──→ REPORT-data.md ──→ /orch:report ──→ REPORT.html ──→ 페인포인트 발견
                                                                        │
plugin 개선 ←── version bump ←── PR 머지 ←── orch-plugin fix ←── 이슈 트래커 등록
```

#### 1. 자동 데이터 덤프

`issue-down` 이 archive 직전에 `report.sh` 호출 → `archive/<mp>-YYYY-MM-DD/REPORT-data.md` 작성. 포함:

- **워커별 토큰 사용량** — sidecar jsonl (`~/.claude/projects/<encoded-cwd>/`) 파싱
- **도구 호출 분포** — Read / Edit / Bash / 슬래시 명령 빈도
- **메시지 흐름** — orch ↔ leader ↔ worker 송수신 타임라인
- **에러 로그** — `errors.jsonl` 항목

#### 2. HTML 렌더

orch 가 `/orch:report <mp>` 실행 → REPORT-data.md 를 구조화된 JSON 으로 요약 → `render_report.py` 가 결정적 HTML (`REPORT.html`) 렌더. 골격:

- 회고 메타 (시간 / 워커 수 / PR 수)
- 워커별 토큰·도구 통계
- **핸드오프 페인포인트** — 메시지 누락·지연, 권한 차단, 컨텍스트 사고, escalation 횟수
- **Follow-up 개선 액션** — 다음 사이클 입력

#### 3. 페인포인트 → 이슈 트래커

사용자가 REPORT.html 의 페인포인트 / Follow-up 섹션을 보고 이슈 트래커에 `[orch] …` 류로 등록 (Linear / GitHub Issues / 사내 트래커 무관). 워커가 이미 자신의 마찰을 회고에 기록해 두었으면 그대로 ticketize.

#### 4. plugin 개선 → 다음 사이클 적용

- 이슈 fix PR → 머지 → `plugin.json` + `marketplace.json` version bump
- 클라이언트: `/plugin marketplace update padosol` + `/plugin update orch@padosol`
- 다음 issue-up 사이클부터 워커 first_msg / reviewer 가이드 / 정리 로직 등이 갱신된 동작으로 spawn

이 루프가 작동하려면 사이클 종료 시 REPORT.html 을 한 번 훑는 습관이 필요하다. 마찰을 그냥 두면 다음 사이클에서 같은 비용이 반복된다.

---

## Slack 알림 (선택)

워커 / leader 들이 동시다발로 끝나면 "지금 무엇을 확인해야 하는지" 헷갈린다. 주요 이벤트마다 Slack incoming webhook 으로 즉시 push.

| 이모지 | 카테고리 | 트리거 |
|---|---|---|
| 🤔 | `mp_select` | `issue-up` 직후 — leader 떴음, plan 컨펌 곧 도착 |
| 🟡 | `pr_open` | 워커 → leader 메시지에 `PR #N ready for review` 매치 |
| 🟢 | `pr_ready` | reviewer 워커가 `worker-shutdown` 직전 (머지 가능) |
| ❓ | `worker_question` | 워커 → orch 메시지 송신 |
| ✅ | `mp_done` | `issue-down` 종료 |
| 🔴 | `error` | `errors.jsonl` 새 entry (자동 트랩) |

**활성화 조건** (둘 다 만족해야 POST):

1. `.orch/settings.json` 에 `notify.slack_enabled: true` (master 토글 — `cat` 한 번에 켜져 있는지 확인)
2. webhook URL 이 환경변수 (`ORCH_SLACK_WEBHOOK`) 또는 `${ORCH_ROOT}/notify.local.json` (gitignore 필수) 에 설정

기본값 `false` — 셋업 안 한 사용자는 절대 알림 안 발생 (소음 없음).

**셋업**:

1. Slack workspace 채널에 *Incoming Webhooks* 추가 → URL 발급.
2. `.orch/settings.json`:
   ```json
   { "notify": { "slack_enabled": true } }
   ```
3. webhook URL — 셸 rc 에:
   ```bash
   export ORCH_SLACK_WEBHOOK='https://hooks.slack.com/services/.../.../...'
   ```
4. tmux 세션 재시작 → 모든 pane 환경변수 상속.
5. 동작 확인:
   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/notify-slack.sh" mp_done MP-test "동작 확인"
   ```

**비활성화**:
- 영구: `settings.json` 에서 `slack_enabled: false`.
- 셸 단위 임시: `export ORCH_NOTIFY_ENABLED=0`.

**주의**: 실패는 silent (호출자 본 흐름 안 막음). webhook URL 은 secret — settings.json 에 박지 말 것 (커밋 누출 위험).

---

## 디스크 레이아웃

워크스페이스 루트의 `.orch/`:

```
.orch/
├── settings.json                  # 프로젝트 메타데이터
├── inbox/<id>.md                  # orch / leader 인박스
├── archive/<id>-YYYY-MM-DD.md     # 처리 완료 메시지
├── archive/<scope>-YYYY-MM-DD/    # issue-down 시 scope dir 통째 archive
├── workers/<id>.json              # orch / leader registry
├── errors.jsonl                   # top-level 에러 로그
└── runs/<scope>/                  # 진행 중 MP 들 (wrapper)
    └── mp-13/
        ├── inbox/<role>.md
        ├── archive/<role>-YYYY-MM-DD.md
        ├── workers/<role>.json         # 살아있는 워커 등록
        ├── workers-archive/<role>.json # 종료된 워커 (sidecar 분석용 보존)
        ├── worktrees/<project>/        # git worktree
        ├── leader-archive.md
        └── errors.jsonl
```

- **`runs/` wrapper**: 동시 진행 MP 가 많아져도 `.orch/` 루트가 정돈됨.
- **inbox 0 bytes = 정상**: `inbox-archive.sh` 가 처리된 메시지를 archive 로 옮기고 inbox 를 truncate. 처리 흔적은 archive 에서 확인.

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

- `default_base_branch` 는 **프로젝트별 키만 의미있음** (0.12.0 부터 root 글로벌 필드 제거). 누락 시 `/orch:setup` 의 후속 절차가 AskUserQuestion 으로 채움. 그래도 비어 있으면 폴백은 `develop` 하드코딩.
- `/orch:setup` 이 `git symbolic-ref refs/remotes/origin/HEAD` 로 자동 감지. 한 워크스페이스에 develop / main 플로우 섞여 있어도 안전.
- `/orch:validate-settings` 로 description / tech_stack 이 실제 repo 와 어긋나는지 점검.
- `issue_tracker` / `github_issue_repo` / `git_host` / `notify` 는 다음 절 참조.

### 이슈 트래커 / git 호스트 / 알림 선택

`/orch:setup` 시 3 종을 한 번에 묻는다 (`AskUserQuestion` TUI). 변경하려면 `/orch:setup --update --issue-tracker <new>` / `--git-host <new>` / `--notify on|off`.

**Issue tracker (`issue_tracker`)**:

| 값 | leader 가 하는 일 | 추가 셋업 |
|---|---|---|
| `linear` | `mcp__linear-server__get_issue MP-N` 으로 컨텍스트 fetch. issue-down 시 Done 처리, REPORT 의 stale docs → Linear sub-issue 자동 생성. | Linear MCP 서버 등록 (`~/.claude.json` 의 mcpServers). |
| `github` | `gh issue view N --repo <github_issue_repo>` 로 fetch. stale docs → `gh issue create` 로 GitHub issue 생성. | `github_issue_repo` 필수 (이슈가 사는 저장소). 이미 `gh auth login` 되어있어야. |
| `jira` | 자동 fetch 미지원. leader 가 orch / 사용자에게 spec 직접 요청 (metadata 만 저장). | 없음. 후속 자동 fetch 는 향후 작업. |
| `gitlab` | 자동 fetch 미지원. leader 가 orch / 사용자에게 spec 직접 요청 (metadata 만 저장). | 없음. 후속 자동 fetch 는 향후 작업. |
| `none` | 트래커 호출 없음. leader 가 orch 에 spec 직접 요청 → orch 가 사용자에게 묻고 spec 을 leader inbox 로 전달. stale docs 는 REPORT.html 에만 기록 (자동 이슈 생성 안 함). | 없음. 가장 가벼움. |

내부적으로 worker_id 는 항상 `mp-NN` 형식 — 트래커 종류와 무관 (`MP` 는 multi-project 의 약자, Linear-specific 아님). `/orch:issue-up <num>` 의 `<num>` 만 트래커별 의미가 다르다 (Linear MP-N / GitHub issue # / 자유 식별자).

**한 번만 이슈 없이 띄우기**: `--no-issue` 플래그. 워크스페이스가 `linear` / `github` 모드여도 이번 호출만 fetch 스킵, leader 가 orch 에 spec 직접 요청. 이슈 만들기 번거로운 작은 작업이나 try-out 에 유용.

**Git host (`git_host`)**:

| 값 | 동작 |
|---|---|
| `github` | `gh` 기반 PR 라이프사이클 (await-merge / post-review / pr_open 알림) 가능. 현재 자동화 지원하는 유일한 호스트. |
| `gitlab` | metadata 저장만. PR/MR 자동화는 향후 작업 (`glab` 통합 예정). |
| `none` | git 호스트 미사용 (로컬 전용 또는 self-hosted). PR 자동화 비활성. |

**Notify (`notify.slack_enabled`)**:

`on` 으로 켜면 Slack 알림 6 카테고리가 활성화됨. 자세한 셋업은 [Slack 알림](#slack-알림-선택) 절.

---

## 트러블슈팅

**워커가 응답 없음**:
```
/orch:peek mp-13/repo-a
```
→ 마지막 30줄 + 활동 시각 + inbox 카운트. claude 가 사용자 입력 대기 중인지 확인.

**`fatal: invalid reference: origin/<base>`**:
프로젝트 entry 의 `default_base_branch` 가 원격에 없거나 비어 있는 경우 (0.12.0 부터 root 글로벌 fallback 제거 — 누락 시 `develop` 하드코딩 폴백뿐이라 develop 없는 repo 는 무조건 깨짐). `/orch:setup --update` 로 git remote 자동 감지값 다시 받거나 `settings.json` 직접 수정.

**머지된 worktree / 로컬 브랜치 잔재**:
`/orch:issue-down` 이 자동 정리. 그래도 남아 있으면 `git worktree prune` + `git branch -D <branch>` 수동.

**inbox 메시지 본문에 따옴표·괄호·줄바꿈**:
슬래시 `/orch:send` 대신 Bash + heredoc:
```bash
"$ORCH_BIN_DIR/send.sh" <target> <<'ORCH_MSG'
여러 줄 메시지
'따옴표' 와 `백틱` 그대로 안전
ORCH_MSG
```

**메시지가 잘려 도착한 의심**:
`send.sh` 의 OK 라인 끝에 `(N chars)` 가 출력된다. 송신 의도와 차이가 크면 argv 단계에서 잘린 것 — `--file` 또는 stdin/heredoc 으로 재송신.

---

## 핑퐁 방지

답신이 필요 없는 알림성 메시지는 본문 끝에 `**[답신 불필요]**` 를 붙인다. 받는 워커는 이를 보고 자동 답신을 보내지 않는다.

---

## 더 깊이

- 라이프사이클 / 라우팅 코드: `scripts/lib.sh`
- MP 시작·종료: `scripts/issue-up.sh`, `scripts/issue-down.sh`
- PR 머지 대기: `scripts/wait-merge.sh`
- worker→leader 차단 질문: `scripts/wait-reply.sh`
- REPORT 렌더러: `scripts/render_report.py`
- 설정 검증: `skills/validate-settings/SKILL.md`
- 우선순위 추천: `skills/prioritize-issues/SKILL.md`
