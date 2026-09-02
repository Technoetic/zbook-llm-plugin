---
description: 로컬 AI(llama-server) 연동 3단계 검증 — 생존 · 신원 · 실추론 왕복
---

로컬 AI 연동을 검증하라:

1. 실행: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/llm-check.ps1"`
2. 종료코드 해석: **0=PASS**(연동 정상) / **1**=서버 미가동 / **2**=포트 8080 응답자가 llama-server 규약(키 인증 + `/v1/models`)에 응하지 않음 / **3**=추론 실패(빈 응답이면 thinking 미해제 의심).
3. 종료코드 **1**이면 `/llm-up`으로 기동하고(모델 로딩에 수십 초 소요), 끝나면 1번을 재실행하라. 재실행도 1이면 `<드라이브>:\LLM\logs\server.log`와 `server-error.txt`(기동 직후 죽은 경우는 이쪽에만 남는다) 마지막 줄을 확인해 보고하라. 설치 폴더(`<드라이브>:\LLM`) 자체가 없으면 로컬 AI 설치 패키지(「2. 설치.bat」)가 선행이다.
4. 결과를 3줄 이내로 보고하라: 가동 여부 · 모델명 · 왕복 확인(응답/소요 시간/토큰). 실패 시 원인 한 줄과 다음 조치를 덧붙여라.
5. 이 스택의 호출 규약(이 세션에서 로컬 AI를 쓸 때 그대로 적용하라):
   - 엔드포인트: OpenAI 호환 `http://127.0.0.1:8080/v1/chat/completions`
   - 인증 헤더: `Authorization: Bearer ns-local`
   - ⚠️ Qwen3 계열은 thinking 모델이다 — 직답이 필요하면 요청 본문에 `"chat_template_kwargs": {"enable_thinking": false}`를 반드시 넣어라. 누락하면 추론에만 토큰을 소모해 `content`가 빈 채 온다(`/no_think` 태그는 무효).
