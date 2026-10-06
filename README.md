# Windows Downloads Organizer

A lightweight, rock-solid, open-source file organizer for the Windows `Downloads` folder powered by native **PowerShell** and **Windows Task Scheduler**.

Requires **zero third-party background applications**, introduces **zero resident memory overhead**, and operates with strict **safety guarantees**.

---

## Table of Contents

1. [What It Does](#what-it-does)
2. [Why It Exists](#why-it-exists)
3. [Design Philosophy](#design-philosophy)
4. [Safety Guarantees](#safety-guarantees)
5. [Architecture](#architecture)
6. [Supported Extensions & Categories](#supported-extensions--categories)
7. [Installation & Requirements](#installation--requirements)
8. [Usage & Modes](#usage--modes)
   - [Dry-Run Mode (Default)](#dry-run-mode-default)
   - [Apply Mode (Actual Movement)](#apply-mode-actual-movement)
9. [Automating with Windows Task Scheduler](#automating-with-windows-task-scheduler)
10. [Torrent & Application Folder Behavior](#torrent--application-folder-behavior)
11. [Large Downloads & Active File Detection](#large-downloads--active-file-detection)
12. [Collision Handling (Never Overwrite)](#collision-handling-never-overwrite)
13. [Logging & Diagnostics](#logging--diagnostics)
14. [Limitations](#limitations)
15. [Troubleshooting](#troubleshooting)
16. [Contributing & License](#contributing--license)

---

## What It Does

The Windows Downloads folder easily accumulates a disorganized mess of PDFs, software installers, code notebooks, datasets, images, and archives.

This organizer automatically categorizes loose files directly in the root of your `Downloads` directory into dedicated subfolders:

```text
%USERPROFILE%\Downloads\
├── Documents/       <- .pdf, .docx, .txt, .xlsx, .pptx, .md
├── Development/     <- .ipynb, .py, .cpp, .js, .ts, .json, .sql
├── Images/          <- .png, .jpg, .gif, .webp, .svg
├── Archives/        <- .zip, .7z, .rar, .tar, .gz
├── Media/           <- .mp4, .mkv, .mp3, .flac
├── Installers/      <- .exe, .msi, .msix
├── Other/           <- Any unrecognized extensions
└── Torrents/        <- Untouched (folders are strictly ignored)
```

---

## Why It Exists

Most file-sorting solutions suffer from critical flaws:
- **Bulky Background Daemons:** They run persistent Node.js, Python, or Electron tray apps that sit in system memory consuming 100+ MB of RAM just to monitor one folder.
- **Destructive Assumptions:** Many tools aggressively scan subdirectories, moving game installation data, unpackaged archives, or active torrent folders without caution.
- **Race Conditions on Incomplete Downloads:** Naive scripts move files while a browser or downloader is still streaming bytes, corrupting downloads.
- **Silent Overwrites:** If a destination folder already has a file with the same name, simple scripts overwrite it, resulting in data loss.

**Windows Downloads Organizer** is designed to solve these issues using built-in Windows components: it runs on a scheduled interval (e.g., every 5 minutes), performs its sweep in under a second, and completely terminates. Between runs, it uses **0.00% CPU and 0 MB RAM**.

---

## Design Philosophy

> **Built-in Windows capabilities first → reversible changes → dry-run before mutation → minimal background overhead → clear documentation.**

- **Native Only:** Uses built-in Windows PowerShell 5.1+ and Windows Task Scheduler. No external dependencies, binaries, or runtimes required.
- **Dry-Run by Default:** Running the script without parameters performs a simulated run with zero filesystem modifications.
- **Never Overwrite:** Collision resolution automatically numbers identical filenames (`report (1).pdf`).
- **Never Delete:** Files are only ever moved. Automatic deletion is not implemented by design.
- **No Elevation Needed:** Operates entirely within the current user's profile and privileges. No Administrator prompt required.

---

## Safety Guarantees

| Guarantee | Mechanism | Why This Matters |
| :--- | :--- | :--- |
| **No Folder Mutation** | Only inspects `Get-ChildItem -File` in the Downloads root. | Never rearranges game installations, extracted folders, or application directories. |
| **Ignore Incomplete Downloads** | Excludes `.crdownload`, `.part`, `.tmp`, `.download`, etc. | Chromium and Firefox write to temporary extensions during downloads. Moving them breaks downloads. |
| **Active File Lock Detection** | Tests exclusive read-write lock before moving. | Prevents moving files that an active process is currently writing. |
| **Stability Window** | Requires file write age $\ge$ `MinAgeSeconds` (default: 120s). | Ensures files written directly to their target names are finished. |
| **No Overwriting** | Smart collision numbering: `name (1).ext`. | Eliminates accidental overwrites when downloading multiple reports or files with the same name. |
| **Protected Subdirectories** | Ignores `Downloads\Torrents` and all other folders. | Preserves torrent downloads and seeding clients without interfering. |

---

## Architecture

```text
Windows Task Scheduler
        │
        │ Triggers every 5 minutes
        ▼
PowerShell Process (powershell.exe -WindowStyle Hidden)
        │
        ▼
Resolve $env:USERPROFILE\Downloads
        │
        ▼
Inspect Root Files (Get-ChildItem -File)
        │
        ├── Skip directories (Torrents, app folders, etc.)
        ├── Skip system metadata (desktop.ini, thumbs.db)
        ├── Skip temporary extensions (.crdownload, .part, .tmp)
        └── Verify stability (File Lock check + Age >= 120s)
        │
        ▼
Classify File by Extension
        │
        ▼
Calculate Collision-Safe Destination (e.g. file (1).ext)
        │
        ├── DryRun: Print proposed action (0 mutations)
        └── Apply: Create target directory (if missing) & Move-Item
        │
        ▼
Process Exits (0 resident memory)
```

---

## Supported Extensions & Categories

| Category | Default Extensions |
| :--- | :--- |
| **Documents** | `.pdf`, `.doc`, `.docx`, `.txt`, `.rtf`, `.odt`, `.xlsx`, `.xls`, `.csv`, `.pptx`, `.ppt`, `.epub`, `.mobi`, `.md`, `.markdown` |
| **Development** | `.ipynb`, `.py`, `.cpp`, `.c`, `.h`, `.hpp`, `.cs`, `.java`, `.js`, `.jsx`, `.ts`, `.tsx`, `.html`, `.htm`, `.css`, `.json`, `.xml`, `.yaml`, `.yml`, `.sql`, `.sh`, `.ps1`, `.rs`, `.go` |
| **Images** | `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.bmp`, `.svg`, `.ico`, `.tiff`, `.tif`, `.psd`, `.ai` |
| **Archives** | `.zip`, `.7z`, `.rar`, `.tar`, `.gz`, `.bz2`, `.xz`, `.tgz`, `.iso` |
| **Media** | `.mp4`, `.mkv`, `.avi`, `.mov`, `.wmv`, `.flv`, `.webm`, `.mp3`, `.flac`, `.wav`, `.aac`, `.ogg`, `.m4a` |
| **Installers** | `.exe`, `.msi`, `.msix`, `.appx` |
| **Other** | Any extension not listed above |

*Need custom rules? See [examples/custom-rules.ps1](examples/custom-rules.ps1) to add custom categories or override defaults.*

---

## Installation & Requirements

### System Requirements
- **OS:** Windows 10, Windows 11, or Windows Server 2016+
- **PowerShell:** Version 5.1 or newer (built into Windows)
- **Permissions:** Standard user (Administrator privileges are **not** needed)

### Clone or Download
Clone this repository to your local machine:
```powershell
git clone https://github.com/your-username/windows-download-organizer.git
cd windows-download-organizer
```

---

## Usage & Modes

### Dry-Run Mode (Default)
Preview what actions would be taken without moving any files or creating directories:

```powershell
# Using explicit flag
.\scripts\Sort-Downloads.ps1 -DryRun

# Or simply run without flags (defaults to dry-run safely)
.\scripts\Sort-Downloads.ps1
```

**Example output:**
```text
=== RUNNING IN DRY RUN MODE (No changes will be made) ===
Target Directory: C:\Users\user\Downloads
Pass -Apply to perform actual file movement.

[DRY RUN] 23070122109.pdf -> Documents\23070122109.pdf
[DRY RUN] NLP_Expt5_Query_Expansion.ipynb -> Development\NLP_Expt5_Query_Expansion.ipynb
[DRY RUN] invoice.pdf -> Documents\invoice (1).pdf (renamed to avoid collision: 'invoice (1).pdf')

Summary: 3 files evaluated | 3 planned/moved | 0 skipped | 0 errors
```

### Apply Mode (Actual Movement)
Move eligible files into categorized folders:

```powershell
.\scripts\Sort-Downloads.ps1 -Apply
```

**Example output:**
```text
=== EXECUTING DOWNLOADS SORT (-Apply) ===
Target Directory: C:\Users\user\Downloads

[MOVED] 23070122109.pdf -> Documents\23070122109.pdf
[MOVED] NLP_Expt5_Query_Expansion.ipynb -> Development\NLP_Expt5_Query_Expansion.ipynb

Summary: 2 files evaluated | 2 planned/moved | 0 skipped | 0 errors
```

---

## Automating with Windows Task Scheduler

To set up automatic sorting in the background without popups:

### 1. Register Task (Runs every 5 minutes)
```powershell
.\scripts\Register-Task.ps1
```

This creates a user-level scheduled task named `DownloadOrganizer` that:
- Runs every 5 minutes in a hidden background window (`-WindowStyle Hidden`).
- Runs only when you are logged in.
- Appends activity logs to `%LOCALAPPDATA%\DownloadOrganizer\organizer.log`.

### 2. Custom Intervals or Instant Test
```powershell
# Run every 15 minutes instead
.\scripts\Register-Task.ps1 -IntervalMinutes 15

# Trigger immediately to verify
.\scripts\Register-Task.ps1 -RunNow
```

### 3. Unregister / Remove Task
```powershell
.\scripts\Unregister-Task.ps1
```

*For step-by-step instructions on setting up via the Windows Task Scheduler GUI, see [docs/task-scheduler.md](docs/task-scheduler.md).*

---

## Torrent & Application Folder Behavior

Many users configure torrent clients (qBittorrent, Transmission, etc.) or application downloaders to save files directly into:

```text
Downloads/
└── Torrents/
    ├── .incomplete/
    └── Completed/
```

The organizer strictly enforces:
1. **Directories are completely skipped:** `Get-ChildItem -File` is used without recursion. Any folder, whether named `Torrents`, `Games`, or `ExtractedTool`, is ignored.
2. **Files inside folders are never inspected:** Subdirectories are never scanned or reorganized.

---

## Large Downloads & Active File Detection

A common hazard in downloads sorters is moving a 10 GB ISO or game installer while the browser or download manager is still writing to disk.

The organizer prevents this with two checks:

1. **Temporary Extension Exclusion:**
   Browsers create temporary placeholder files while downloading (e.g. `.crdownload` for Chrome/Edge, `.part` for Firefox). The organizer ignores:
   - `.crdownload`
   - `.part`
   - `.tmp`
   - `.download`
   - `.opdownload`
   - `.aria2`

2. **File Lock & Age Verification (`Test-IsStable`):**
   Some downloads write directly to the final filename. The organizer requires:
   - **Exclusive Lock Check:** Attempts to open the file handle exclusively via .NET `[System.IO.File]::Open`. If an active process holds a write handle, it fails the check and is skipped.
   - **Minimum Age Threshold (`MinAgeSeconds`):** Files must have remained unmodified for at least 120 seconds (configurable via `-MinAgeSeconds`).

---

## Collision Handling (Never Overwrite)

When you download multiple files with the same name (such as `receipt.pdf` or `invoice.pdf`), standard Windows tools often ask to replace or overwrite.

This organizer will **never overwrite an existing file**:
- If `Documents\receipt.pdf` already exists, the incoming file is named `receipt (1).pdf`.
- If `receipt (1).pdf` also exists, it uses `receipt (2).pdf`, continuing until a unique name is found.

---

## Logging & Diagnostics

When running in automated or scheduled mode, pass `-LogToFile`:

```powershell
.\scripts\Sort-Downloads.ps1 -Apply -LogToFile
```

Logs are saved to:
```text
%LOCALAPPDATA%\DownloadOrganizer\organizer.log
```

To view the log entries in real-time or view recent entries:
```powershell
Get-Content -Path "$env:LOCALAPPDATA\DownloadOrganizer\organizer.log" -Tail 20
```

---

## Testing

An automated test suite is included in `tests/Test-SortDownloads.ps1`. It creates an isolated sandbox environment in `%TEMP%` and verifies:
- Dry-run zero mutation guarantees.
- Fresh and locked file safety.
- Excluded system files (`desktop.ini`) and temporary downloads (`.crdownload`, `.part`, `.tmp`).
- Subdirectory isolation (`Torrents`, folders).
- Extension routing across categories.
- Collision renaming safety.

To execute the tests:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tests\Test-SortDownloads.ps1
```

---

## Limitations

- **Top-Level Files Only:** Does not organize files nested inside subdirectories. (This is an intentional safety design).
- **Extension-Based:** Does not inspect binary file magic bytes / MIME types. (Predictable and fast).
- **Non-Admin Scope:** Operates only within the user's Downloads folder.

---

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for detailed solutions for:
- PowerShell script execution policy errors.
- Unmoved files and stability timeouts.
- Task Scheduler diagnostic steps.

---

## Contributing & License

Contributions are welcome! Please submit an issue or pull request on GitHub.

Distributed under the [MIT License](LICENSE).
