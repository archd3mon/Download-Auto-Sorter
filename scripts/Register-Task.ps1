#Requires -Version 5.1
<#
.SYNOPSIS
    Registers a Windows Scheduled Task for Downloads Auto Sorter.

.DESCRIPTION
    Creates a Windows Scheduled Task running under the current user's
    credentials (no administrator rights needed) that runs Sort-Downloads.ps1:
    1. Once on user logon / startup (default: enabled).
    2. Periodically at a customizable interval (default: every 60 minutes).

.PARAMETER TaskName
    Name of the scheduled task. Defaults to "DownloadAutoSorter".

.PARAMETER IntervalMinutes
    How often (in minutes) to run the organizer periodically. Defaults to 60.
    Set to 0 or use -NoRepeat to only run on startup.

.PARAMETER IntervalHours
    Alternative to IntervalMinutes for specifying the recurring interval in hours.
    Takes precedence over IntervalMinutes if greater than 0.

.PARAMETER RunOnStartup
    Whether to trigger the task automatically when the user logs in. Defaults to $true.

.PARAMETER NoStartup
    Switch to disable running on startup / logon (recurring interval only).

.PARAMETER NoRepeat
    Switch to disable recurring execution (startup / logon only).

.PARAMETER ScriptPath
    Path to Sort-Downloads.ps1. Defaults to the sibling script in the same directory.

.PARAMETER MinAgeSeconds
    Minimum age (in seconds) before moving files. Defaults to 120 (2 minutes).

.PARAMETER RunNow
    If set, triggers the task immediately after registration to verify.

.EXAMPLE
    .\Register-Task.ps1
    Registers the task to run once on startup and then every 60 minutes.

.EXAMPLE
    .\Register-Task.ps1 -IntervalHours 2
    Registers the task to run once on startup and then every 2 hours.

.EXAMPLE
    .\Register-Task.ps1 -IntervalMinutes 30
    Registers the task to run once on startup and then every 30 minutes.

.EXAMPLE
    .\Register-Task.ps1 -NoRepeat
    Registers the task to run ONLY once on startup / logon (no periodic runs).

.EXAMPLE
    .\Register-Task.ps1 -NoStartup -IntervalHours 4
    Registers the task to run only every 4 hours without running on logon.
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'DownloadAutoSorter',
    [int]$IntervalMinutes = 60,
    [int]$IntervalHours = 0,
    [bool]$RunOnStartup = $true,
    [switch]$NoStartup,
    [switch]$NoRepeat,
    [string]$ScriptPath = '',
    [int]$MinAgeSeconds = 120,
    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($IntervalHours -gt 0) {
    $IntervalMinutes = $IntervalHours * 60
}

$enableStartup = $RunOnStartup -and -not $NoStartup
$enableRepeat = -not $NoRepeat -and ($IntervalMinutes -gt 0)

if (-not $enableStartup -and -not $enableRepeat) {
    throw "At least one trigger must be active. Neither startup trigger nor recurring interval is enabled."
}

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = Join-Path $PSScriptRoot 'Sort-Downloads.ps1'
}

# Validate script path
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Target script not found at '$ScriptPath'."
}

$fullScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
$currentUser = if ($env:USERNAME) { $env:USERNAME } else { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }

Write-Host "Configuring Scheduled Task '$TaskName'..." -ForegroundColor Cyan
Write-Host "Target Script: $fullScriptPath"
Write-Host "Startup Trigger: $(if ($enableStartup) { 'Enabled (at user logon)' } else { 'Disabled' })"
Write-Host "Recurring Interval: $(if ($enableRepeat) { "Every $IntervalMinutes minute(s)" + $(if ($IntervalMinutes -ge 60 -and ($IntervalMinutes % 60 -eq 0)) { " ($([int]($IntervalMinutes / 60)) hour(s))" } else { '' }) } else { 'Disabled (startup only)' })"
Write-Host "Stability Window: $MinAgeSeconds seconds"

# Build arguments for powershell.exe
$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$fullScriptPath`" -Apply -MinAgeSeconds $MinAgeSeconds -LogToFile -Quiet"

# Define Task Action
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs

# Define Task Triggers
$triggers = @()

if ($enableStartup) {
    # Non-elevated user logon trigger
    $triggers += New-ScheduledTaskTrigger -AtLogOn -User $currentUser
}

if ($enableRepeat) {
    $now = (Get-Date)
    $triggers += New-ScheduledTaskTrigger -Once -At $now -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
}

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
        -Trigger $triggers `
        -User $currentUser `
        -Settings $settings `
        -Description "Lightweight Downloads auto sorter for user Downloads folder."

    Write-Host "`n[SUCCESS] Scheduled task '$TaskName' registered successfully!" -ForegroundColor Green
    if ($enableStartup -and $enableRepeat) {
        Write-Host "It will run once on startup (logon) and every $IntervalMinutes minute(s) in the background with zero visible windows."
    } elseif ($enableStartup) {
        Write-Host "It will run once on startup (logon) with zero visible windows."
    } else {
        Write-Host "It will run every $IntervalMinutes minute(s) in the background with zero visible windows."
    }
    Write-Host "Activity logs will be written to: $env:LOCALAPPDATA\DownloadAutoSorter\organizer.log"
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
