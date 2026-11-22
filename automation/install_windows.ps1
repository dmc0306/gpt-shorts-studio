# Run once in a normal PowerShell session from the cloned repository:
#   powershell -ExecutionPolicy Bypass -File .\automation\install_windows.ps1
# This registers two local Windows tasks. It NEVER enables uploads.
[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$homeDir = Join-Path $env:LOCALAPPDATA "ShortsStudioAutomation"
$tasks = @(
    @{ Name = "ShortsStudio-Morning"; Slot = "morning"; Hour = 6 },
    @{ Name = "ShortsStudio-Evening"; Slot = "evening"; Hour = 18 }
)

if ($Uninstall) {
    foreach ($entry in $tasks) {
        Unregister-ScheduledTask -TaskName $entry.Name -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Host "두 Windows 예약 작업만 제거했습니다. 로컬 설정과 기록은 그대로 유지합니다."
    exit 0
}

$pythonCommand = Get-Command python -ErrorAction Stop
$pythonExe = $pythonCommand.Source
& $pythonExe --version
if ($LASTEXITCODE -ne 0) {
    throw "Python 실행이 되지 않습니다. Python 3.11 이상을 설치해 주세요."
}

New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $homeDir "state") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $homeDir "logs") | Out-Null

$configFile = Join-Path $homeDir "daily_config.json"
if (-not (Test-Path $configFile)) {
    $template = Get-Content (Join-Path $PSScriptRoot "daily_config.json") -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $template.enabled = $false
    $template.publish_mode = "scheduled"
    $content = ConvertTo-Json $template -Depth 20
    [System.IO.File]::WriteAllText(
        $configFile, $content + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "로컬 설정 생성됨 (업로드 비활성화): $configFile"
} else {
    Write-Host "기존 설정 유지: $configFile"
}

$script = Join-Path $PSScriptRoot "windows_twice_daily.py"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
foreach ($entry in $tasks) {
    $arguments = ('-u "{0}" --slot {1}' -f $script, $entry.Slot)
    $action = New-ScheduledTaskAction -Execute $pythonExe -Argument $arguments -WorkingDirectory $repo
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours($entry.Hour))
    Register-ScheduledTask -TaskName $entry.Name -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "$($entry.Name): 매일 $($entry.Hour):00 (Windows 로컬 시간)"
}

Write-Host ""
Write-Host "등록 완료. 아직 enabled=false이므로 업로드하지 않습니다."
Write-Host "필수 준비: requirements.txt, FFmpeg, ffprobe, Tesseract kor+eng, YouTube Desktop OAuth, 로컬 server.env"
Write-Host "한국 표준시(Asia/Seoul)로 Windows 시간대 설정이 필요합니다."
Write-Host "사용자가 Windows에 로그인한 상태에서 예약 작업이 실행됩니다."
Write-Host "가이드: automation/WINDOWS_TWICE_DAILY_ko.md"
