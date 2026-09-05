---
description: GPU 메모리 16GB 유지 확인 — HP BIOS 설정·설치 RAM·Windows 인식 RAM을 읽기 전용으로 검사
---

현재 GPU 메모리가 **16GB 유지 정책**과 일치하는지 확인하라.

1. `${CLAUDE_PLUGIN_ROOT}/docs/vgm-16gb.md`를 먼저 읽고, 다음 검사를 실행하라.
   `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/vgm-check.ps1"`
2. 종료코드는 **0=BIOS 16GB 확인**, **1=16GB 정책 불일치**, **2=확인 불가**다. 실패를 성공으로 바꾸어 보고하지 마라. 확인 불가일 때는 해당 조회 오류를 그대로 보고하라.
3. 결과는 BIOS 설정값·설치 RAM·Windows 인식 총 RAM을 구분해 3줄 이내로 보고하라. 설치 RAM은 `Win32_PhysicalMemory.Capacity`의 합이며, `Win32_ComputerSystem.TotalPhysicalMemory`를 설치 용량으로 사용하지 마라.
4. BIOS 값을 쓰거나 재부팅하지 마라. 32GB 설정을 권장하지 마라. 불일치여도 자동 수정 없이 관측값과 종료코드만 보고하라.
5. BIOS 설정 확인은 GPU 드라이버의 실제 예약량 측정과 다르다. 설치 RAM과 Windows 인식 RAM의 차이만으로 실제 GPU 예약량을 확정하지 마라. 16GB에서 35B 모델의 동작 여부와 속도는 미측정이다.
