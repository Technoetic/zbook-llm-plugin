---
description: 로컬 AI 읽기 전용 검증 — 준비 상태 · API 인증 · 실추론 정답
---

로컬 AI 연동을 검증하라:

1. 실행: `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/llm-check.ps1"`
2. 종료코드 해석: **0=PASS** / **1**=서버 준비 안 됨 / **2**=API·인증 불일치(올바른 키 허용 + 무인증·틀린 키 거부 필요) / **3**=추론 실패(정답 `2` + `finish_reason=stop` 필요). 공개 키의 적용 여부 확인이며 프로세스 신원 보증이 아니다.
3. 실패 원인과 다음 조치만 안내하라. 이 명령은 자동 기동·재시작·BIOS 변경을 하지 않는다. 서버 미가동이면 `/llm-up`, 로딩 중이면 기다린 뒤 재검증을 안내하라. 필요하면 `<드라이브>:\LLM\logs\server.log` 마지막 줄을 확인하라. 로그 작성 전 초기 종료는 종료코드만 남을 수 있으며, 이전 버전의 `server-error.txt`는 현재 기동에서 갱신하지 않는다.
4. 결과를 3줄 이내로 보고하라: 가동 여부 · 모델명 · 왕복 확인(응답/소요 시간/토큰). 실패 시 원인 한 줄과 다음 조치를 덧붙여라.
5. 이 스택의 호출 규약(이 세션에서 로컬 AI를 쓸 때 그대로 적용하라):
   - 엔드포인트: OpenAI 호환 `http://127.0.0.1:8080/v1/chat/completions`
   - 인증 헤더: `Authorization: Bearer ns-local`
   - 직답이 필요하면 요청 본문에 `"chat_template_kwargs": {"enable_thinking": false}`를 넣어라. 이 스택에서 생략 시 추론 토큰으로 예산을 소모하고 `content`가 비는 경우가 관측됐다.
   - 구조화 추출에는 위 설정과 함께 `"temperature": 0` 및 `response_format`의 JSON 스키마를 명시한다. 서버 기본 temperature 0.8은 유지되며, thinking만 꺼서는 추출 실험의 설정과 같아지지 않는다. 스키마가 맞아도 내용은 틀릴 수 있으므로 결과를 원문과 대조한다.
   - `/v1/models`에서 확인한 모델 ID를 사용하라. GPU 메모리는 **16GB 유지**이며 필요하면 `/vgm-check`로 읽기만 한다.
6. PASS는 준비 상태·인증·단순 산술의 성공이다. 업무 추출 정확도나 요약 신뢰성, 4슬롯 장문 처리 성능으로 확대 해석하지 않는다. 9B Q8은 합성 추출 정확도, 4B Q8은 속도를 우선하는 선택이며 비교 조건과 요청 예시는 `${CLAUDE_PLUGIN_ROOT}/docs/model-policy-16gb.md`에 있다. 검증 대상 서버의 모델을 바꾸지 않는다.
