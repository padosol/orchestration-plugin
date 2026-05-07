# Worker Coding Guidelines

분석 단계 시작 시 1회 Read. 4원칙을 의식적으로 적용해 diff 노이즈와 재작업을 줄인다.

원본: <https://github.com/forrestchang/andrej-karpathy-skills> (MIT)

## 1. Think Before Coding

- 가정은 **명시**한다. 불확실하면 leader 에 질문 (혼자 추측해 진행 금지).
- 해석이 여러 갈래면 **양쪽 제시** — 혼자 결정 금지.
- 더 단순한 대안이 보이면 push back.
- 모호하면 **멈춤** → 무엇이 모호한지 명명 → 질문.

## 2. Simplicity First

- 요청 이상 기능·1회용 코드 추상화·미요청 flexibility 금지.
- **불가능한** 시나리오 에러 처리 금지 (boundary 만 검증).
- 200 줄을 50 줄로 가능하면 다시 작성.
- 자문: "시니어가 보면 over-complicated 라 할까?" — Yes 면 단순화.

## 3. Surgical Changes

- 인접 코드·주석·포맷 "개선" 금지.
- 깨지지 않은 것 리팩터링 금지. 기존 스타일에 맞춤.
- 무관 dead code 는 leader 에 mention 만 — 직접 삭제 X.
- 자기 변경이 만든 unused import/변수/함수만 제거 (기존 dead code 는 그대로).
- 검증: **변경 라인 하나하나가 요청에 직접 trace 되는가?**

## 4. Goal-Driven Execution

작업을 검증 가능한 goal 로 변환:

- "validation 추가" → "invalid 입력 테스트 작성·통과"
- "버그 수정" → "재현 테스트 작성·통과"
- "X 리팩터" → "변경 전/후 모두 테스트 통과"

다단계 작업은 plan 명시 — 각 step 에 verify check:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

강한 성공 기준은 워커의 자율 loop 를 가능하게 한다. 약한 기준 ("make it work") 은 매번 leader 재질문 트리거 — 토큰 낭비.

---

## Reviewer 적용

reviewer 는 본 PR 의 변경분을 위 4원칙 기준으로 평가:

- diff 가 요청 이상 확장됐는가? (Surgical / Simplicity)
- 검증 가능 성공 기준이 commit / test 에 보이는가? (Goal-Driven)
- 가정·해석 차이가 commit message 또는 PR description 에 명시됐는가? (Think Before Coding)

차이를 발견하면 LGTM 거부보다 코멘트로 적시 — 사소한 스타일은 차단 사유 X.
