# zbook-tools — ZBook 로컬 AI 플러그인 마켓플레이스

같은 기종 ZBook에 구축한 **로컬 AI 스택(llama.cpp Vulkan + Qwen GGUF, `<드라이브>:\LLM`)**을 Claude Code에서 바로 다루는 플러그인 모음입니다.

## 플러그인

### zbook-llm

| 커맨드 | 하는 일 |
|---|---|
| `/llm-check` | 연동 3단계 검증 — ①서버 생존(`/health`) ②신원(포트 8080 응답자가 llama-server 규약대로 키 인증 + `/v1/models`에 응하는지) ③**실추론 왕복**(thinking 해제 직답까지 확인해야 PASS) |
| `/llm-up` | 서버 기동 — 로컬 고정 디스크에서 `<드라이브>:\LLM`을 자동 탐색, 이미 켜져 있으면 그대로 통과(멱등), 인터넷 불필요 |
| `/vgm-32gb` | 그래픽 메모리 32GB 설정(큰 모델 20GB급 쓸 때만) — 확인→사용자 동의→적용→재부팅 후 검증. BIOS 화면 진입 없이 명령으로, 🚫48GB 금지 내장 |

## 설치 (Claude Code)

```
/plugin marketplace add <GitHub계정>/zbook-llm-plugin
/plugin install zbook-llm@zbook-tools
```

설치 후 Claude Code를 재시작하면 `/llm-check` · `/llm-up` · `/vgm-32gb`가 생깁니다.
같은 이름의 커맨드를 이미 갖고 있다면 `/zbook-llm:llm-check`처럼 플러그인 이름을 붙여 부르면 됩니다.

> 로컬 폴더로도 설치할 수 있습니다: `/plugin marketplace add <이 폴더 경로>`
> (이 방식은 폴더를 지우면 플러그인도 깨지므로, 지워지지 않을 위치에 두세요.)

## 전제 조건

- **로컬 AI 설치 패키지**(별도 전달)로 스택이 먼저 깔려 있어야 합니다 — `<드라이브>:\LLM`에 llama-server 런타임과 모델(GGUF), 포트 `8080`, 키 `ns-local` 규약.
- 스택이 없으면 `/llm-check`는 종료코드 1(서버 미가동), `/llm-up`은 `[중단] 설치 폴더를 찾지 못했다`로 안내합니다 — 설치 패키지의 「2. 설치.bat」이 선행입니다.

## 문제가 생기면

- `/llm-check`의 종료코드: `0` PASS / `1` 서버 미가동 → `/llm-up` / `2` 포트 점유자 신원 불일치 / `3` 추론 실패(빈 응답 = thinking 미해제 의심)
- 서버 로그: `<드라이브>:\LLM\logs\server.log` · 기동 직후 죽은 경우는 `server-error.txt`(이쪽에만 남습니다)
- 해결이 안 되면 화면 출력을 그대로 복사해 배포자에게 보내 주세요.
