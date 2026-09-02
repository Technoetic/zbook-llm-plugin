# ZBook Ultra G1a — 그래픽 메모리 32GB 설정 절차 (검증본)

> 같은 기종(ZBook Ultra G1a)에서 **2026-09-01 직접 실행해 성공(`Return : 0`)을 확인한 절차**를 그대로 옮긴 것이다.
> 추측이 없고, 되돌리기도 명령 한 줄이다. 소요: 명령 1분 + 재부팅.
>
> **큰 AI 모델(20GB급)을 쓸 때만 필요하다.** 기본 모델(4GB급)만 쓸 거면 하지 않아도 된다.

## 왜 하는가

이 노트북은 CPU·GPU가 **64GB 메모리를 나눠 쓰는 구조**(통합 메모리)다. 공장 기본값은 그중 **16GB만 GPU 몫**이다. 쓸 만한 큰 모델이 17~21GB라 16GB 칸에 물리적으로 안 들어간다 — 넘치면 느린 경로로 처리되거나 로드에 실패한다. **32GB로 올리면 그 벽이 사라진다.** 하드웨어 변경이 아니라 원래 있던 메모리의 배분 변경이라, 되돌리기도 명령 한 줄이다.

> ⚠️ 이 설정이 모든 걸 빠르게 만들지는 않는다. 대역폭이 성능을 지배해 dense 대형 모델은 32GB로 올려도 초당 10토큰 안팎이 천장이다. 값어치는 **큰 모델이 일단 들어가게 되는 것**과 **MoE 모델이 제 속도를 내는 것**이다. 실측(2026-09-01, 검증 기계): 22.1GB MoE 모델(Qwen3.6-35B-A3B)이 초당 51토큰(GPU 메모리 22.9GB 사용 — 16GB 설정으로는 정상 동작 기대 불가).

## 1단계 — 시작 전 확인 (읽기 전용, 관리자 불필요)

```powershell
$g = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSEnumeration |
     Where-Object Name -eq 'Dedicated Graphics Memory'
"기종      : " + (Get-CimInstance Win32_ComputerSystem).Model
"현재 설정 : " + $g.CurrentValue
"선택 가능 : " + ($g.PossibleValues -join ' / ')
"읽기전용  : " + $g.IsReadOnly + "   (0이어야 함)"
"BIOS 암호 : " + ((Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSPassword |
                   Where-Object Name -eq 'Setup Password').IsSet) + "   (0이면 암호 없음)"
```

기대 출력(검증 기계 기준): 기종 `HP ZBook Ultra G1a 14 inch Mobile Workstation PC` / 현재 `16 GB` / 선택 가능 `512 MB / 4 GB / 8 GB / 16 GB / 32 GB / 48 GB` / 읽기전용 `0` / 암호 `0`.

| 다르게 나오면 | 뜻 | 어떻게 |
|---|---|---|
| 명령 자체가 에러 | HP 상용 BIOS 도구가 없는 기종 | **방법 B**(BIOS 화면)로 |
| `현재 설정 : 32 GB` | 이미 돼 있음 | 끝. 재부팅만 |
| `읽기전용 : 1` | 명령으로 못 바꿈 | **방법 B** |
| `BIOS 암호 : 1` | 암호가 걸려 있음 | 아래 **암호가 있을 때** |

## 2단계 — 방법 A: 명령 한 줄 (권장, ⚠️관리자 터미널 필수)

```powershell
$i = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSettingInterface
Invoke-CimMethod -InputObject $i -MethodName SetBIOSSetting -Arguments @{
    Name     = 'Dedicated Graphics Memory'
    Value    = '32 GB'
    Password = '<utf-16/>'
}
```

성공 = `Return : 0`. 다른 숫자면:

| Return | 뜻 | 대응 |
|---|---|---|
| 0 | 성공 | 재부팅으로 |
| 1 | 지원 안 함 | 방법 B |
| 2 | 원인 불명 실패 | 1회 재시도 → 같으면 방법 B |
| 3 | 시간 초과 | 다른 HP 관리 도구를 닫고 재시도 |
| 4 | 실패(대개 암호 형식) | `Password = ''`로 재시도 |
| 5 | 잘못된 값 | `'32 GB'`의 띄어쓰기·대문자 GB 확인 |
| 6 | 접근 거부 | 관리자 터미널이 아님 — 관리자로 다시 |

표에 없는 숫자는 임의 재시도하지 말고 그 숫자를 그대로 보고한다.

즉시 확인(재부팅 전 예약값):

```powershell
(Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSEnumeration |
 Where-Object Name -eq 'Dedicated Graphics Memory').CurrentValue
```

## 방법 B — BIOS 화면 (A가 안 될 때만)

재시작 → HP 로고에서 `ESC` 연타 → `F10`(BIOS Setup) → **Advanced → Built-In Device Options** → **Dedicated Graphics Memory**(또는 `Video memory size` / `UMA Frame Buffer Size`) → **32 GB** → `F10` 저장.

## 3단계 — 재부팅 후 검증

```powershell
"BIOS 설정값      : " + (Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSEnumeration |
                          Where-Object Name -eq 'Dedicated Graphics Memory').CurrentValue
$base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$vram = Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
          (Get-ItemProperty $_.PSPath -EA SilentlyContinue).'HardwareInformation.qwMemorySize'
        } | Where-Object { $_ -gt 0 } | Sort-Object -Descending | Select-Object -First 1
if ($vram) { "실제 적용 VRAM   : {0:N0} GB" -f ($vram/1GB) }
else       { "실제 적용 VRAM   : 읽지 못함 — 실패가 아니라 확인 불가. 아래 두 줄로 판단" }
$ram = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1MB
"Windows 가용 RAM : {0:N2} GB" -f $ram
"이 기계 총 메모리 : {0:N0} GB" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)
```

완료 기준(64GB 기계): BIOS `32 GB` · VRAM `32 GB`(또는 읽기 불가) · 가용 RAM 약 31.8GB · 총 64GB.
💡 가용 RAM이 ~48 → ~32GB로 주는 것이 **정상**이다(사라진 게 아니라 GPU로 옮겨간 것). VRAM 줄을 못 읽어도 실패가 아니다 — BIOS 값 + 가용 RAM 감소 두 가지로 판단한다. ⚠️총 메모리가 64GB가 아니면(128GB 모델 등) 이 문서의 기대 숫자가 달라진다 — 값을 그대로 따르지 말고 보고한다.

## 🚫 48GB를 고르지 말 것

48GB로 몰면 Windows에 16GB만 남아 야간 작업이 메모리 부족으로 죽는다 — **32GB가 성능과 안정성의 균형점**이다. (64GB 기계 상한이 48GB이고, 인터넷의 "96GB"는 전부 128GB 모델 얘기다.)

## 되돌리기

같은 명령에서 `Value='16 GB'`로 바꾸고 재부팅.

## 암호가 있을 때

`BIOS 암호 : 1`이면 `Password = '<utf-16/>' + '실제암호'` 형식으로. 암호를 모르면 방법 A·B 모두 불가 — 관리 담당에게 문의.

## 확인된 근거

- 같은 기종에서 2026-09-01 실행, `Return : 0` 성공. 설정 속성 `IsReadOnly = 0`, `RequiresPhysicalPresence = 0` → 명령 변경 가능, BIOS 화면 진입 불필요.
- 선택지 상한 48GB는 AMD의 64GB 구성 상한(가용 메모리 75%) 규정과 일치.
