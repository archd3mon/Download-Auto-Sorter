#Requires -Version 5.1
<#
.SYNOPSIS
    Automated test suite for Register-Task.ps1.

.DESCRIPTION
    Validates that Register-Task.ps1 properly registers scheduled tasks with:
    1. Default startup (logon) and 60-minute recurring triggers.
    2. Custom interval hours (-IntervalHours 2).
    3. Custom interval minutes (-IntervalMinutes 30).
    4. Startup-only trigger (-NoRepeat).
    5. Recurring-only trigger (-NoStartup).
    Cleans up the test task when finished.

.EXAMPLE
    .\Test-RegisterTask.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir
$registerTaskScript = Join-Path $projectRoot 'scripts\Register-Task.ps1'
$unregisterTaskScript = Join-Path $projectRoot 'scripts\Unregister-Task.ps1'

$testTaskName = "DownloadAutoSorter_Test_" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    Register-Task Suite Execution" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Assert-Test {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$FailureMessage = ""
    )

    $script:totalTests++
    if ($Condition) {
        $script:passedTests++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    }
    else {
        $script:failedTests++
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "         $FailureMessage" -ForegroundColor Yellow
        }
    }
}

try {
    # Test 1: Default registration (Startup + 60 min recurring)
    Write-Host "`n--- Test 1: Default Registration (Startup + Hourly) ---"
    & $registerTaskScript -TaskName $testTaskName | Out-Null
    $task = Get-ScheduledTask -TaskName $testTaskName -ErrorAction SilentlyContinue
    Assert-Test "Task was successfully registered" ($null -ne $task)
    Assert-Test "Has exactly 2 triggers by default" ($task.Triggers.Count -eq 2)
    $hasLogon = ($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }) -ne $null
    $timeTrigger = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger' }
    Assert-Test "Has startup (logon) trigger" $hasLogon
    Assert-Test "Has 60-minute (PT1H) recurring trigger" ($timeTrigger.Repetition.Interval -eq 'PT1H')

    # Test 2: Custom Interval Hours
    Write-Host "`n--- Test 2: Custom Interval Hours (-IntervalHours 3) ---"
    & $registerTaskScript -TaskName $testTaskName -IntervalHours 3 | Out-Null
    $task = Get-ScheduledTask -TaskName $testTaskName
    $timeTrigger = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger' }
    Assert-Test "Has 3-hour (PT3H) recurring trigger" ($timeTrigger.Repetition.Interval -eq 'PT3H')

    # Test 3: Startup-Only (-NoRepeat)
    Write-Host "`n--- Test 3: Startup-Only Trigger (-NoRepeat) ---"
    & $registerTaskScript -TaskName $testTaskName -NoRepeat | Out-Null
    $task = Get-ScheduledTask -TaskName $testTaskName
    Assert-Test "Has only 1 trigger" ($task.Triggers.Count -eq 1)
    Assert-Test "Trigger is logon trigger" ($task.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger')

    # Test 4: Interval-Only (-NoStartup)
    Write-Host "`n--- Test 4: Interval-Only Trigger (-NoStartup) ---"
    & $registerTaskScript -TaskName $testTaskName -NoStartup -IntervalMinutes 45 | Out-Null
    $task = Get-ScheduledTask -TaskName $testTaskName
    Assert-Test "Has only 1 trigger" ($task.Triggers.Count -eq 1)
    Assert-Test "Trigger is time trigger" ($task.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger')
    Assert-Test "Repetition interval is 45 minutes (PT45M)" ($task.Triggers[0].Repetition.Interval -eq 'PT45M')
}
finally {
    # Cleanup test task
    Write-Host "`nCleaning up test task '$testTaskName'..." -ForegroundColor Cyan
    & $unregisterTaskScript -TaskName $testTaskName | Out-Null
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "Test Results: $passedTests / $totalTests passed" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
}
