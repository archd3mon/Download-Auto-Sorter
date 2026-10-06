#Requires -Version 5.1
<#
.SYNOPSIS
    Registers a Windows Scheduled Task for Download Organizer.

.DESCRIPTION
    Creates a recurring Windows Scheduled Task running under the current user's
    credentials (no administrator rights needed) that runs Sort-Downloads.ps1
    periodically (default: every 5 minutes).

.PARAMETER TaskName
    Name of the scheduled task. Defaults to "DownloadOrganizer".

.PARAMETER IntervalMinutes
    How often (in minutes) to run the organizer. Defaults to 5.

.PARAMETER ScriptPath
    Path to Sort-Downloads.ps1. Defaults to the sibling script in the same directory.

.PARAMETER MinAgeSeconds
    Minimum age (in seconds) before moving files. Defaults to 120 (2 minutes).

.PARAMETER RunNow
    If set, triggers the task immediately after registration to verify.

.EXAMPLE
    .\Register-Task.ps1
    Registers the task to run every 5 minutes under the current user.

.EXAMPLE
    .\Register-Task.ps1 -IntervalMinutes 10
    Registers the task to run every 10 minutes.
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'DownloadOrganizer',
    [int]$IntervalMinutes = 5,
    [string]$ScriptPath = '',
    [int]$MinAgeSeconds = 120,
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = Join-Path $PSScriptRoot 'Sort-Downloads.ps1'
}

# Validate script path
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Target script not found at '$ScriptPath'."
}

$fullScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
Write-Host "Configuring Scheduled Task '$TaskName'..." -ForegroundColor Cyan
Write-Host "Target Script: $fullScriptPath"
Write-Host "Interval: Every $IntervalMinutes minute(s)"
Write-Host "Stability Window: $MinAgeSeconds seconds"

# Build arguments for powershell.exe
$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$fullScriptPath`" -Apply -MinAgeSeconds $MinAgeSeconds -LogToFile -Quiet"

# Define Task Action
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs

# Define Task Trigger: Run every N minutes indefinitely
$now = (Get-Date)
$trigger = New-ScheduledTaskTrigger -Once -At $now -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

# Define Task Settings: Battery friendly, auto-catch-up
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

# Unregister existing task if present
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Write-Host "Existing task '$TaskName' found. Replacing..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Register the new task under current user (non-elevated)
try {
    $null = Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Lightweight automatic organizer for user Downloads folder."

    Write-Host "`n[SUCCESS] Scheduled task '$TaskName' registered successfully!" -ForegroundColor Green
    Write-Host "It will run every $IntervalMinutes minute(s) in the background with zero visible windows."
    Write-Host "Activity logs will be written to: $env:LOCALAPPDATA\DownloadOrganizer\organizer.log"
}
catch {
    Write-Host "`n[ERROR] Failed to register scheduled task: $_" -ForegroundColor Red
    throw $_
}

if ($RunNow) {
    Write-Host "`nTriggering task '$TaskName' now..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[SUCCESS] Task triggered." -ForegroundColor Green
}
