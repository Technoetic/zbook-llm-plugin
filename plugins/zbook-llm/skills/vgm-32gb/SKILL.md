---
name: vgm-32gb
description: Use when a user invokes vgm-32gb or refers to the retired Windows ZBook 32GB graphics-memory command. 이전 vgm-32gb 명령 호출에 사용한다.
---

# 이전 VGM 명령 호환

`vgm-32gb`는 **읽기 전용 호환 별칭**이다. 먼저 변경 기능은 폐기되었으며 `vgm-check` 스킬과 같은 **16GB 유지 확인**을 수행한다고 짧게 알린다.

이 스킬을 불러온 **실제 `SKILL.md` 절대 경로의 부모 디렉터리**를 `$skillDir`로 지정한다. 현재 작업 폴더나 특정 사용자 설치 경로를 기준으로 삼지 않는다. 같은 기준으로 [16GB 확인 기준](../../docs/vgm-16gb.md)을 읽고, Windows에서 [공유 검증 스크립트](../../scripts/vgm-check.ps1)만 절대 경로로 확인하여 실행한다. 파일이 없거나 Windows가 아니면 실행 불가 사유를 보고한다.

```powershell
$vgmScript = (Resolve-Path -LiteralPath (Join-Path $skillDir '../../scripts/vgm-check.ps1') -ErrorAction Stop).Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $vgmScript
$vgmExit = $LASTEXITCODE
```

| 종료코드 | 판정 |
|---|---|
| 0 | BIOS 16GB와 RAM 조회 확인; 현재 설정 유지 |
| 1 | 16GB 정책 불일치; 관측값을 보고하고 자동 수정하지 않음 |
| 2 | BIOS 또는 RAM 확인 불가; 조회 오류를 그대로 보고 |

3줄 이내로 **BIOS 설정값**, **설치 RAM**, **Windows 인식 총 RAM**과 종료코드를 구분해 보고한다. 설치 RAM은 `Win32_PhysicalMemory.Capacity`의 합이며 `Win32_ComputerSystem.TotalPhysicalMemory`로 대체하지 않는다. Windows 인식 총 RAM은 현재 여유 RAM과 다르다. RAM 차이로 BIOS 설정이나 정확한 GPU 예약량을 확정하지 않는다. 이 검사는 GPU 드라이버의 현재 할당량 측정이 아니다.

BIOS 변경 명령·BIOS 화면 변경 절차·재부팅·32GB 전환 권장을 제공하거나 실행하지 않는다. 과거 32GB 문서를 현재 실행 지침으로 사용하지 않는다. 불일치나 조회 실패여도 설정을 바꾸지 않으며, 16GB에서 35B 모델의 적재·성능은 미측정이다.
