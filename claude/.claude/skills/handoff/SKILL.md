---
name: handoff
description: 세션 컨텍스트를 다음 세션으로 전달
user-invocable: true
allowed-tools: Bash,Read,Grep,Glob,Write
effort: medium
---

## 워크플로우

1. 현재 세션에서 작업한 내용 요약:
   - 어떤 파일을 변경했는가 (`git diff --name-only`)
   - 무엇을 달성했는가
   - 어떤 문제가 남아있는가
   - 다음 단계는 무엇인가

2. 핸드오프 파일 생성:
   ```
   ~/.claude/handoff/<date>-<topic>.md
   ```

3. 파일 내용:
   ```markdown
   # Handoff: <topic>
   Date: <YYYY-MM-DD HH:MM>
   Branch: <current branch>

   ## 완료
   - ...

   ## 미완료
   - ...

   ## 다음 단계
   - ...

   ## 주의사항
   - ...

   ## 관련 파일
   - ...
   ```

4. 다음 세션에서 `claude --resume` 또는 이 파일을 참조하여 컨텍스트 복원
