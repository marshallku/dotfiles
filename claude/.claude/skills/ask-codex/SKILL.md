---
name: ask-codex
description: 설계 결정이나 트레이드오프에 대해 codex에게 빠르게 의견 구하기. 작업 중 언제든 호출 가능한 one-shot 자문.
user-invocable: true
allowed-tools: Bash, Read
effort: low
---

## 언제 사용하나

- 설계 선택지가 갈릴 때 ("X vs Y 중 어느 쪽?")
- 본인 접근 방식에 확신이 없을 때
- 큰 결정 전에 second opinion이 필요할 때
- 특정 패턴이 관용적인지 확인하고 싶을 때

작업 중간에 가볍게 부를 수 있도록 설계된 low-effort skill입니다. `/cross-review`는 전체 리뷰, `/ask-codex`는 단발 질문.

## 워크플로우

1. 사용자의 질문, 또는 Claude 본인이 판단이 필요한 지점을 정리
2. 필요한 파일 내용을 stdin으로 파이프해서 컨텍스트 제공
3. `bash ~/.claude/scripts/codex-ask.sh "질문"` 실행
4. codex 응답을 사용자에게 전달하되, **Claude 본인의 의견도 함께** 제시

## 사용 예시

```bash
# 컨텍스트 없이 단순 질문
bash ~/.claude/scripts/codex-ask.sh "This retry logic runs in a hot path. Exponential backoff or fixed 100ms interval?"

# 관련 파일을 컨텍스트로 주입
cat src/middleware/auth.ts | bash ~/.claude/scripts/codex-ask.sh "Is this middleware order correct for CORS + auth + rate limit?"

# 여러 파일 합쳐서 주입
(cat src/a.ts; echo "---"; cat src/b.ts) | bash ~/.claude/scripts/codex-ask.sh "These two files have overlapping responsibility. Merge or split differently?"
```

## 응답 포맷 (사용자에게 보여줄 때)

```
## Codex 의견
<codex 응답 그대로, 요약하지 말 것>

## Claude 의견
<Claude 본인 분석. codex와 같으면 "동일"이라고 짧게, 다르면 이유 제시>

## 결론
<둘이 일치하면: 해당 방향으로 진행 제안>
<둘이 갈리면: 차이점 명시하고 사용자에게 판단 요청>
```

## 원칙

- **Codex는 ground truth가 아니다**. 또 다른 LLM이고 서로 다른 실수를 한다. 답변을 그대로 받아들이지 말 것.
- **두 의견이 갈리면 반드시 명시**. 한쪽을 조용히 선택해서 진행하는 건 금지.
- **질문은 구체적으로**. "이 코드 어때?" 같은 막연한 질문은 답변 품질이 낮다. "X 상황에서 A와 B 중 어느 쪽?" 형태가 best.
- **Consultation mode 활용**. AGENTS.md에 정의된 consultation mode는 hedging 없이 한 가지를 추천하도록 되어 있음. 이걸 활용해서 명확한 신호를 얻는다.
- **과도한 호출 피할 것**. 트리비얼한 결정에까지 codex를 부르면 소음만 늘고 시간만 쓴다. 본인이 80% 이상 확신하는 건은 그냥 진행.
