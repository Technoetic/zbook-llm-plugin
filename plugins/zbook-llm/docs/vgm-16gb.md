# ZBook Ultra G1a — GPU 메모리 16GB 유지 확인

운영 정책은 **GPU 메모리 16GB 유지**다. `vgm-check` 스킬은 HP BIOS 설정과 RAM 수치를 읽기 전용으로 확인한다. BIOS 변경이나 재부팅은 수행하지 않는다. `vgm-32gb` 호환 별칭은 0.5.0에서 제거됐다.

2026-09-05 확인된 기계는 `HP ZBook Ultra G1a 14 inch Mobile Workstation PC`이며, BIOS `Dedicated Graphics Memory` 값은 `16 GB`, 설치 RAM은 `64.00 GiB`, Windows 인식 총 RAM은 약 `47.78 GiB`다. 다른 기계에서는 실제 조회 결과를 보고하며 이 RAM 수치를 강제하지 않는다.

## 실행과 판정

Claude Code에서는 `/zbook-llm:vgm-check`, Codex에서는 `$zbook-llm:vgm-check`를 사용한다. 스크립트를 직접 실행할 때는 설치 경로를 지정한다.

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<플러그인 설치 폴더>\scripts\vgm-check.ps1"
```

| 종료코드 | 의미 | 다음 조치 |
|---|---|---|
| 0 | HP BIOS가 `16 GB`를 보고하고 RAM 수치를 읽음 | 현재 설정 유지 |
| 1 | BIOS 설정이 16GB 정책과 다름 | 관측값과 불일치를 보고; 자동 변경 없음 |
| 2 | HP BIOS 네임스페이스·설정 또는 RAM 조회 실패 | 확인 불가와 조회 오류 보고; 성공 판정 금지 |

HP BIOS 네임스페이스가 없거나 접근할 수 없으면 RAM 수치로 BIOS 값을 추정하지 않는다. 설정이 다르게 나와도 이 검사에서 BIOS 값을 쓰거나 재부팅하지 않는다.

## 수치의 의미

| 표시 | 조회 근거 | 해석 |
|---|---|---|
| Configured GPU memory | `root\HP\InstrumentedBIOS`의 `HP_BIOSEnumeration`, `Dedicated Graphics Memory.CurrentValue` | BIOS가 보고하는 설정값 |
| Installed RAM | 모든 `Win32_PhysicalMemory.Capacity`의 합, byte → GiB | 물리적으로 설치된 RAM 용량 |
| OS-visible RAM | `Win32_OperatingSystem.TotalVisibleMemorySize`, KiB → GiB | Windows가 인식하는 총 RAM; 현재 남은 여유 RAM과 다름 |

`Win32_ComputerSystem.TotalPhysicalMemory`를 설치 RAM으로 사용하지 않는다. 이 기계에서는 하드웨어 예약 이후 OS가 사용할 수 있는 용량을 보고하므로 실제 설치된 64GiB와 다르다. 설치 RAM과 OS 인식 RAM의 차이에는 GPU 이외의 하드웨어 예약도 포함될 수 있다. 차이만으로 GPU의 정확한 예약량을 계산하거나 실제 적용을 확정할 수 없다.

이 검사는 BIOS 설정 확인이며 GPU 드라이버의 현재 할당량을 측정하지 않는다. BIOS에 변경 예약이 남아 있는지 또는 드라이버에 반영되었는지도 이 결과만으로 확정하지 않는다.

## 모델 운영 범위

현재 4B·9B 모델의 운영 기준은 16GB다. 선택 기준과 측정 조건은 [모델 운영 정책](model-policy-16gb.md)을 따른다. 기존 35B-A3B 모델 측정은 **32GB 설정에서만** 수행되었다. **16GB에서 35B의 실행 여부와 처리 속도는 미측정**이며, 과거 결과를 근거로 16GB에서는 실행 불가라거나 특정 토큰 속도가 나온다고 단정하지 않는다.

16GB 조건에서 큰 모델을 평가하려면 모델·양자화·컨텍스트·GPU 오프로딩 조건을 기록한 별도 측정이 필요하다. 현재 설정을 유지하며, 32GB 전환을 이 플러그인의 권장 해결책으로 삼지 않는다.
