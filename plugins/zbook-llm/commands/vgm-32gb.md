---
description: 폐기된 32GB 변경 명령의 호환 별칭 — /vgm-check로 16GB 유지 여부만 읽기 전용 확인
---

이 명령은 기존 호출을 위한 **읽기 전용 호환 별칭**이다. GPU 메모리 운영 정책은 **16GB 유지**다.

1. 사용자에게 `/vgm-32gb`의 변경 기능은 폐기되었으며 `/vgm-check`로 확인한다고 짧게 알린다.
2. `${CLAUDE_PLUGIN_ROOT}/commands/vgm-check.md`와 `${CLAUDE_PLUGIN_ROOT}/docs/vgm-16gb.md`를 읽고 동일한 검사를 실행한다.
   `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/vgm-check.ps1"`
3. 종료코드 **0=BIOS 16GB 확인**, **1=16GB 정책 불일치**, **2=확인 불가**를 그대로 보고한다. RAM 수치는 설치 용량과 Windows 인식 총량을 구분한다.
4. BIOS 변경 명령·BIOS 화면에서의 변경 절차·재부팅·32GB 전환 권장을 제공하거나 실행하지 않는다. 과거 32GB 절차는 현재 작업 지침으로 사용하지 않는다.
