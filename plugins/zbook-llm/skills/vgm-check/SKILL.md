---
name: vgm-check
description: Use when a Windows HP ZBook user asks to check GPU memory, the 16GB BIOS policy, installed versus OS-visible RAM, or invokes vgm-check. GPU 메모리·RAM 상태 확인 요청에 사용한다.
---

# GPU 메모리 16GB 확인

HP BIOS 설정과 RAM 수치를 읽어 **GPU 메모리 16GB 유지 정책**과 비교한다. BIOS 값을 쓰거나 재부팅하지 않는다.

이 스킬을 불러온 **실제 `SKILL.md` 절대 경로의 부모 디렉터리**를 `$skillDir`로 지정한다. 현재 작업 폴더나 특정 사용자 설치 경로를 기준으로 삼지 않는다. 같은 기준으로 [16GB 확인 기준](../../docs/vgm-16gb.md)을 읽고, Windows에서 [공유 스크립트](../../scripts/vgm-check.ps1)를 절대 경로로 확인한 뒤 실행한다. 파일이 없거나 Windows가 아니면 실행 불가 사유를 보고한다.

```powershell
$vgmScript = (Resolve-Path -LiteralPath (Join-Path $skillDir '../../scripts/vgm-check.ps1') -ErrorAction Stop).Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $vgmScript
$vgmExit = $LASTEXITCODE
```

| 종료코드 | 판정과 조치 |
|---|---|
| 0 | BIOS 16GB와 RAM 조회 확인; 현재 설정 유지 |
| 1 | 16GB 정책 불일치; 관측값을 보고하고 자동 수정하지 않음 |
| 2 | BIOS 또는 RAM 확인 불가; 조회 오류를 그대로 보고 |

3줄 이내로 **BIOS 설정값**, **설치 RAM**, **Windows 인식 총 RAM**을 구분하고 종료코드를 함께 보고한다. 실패를 성공으로 바꾸거나 과거 장비의 수치를 현재 측정값으로 쓰지 않는다.

- 설치 RAM은 `Win32_PhysicalMemory.Capacity`의 합이다. `Win32_ComputerSystem.TotalPhysicalMemory`를 설치 용량으로 쓰지 않는다.
- Windows 인식 총 RAM은 `Win32_OperatingSystem.TotalVisibleMemorySize`이며, 현재 여유 RAM과 다르다.
- BIOS 조회가 실패하면 RAM 차이로 설정값을 추정하지 않는다. BIOS 설정 확인은 GPU 드라이버의 현재 할당량 측정이 아니다. RAM 차이만으로 정확한 GPU 예약량을 확정하지 않는다.
- 32GB 전환을 권장하지 않는다. 16GB에서 35B 모델의 적재·성능은 미측정이다.
