---
description: 누적된 orphan inbox 파일 일괄 청소 (--dry-run 으로 미리보기)
argument-hint: [--dry-run]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inbox-prune.sh:*)
---

다음 명령으로 orphan inbox 를 청소하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/inbox-prune.sh $ARGUMENTS`

**역할**:
- `<workspace>/.orch/inbox/mp-*.md` 중 `workers/<mp-NN>.json` 에 등록 안 된 (= 종료된) leader 의 inbox 파일 + `.lock` 일괄 제거.
- 살아있는 leader inbox 는 건드리지 않음.

**언제 사용**:
- `ls .orch/inbox/` 에 0 byte 파일이 누적돼 active 워커 식별이 어려울 때
- 0.7.1 이전 버전으로 운영했던 `.orch/` 의 정리 (issue-down 에서 자동 정리 빠진 시기)

**0.7.1+ 부터는 자동**: `/orch:issue-down` 이 leader 종료 시 inbox 파일 + lock 자동 제거. 이 명령은 과거 누적분 일회성 청소 또는 비정상 종료(force kill) 후 청소용.

**`--dry-run`** — 실제 삭제 없이 후보만 표시. 처음 호출 시 권장.

**제외 대상**:
- 살아있는 leader (workers/<mp-NN>.json 존재) 의 inbox
- 비-leader 파일 (예: `orch.md`)
- `mp-*` 패턴 외 파일

**주의**:
- ❌ active leader inbox 직접 삭제 — 라우팅 차단 + flock race 가능. 이 스크립트는 등록 상태로만 판단.
- ❌ scope dir (`runs/mp-NN/`) 의 워커 inbox — issue-down scope archive 가 함께 처리. 손대지 않음.
