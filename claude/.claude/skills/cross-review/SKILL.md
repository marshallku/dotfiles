---
name: cross-review
description: 구현 주체와 반대 모델로 교차 리뷰한다 (Claude 작성→Codex, Codex 작성→Claude). 작업 단위 승인 재사용, 근거 검증, 수정분 재리뷰, 최대 3라운드.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Edit
effort: high
---

## 호출 시점

관련 테스트를 통과한 구현 작업을 마무리하기 직전, 커밋 전에 한 번 실행한다.
같은 승인 스냅샷은 스테이징·커밋 후에도 재사용한다. 새로운 구현 변경은 새 작업 단위다.
문서만 고친 작업은 생략할 수 있지만 에이전트 지침·실행 설정은 구현 변경으로 취급한다.
작은 인증·권한·설정 변경도 파일 수나 줄 수로 생략하지 않는다.

## 첫 리뷰

구현 주체에 따라 리뷰어를 **명시적으로** 선택한다:

- Claude가 구현 → `REVIEWER=codex`
- Codex가 구현 → `REVIEWER=claude`

`~/.claude/state/codex-delegate-pending-<repo-hash>`가 있으면 부모와 위임자의 코드가
섞일 수 있으므로 **Claude와 Codex 양쪽**을 같은 전체 스냅샷으로 리뷰시킨다.
위임 작업이 끝난 뒤 `--reviewer claude`, `--reviewer codex`를 각각 실행한다.
한쪽 APPROVED만으로는 커밋 게이트가 열리지 않으며 기준점도 전진하지 않는다.
수정으로 스냅샷이 바뀌면 양쪽 모두 새 내용에 대한 승인이 필요하다.

모든 호출에 `--reviewer "$REVIEWER"`를 전달한다. `codex-review.sh`는 호환성을 위해
이름만 유지한 공통 엔진이다. 기본값 codex에 의존하지 않는다. 선택한 CLI 실행·인증에
실패하면 오류를 보고하고 멈춘다. 같은 모델 리뷰로 조용히 대체하지 않는다.
Claude 리뷰어는 Read/Glob/Grep만 제공하고 Bash·Edit·Write·MCP·훅·다른 스킬은 로드하지 않는다.
관련 파일은 직접 읽지만 테스트 실행은 구현 주체가 맡고 리뷰어는 그 결과를 검증한다.

현재 저장소와 세션 ID를 확인한다. SessionStart가 시작 tree를 저장하며,
승인 후에는 승인 tree가 다음 작업의 기준점이 된다. 세션 기준점이 없으면
작업 이력에서 시작 커밋을 확인하여 `--base <commit>`을 명시한다.
이미 커밋한 변경이 있을 수 있으므로 임의로 HEAD를 기준점으로 삼지 않는다.
`--session`은 해당 저장소 전체의 기준점 이후 변경을 검토한다.
다른 작업의 변경이 섞여 있으면 별도 worktree로 분리하거나 컨텍스트에 정확히 설명한다.

```bash
. "$HOME/.claude/hooks/_lib.sh"
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_HASH=$(repo_hash "$REPO_ROOT")
INTENT_MARKER="$HOME/.claude/state/intent-active-${SESSION_ID}-${REPO_HASH}.path"
```

활성 intent가 있으면 `--intent-file`로 전달한다. 없으면 원래 사용자 요청,
실제 구현, 의도적 제외·트레이드오프를 150단어 이하의 brief 파일에 작성한다.
미구현 사항을 숨기지 않는다. 임시 파일은 저장소 밖에 둔다.

```bash
bash ~/.claude/scripts/codex-review.sh --reviewer "$REVIEWER" --session "$SESSION_ID" --intent-file "$INTENT_FILE"
# intent가 없는 경우
bash ~/.claude/scripts/codex-review.sh --reviewer "$REVIEWER" --session "$SESSION_ID" --context-file "$BRIEF"
```

Bash 호출은 foreground, `timeout: 600000`을 사용한다. Round 1에는 `--resume`을 붙이지 않는다.
`--files`와 `--focus`는 부분 검토이며 커밋을 위한 전체 승인을 발급하지 않는다.

## 지적 처리와 재리뷰

- exit 0: APPROVED. 같은 코드로 커밋할 때 추가 리뷰하지 않는다.
- exit 1: REVISE. 각 CRITICAL을 원래 요청·관련 코드·재현 결과로 검증한다.
- exit 2: 실행 오류·변경 경합·라운드 한도. 원인을 보고하며 승인으로 취급하지 않는다.

각 지적을 `수용 / 근거 있는 반박 / 사용자 판단 필요`로 분류한다.
수용한 지적은 최소 수정하고 관련 테스트를 실행한다. INTENT-MISMATCH도 먼저
요청과 소유권을 확인한다. 태그만 보고 기능을 추가하거나 타 작업의 변경을 revert하지 않는다.
스타일·네이밍·추후 개선·커버리지 요구는 기존 AGENTS.md 억제 규칙을 따른다.

저장소 밖 response 파일에 지적 ID, 처리 판단, 코드 근거, 수정 경로, 실행한 테스트 결과를 기록한다.
원래 intent/brief는 유지하고, 같은 명령에 다음 인자를 추가한다:

```bash
bash ~/.claude/scripts/codex-review.sh --reviewer "$REVIEWER" --session "$SESSION_ID" --context-file "$BRIEF" \
    --resume --response-file "$RESPONSES"
```

재리뷰는 직전 스냅샷 이후 diff와 response만 전달한다. 관련 호출자 검토는 허용한다.
컨텍스트가 달라졌거나 thread가 없으면 전체 리뷰로 전환한다.
같은 미완료 작업을 다시 호출하면 자동으로 resume하며, 최대 3라운드로 제한한다. 한도를 우회하려고 fresh로 다시 시작하지 않는다.
같은 CRITICAL이 수정·반박 후에도 반복되면 자동 수정을 중단하고 양쪽 근거를 사용자에게 제시한다.

## 승인과 보고

승인은 리뷰어·저장소·세션·전체 스냅샷에 묶인다. 다른 모델의 재시도 스레드는 재사용하지 않는다.
위임 작업에서는 동일 스냅샷에 대한 양쪽 승인을 합쳐 전체 승인을 완성한다.
이미 승인한 후 리뷰어를 바꾸면 이전 승인이 기준점을 전진시켰으므로 알려진 시작 커밋을
`--base`로 명시해 전체 작업을 다시 리뷰한다. 빈 diff로 승인을 바꿔치기하지 않는다.
Bash·포매터·외부 도구 변경도 승인을 무효화한다.
리뷰 당시 코드와 다른 중간 버전만 부분 스테이징하면 게이트가 차단한다.
`touch reviewed-*`는 승인으로 인정하지 않는다. 전역 opt-out은 기존
`~/.claude/state/auto-review-disabled`이며 사용자가 요청한 경우에만 사용한다.

사용자 언어로 최종 판정, 라운드 수, 수용한 수정, 테스트 결과, 남은 판단 사항만 간결하게 보고한다.
사용량은 Codex의 `~/.claude/state/codex-usage.jsonl`, Claude의
`~/.claude/state/claude-review-usage.jsonl`에 각 CLI가 제공한 정보로 기록된다.
`usage_reported=false`인 호출의 0은 사용량 미확인이며 무료 실행을 뜻하지 않는다.
실제 모델을 CLI가 알려주지 않으면 `actual_model=null`로 남긴다.
