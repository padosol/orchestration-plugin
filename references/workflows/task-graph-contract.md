# Task Graph / Workflow Template 계약 v1

## 목적과 범위

본 문서는 `design-first-task-graph.md` 가 정의한 워크플로우의 **데이터 계약** 을 확정한다. SKILL / schema / workflow template 파일이 모두 본 문서를 단일 source 로 참조한다.

- 본 문서는 사람 간 계약 합의가 목표다. 기계 검증용 JSON Schema 는 후속 작업 (`references/schemas/task-graph.schema.json`) 에서 본 계약을 그대로 옮긴다.
- v1 의 핵심 결정: core / extension 경계 명시 + proposed/approved task graph 분리 + role 별 workflow template versioning.
- 본 v1 계약은 안정 계약 (stable). 다음 변경은 v2 로 bump 한다 — §10 versioning 규칙 참고.

## 1. 최상위 구조

Task graph 는 단일 이슈 (`issue_id`) 에 묶인 1 개 JSON 객체다.

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `issue_id` | string | yes | 이슈 식별자 (예: `MP-123`, `gh-42`). |
| `workflow_version` | integer | yes | 본 계약 버전. v1 = `1`. |
| `phase` | enum | yes | `design` \| `execution` \| `report`. 현재 lifecycle 단계. |
| `design` | object | yes | §6 design 산출물 묶음. |
| `execution` | object | conditional | phase 가 `execution` 또는 `report` 일 때 필수. §7 참고. |

알 수 없는 최상위 키는 **거부 (strict core)**. 확장은 §11 의 extension 규칙을 따른다. 실행 task 의 canonical 위치는 §7 의 `execution.approved_task_graph.tasks` 다 — root 레벨에 별도 `tasks` 필드는 두지 않는다 (단일 source).

## 2. Task 구조 (core)

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `id` | string | yes | task graph 내 unique. kebab-case 권장. |
| `project` | string \| null | yes | worker 가 작업할 project 디렉토리명. PM / report task 는 `null` 허용. |
| `role` | enum | yes | `developer` \| `reviewer` \| `pm` \| `integration` \| `leader`. |
| `type` | enum | conditional | `feat` \| `fix` \| `refactor` \| `chore` \| `docs` \| `test`. developer role 일 때 필수. |
| `depends_on` | string[] | yes | 선행 task `id` 배열. 빈 배열 허용. |
| `status` | enum | yes | §4 TaskStatus. |
| `current_step` | string | yes | `workflow[].id` 중 하나. status 가 `pending` 이면 첫 step. |
| `workflow_template` | string | yes | 적용된 template 식별자 (예: `developer_pr_v1`). §9 참고. |
| `workflow` | WorkflowStep[] | yes | §3 step 배열. template 의 step 순서를 그대로 복사. |
| `artifacts` | object | yes | role 별 실행 산출물 (branch / pr / ci_url / review_verdict 등). role 별 키는 §8 참고. |

추가 키는 §11 extension 규칙으로만 허용.

## 3. WorkflowStep 구조 (core)

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `id` | string | yes | template 내 step 식별자. 예: `implement`. |
| `owner` | enum | yes | `leader` \| `developer` \| `reviewer` \| `pm`. step 실행 주체. |
| `status` | enum | yes | §5 StepStatus. |
| `required` | boolean | yes | `false` 면 skip 가능 — `status=skipped` 로 마킹하고 후속 step 진행. |
| `blocking` | boolean | no | 기본 `true`. `false` 면 비차단 step (예: brief_validation). 비차단 step 은 결과 도착을 기다리지 않고 다음 step 진입. |

## 4. TaskStatus enum

| 값 | 의미 | 전이 가능 from |
| --- | --- | --- |
| `pending` | task 정의됨, 아직 spawn 안 됨. | (초기 상태) |
| `ready` | `depends_on` 전부 완료, spawn 대기. | pending |
| `running` | worker spawn 됨, 실행 중. | ready, blocked, needs_changes |
| `blocked` | 외부 입력 대기 (사용자 컨펌 / wait-reply). | running |
| `needs_changes` | reviewer 가 needs-changes 반환. | running |
| `merged` | PR merged, shutdown 미완료. | running |
| `done` | shutdown 완료 또는 PR 없는 task 완료. | merged, running |
| `failed` | CI 실패 또는 worker 종료 실패로 leader 가 포기. | running, needs_changes, blocked |
| `skipped` | leader 가 task graph 재계획으로 폐기. | pending, ready, blocked, needs_changes |

`done` 또는 `failed` 또는 `skipped` 는 terminal — 더 이상 전이하지 않는다.

## 5. WorkflowStep Status enum

| 값 | 의미 |
| --- | --- |
| `pending` | 아직 시작 안 됨. |
| `running` | 현재 실행 중인 step. task 내 `running` step 은 최대 1 개. |
| `done` | 완료. |
| `failed` | 실행 실패 — task status 는 `failed` 또는 `needs_changes` 로 전이. |
| `skipped` | `required=false` step 을 건너뜀. |

## 6. Design Phase (`design`)

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `status` | enum | yes | `draft` \| `proposed` \| `approved`. leader 가 approved 로 옮긴 시점에 execution phase 진입 가능. |
| `proposed_by` | enum | yes | `pm` \| `leader`. PM session 이 있으면 `pm`, leader lightweight design 이면 `leader`. |
| `pm_pr` | integer \| null | no | PM 산출물 PR 번호. PM session 이 있을 때만. |
| `summary` | string | yes | 한 줄 요약 — leader 가 사용자 보고에 사용. |
| `artifacts` | object | yes | §6.1 core artifact 6개. extension 은 §11. |

### 6.1 Core Design Artifacts (6개, v1)

| key | 타입 | 필수 | 내용 |
| --- | --- | --- | --- |
| `problem_frame` | object \| string | yes | 요구사항·제약·범위. `summary` 한 줄 필수. |
| `architecture_decision` | object \| string | yes | 채택안 + (의미 있을 때만) 대안 비교. `summary` 한 줄 필수. |
| `implementation_brief` | object \| string | yes | developer 가 받을 작업 분해 후보 + 산출물 위치. `summary` 한 줄 필수. |
| `risk_register` | array | yes | `[{ risk, mitigation }]`. 식별된 리스크 없으면 빈 배열. |
| `open_decisions` | array | yes | `[{ id, question, options?, recommended? }]`. 없으면 빈 배열. |
| `proposed_task_graph` | object | yes | §6.2. PM 이 제안한 task 목록과 의존성. |

PM SKILL §2 의 5섹션 direction-check 메시지가 본 artifact 6개의 사람 가독 표현이다. 본 계약은 그것을 typed artifact 로 변환한 것.

### 6.2 `proposed_task_graph`

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `tasks` | TaskDraft[] | yes | §6.3 TaskDraft. PM 이 제안 단계에 알 수 있는 필드만. |
| `notes` | string | no | leader 검토 시 참고용 메모. |

PM 이 제안할 때는 task draft 만 채운다. leader 가 검토 후 status / current_step / workflow / artifacts 를 채워 §2 Task 로 완성하면서 `execution.approved_task_graph.tasks` 로 옮긴다.

### 6.3 TaskDraft 구조

`proposed_task_graph.tasks` 의 요소. §2 Task 의 부분집합이며 PM 이 제안 단계에 결정할 수 있는 필드만 가진다. 실행 status / workflow 인스턴스는 leader 가 approved 단계에서 채운다.

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `id` | string | yes | 후속 approved task 와 동일 id 로 옮겨진다. |
| `project` | string \| null | yes | §2 와 동일. PM / report task 는 `null`. |
| `role` | enum | yes | §2 와 동일. |
| `type` | enum | no | developer role 이면 PM 이 권고. leader 가 approved 단계에서 확정. |
| `depends_on` | string[] | yes | 같은 draft 배열 내 `id` 만 참조. |
| `workflow_template` | string | no | PM 권고. leader 가 변경 가능. |
| `notes` | string | no | 작업 분해 메모. |

schema 작업 (2번) 에서는 TaskDraft 를 별도 정의로 분리하고, approved 단계에서 Task 로 확장되는 흐름을 그대로 반영한다.

## 7. Execution Phase (`execution`)

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `approved_by` | enum | yes | `leader`. (현재 v1 은 leader 만 승인 가능.) |
| `approved_at` | string (ISO 8601) | no | leader 승인 시각. |
| `approved_task_graph` | object | yes | §7.1. worker spawn / status 판단의 단일 기준. |

worker spawn / task status 판단은 **반드시** `approved_task_graph` 만 본다. `proposed_task_graph` 는 참고용 (감사 추적).

### 7.1 `approved_task_graph`

| 필드 | 타입 | 필수 | 설명 |
| --- | --- | --- | --- |
| `tasks` | Task[] | yes | leader 가 확정한 실행 task 배열. `tasks[].depends_on` 은 본 배열 내 `id` 만 참조. |
| `revision` | integer | yes | 0 부터 시작. leader 가 graph 를 재계획하면 +1. |

`tasks[]` 는 §2 Task 와 동일 구조다. status 흐름은 §4 enum 을 따른다.

## 8. Role 별 `artifacts` 키

각 task 의 `artifacts` 객체에 들어가는 키. 모든 키는 optional 이지만 role 마다 표준 키가 있다.

| role | 표준 키 |
| --- | --- |
| `developer` | `branch`, `commit`, `pr`, `ci_url`, `review_verdict`, `merged_at` |
| `reviewer` | `pr`, `verdict` (`LGTM` \| `needs-changes`), `comment_url` |
| `pm` | `spec_path`, `pr` |
| `integration` | `verified_prs` (number[]), `report_path` |
| `leader` | (없음 — leader 는 task 가 아니라 scheduler. 예외적으로 `report.md` 같은 산출물을 가질 수 있음) |

표준 키 외 추가는 §11 extension 규칙.

## 9. Workflow Templates v1

role 별 step 순서를 고정한 template. task 가 spawn 될 때 template 의 step 배열을 그대로 task `workflow` 에 복사한다.

### 9.1 `developer_pr_v1` (14 step)

| 순서 | step id | owner | required | blocking |
| --- | --- | --- | --- | --- |
| 1 | `receive_instruction` | leader | yes | yes |
| 2 | `analyze` | developer | yes | yes |
| 3 | `hold_before_edit` | developer | yes | yes |
| 4 | `brief_validation` | developer | yes | no |
| 5 | `implement` | developer | yes | yes |
| 6 | `test` | developer | yes | yes |
| 7 | `commit` | developer | yes | yes |
| 8 | `hold_before_push` | developer | yes | yes |
| 9 | `push_and_pr` | developer | yes | yes |
| 10 | `ci` | developer | yes | yes |
| 11 | `ready_for_review` | developer | yes | yes |
| 12 | `review` | reviewer | yes | yes |
| 13 | `wait_merge` | developer | yes | yes |
| 14 | `shutdown` | developer | yes | yes |

순서 invariant:

- `ci` 가 `done` 이 되기 전 `ready_for_review` 진입 금지.
- `review` 가 `done` (verdict=LGTM) 이 되기 전 `wait_merge` 진입 금지.
- `wait_merge` 가 `done` (PR merged) 이 되기 전 `shutdown` 진입 금지.

### 9.2 `pm_design_v1` (11 step)

PM SKILL §1 책임 범위 + §2 direction-check 흐름 + §5 PR 4단계를 step 으로 직렬화. `direction_check` step 은 wait-reply 사용자 컨펌 차단 대기까지 포함하므로 별도 `wait_user_confirm` step 은 두지 않는다.

| 순서 | step id | owner | required | blocking |
| --- | --- | --- | --- | --- |
| 1 | `receive_instruction` | leader | yes | yes |
| 2 | `analyze` | pm | yes | yes |
| 3 | `direction_check` | pm | yes | yes |
| 4 | `finalize_artifacts` | pm | yes | yes |
| 5 | `commit` | pm | yes | yes |
| 6 | `push_and_pr` | pm | yes | yes |
| 7 | `ci` | pm | yes | yes |
| 8 | `ready_for_review` | pm | yes | yes |
| 9 | `review` | reviewer | yes | yes |
| 10 | `wait_merge` | pm | yes | yes |
| 11 | `shutdown` | pm | yes | yes |

순서 invariant (`developer_pr_v1` 와 동일 패턴):

- `direction_check` 가 `done` (사용자 컨펌 수신) 이 되기 전 `finalize_artifacts` 진입 금지.
- `ci` 가 `done` 이 되기 전 `ready_for_review` 진입 금지.
- `review` 가 `done` (verdict=LGTM) 이 되기 전 `wait_merge` 진입 금지.
- `wait_merge` 가 `done` 이 되기 전 `shutdown` 진입 금지.

### 9.3 `reviewer_pr_v1` (5 step)

단발성 PR review lifecycle. reviewer SKILL §3 정보 도구 + §2 평가 체크리스트 + §4 두 채널 답신 + §6 shutdown 을 step 으로 직렬화. `respond` step 은 GitHub PR comment + leader inbox 송신 둘 다 포함 — 본문 동일성이 invariant 이므로 송신 채널을 별도 step 으로 분리하지 않는다.

| 순서 | step id | owner | required | blocking |
| --- | --- | --- | --- | --- |
| 1 | `receive_instruction` | leader | yes | yes |
| 2 | `read_pr` | reviewer | yes | yes |
| 3 | `evaluate` | reviewer | yes | yes |
| 4 | `respond` | reviewer | yes | yes |
| 5 | `shutdown` | reviewer | yes | yes |

reviewer 는 단발성 (PR 1개 검토 후 shutdown). 추가 라운드 필요하면 leader 가 새 reviewer 워커 spawn — 같은 reviewer 가 두 번 평가하지 않는다.

### 9.4 `integration_check_v1` (placeholder)

멀티 task 통합 검증 (예: 백엔드 + 프론트엔드 PR 머지 후 contract 일치 확인). step id 후보: `receive_instruction` → `verify_dependencies_merged` → `run_integration_scenario` → `report` → `shutdown`.

### 9.5 `report_cleanup_v1` (placeholder)

Phase 2 의 보고서 / follow-up / `issue-down` 흐름. step id 후보: `collect_artifacts` → `write_report` → `notify_user` → `issue_down`.

placeholder template 은 step id 만 등록한 상태. 실제 owner / required / blocking 및 SKILL 통합은 해당 SKILL 개정 작업 (design-first-task-graph.md 작업 4·5·6·7 번) 에서 확정한다.

## 10. Versioning 규칙

### 10.1 `workflow_version` (root level)

- v1 에서는 항상 `1`.
- 다음 중 하나면 `+1` bump:
  - core 필드 (§1~§5, §6.1, §7.1) 추가/제거/타입 변경.
  - TaskStatus / StepStatus enum 추가/제거.
  - core artifact key 추가/제거.
- extension 추가 / 표준 키 추가는 bump 없음 (additive).

### 10.2 Workflow Template 버전 (`<role>_<purpose>_v<N>`)

- 네이밍: `<role>_<purpose>_v<N>` (예: `developer_pr_v1`, `pm_design_v2`).
- step 순서 / 이름 / required / blocking 이 바뀌면 `vN+1`.
- step 의 owner 변경은 `vN+1`.
- step 추가는 `vN+1` (기존 task 호환성을 위해).
- 기존 task 는 spawn 시점의 template 버전을 유지 (마이그레이션 없음). 새 task 만 새 버전 사용.

### 10.3 Extension Artifact 버전

- extension artifact 각각은 자기 schema 를 가지고 자기 versioning 함.
- core 와 무관 — extension 만의 변경은 `workflow_version` bump 안 함.

## 11. Core / Extension 경계

### 11.1 Strict Core

§1~§9 (template 의 step id 표준 포함) 의 키와 enum 값은 **strict** 다.

- 알 수 없는 최상위 키 / 알 수 없는 enum 값 → schema 검증에서 거부.
- 모든 SKILL / schema / template 이 의존하는 최소 계약.

### 11.2 Flexible Extensions

다음 위치는 extension 추가 가능:

| 위치 | extension 규칙 |
| --- | --- |
| `design.artifacts.*` | core 6 외 임의 key 허용 (`api_contract`, `db_model` 등). |
| `execution.approved_task_graph.tasks[].artifacts.*` | §8 표준 키 외 임의 key 허용. |
| `execution.approved_task_graph.tasks[].workflow[].*` | core 필드 외 추가 메타데이터 (예: `duration_ms`) 허용. |

규칙:

- extension key 는 ASCII snake_case 권장.
- 알 수 없는 extension key 는 **무시** (forward-compat). 거부하지 않는다.
- extension 이 워크플로우 진행을 차단하려면 별도 core 필드 / step 으로 승격해야 한다 — bump 필요.

### 11.3 v1 에서 이름만 등록된 Extension Artifact

다음은 design-first-task-graph.md 가 언급한 확장 artifact 후보다. v1 에서는 **이름만 placeholder 로 인정** 하고, 형식·필드 정의는 v2 이후 또는 별도 PR 에서.

- `api_contract`
- `db_model`
- `event_flow`
- `migration_plan`
- `security_review`
- `test_strategy`
- `rollout_plan`
- `observability_plan`

## 12. JSON 예시 (v1 minimum)

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
      "problem_frame": {
        "summary": "Publishing flow requires API and management UI changes"
      },
      "architecture_decision": {
        "summary": "API owns publishing state; management UI calls the new endpoint"
      },
      "implementation_brief": {
        "summary": "Implement backend endpoint and management UI action"
      },
      "risk_register": [
        {
          "risk": "Frontend/backend contract mismatch",
          "mitigation": "Add integration_check task after both PRs merge"
        }
      ],
      "open_decisions": [],
      "proposed_task_graph": {
        "tasks": [
          { "id": "backend-api", "project": "contents-hub-api-serv", "role": "developer", "type": "feat", "depends_on": [] },
          { "id": "mgmt-ui",     "project": "management-ui",         "role": "developer", "type": "feat", "depends_on": [] },
          { "id": "integration-check", "project": null, "role": "integration", "depends_on": ["backend-api", "mgmt-ui"] }
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
          "status": "running",
          "current_step": "implement",
          "workflow_template": "developer_pr_v1",
          "workflow": [
            { "id": "receive_instruction", "owner": "leader",    "status": "done",    "required": true },
            { "id": "analyze",             "owner": "developer", "status": "done",    "required": true },
            { "id": "hold_before_edit",    "owner": "developer", "status": "done",    "required": true },
            { "id": "brief_validation",    "owner": "developer", "status": "done",    "required": true, "blocking": false },
            { "id": "implement",           "owner": "developer", "status": "running", "required": true },
            { "id": "test",                "owner": "developer", "status": "pending", "required": true },
            { "id": "commit",              "owner": "developer", "status": "pending", "required": true },
            { "id": "hold_before_push",    "owner": "developer", "status": "pending", "required": true },
            { "id": "push_and_pr",         "owner": "developer", "status": "pending", "required": true },
            { "id": "ci",                  "owner": "developer", "status": "pending", "required": true },
            { "id": "ready_for_review",    "owner": "developer", "status": "pending", "required": true },
            { "id": "review",              "owner": "reviewer",  "status": "pending", "required": true },
            { "id": "wait_merge",          "owner": "developer", "status": "pending", "required": true },
            { "id": "shutdown",            "owner": "developer", "status": "pending", "required": true }
          ],
          "artifacts": {
            "branch": "feat/MP-123-publishing-api",
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

실행 task 의 canonical 위치는 `execution.approved_task_graph.tasks` 다. root 레벨 별도 `tasks` 필드는 두지 않는다 — schema / SKILL / template 이 모두 본 한 곳만 본다.

## 13. 후속 작업 연결

본 계약 확정으로 다음 작업이 같은 기준 위에서 진행 가능:

- 작업 2 (JSON Schema 초안) — 본 §1~§11 을 schema 로 옮김.
- 작업 3 (workflow template 파일) — 본 §9 의 template 을 별도 JSON 파일로.
- 작업 4~7 (leader / PM / developer / reviewer SKILL 개정) — 본 §2 / §3 / §6 / §9 를 SKILL 본문이 참조.
- 작업 9 (회귀 테스트) — 본 §1~§11 의 invariant 를 tests/scenarios 가드로.
