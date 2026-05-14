---
description: .orch/settings.json 의 description / tech_stack 이 실제 프로젝트 파일과 어긋나는지 검증
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/config/validate-settings.sh:*), Read, Edit
---

`validate-settings` 스킬을 호출해 `.orch/settings.json` 의 정확성을 검증하세요.

스킬 절차 요약:
1. `${CLAUDE_PLUGIN_ROOT}/scripts/config/validate-settings.sh` 실행 → JSON 신호 추출
2. 각 프로젝트의 declared description/tech_stack/kind 를 actual 과 대조
3. drift 가 있으면 표로 보고 → 사용자 동의 받고 `Edit` 으로 settings.json patch

**언제 사용**:
- `/orch:setup` 직후 (자동 연계)
- 프로젝트 의존성 업그레이드 후 settings.json 이 stale 한지 확인할 때
- leader 가 위임 판단을 잘못한다고 의심될 때

**검증 범위**: 버전 숫자(Next.js/React/Spring Boot/JDK), 프레임워크 이름, kind 분류만. description 의 책임/도메인 설명은 건드리지 않음 — 사용자가 직접 쓴 의미.
