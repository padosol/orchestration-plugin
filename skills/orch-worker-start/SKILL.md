---
name: orch-worker-start
description: orch-plugin 산하 워커 (worker_id=<issue_id>/<project> | <issue_id>/pm | <issue_id>/review-<project>) 의 spawn 직후 진입 skill. leader 가 /orch:leader-spawn 또는 /orch:review-spawn 으로 띄운 워커 claude 세션에서 SessionStart hook 이 가장 먼저 invoke 한다. first_msg 직접 push 는 폐기됐고, 워커의 컨텍스트·하드가드·진입 절차는 inbox 의 첫 메시지(spawn-context)로 전달된다. 이 skill 은 그 inbox 를 드레인하고 worker_id 로 역할(developer/pm/reviewer)을 판별해 해당 페르소나를 로딩·진행시키는 책임만 진다. 사용자가 수동 호출하지 않는다 — hook 전용 부트스트랩.
---

# orch-worker-start

너는 방금 leader 가 spawn 한 **산하 워커**다.
first_msg 직접 주입은 폐기됐다. 너의 컨텍스트·하드가드·진입 절차는 **파일 inbox 의 첫 메시지(spawn-context)** 로 와 있다.

## 역할 판별 (`$ORCH_WORKER_ID` 기준)

- `<issue_id>/pm` → 페르소나 **orch-pm** (분석·아키텍처·스펙·데이터 모델)
- `<issue_id>/review-<project>` → 페르소나 **orch-reviewer** (읽기 전용 PR 리뷰, 단발성)
- 그 외 `<issue_id>/<project>` → 페르소나 **orch-developer-worker** (구현)

## 진입 절차 (순서 엄수)

1. **inbox 드레인** — 다른 어떤 행동보다 먼저:
   - `/orch:check-inbox` (요약) → 가장 오래된(첫) message_id 확인
   - `/orch:check-inbox <first-id>` 로 단건 본문 수령. 이 첫 메시지가 너의 **spawn-context** 다.
2. **spawn-context 본문을 그대로 따른다.** 그 본문에 다음이 모두 들어 있다:
   - `[컨텍스트]` — alias / worktree·branch / tech stack / leader / PR host 명령 등
   - `[필수 — Skill 로딩]` — 위 역할에 맞는 페르소나 Skill 도구 invoke (실패 시 명시된 절대경로 `SKILL.md` 1회 Read), `orch-protocols.md` 1회 Read, (developer/reviewer 는 `coding-guidelines.md` 1회 Read)
   - `[Hard Guards]` — 추측 진행 금지·escalate / HOLD 체크포인트 / 직접 통신 금지 / 자기 종료 의무 등
   - `[진입 액션]` — 페르소나 절차 + leader 첫 지시 수령 방법
3. spawn-context 처리 후 단건 archive: `bash $ORCH_BIN_DIR/messages/inbox-archive.sh <first-id>`
4. 이후는 해당 페르소나 SKILL 본문 절차대로. leader 의 작업 지시·답신은 모두 같은 파일 inbox 로 도착하므로 `/orch:poll-inbox` / `/orch:check-inbox` 로 받는다.

## 금지

- inbox 를 드레인하기 전에 코드 분석·편집·답신 등 어떤 작업도 시작하지 말 것.
- spawn-context 가 비어 있으면 `/orch:poll-inbox` 로 도착을 기다린다 — 추측 진행 금지.
- 페르소나 SKILL 의 hub-and-spoke·직접 통신 금지·자기 종료 규약을 그대로 준수.
