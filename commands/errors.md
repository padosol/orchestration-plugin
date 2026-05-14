---
description: 누적된 orch 에러 로그 조회 — scope-aware (top-level + 모든 issue scope errors.jsonl 통합)
argument-hint: [--tail N] [--analyze] [--mp <id>] [--worker <wid>] [--script <name>] [--clear]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect/errors.sh:*)
---

다음 명령으로 누적된 에러 로그를 확인하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/inspect/errors.sh $ARGUMENTS`

**역할**:
- orch 스크립트 비0 종료 시 자동으로 errors.jsonl 에 한 줄 JSON 로그 추가
- **scope-aware**: 워커가 issue scope (`<issue_id>` 또는 `<issue_id>/role`) 면 `.orch/runs/<issue_id>/errors.jsonl`, orch/unknown 이면 `.orch/errors.jsonl`. issue-down 시 scope 째 archive 됨.
- 패턴 보고 시스템(스크립트 / 첫 메시지 / 라우팅) 지속 개선용

**예**:
- `/orch:errors` — top-level + 모든 이슈 scope 통합, 마지막 20건
- `/orch:errors --tail 50` — 마지막 50건
- `/orch:errors --mp MP-9` — MP-9 scope (live 또는 archive) 만 (--mp 옵션명은 호환 유지; 값은 임의 이슈 키)
- `/orch:errors --analyze` — script×rc / worker×script / stderr 그룹 통계 / top-3 전문
- `/orch:errors --analyze --mp MP-9` — MP-9 만 분석
- `/orch:errors --worker MP-9/server` — 특정 worker_id
- `/orch:errors --script send` — send.sh 실패만
- `/orch:errors --clear` — top-level 비움
- `/orch:errors --clear --mp MP-9` — 그 이슈 scope 만 비움

**보완 사이클**:
1. 사용자가 "이상한데" 라고 하면 `/orch:errors` 로 최근 패턴 확인
2. 반복되는 실패는 root cause 식별 → 스크립트 / 슬래시 / 첫 메시지 가이드 수정
3. 수정 후 다시 운영하며 로그 누적 → 다시 1번

**stderr 전체가 필요하면**:
바로 raw 파일 보기: `tail -n 1 <workspace>/.orch/errors.jsonl | jq .`
