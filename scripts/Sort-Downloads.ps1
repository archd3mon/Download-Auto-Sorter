#Requires -Version 5.1
<#
.SYNOPSIS
    Sort-Downloads - Lightweight, safe Windows Downloads organizer.

.DESCRIPTION
    Sorts files located strictly in the root of the user's Downloads directory
    into categorized subfolders (Documents, Development, Images, Archives, Media,
    Installers, Other) based on file extension.

    Safety Guarantees:
    - Never touches subdirectories or any folder inside Downloads (e.g. Torrents).
    - Ignores incomplete and temporary download files (.crdownload, .part, .tmp, etc.).
    - Detects locked files and actively changing files (minimum age stability check).
    - Never overwrites existing destination files (automatic collision renaming: file (1).ext).
    - Never deletes any file.
    - Runs in Dry-Run mode by default unless -Apply is explicitly specified.
    - Requires no administrator privileges.

.PARAMETER DryRun
    Simulates the sorting operation without creating folders or moving files.
    This is the default mode if -Apply is omitted.

.PARAMETER Apply
    Executes the actual file movements. Required to commit changes.

.PARAMETER DownloadsPath
    Path to the Downloads directory. Defaults to "$env:USERPROFILE\Downloads".

.PARAMETER MinAgeSeconds
    Minimum age (in seconds) since last modification before a file is considered
    stable for moving. Defaults to 120 seconds (2 minutes).

.PARAMETER LogToFile
    If specified, appends output to the log file.

.PARAMETER LogPath
    Path to log file. Defaults to "$env:LOCALAPPDATA\DownloadOrganizer\organizer.log".

.PARAMETER Quiet
    Suppresses console output (useful for non-interactive scheduled task execution).

.EXAMPLE
    .\Sort-Downloads.ps1
    Runs in safe Dry-Run mode and previews what would be moved.

.EXAMPLE
    .\Sort-Downloads.ps1 -DryRun
    Explicit dry-run preview.

.EXAMPLE
    .\Sort-Downloads.ps1 -Apply
    Organizes eligible files into their respective subfolders.

.EXAMPLE
    .\Sort-Downloads.ps1 -Apply -LogToFile
    Organizes files and logs actions to %LOCALAPPDATA%\DownloadOrganizer\organizer.log.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Apply,
    [string]$DownloadsPath = (Join-Path $env:USERPROFILE 'Downloads'),
    [int]$MinAgeSeconds = 120,
    [switch]$LogToFile,
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'DownloadOrganizer\organizer.log'),
    [switch]$Quiet
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determine execution mode: default to DryRun unless -Apply is explicitly supplied
$IsDryRun = $true
if ($Apply -and -not $DryRun) {
    $IsDryRun = $false
}

# -------------------------------------------------------------------------
# Configuration Rules
# -------------------------------------------------------------------------

$DefaultRules = @{
    # Documents
    '.pdf'   = 'Documents'
    '.doc'   = 'Documents'
    '.docx'  = 'Documents'
    '.txt'   = 'Documents'
    '.rtf'   = 'Documents'
    '.odt'   = 'Documents'
    '.xlsx'  = 'Documents'
    '.xls'   = 'Documents'
    '.csv'   = 'Documents'
    '.pptx'  = 'Documents'
    '.ppt'   = 'Documents'
    '.epub'  = 'Documents'
    '.mobi'  = 'Documents'
    '.md'    = 'Documents'
    '.markdown' = 'Documents'

    # Development
    '.ipynb' = 'Development'
    '.py'    = 'Development'
    '.cpp'   = 'Development'
    '.c'     = 'Development'
    '.h'     = 'Development'
    '.hpp'   = 'Development'
    '.cs'    = 'Development'
    '.java'  = 'Development'
    '.js'    = 'Development'
    '.jsx'   = 'Development'
    '.ts'    = 'Development'
    '.tsx'   = 'Development'
    '.html'  = 'Development'
    '.htm'   = 'Development'
    '.css'   = 'Development'
    '.json'  = 'Development'
    '.xml'   = 'Development'
    '.yaml'  = 'Development'
    '.yml'   = 'Development'
    '.sql'   = 'Development'
    '.sh'    = 'Development'
    '.ps1'   = 'Development'
    '.rs'    = 'Development'
    '.go'    = 'Development'

    # Images
    '.jpg'   = 'Images'
    '.jpeg'  = 'Images'
    '.png'   = 'Images'
    '.gif'   = 'Images'
    '.webp'  = 'Images'
    '.bmp'   = 'Images'
    '.svg'   = 'Images'
    '.ico'   = 'Images'
    '.tiff'  = 'Images'
    '.tif'   = 'Images'
    '.psd'   = 'Images'
    '.ai'    = 'Images'

    # Archives
    '.zip'   = 'Archives'
    '.7z'    = 'Archives'
    '.rar'   = 'Archives'
    '.tar'   = 'Archives'
    '.gz'    = 'Archives'
    '.bz2'   = 'Archives'
    '.xz'    = 'Archives'
    '.tgz'   = 'Archives'
    '.iso'   = 'Archives'

    # Media
    '.mp4'   = 'Media'
    '.mkv'   = 'Media'
    '.avi'   = 'Media'
    '.mov'   = 'Media'
    '.wmv'   = 'Media'
    '.flv'   = 'Media'
    '.webm'  = 'Media'
    '.mp3'   = 'Media'
    '.flac'  = 'Media'
    '.wav'   = 'Media'
    '.aac'   = 'Media'
    '.ogg'   = 'Media'
    '.m4a'   = 'Media'

    # Installers
    '.exe'   = 'Installers'
    '.msi'   = 'Installers'
    '.msix'  = 'Installers'
    '.appx'  = 'Installers'
}

# Temporary or incomplete download extensions to completely ignore
$TemporaryExtensions = @(
    '.crdownload', # Chrome, Chromium, Edge incomplete
    '.part',       # Firefox incomplete
    '.tmp',        # Windows temporary file
    '.download',   # Apple/Browser temporary file
    '.opdownload', # Opera incomplete
    '.aria2'       # aria2 download chunk
)

# System/metadata files directly in root to skip
$IgnoredFilenames = @(
    'desktop.ini',
    'thumbs.db',
    '.ds_store'
)

# -------------------------------------------------------------------------
# Logging Helper
# -------------------------------------------------------------------------

function Write-OrganizerMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'DRY_RUN', 'MOVED', 'SKIP', 'ERROR', 'WARN')]
        [string]$Level = 'INFO'
    )

    $tag = switch ($Level) {
        'DRY_RUN' { '[DRY RUN] ' }
        'MOVED'   { '[MOVED] ' }
        'SKIP'    { '[SKIP] ' }
        'ERROR'   { '[ERROR] ' }
        'WARN'    { '[WARN] ' }
        default   { '' }
    }

    $displayText = if ($tag -and -not $Message.StartsWith($tag) -and -not $Message.StartsWith("[$Level]")) { "$tag$Message" } else { $Message }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $formattedLog = "[$timestamp] $displayText"

    if (-not $Quiet) {
        switch ($Level) {
            'DRY_RUN' { Write-Host $displayText -ForegroundColor Cyan }
            'MOVED'   { Write-Host $displayText -ForegroundColor Green }
            'SKIP'    { Write-Host $displayText -ForegroundColor DarkGray }
            'WARN'    { Write-Warning $displayText }
            'ERROR'   { Write-Host $displayText -ForegroundColor Red }
            default   { Write-Host $displayText -ForegroundColor White }
        }
    }

    if ($LogToFile) {
        try {
            $logDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path -LiteralPath $logDir)) {
                $null = New-Item -ItemType Directory -Path $logDir -Force
            }
            Add-Content -LiteralPath $LogPath -Value $formattedLog -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write to log file '$LogPath': $_"
        }
    }
}

# -------------------------------------------------------------------------
# Inspection & Safety Functions
# -------------------------------------------------------------------------

function Get-DownloadFiles {
    <#
    .SYNOPSIS
        Retrieves only files directly in the root of the specified Downloads directory.
        Subdirectories and files inside subdirectories are NEVER returned.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Downloads directory does not exist: $Path"
    }

    # Direct files only - zero recursion
    Get-ChildItem -LiteralPath $Path -File
}

function Test-IsExcluded {
    <#
    .SYNOPSIS
        Checks if a file should be ignored based on system or excluded filename rules.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    return ($IgnoredFilenames -contains $File.Name.ToLowerInvariant())
}

function Test-IsTemporary {
    <#
    .SYNOPSIS
        Checks if a file is an in-progress or temporary download.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $ext = $File.Extension.ToLowerInvariant()
    return ($TemporaryExtensions -contains $ext)
}

function Test-IsFileLocked {
    <#
    .SYNOPSIS
        Checks if a file is currently opened or locked by another process (e.g. browser).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $fileStream = $null
    try {
        # Attempt to open file exclusively to check if another process holds an open write handle
        $fileInfo = [System.IO.FileInfo]::new($FilePath)
        $fileStream = $fileInfo.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        return $false
    }
    catch [System.IO.IOException] {
        return $true
    }
    catch [System.UnauthorizedAccessException] {
        return $true
    }
    catch {
        # Any other unexpected exception, treat as unsafe/locked
        return $true
    }
    finally {
        if ($null -ne $fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }
    }
}

function Test-IsStable {
    <#
    .SYNOPSIS
        Checks if a file has remained stable (not modified recently and not locked).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory = $true)]
        [int]$MinAge
    )

    # 1. Check age based on LastWriteTime
    $now = Get-Date
    $age = ($now - $File.LastWriteTime).TotalSeconds
    if ($age -lt $MinAge) {
        Write-OrganizerMessage "File '$($File.Name)' was modified $([int]$age)s ago (requires ${MinAge}s stability). Skipping." -Level 'SKIP'
        return $false
    }

    # 2. Check if locked by another active process
    if (Test-IsFileLocked -FilePath $File.FullName) {
        Write-OrganizerMessage "File '$($File.Name)' is currently locked by another process. Skipping." -Level 'SKIP'
        return $false
    }

    return $true
}

function Get-Destination {
    <#
    .SYNOPSIS
        Determines the target category folder name for a given file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory = $true)]
        [hashtable]$Rules
    )

    $ext = $File.Extension.ToLowerInvariant()
    if ($Rules.ContainsKey($ext)) {
        return $Rules[$ext]
    }

    return 'Other'
}

function Get-UniqueDestinationPath {
    <#
    .SYNOPSIS
        Calculates a collision-safe destination file path.
        If a file already exists at the destination, appends ' (1)', ' (2)', etc.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDirectory,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $candidatePath = Join-Path -Path $TargetDirectory -ChildPath $FileName
    if (-not (Test-Path -LiteralPath $candidatePath)) {
        return $candidatePath
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    $counter = 1
    while ($true) {
        $newFileName = "$baseName ($counter)$extension"
        $candidatePath = Join-Path -Path $TargetDirectory -ChildPath $newFileName
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            return $candidatePath
        }
        $counter++
    }
}

function Move-Download {
    <#
    .SYNOPSIS
        Moves a file safely to its designated destination.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $destinationDir = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        $null = New-Item -ItemType Directory -Path $destinationDir -Force
    }

    Move-Item -LiteralPath $File.FullName -Destination $DestinationPath -ErrorAction Stop
}

# -------------------------------------------------------------------------
# Main Execution Orchestrator
# -------------------------------------------------------------------------

function Invoke-DownloadSorter {
    # Resolve real path
    if (-not (Test-Path -LiteralPath $DownloadsPath -PathType Container)) {
        Write-OrganizerMessage "Downloads directory '$DownloadsPath' was not found." -Level 'ERROR'
        return
    }

    $resolvedDownloads = (Resolve-Path -LiteralPath $DownloadsPath).Path

    if ($IsDryRun) {
        Write-OrganizerMessage "=== RUNNING IN DRY RUN MODE (No changes will be made) ===" -Level 'INFO'
        Write-OrganizerMessage "Target Directory: $resolvedDownloads" -Level 'INFO'
        Write-OrganizerMessage "Pass -Apply to perform actual file movement.`n" -Level 'INFO'
    } else {
        Write-OrganizerMessage "=== EXECUTING DOWNLOADS SORT (-Apply) ===" -Level 'INFO'
        Write-OrganizerMessage "Target Directory: $resolvedDownloads`n" -Level 'INFO'
    }

    # Milestone 0 & 1: Retrieve only files directly inside Downloads root
    try {
        $candidateFiles = Get-DownloadFiles -Path $resolvedDownloads
    }
    catch {
        Write-OrganizerMessage "Error scanning directory '$resolvedDownloads': $_" -Level 'ERROR'
        return
    }

    if ($candidateFiles.Count -eq 0) {
        Write-OrganizerMessage "No files found in '$resolvedDownloads'." -Level 'INFO'
        return
    }

    $processedCount = 0
    $movedCount = 0
    $skippedCount = 0
    $errorCount = 0

    foreach ($file in $candidateFiles) {
        $processedCount++

        # Safety Check 1: Excluded system files
        if (Test-IsExcluded -File $file) {
            Write-OrganizerMessage "Ignoring excluded system file '$($file.Name)'" -Level 'SKIP'
            $skippedCount++
            continue
        }

        # Safety Check 2: Incomplete/temporary downloads
        if (Test-IsTemporary -File $file) {
            Write-OrganizerMessage "Ignoring incomplete/temporary download '$($file.Name)'" -Level 'SKIP'
            $skippedCount++
            continue
        }

        # Safety Check 3: Stability and lock detection
        if (-not (Test-IsStable -File $file -MinAge $MinAgeSeconds)) {
            $skippedCount++
            continue
        }

        # Classification
        $category = Get-Destination -File $file -Rules $DefaultRules
        $categoryDir = Join-Path -Path $resolvedDownloads -ChildPath $category
        $destinationPath = Get-UniqueDestinationPath -TargetDirectory $categoryDir -FileName $file.Name
        $destFileName = Split-Path -Path $destinationPath -Leaf

        # Output / Action
        if ($IsDryRun) {
            $collisionNotice = if ($destFileName -ne $file.Name) { " (renamed to avoid collision: '$destFileName')" } else { "" }
            Write-OrganizerMessage "[DRY RUN] $($file.Name) -> $category\$destFileName$collisionNotice" -Level 'DRY_RUN'
            $movedCount++
        }
        else {
            try {
                Move-Download -File $file -DestinationPath $destinationPath
                $collisionNotice = if ($destFileName -ne $file.Name) { " (collision avoided, renamed to '$destFileName')" } else { "" }
                Write-OrganizerMessage "[MOVED] $($file.Name) -> $category\$destFileName$collisionNotice" -Level 'MOVED'
                $movedCount++
            }
            catch {
                Write-OrganizerMessage "Failed to move '$($file.Name)' to '$destinationPath': $_" -Level 'ERROR'
                $errorCount++
            }
        }
    }

    Write-OrganizerMessage "`nSummary: $processedCount files evaluated | $movedCount planned/moved | $skippedCount skipped | $errorCount errors" -Level 'INFO'
}

# Run the sorter
Invoke-DownloadSorter
