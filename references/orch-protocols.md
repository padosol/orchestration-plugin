# orch 공통 운영 규약 (모든 워커 SKILL 의 단일 source)

leader / developer / PM / reviewer 의 4개 SKILL 이 공통으로 따르는 라우팅·차단·라이프사이클 규약. 각 SKILL 은 이 문서를 "1회 Read 후 절차대로 따른다" 식으로 참조하고, 본문은 여기 한 곳에서만 갱신한다.

---

## 1. Hub-and-Spoke 라우팅

leader ↔ worker 는 hub-and-spoke 모델. orch 는 이슈 생성 / 분배 / 후속 후보 관리만 맡고, 사용자 결정이 필요한 작업 진행 판단은 leader 가 사용자와 직접 소통한다.

```
사용자 ─┬─ orch (issue manager / dispatcher)
        └─ leader (<issue_id>) ─ worker (<issue_id>/<project>|pm|review-*)
```

- **워커끼리 직접 통신 금지** — `send.sh` 가 가드. 다른 프로젝트 의존 생기면 leader 에 escalate → leader 가 라우팅 또는 orch escalate.
- **사용자 ↔ leader 직접 접점 허용 및 권장** — phase plan 승인 / 타입 결정 / PM direction-check 같은 진행 결정은 leader 가 직접 `AskUserQuestion` 으로 받는다. orch 에 사용자 응답 중계를 맡기지 않는다.
- **orch 책임 범위** — `/orch:issue-up` 으로 leader spawn, `/orch:issue-down` 정리, follow-up 후보의 트래커 등록 여부 검토. leader 의 phase plan/type clarify/direction-check 응답 중계는 하지 않는다.
- **모든 메시지는 `/orch:send <target> <msg>`** — target 은 `orch | <issue_id> | <issue_id>/<project>` 중 하나.
- **따옴표·줄바꿈·백틱 메시지는 Bash heredoc 필수**:
  ```bash
  bash -c "$ORCH_BIN_DIR/messages/send.sh <target> <<'ORCH_MSG'
  본문
  ORCH_MSG"
  ```
  슬래시 `/orch:send` 는 `$ARGUMENTS` 가 셸 파서 깨뜨려 특수문자에서 실패. `$ORCH_BIN_DIR` 는 워커 spawn 시 자동 export.

---

## 2. wait-reply.sh — 차단 질문 패턴

답이 필요한 질문을 보낸 뒤 답을 못 받았는데 다른 마디로 진행하면 추측 작업이 PR 까지 가서 회수 불가. 송신 직후 `wait-reply.sh` 로 차단 대기.

### 마커 규약 (correlation id 의무)

- 질문 본문에 `[question:<qid>]` — qid 는 매 송신마다 새로 생성.
- 답 본문에 `[reply:<qid>]` — 같은 qid 를 다시 박아야 wait-reply 가 그 라운드 답으로 인식.
- 동시·재질문 시 답 섞임 차단 목적. 다른 qid 의 reply 가 도착하면 무시.

### qid 생성

```bash
qid="q-$(date +%s)-$RANDOM"
```

### 송신 + 블록 대기

```bash
bash -c "$ORCH_BIN_DIR/messages/send.sh <target> <<ORCH_MSG
[question:$qid]
<질문 본문 + 옵션 후보 + 디폴트 추천>
ORCH_MSG"
bash $ORCH_BIN_DIR/messages/wait-reply.sh $qid    # 차단. 답 본문 + msg_id 출력. exit 2 면 timeout.
# 처리 후:
bash $ORCH_BIN_DIR/messages/inbox-archive.sh <msg_id>
```

- **timeout 기본 1h** (`ORCH_WAIT_REPLY_TIMEOUT` 으로 조정). exit 2 → 재prompt 후 재대기.
- **답 받기 전 다른 마디 진행 금지** — wait-reply 가 exit 0 으로 풀린 다음에만.
- **답신 불필요 케이스** (FYI / ack / 단발성 진행 보고) 는 wait-reply 안 쓰고 비-blocking. 본문에 `**[답신 불필요]**` 마커.

### 차단 질문 응답 의무 (leader / orch)

`[question:<qid>]` 마커가 박힌 메시지는 송신측이 wait-reply 로 막힌 상태. 답 미루지 말고 우선 처리. 사용자 차원 결정이면 leader 가 직접 사용자에게 묻고, 같은 `[reply:<qid>]` 로 송신측에 돌려준다.

---

## 3. HOLD 체크포인트 — 의무 (워커 공통)

leader 의 HOLD / 취소 / 방향 전환 메시지가 자기 작업에 묻히지 않도록, 다음 두 마디에서 `/orch:check-inbox` 1회 (요약 → 단건):

1. **분석 → 편집(또는 산출물 finalize) 전환 직전** — 수정·문서화 시작 전. spec 재검토 + HOLD 도착 여부 확인.
2. **push 직전** — 로컬 commit 끝났지만 origin push 전. push 후엔 PR/CI 비용 발생.

처리:
- HOLD / 취소 / 방향 전환 발견 → 즉시 중단, leader 에 ack 후 다음 지시 대기.
- 새 메시지 0건 → 그대로 진행.

---

## 4. PR 4단계

워커 (developer / PM 산출물 PR) 가 PR 을 만든 뒤 다음 4단계를 그대로 따른다.

### 순서 invariant (워커 자체 검증)

design-first task graph (`references/workflows/task-graph-contract.md` §9.1 developer_pr_v1) 와 일관되게 워커는 다음 invariant 를 위반하지 않는다. 위반 시 leader 가 HOLD 로 차단.

- `ci` step `status="done"` 전 `ready_for_review` 진입 금지.
- `review` step `status="done"` (verdict=LGTM) 전 `wait_merge` 진입 금지.
- `wait_merge` step `status="done"` (PR merged) 전 `worker-shutdown.sh` 호출 금지.

### 1. CI

worker first_msg 가 git_host (github/gitlab) 별로 `<pr_create_cmd>` / `<pr_checks_watch_cmd>` / `<pr_run_log_failed_cmd>` 를 주입한다. SKILL 본문은 그 변수만 참조 — gh / glab 분기 직접 안 함.

```bash
# commit + push 후
<pr_create_cmd>          # gh pr create --base "$base" --title "$title" --body "$body"
                         # 또는 glab mr create --target-branch "$base" --title "$title" --description "$body"
<pr_checks_watch_cmd>    # gh pr checks "$pr" --watch --required
                         # 또는 glab ci status --live   (glab 1.36+ 는 --wait 미지원; --live 가 pipeline ends 까지 block)
```

- 실패: `<pr_run_log_failed_cmd>` (gh: `gh run view "$run_id" --log-failed | head -200` / glab: `glab api projects/:fullpath/pipelines/$pipeline_id/jobs?scope[]=failed` 의 첫 실패 job 의 `/trace` endpoint head -200 — glab CLI 의 `ci view` 는 TUI interactive 라 automation 불가, REST API 우회) 로 진단. 자기 영역이면 직접 fix → 재push → 재watch. 다른 워커 영역이면 leader 에 escalate.
- 통과: leader 에 `PR #N ready for review + URL` 답신.

### 2. 리뷰

- leader 가 받은 'ready' 답신을 트리거로 `/orch:review-spawn <project> <pr>` 호출.
- reviewer 답신 (PR 코멘트 + leader inbox 두 채널, 같은 본문) 본문 첫 줄:
  - `[review PR #N] LGTM` → **즉시 3 진입** (leader 추가 지시 기다리지 말 것)
  - `[review PR #N] needs-changes` → 수정 push → 're-review please' 답신 → 라운드 N+1 반복

### 3. 머지 대기

```bash
bash $ORCH_BIN_DIR/issues/wait-merge.sh <pr-num>    # 30s 폴링.
```

- exit 0 (MERGED) → leader 에 'PR #N merged' 답신 → 4 진입.
- exit 1 (CLOSED) / exit 2 (timeout) → leader 보고 후 대기.

### 4. 자기 종료 (필수)

```bash
bash $ORCH_BIN_DIR/issues/worker-shutdown.sh
```

- registry 해제 + pane kill 한 번에. `exit` 키 입력 금지 (Claude Code 가 떠 있어 셸에 안 닿음).
- 이 명령 이후 응답 못 받는다 (정상).

---

## 5. 컨텍스트 위생

- 컨텍스트 150k 넘으면 **작업 마디 (커밋 / 보고 직후)** 에서 `/compact` 1회. 마디 중간에 호출하면 진행 상태 파편화.
- 전체 빌드·전체 테스트 금지 — 변경분 한정 (`./gradlew :module:test --tests <변경 클래스>` / `pnpm test -- --findRelatedTests <변경 파일>`). 크로스-프로젝트 E2E 는 SKIP — 의존 보이면 leader 보고.

---

## 6. 메시지 ID 인용 의무

처리 결과 보고 시 **반드시 message_id 인용**. 같은 보낸이의 비슷한 본문이 여러 번 와도 추적 가능하도록.

- ✅ `[id=1778074602-9oovce] mp-7 issue-down 알림 처리. /orch:report mp-7 곧바로 트리거합니다.`
- ❌ `mp-7 issue-down 알림 받았어요, report 작성 시작합니다.` (id 누락)

처리한 메시지는 단건 archive: `bash -c "$ORCH_BIN_DIR/messages/inbox-archive.sh <id>"`.

---

## 7. 모호한 사용자 prompt → escalate

auto-mode classifier 가 사용자 prompt 띄우고 답이 "보류" / "잠시" / "음..." 등 모호하면 추측 진행 금지. leader 에 사유 명시 요청 (보류 사유 / PR 분리 / 재검토 / 단순 확인 중 어느 것?). 명확한 GO·STOP 아니면 대기.
