---
name: orch-leader-start
description: orch-plugin leader (worker_id=<issue_id>) 의 spawn 직후 진입 skill. /orch:issue-up 으로 띄워진 leader claude 세션에서 SessionStart hook 이 가장 먼저 invoke 한다. first_msg 직접 push 는 폐기됐고, leader 의 컨텍스트·하드가드·진입 절차는 inbox 의 첫 메시지(spawn-context)로 전달된다. 이 skill 은 그 inbox 를 드레인해 spawn-context 를 수령하고 그 지시대로 orch-leader 페르소나를 로딩·진행시키는 책임만 진다. 사용자가 수동 호출하지 않는다 — hook 전용 부트스트랩.
---

# orch-leader-start

너는 방금 `/orch:issue-up` 으로 spawn 된 **leader** (`worker_id=<issue_id>`) 다.
first_msg 직접 주입은 폐기됐다. 너의 컨텍스트·하드가드·진입 절차는 **파일 inbox 의 첫 메시지(spawn-context)** 로 와 있다.

## 진입 절차 (순서 엄수)

1. **inbox 드레인** — 다른 어떤 행동보다 먼저:
   - `/orch:check-inbox` (요약) → 가장 오래된(첫) message_id 확인
   - `/orch:check-inbox <first-id>` 로 그 단건 본문 수령. 이 첫 메시지가 너의 **spawn-context** 다.
2. **spawn-context 본문을 그대로 따른다.** 그 본문에 다음이 모두 들어 있다:
   - `[컨텍스트]` — issue / 사용 가능 프로젝트 / 이슈 fetch step / workflows 디렉토리 / plugin root
   - `[필수 — Skill 로딩]` — `orch-leader` Skill 도구 invoke (실패 시 명시된 절대경로 `SKILL.md` 1회 Read), `orch-protocols.md` 1회 Read
   - `[Hard Guards]` — 사용자 GO 전 워커 spawn 금지 / PR step 순서 invariant / 타입 모호 시 직접 AskUserQuestion 등
   - `[진입 액션]` — 셋업·타입 판별·phase plan 작성 → 사용자 직접 컨펌
3. spawn-context 처리 후 단건 archive: `bash $ORCH_BIN_DIR/messages/inbox-archive.sh <first-id>`
4. 이후는 `orch-leader` SKILL 본문 절차대로. 추가 지시는 모두 같은 파일 inbox 로 도착하므로 필요한 지점에서 `/orch:check-inbox` 또는 `/orch:poll-inbox` 로 받는다.

## 금지

- inbox 를 드레인하기 전에 셋업·타입판별·phase plan·워커 spawn 등 어떤 작업도 시작하지 말 것.
- spawn-context 가 비어 있으면(첫 메시지 없음) `/orch:poll-inbox` 로 도착을 기다린다 — 추측 진행 금지.
