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

### 1. 설치

```
/plugin marketplace add padosol/padosol-marketplace
/plugin install orch
```

scope 는 **project** 권장 (`<project>/.claude/settings.json` 에 등록 → 그 워크스페이스에서만 활성화).

### 2. 워크스페이스 진입 (한 명령)

어디서든 워크스페이스 path 를 인자로 주면 tmux 세션 + Claude + orch 등록까지 자동:

```bash
orch ~/path/to/workspace
```

(`orch` 는 아래 셸 함수. 등록 1회로 어디서든 호출 가능.)

내부 동작:
- 워크스페이스 디렉토리 이름의 tmux 세션 attach (없으면 create)
- 새 세션이면 orch pane 에서 `claude` 실행 + `/orch:up` 자동 입력
- 기존 세션이면 그대로 attach (이미 등록된 orch 그대로 활용)

#### 셸 함수 등록 (1회)

`.bashrc` / `.zshrc`:

```bash
orch() {
    local script
    script="$(ls -d ~/.claude/plugins/cache/padosol/orch/*/scripts/bootstrap.sh 2>/dev/null | sort -V | tail -n1)"
    [ -z "$script" ] && { echo "orch plugin not installed (run /plugin install orch@padosol)" >&2; return 1; }
    bash "$script" "${1:-$PWD}"
}
```

플러그인 version bump 와 무관하게 가장 최신 cache 의 bootstrap 을 자동 선택.

### 3. settings 생성 (워크스페이스당 1회)

orch pane 안에서:

```
/orch:setup
```

→ 산하 git repo 들을 자동 발견해 `.orch/settings.json` 작성 (alias, path, kind, default_base_branch 자동 감지).

### 4. 첫 MP 위임

orch 와 평소처럼 대화하다가 큰 이슈가 떴을 때:

```
/orch:issue-up MP-13
```

→ MP-13 leader pane 이 뜨고 Linear 이슈를 읽어 plan 을 orch 인박스로 보고 → 사용자가 confirm → leader 가 `/orch:leader-spawn repo-a fix` 등으로 워커 spawn → 워커 PR → reviewer → 머지 → `/orch:issue-down MP-13` 으로 정리.

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

사용자가 REPORT.html 의 페인포인트 / Follow-up 섹션을 보고 Linear 등 이슈 트래커에 `[orch] …` 류로 등록. 워커가 이미 자신의 마찰을 회고에 기록해 두었으면 그대로 ticketize.

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
  "default_base_branch": "develop",
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

- `default_base_branch` 결정 우선순위: 프로젝트별 override → 글로벌 → `develop`.
- `/orch:setup` 이 `git symbolic-ref refs/remotes/origin/HEAD` 로 자동 감지. 한 워크스페이스에 develop / main 플로우 섞여 있어도 안전.
- `/orch:validate-settings` 로 description / tech_stack 이 실제 repo 와 어긋나는지 점검.

---

## 트러블슈팅

**워커가 응답 없음**:
```
/orch:peek mp-13/repo-a
```
→ 마지막 30줄 + 활동 시각 + inbox 카운트. claude 가 사용자 입력 대기 중인지 확인.

**`fatal: invalid reference: origin/<base>`**:
프로젝트 entry 의 `default_base_branch` 가 원격에 없는 경우. `/orch:setup` 재실행 또는 `settings.json` 직접 수정.

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

---

## 핑퐁 방지

답신이 필요 없는 알림성 메시지는 본문 끝에 `**[답신 불필요]**` 를 붙인다. 받는 워커는 이를 보고 자동 답신을 보내지 않는다.

---

## 더 깊이

- 라이프사이클 / 라우팅 코드: `scripts/lib.sh`
- MP 시작·종료: `scripts/issue-up.sh`, `scripts/issue-down.sh`
- PR 머지 대기: `scripts/wait-merge.sh`
- REPORT 렌더러: `scripts/render_report.py`
- 설정 검증: `skills/validate-settings/SKILL.md`
