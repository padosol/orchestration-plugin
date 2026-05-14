# Design-first Task Graph Workflow

## 목적

기존 phase 중심 워크플로우는 단일 repo / 단일 PR 작업에는 안정적이지만, 멀티 repo 병렬 개발에서는 phase 가 지나치게 직렬화된다. 이 문서는 PM 설계를 먼저 받고, 그 결과를 task graph 로 변환한 뒤, 의존성 기반으로 작업을 진행하는 새 워크플로우를 정의하기 위한 작업 계획이다.

목표는 다음과 같다.

- PM 설계 산출물을 실행 계획의 입력으로 사용한다.
- leader 는 task graph 의 최종 소유자이자 scheduler 역할을 맡는다.
- task 는 명시적인 workflow step 순서를 가진다.
- 병렬 가능한 작업은 depends_on 기준으로 동시에 진행할 수 있다.
- PR / CI / review / merge 순서를 task 단위로 강제한다.
- 마지막에는 task 결과를 기반으로 report / cleanup 으로 진입한다.

## 목표 흐름

```text
Phase 0. Analysis / Design
- PM 또는 leader lightweight design
- direction-check
- proposed task graph 작성
- 사용자 승인

Phase 1. Task Execution
- leader 가 task graph 를 확정
- depends_on 이 완료된 ready task 를 spawn
- 각 task 는 workflow step 순서대로 진행
- developer -> test -> PR -> CI -> review -> merge -> shutdown

Phase 2. Report / Cleanup
- task 결과 수집
- 미해결 risk / follow-up 후보 정리
- REPORT 생성
- issue-down
```

## 핵심 모델

### 확장 원칙

이 워크플로우는 role 별 능력 강화를 기존 실행 흐름에 덜 침투시키는 것을 목표로 한다.

- core 계약은 작게 유지한다.
- role 별 세부 능력은 `workflow_template` 와 typed artifact 로 확장한다.
- PM 은 풍부한 설계 산출물과 proposed task graph 를 만들 수 있다.
- leader 는 PM 산출물을 검토해 approved task graph 로 확정한다.
- developer / reviewer workflow 는 PM 능력 강화와 독립적으로 유지한다.

즉, PM 을 강화할 때 developer PR lifecycle 을 다시 설계하지 않아도 되어야 한다.

### Phase

워크플로우의 큰 lifecycle 단계다.

- `phase_0_design`: 분석 / 설계 / task graph 제안
- `phase_1_execution`: task graph 실행
- `phase_2_report`: 보고서 작성 / 정리

### Task

실제 worker 가 수행하거나 leader 가 직접 처리하는 실행 단위다.

Task 는 다음 정보를 가진다.

- `id`
- `project`
- `role`
- `type`
- `depends_on`
- `status`
- `workflow_template`
- `workflow`
- `artifacts`

### Task Graph

task 들과 의존성의 집합이다. 개념적으로 DAG 이며, leader 는 선행 task 가 완료된 task 만 ready 로 판단한다.

```text
A: pm-design
B: backend-api
C: frontend-ui
D: integration-check

A -> B
A -> C
B -> D
C -> D
```

Task graph 는 두 종류를 구분한다.

- `proposed_task_graph`: PM 이 제안한 실행 그래프. 설계 산출물의 일부이며, leader 의 검토 전 상태다.
- `approved_task_graph`: leader 가 확정한 실행 그래프. worker spawn 과 task status 판단의 기준이다.

PM 이 제안한 graph 를 leader 가 그대로 채택할 수도 있지만, 소유권은 분리한다. PM 은 제안자이고 leader 는 scheduler / router / 최종 확정자다.

### Workflow Template

task 내부의 실행 순서다. 예를 들어 developer PR task 는 다음 순서를 따른다.

```text
receive_instruction
analyze
hold_before_edit
brief_validation
implement
test
commit
hold_before_push
push_and_pr
ci
ready_for_review
review
wait_merge
shutdown
```

Role 별 workflow template 는 독립적으로 확장할 수 있다.

- `developer_pr_v1`: 구현 PR lifecycle
- `pm_design_v1`: 분석 / 설계 / direction-check / proposed task graph lifecycle
- `reviewer_pr_v1`: 단일 PR review lifecycle
- `integration_check_v1`: 멀티 task 통합 검증 lifecycle
- `report_cleanup_v1`: 보고서 / follow-up / issue-down lifecycle

새 PM 능력을 추가할 때는 우선 `pm_design_vN` template 와 design artifact 를 확장한다. developer / reviewer template 변경은 실제 실행 순서가 바뀔 때만 한다.

### Design Artifacts

PM 또는 leader lightweight design 이 만드는 설계 산출물이다. 산출물은 typed artifact 로 관리한다.

Core artifact:

- `problem_frame`
- `architecture_decision`
- `implementation_brief`
- `risk_register`
- `open_decisions`
- `proposed_task_graph`

확장 artifact 예시:

- `api_contract`
- `db_model`
- `event_flow`
- `migration_plan`
- `security_review`
- `test_strategy`
- `rollout_plan`
- `observability_plan`

Core artifact 는 PM direction-check 와 task graph 생성에 필요한 최소 계약이다. 확장 artifact 는 PM 능력 강화나 프로젝트 특성에 따라 추가한다.

## PM 적용 분기

복잡도 신호에 따라 PM session 사용 여부가 갈린다. 본 표는 사용자 가독용 요약이며 실행 canonical 은 `skills/orch-leader/SKILL.md` §3.5.1 — leader 가 결정 시 SKILL 본문을 우선 본다.

| 신호 | 분류 | PM session |
| --- | --- | --- |
| project ≥ 2 개 (멀티 repo) | 복잡 | **필수** |
| API contract / DB model / migration / auth / 권한 / 외부 연동 변경 | 복잡 | **권장** |
| 비기능 리스크 (성능 / 보안 / 호환성) 또는 acceptance criteria 모호 | 복잡 | **권장** |
| 위 조건 모두 해당 안 됨 (단일 repo, 명확 AC, 작은 UI / 단순 fix / refactor) | 단순 | **생략 — leader lightweight design** |

PM 권장 케이스인데 leader 가 PM 을 생략하기로 결정하면 phases.md 에 생략 사유 한 줄 기록 (예: "단일 API endpoint 추가, contract 기존 패턴 그대로"). 단순 이슈는 leader 가 task-graph.json 의 `design.proposed_by = "leader"` 로 lightweight design 직접 작성.

## 예시 Task Graph

두 예시 모두 `references/schemas/task-graph.schema.json` strict 형식. shorthand string-array 또는 root.tasks 필드는 schema 위반 — 따르지 말 것.

### 단순 이슈 예시 — lightweight design (PM 생략)

단일 repo, 명확 acceptance, 작은 UI fix. PM session 없이 leader 가 design + execution 두 절을 1 라운드로 작성.

```json
{
  "issue_id": "MP-200",
  "workflow_version": 1,
  "phase": "execution",
  "design": {
    "status": "approved",
    "proposed_by": "leader",
    "pm_pr": null,
    "summary": "Increase content-list pagination size from 20 to 50",
    "artifacts": {
      "problem_frame": { "summary": "기본 페이지 크기가 너무 작아 사용자 클릭이 많아짐" },
      "architecture_decision": { "summary": "기존 페이지네이션 컴포넌트 그대로, 기본값 상수만 변경" },
      "implementation_brief": { "summary": "constants.ts 의 DEFAULT_PAGE_SIZE 20→50 + 회귀 테스트 보강" },
      "risk_register": [],
      "open_decisions": [],
      "proposed_task_graph": {
        "tasks": [
          {
            "id": "pagination-fix",
            "project": "management-ui",
            "role": "developer",
            "type": "fix",
            "depends_on": [],
            "workflow_template": "developer_pr_v1"
          }
        ]
      }
    }
  },
  "execution": {
    "approved_by": "leader",
    "approved_at": "2026-05-13T09:00:00Z",
    "approved_task_graph": {
      "revision": 0,
      "tasks": [
        {
          "id": "pagination-fix",
          "project": "management-ui",
          "role": "developer",
          "type": "fix",
          "depends_on": [],
          "status": "pending",
          "current_step": "receive_instruction",
          "workflow_template": "developer_pr_v1",
          "workflow": [
            { "id": "receive_instruction", "owner": "leader",    "status": "pending", "required": true, "blocking": true },
            { "id": "analyze",             "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "hold_before_edit",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "brief_validation",    "owner": "developer", "status": "pending", "required": true, "blocking": false },
            { "id": "implement",           "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "test",                "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "commit",              "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "hold_before_push",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "push_and_pr",         "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "ci",                  "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "ready_for_review",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "review",              "owner": "reviewer",  "status": "pending", "required": true, "blocking": true },
            { "id": "wait_merge",          "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "shutdown",            "owner": "developer", "status": "pending", "required": true, "blocking": true }
          ],
          "artifacts": {
            "branch": null,
            "commit": null,
            "pr": null,
            "ci_url": null,
            "review_verdict": null
          }
        }
      ]
    }
  }
}
```

### 멀티 repo 이슈 예시 — PM 필수

project ≥ 2. PM session 으로 design artifact 6개 산출 + proposed_task_graph 에 3 TaskDraft (backend / mgmt-ui / integration-check). leader 는 approved_task_graph 로 확장하되, `integration-check` 는 `integration_check_v1` 이 아직 placeholder 라 현재 revision 의 approved 에 포함하지 않는다 — stable 화 (작업 11+ 후속) 후 leader 가 `revision +1` 로 추가. 따라서 현재 approved 는 2 Task (`backend-api` + `mgmt-ui`).

```json
{
  "issue_id": "MP-123",
  "workflow_version": 1,
  "phase": "execution",
  "design": {
    "status": "approved",
    "proposed_by": "pm",
    "pm_pr": 42,
    "summary": "Add publishing flow across API and management UI",
    "artifacts": {
      "problem_frame": { "summary": "Publishing flow requires API and management UI changes" },
      "architecture_decision": { "summary": "API owns publishing state; management UI calls the new endpoint" },
      "implementation_brief": { "summary": "Implement backend endpoint and management UI action" },
      "risk_register": [
        { "risk": "Frontend / backend contract mismatch", "mitigation": "Add integration_check task after both PRs merge" }
      ],
      "open_decisions": [],
      "proposed_task_graph": {
        "tasks": [
          { "id": "backend-api",        "project": "contents-hub-api-serv", "role": "developer",   "type": "feat", "depends_on": [],                                "workflow_template": "developer_pr_v1" },
          { "id": "mgmt-ui",            "project": "management-ui",         "role": "developer",   "type": "feat", "depends_on": [],                                "workflow_template": "developer_pr_v1" },
          { "id": "integration-check",  "project": null,                    "role": "integration",                 "depends_on": ["backend-api", "mgmt-ui"],        "workflow_template": "integration_check_v1" }
        ]
      }
    }
  },
  "execution": {
    "approved_by": "leader",
    "approved_at": "2026-05-13T09:00:00Z",
    "approved_task_graph": {
      "revision": 0,
      "tasks": [
        {
          "id": "backend-api",
          "project": "contents-hub-api-serv",
          "role": "developer",
          "type": "feat",
          "depends_on": [],
          "status": "pending",
          "current_step": "receive_instruction",
          "workflow_template": "developer_pr_v1",
          "workflow": [
            { "id": "receive_instruction", "owner": "leader",    "status": "pending", "required": true, "blocking": true },
            { "id": "analyze",             "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "hold_before_edit",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "brief_validation",    "owner": "developer", "status": "pending", "required": true, "blocking": false },
            { "id": "implement",           "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "test",                "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "commit",              "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "hold_before_push",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "push_and_pr",         "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "ci",                  "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "ready_for_review",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "review",              "owner": "reviewer",  "status": "pending", "required": true, "blocking": true },
            { "id": "wait_merge",          "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "shutdown",            "owner": "developer", "status": "pending", "required": true, "blocking": true }
          ],
          "artifacts": { "branch": null, "commit": null, "pr": null, "ci_url": null, "review_verdict": null }
        },
        {
          "id": "mgmt-ui",
          "project": "management-ui",
          "role": "developer",
          "type": "feat",
          "depends_on": [],
          "status": "pending",
          "current_step": "receive_instruction",
          "workflow_template": "developer_pr_v1",
          "workflow": [
            { "id": "receive_instruction", "owner": "leader",    "status": "pending", "required": true, "blocking": true },
            { "id": "analyze",             "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "hold_before_edit",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "brief_validation",    "owner": "developer", "status": "pending", "required": true, "blocking": false },
            { "id": "implement",           "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "test",                "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "commit",              "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "hold_before_push",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "push_and_pr",         "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "ci",                  "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "ready_for_review",    "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "review",              "owner": "reviewer",  "status": "pending", "required": true, "blocking": true },
            { "id": "wait_merge",          "owner": "developer", "status": "pending", "required": true, "blocking": true },
            { "id": "shutdown",            "owner": "developer", "status": "pending", "required": true, "blocking": true }
          ],
          "artifacts": { "branch": null, "commit": null, "pr": null, "ci_url": null, "review_verdict": null }
        }
      ]
    }
  }
}
```

위 approved 는 `revision: 0`. `integration_check_v1` stable 화 후 leader 가 `revision: 1` 로 `integration-check` Task (depends_on: ["backend-api", "mgmt-ui"], workflow_template: "integration_check_v1") 를 추가하는 흐름. proposed_task_graph 에는 placeholder 참조 TaskDraft 를 둘 수 있지만 approved_task_graph 의 Task 로 확장은 stable template 필요 — leader SKILL §3.5.4 "placeholder template 사용 금지" invariant.

## 상태 값 초안

Task status:

- `pending`
- `ready`
- `running`
- `blocked`
- `needs_changes`
- `merged`
- `done`
- `failed`
- `skipped`

Workflow step status:

- `pending`
- `running`
- `done`
- `failed`
- `skipped`

## 설계 원칙

- PM 은 task graph 를 제안한다. 최종 확정과 scheduling 은 leader 책임이다.
- `design.artifacts.proposed_task_graph` 와 `execution.approved_task_graph` 는 구분한다.
- worker spawn / task status 판단은 approved task graph 만 기준으로 한다.
- 단순 이슈도 Phase 0 을 가진다. 다만 PM session 은 조건부다.
- 복잡 이슈 / 멀티 repo / API contract / DB model 변경은 PM session 을 기본값으로 한다.
- PM 능력 강화는 우선 `pm_design_vN` workflow template 와 design artifact 확장으로 처리한다.
- schema 는 strict core 와 flexible extensions 를 분리한다. core 필드는 모든 workflow 가 의존하고, extension 필드는 role / project 별로 추가 가능하다.
- developer 는 review 완료 전 `wait_merge` 로 진입할 수 없다.
- CI 통과 전 reviewer spawn 금지.
- task graph 승인 전 developer spawn 금지.
- report 는 task graph 의 artifacts 와 status 를 기반으로 작성한다.

## 작업 순서

- [x] 1. task graph / workflow template 계약 문서 확정 → [task-graph-contract.md](task-graph-contract.md)
  - task graph 필드 정의
  - workflow step 필드 정의
  - task / step status 정의
  - developer PR workflow 순서 확정
  - `proposed_task_graph` / `approved_task_graph` 분리 확정
  - `design.artifacts` typed artifact 구조 확정
  - role 별 workflow template 확장 규칙 확정
  - strict core / flexible extensions 경계 확정

- [x] 2. JSON schema 초안 추가 → [task-graph.schema.json](../schemas/task-graph.schema.json)
  - `references/schemas/task-graph.schema.json`
  - 필수 필드 / enum / artifacts 구조 정의
  - core 필드와 extension 필드 구분

- [x] 3. workflow template 파일 추가 → [task-templates/](task-templates/) + [task-template.schema.json](../schemas/task-template.schema.json)
  - `references/workflows/task-templates/developer_pr_v1.json` (stable, 14 step)
  - `references/workflows/task-templates/pm_design_v1.json` (placeholder — 작업 5)
  - `references/workflows/task-templates/integration_check_v1.json` (placeholder — 작업 6/7)
  - `reviewer_pr_v1.json` / `report_cleanup_v1.json` 은 작업 6/7 에서 추가
  - role 별 template versioning 규칙: 계약 §10.2 single source. 파일 안에 `{name, version, status}` metadata.

- [x] 4. leader SKILL 개정 → [orch-leader §3.5](../../skills/orch-leader/SKILL.md)
  - `Design-first Task Graph Workflow` 도입
  - 단순 이슈와 복잡 이슈 분기 (project ≥ 2 / API · DB · migration · auth 시그널)
  - Phase 0 design 승인 후 execution task graph 확정
  - ready task spawn 규칙 (depends_on ∈ {merged, done}, worker report 트리거)
  - step 순서 invariant 4건 (SKILL §3.5.5 + orch-protocols.md 5절)

- [x] 5. PM SKILL 개정 → [orch-pm §1·§2·§2.1](../../skills/orch-pm/SKILL.md)
  - direction-check 6 섹션 확장 (`## Proposed Task Graph` 추가)
  - typed design artifacts 산출물 2 종 (`docs/spec/<id>/design.md` + `proposed-task-graph.json`)
  - `pm_design_v1.json` placeholder → stable 승격 (11 step, owner/required/blocking 확정 — `direction_check` 가 wait-reply 차단 대기 포함)
  - PM = `proposed_task_graph` 제안자 / leader = `approved_task_graph` 최종 확정자 명시
  - PM 의 `.orch/runs/<mp_id>/task-graph.json` 직접 수정 금지

- [x] 6. developer SKILL 개정 → [orch-developer-worker §0.5·§2·§6·§8](../../skills/orch-developer-worker/SKILL.md)
  - §0.5 Workflow Step Map (14 step ↔ SKILL 절 매핑 + invariant 3건 + 권한 경계)
  - §2 HOLD 마디 2건에 step 3 / 4 / 8 인라인
  - §6 PR 4단계에 step 9~14 인라인 + 순서 invariant 3건 재기술
  - §8 진입 액션 step 1 / 2 명시
  - developer 의 `.orch/runs/<mp_id>/task-graph.json` 직접 수정 금지 (PM SKILL 과 같은 패턴)

- [x] 7. reviewer SKILL 개정 → [orch-reviewer §0.5·§2·§4·§5·§7](../../skills/orch-reviewer/SKILL.md)
  - `reviewer_pr_v1.json` 신설 (stable, 5 step: receive_instruction → read_pr → evaluate → respond → shutdown)
  - 계약 §9.3 도 stable 5-step 표로 갱신
  - §0.5 Workflow Step Map + 권한 경계 (task-graph.json 직접 read/write 금지 + first_msg 단일 입력 + 누락 시 leader 질문)
  - §2 일반 체크리스트 5항목 → 7항목 (6. Task acceptance criteria / 7. depends_on 정합성)
  - §4 답신 = step 4 `respond` 명시 (GitHub PR + leader inbox 둘 다 끝나야 done)
  - Task Graph 결과는 verdict 기존 5섹션에 흡수 (별도 섹션 안 만듦)
  - E2E 대체 검증 기준 (§5) 유지

- [x] 8. issue-up / first_msg hard guard 정리 → [issue-up.sh first_msg + orch-leader SKILL §3.5.5](../../scripts/issues/issue-up.sh)
  - first_msg Hard Guards 5→6 (절차는 SKILL 위임, 런타임 불변식만 first_msg 노출)
  - Guard #1 강화: 복잡 이슈 Round 2 GO (approved_task_graph 승인) 전 developer/reviewer/integration spawn 금지 명시
  - Guard #2 신설: PR workflow step 순서 invariant (ci done 전 ready_for_review / review LGTM 전 wait_merge / wait_merge done 전 shutdown 금지)
  - SKILL §3.5.5 step/token 명칭 정렬 (approved_task_graph / ready_for_review / wait_merge / shutdown)
  - 회귀 테스트 20 / 65 키워드 갱신

- [x] 9. 회귀 테스트 추가 → [tests/scenarios/70~72](../../tests/scenarios/) + 기존 65/66/67/69 유지
  - leader SKILL 에 Design-first Task Graph Workflow 존재 — covered by test 65 (`Design-first Task Graph` / `approved_task_graph` / `placeholder template` 등)
  - PM SKILL 에 Proposed Task Graph 존재 — covered by test 66 (`Proposed Task Graph` / `proposed-task-graph.json` / `pm_design_v1`)
  - developer workflow 에 review 전 wait_merge 순서 존재 — covered by test 67 (SKILL content / step keyword) + test 71 (`developer_pr_v1.json` step 순서 / blocking / owner 구조 검증)
  - schema 에 depends_on / workflow_template / workflow 존재 — covered by test 70 (grep 기반 필드 / role / status enum) + test 72 (jsonschema Draft 2020-12 self-check + 모든 task-template/*.json validate)
  - 기존 PR 4단계 / HOLD / hub-and-spoke 규약 유지 — covered by test 69 (orch-protocols.md 단일 source) + test 67 (developer SKILL workflow step / HOLD / PR 4단계 keyword)

- [x] 10. 문서 예시 갱신 → [design-first-task-graph.md PM 적용 분기 / 예시 두 sub-section](design-first-task-graph.md)
  - 단순 issue 예시 — lightweight design (proposed_by=leader / pm_pr=null / risk_register=[] / 1 TaskDraft → 1 Task)
  - 멀티 repo issue 예시 — PM 필수 (proposed_by=pm / pm_pr=42 / 3 TaskDraft → 2 Task in approved revision 0; integration-check 는 integration_check_v1 stable 화 후 revision +1 로 추가)
  - PM 생략 / 필수 조건 — 새 "## PM 적용 분기" 절 (canonical: orch-leader SKILL §3.5.1 mirror)
  - 기존 예시의 schema 위반 정리 (root.tasks 제거 / tasks: string[] → object array / 두 예시 모두 schema strict)

## 첫 작업

첫 작업은 `1. task graph / workflow template 계약 문서 확정`이다.

이 작업에서는 코드나 SKILL 을 바로 바꾸지 않는다. 먼저 task graph 와 workflow step 의 최소 필드, 상태 값, developer PR workflow 의 순서, PM 확장을 위한 typed design artifacts, proposed / approved task graph 분리를 확정한다. 이 계약이 확정되어야 이후 schema, template, leader / PM / developer / reviewer SKILL 을 같은 기준으로 수정할 수 있다.
