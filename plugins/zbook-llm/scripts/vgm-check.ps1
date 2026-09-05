<#
  vgm-check.ps1 - Read-only HP BIOS 16 GB graphics-memory policy check.

  Installed RAM comes from Win32_PhysicalMemory.Capacity, not the OS-usable
  Win32_ComputerSystem.TotalPhysicalMemory value. OS-visible RAM is reported
  separately; neither figure proves the driver's current GPU allocation.

  Exit codes: 0 = configured 16 GB / 1 = policy mismatch / 2 = cannot confirm.
  This script only reads CIM instances. It never changes BIOS or restarts.
#>
$ErrorActionPreference = 'Stop'

function Out-Line([string]$Text) { Write-Output "[vgm-check] $Text" }

try {
    $settings = @(Get-CimInstance -Namespace 'root\HP\InstrumentedBIOS' -ClassName HP_BIOSEnumeration -ErrorAction Stop |
        Where-Object { $_.Name -eq 'Dedicated Graphics Memory' })
    if ($settings.Count -ne 1 -or [string]::IsNullOrWhiteSpace($settings[0].CurrentValue)) {
        throw 'Dedicated Graphics Memory setting is missing, empty, or ambiguous.'
    }
    $configured = $settings[0].CurrentValue.Trim()
    Out-Line "Configured GPU memory (HP BIOS): $configured"
} catch {
    Out-Line "FAIL(2) cannot confirm 16 GB policy: HP BIOS query failed. $($_.Exception.Message)"
    Out-Line 'Settings unchanged. Report the query error; do not infer BIOS configuration from RAM totals.'
    exit 2
}

try {
    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
    if ($modules.Count -eq 0) { throw 'Installed RAM module capacities are unavailable.' }
    [UInt64]$installedBytes = 0
    foreach ($module in $modules) {
        if ($null -eq $module.Capacity -or [double]$module.Capacity -le 0) {
            throw 'Installed RAM module capacity is missing or invalid.'
        }
        $installedBytes += [UInt64]$module.Capacity
    }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ($null -eq $os.TotalVisibleMemorySize -or [double]$os.TotalVisibleMemorySize -le 0) {
        throw 'OS-visible RAM is unavailable.'
    }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $installedGiB = ($installedBytes / 1GB).ToString('F2', $culture)
    # TotalVisibleMemorySize is in KiB, whereas physical module capacities are bytes.
    $visibleGiB = ([double]$os.TotalVisibleMemorySize / 1MB).ToString('F2', $culture)
    Out-Line "Model: $($system.Model)"
    Out-Line "Installed RAM (DIMM capacity sum): $installedGiB GiB"
    Out-Line "OS-visible RAM (total, not currently free): $visibleGiB GiB"
} catch {
    Out-Line "FAIL(2) cannot confirm memory inventory. $($_.Exception.Message)"
    Out-Line 'Settings unchanged.'
    exit 2
}

Out-Line 'GPU runtime allocation is not measured; the RAM difference is not an exact GPU reservation measurement.'
if ($configured -notmatch '^16\s*GB$') {
    Out-Line "FAIL(1) GPU memory policy mismatch: expected 16 GB, found $configured. Settings unchanged."
    exit 1
}

Out-Line 'PASS - HP BIOS reports 16 GB; keep the current setting. Settings unchanged.'
exit 0
