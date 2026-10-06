#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Windows Scheduled Task for Download Organizer.

.DESCRIPTION
    Safely unregisters and removes the scheduled task created by Register-Task.ps1.

.PARAMETER TaskName
    Name of the scheduled task. Defaults to "DownloadOrganizer".

.EXAMPLE
    .\Unregister-Task.ps1
    Unregisters the default "DownloadOrganizer" task.
#>

[CmdletBinding()]
param(
    [string]$TaskName = 'DownloadOrganizer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Checking for scheduled task '$TaskName'..." -ForegroundColor Cyan

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($null -eq $existingTask) {
    Write-Host "[INFO] No scheduled task named '$TaskName' was found. Nothing to remove." -ForegroundColor Yellow
    return
}

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[SUCCESS] Scheduled task '$TaskName' has been removed." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to unregister scheduled task: $_" -ForegroundColor Red
    throw $_
}
