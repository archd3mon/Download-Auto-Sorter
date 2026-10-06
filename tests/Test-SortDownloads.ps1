#Requires -Version 5.1
<#
.SYNOPSIS
    Automated test suite for Sort-Downloads.ps1.

.DESCRIPTION
    Creates an isolated test sandbox environment (mock Downloads folder) and verifies:
    1. Dry-run mode produces zero mutations (no folders created, no files moved).
    2. Directories directly inside Downloads (e.g. Torrents, game folders) are untouched.
    3. Incomplete downloads (.crdownload, .part, .tmp) are completely ignored.
    4. Excluded system files (desktop.ini) are completely ignored.
    5. Extension classification (PDF -> Documents, IPYNB -> Development, unknown -> Other, etc.).
    6. Non-collision renaming (file (1).pdf, file (2).pdf) prevents overwriting existing destination files.
    7. Locked files (held open with exclusive lock) are skipped safely without terminating the run.
    8. Recently modified files (within MinAgeSeconds) are skipped for stability.
    9. Error resiliency: individual failures do not abort the process.
    Cleans up all sandbox files and folders after running.

.EXAMPLE
    .\Test-SortDownloads.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir
$sortScript = Join-Path $projectRoot 'scripts\Sort-Downloads.ps1'

if (-not (Test-Path -LiteralPath $sortScript)) {
    throw "Sort-Downloads.ps1 not found at '$sortScript'"
}

$sandboxDir = Join-Path $env:TEMP ("DownloadSorter_Test_" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      Download Organizer - Test Suite Execution" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Sandbox Location: $sandboxDir`n"

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
            Write-Host "         Reason: $FailureMessage" -ForegroundColor Yellow
        }
    }
}

try {
    # -------------------------------------------------------------
    # Setup Sandbox
    # -------------------------------------------------------------
    $null = New-Item -ItemType Directory -Path $sandboxDir -Force

    # 1. Directory safety test items
    $torrentDir = Join-Path $sandboxDir 'Torrents'
    $null = New-Item -ItemType Directory -Path $torrentDir -Force
    $torrentIncomplete = Join-Path $torrentDir '.incomplete'
    $null = New-Item -ItemType Directory -Path $torrentIncomplete -Force
    Set-Content -LiteralPath (Join-Path $torrentIncomplete 'movie.mp4') -Value 'torrent chunk'

    $appFolder = Join-Path $sandboxDir 'koreader-kindlepw2-v2026.03'
    $null = New-Item -ItemType Directory -Path $appFolder -Force
    Set-Content -LiteralPath (Join-Path $appFolder 'config.cfg') -Value 'sample app file'

    # 2. Files to be categorized
    $pdfFile = Join-Path $sandboxDir '23070122109.pdf'
    Set-Content -LiteralPath $pdfFile -Value '%PDF-1.4 sample content'

    $notebookFile = Join-Path $sandboxDir 'NLP_Expt5_Query_Expansion.ipynb'
    Set-Content -LiteralPath $notebookFile -Value '{"cells": []}'

    $imageFile = Join-Path $sandboxDir 'photo.png'
    Set-Content -LiteralPath $imageFile -Value 'fake png data'

    $archiveFile = Join-Path $sandboxDir 'backup.zip'
    Set-Content -LiteralPath $archiveFile -Value 'fake zip data'

    $installerFile = Join-Path $sandboxDir 'setup.exe'
    Set-Content -LiteralPath $installerFile -Value 'fake exe data'

    $otherFile = Join-Path $sandboxDir 'unknown_file.xyz123'
    Set-Content -LiteralPath $otherFile -Value 'unknown payload'

    # 3. Temporary / incomplete downloads to ignore
    $crdownloadFile = Join-Path $sandboxDir 'huge_installer.exe.crdownload'
    Set-Content -LiteralPath $crdownloadFile -Value 'incomplete stream'

    $partFile = Join-Path $sandboxDir 'linux_distro.iso.part'
    Set-Content -LiteralPath $partFile -Value 'partial download'

    $tmpFile = Join-Path $sandboxDir 'scratch.tmp'
    Set-Content -LiteralPath $tmpFile -Value 'temporary bits'

    # 4. Excluded system file
    $desktopIni = Join-Path $sandboxDir 'desktop.ini'
    Set-Content -LiteralPath $desktopIni -Value '[.ShellClassInfo]'

    # Set file timestamps older than 5 minutes so they pass the stability check
    $oldDate = (Get-Date).AddMinutes(-10)
    Get-ChildItem -LiteralPath $sandboxDir -File | ForEach-Object {
        $_.LastWriteTime = $oldDate
    }

    # -------------------------------------------------------------
    # TEST SUITE 1: Dry-Run Mode Zero Mutation Guarantee
    # -------------------------------------------------------------
    Write-Host "`n--- Test Suite 1: Dry-Run Mode Zero Mutation ---" -ForegroundColor White
    $preRunFiles = (Get-ChildItem -LiteralPath $sandboxDir -File).Count
    $preRunDirs = (Get-ChildItem -LiteralPath $sandboxDir -Directory).Count

    & powershell.exe -ExecutionPolicy Bypass -File $sortScript -DownloadsPath $sandboxDir -DryRun -MinAgeSeconds 0 -Quiet

    $postRunFiles = (Get-ChildItem -LiteralPath $sandboxDir -File).Count
    $postRunDirs = (Get-ChildItem -LiteralPath $sandboxDir -Directory).Count

    Assert-Test -TestName "Dry-run creates no new directories" -Condition ($preRunDirs -eq $postRunDirs)
    Assert-Test -TestName "Dry-run moves no files from root" -Condition ($preRunFiles -eq $postRunFiles)
    Assert-Test -TestName "PDF still exists in root after dry-run" -Condition (Test-Path -LiteralPath $pdfFile)

    # -------------------------------------------------------------
    # TEST SUITE 2: Stability and File Lock Tests
    # -------------------------------------------------------------
    Write-Host "`n--- Test Suite 2: File Lock and Freshness Safety ---" -ForegroundColor White

    # Create a fresh file modified 1 second ago
    $freshFile = Join-Path $sandboxDir 'just_started.docx'
    Set-Content -LiteralPath $freshFile -Value 'fresh content'
    (Get-Item -LiteralPath $freshFile).LastWriteTime = Get-Date

    # Create a locked file that another process holds open
    $lockedFile = Join-Path $sandboxDir 'locked_download.mp4'
    Set-Content -LiteralPath $lockedFile -Value 'locked media'
    (Get-Item -LiteralPath $lockedFile).LastWriteTime = $oldDate
    $lockStream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    try {
        & powershell.exe -ExecutionPolicy Bypass -File $sortScript -DownloadsPath $sandboxDir -Apply -MinAgeSeconds 120 -Quiet

        Assert-Test -TestName "Fresh file (< MinAgeSeconds) was skipped and remains in root" -Condition (Test-Path -LiteralPath $freshFile)
        Assert-Test -TestName "Locked file was skipped safely and remains in root" -Condition (Test-Path -LiteralPath $lockedFile)
    }
    finally {
        if ($null -ne $lockStream) {
            $lockStream.Close()
            $lockStream.Dispose()
        }
    }

    # -------------------------------------------------------------
    # TEST SUITE 3: Sorting, Categorization & Exclusions (-Apply)
    # -------------------------------------------------------------
    Write-Host "`n--- Test Suite 3: Categorization, Exclusions & Moves ---" -ForegroundColor White

    # Age the fresh file so it can be moved now
    (Get-Item -LiteralPath $freshFile).LastWriteTime = $oldDate
    (Get-Item -LiteralPath $lockedFile).LastWriteTime = $oldDate

    & powershell.exe -ExecutionPolicy Bypass -File $sortScript -DownloadsPath $sandboxDir -Apply -MinAgeSeconds 0 -Quiet

    # Verify directory safety
    Assert-Test -TestName "Torrents directory was not moved or renamed" -Condition (Test-Path -LiteralPath $torrentDir)
    Assert-Test -TestName "Torrents\.incomplete was not touched" -Condition (Test-Path -LiteralPath $torrentIncomplete)
    Assert-Test -TestName "Nested torrent contents intact" -Condition (Test-Path -LiteralPath (Join-Path $torrentIncomplete 'movie.mp4'))
    Assert-Test -TestName "Application directory untouched" -Condition (Test-Path -LiteralPath $appFolder)

    # Verify temporary and excluded files remain untouched in root
    Assert-Test -TestName "Incomplete .crdownload ignored" -Condition (Test-Path -LiteralPath $crdownloadFile)
    Assert-Test -TestName "Incomplete .part ignored" -Condition (Test-Path -LiteralPath $partFile)
    Assert-Test -TestName "Incomplete .tmp ignored" -Condition (Test-Path -LiteralPath $tmpFile)
    Assert-Test -TestName "System desktop.ini ignored" -Condition (Test-Path -LiteralPath $desktopIni)

    # Verify categorized locations
    Assert-Test -TestName "PDF moved to Documents" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Documents\23070122109.pdf'))
    Assert-Test -TestName "Word doc moved to Documents" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Documents\just_started.docx'))
    Assert-Test -TestName "Notebook moved to Development" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Development\NLP_Expt5_Query_Expansion.ipynb'))
    Assert-Test -TestName "PNG moved to Images" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Images\photo.png'))
    Assert-Test -TestName "ZIP moved to Archives" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Archives\backup.zip'))
    Assert-Test -TestName "EXE moved to Installers" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Installers\setup.exe'))
    Assert-Test -TestName "MP4 moved to Media" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Media\locked_download.mp4'))
    Assert-Test -TestName "Unknown extension moved to Other" -Condition (Test-Path -LiteralPath (Join-Path $sandboxDir 'Other\unknown_file.xyz123'))

    # -------------------------------------------------------------
    # TEST SUITE 4: Collision-Safe Renaming
    # -------------------------------------------------------------
    Write-Host "`n--- Test Suite 4: Collision Avoidance (Never Overwrite) ---" -ForegroundColor White

    # Place a new file with the exact same name as an already sorted file
    $duplicatePdf1 = Join-Path $sandboxDir '23070122109.pdf'
    Set-Content -LiteralPath $duplicatePdf1 -Value 'second pdf with same name'
    (Get-Item -LiteralPath $duplicatePdf1).LastWriteTime = $oldDate

    & powershell.exe -ExecutionPolicy Bypass -File $sortScript -DownloadsPath $sandboxDir -Apply -MinAgeSeconds 0 -Quiet

    $expectedDup1 = Join-Path $sandboxDir 'Documents\23070122109 (1).pdf'
    Assert-Test -TestName "Collision renamed to '23070122109 (1).pdf'" -Condition (Test-Path -LiteralPath $expectedDup1)
    Assert-Test -TestName "Original destination file was not overwritten" -Condition ((Get-Content -LiteralPath (Join-Path $sandboxDir 'Documents\23070122109.pdf') -Raw).Trim() -eq '%PDF-1.4 sample content')

    # Place a third duplicate
    $duplicatePdf2 = Join-Path $sandboxDir '23070122109.pdf'
    Set-Content -LiteralPath $duplicatePdf2 -Value 'third pdf with same name'
    (Get-Item -LiteralPath $duplicatePdf2).LastWriteTime = $oldDate

    & powershell.exe -ExecutionPolicy Bypass -File $sortScript -DownloadsPath $sandboxDir -Apply -MinAgeSeconds 0 -Quiet

    $expectedDup2 = Join-Path $sandboxDir 'Documents\23070122109 (2).pdf'
    Assert-Test -TestName "Second collision renamed to '23070122109 (2).pdf'" -Condition (Test-Path -LiteralPath $expectedDup2)

}
finally {
    # Cleanup sandbox completely
    if (Test-Path -LiteralPath $sandboxDir) {
        Remove-Item -LiteralPath $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "Test Results: $passedTests / $totalTests passed" -ForegroundColor $(if ($failedTests -eq 0) { 'Green' } else { 'Red' })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
}
