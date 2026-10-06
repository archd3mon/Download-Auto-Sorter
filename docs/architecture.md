# Architecture & Design Philosophy

## High-Level Architecture

The organizer is built around a simple, non-resident workflow powered entirely by native Windows components:

```text
Windows Task Scheduler
        │
        │ Startup & customizable interval (default: 60m)
        ▼
PowerShell Process (powershell.exe -WindowStyle Hidden)
        │
        ▼
Resolve $env:USERPROFILE\Downloads
        │
        ▼
Retrieve Top-Level Files (Get-ChildItem -File)
        │
        ├── Ignore Directories (never scan subfolders or Torrents)
        ├── Ignore Incomplete Downloads (.crdownload, .part, .tmp)
        ├── Ignore System Metadata (desktop.ini, thumbs.db)
        └── Verify File Stability (MinAgeSeconds & exclusive file lock)
        │
        ▼
Classify File by Extension (Rules Hashtable)
        │
        ▼
Resolve Collision-Safe Path (e.g., file (1).ext)
        │
        ├── Dry-Run Mode: Output proposed move (0 mutations)
        └── Apply Mode: Ensure category directory exists & move file
        │
        ▼
Process Exits (Zero resident memory / daemon overhead)
```

---

## Key Principles & Design Decisions

### 1. Built-in Windows Capabilities First
Instead of installing Python runtimes, Node.js daemons, or electron-wrapped background tray applications, this tool leverages **Windows PowerShell 5.1+** and **Windows Task Scheduler**. Both are pre-installed on virtually all modern Windows systems, require zero installation binaries, and introduce no external security or supply-chain vectors.

### 2. Transient Execution vs. Continuous Watching
A continuous filesystem watcher (`FileSystemWatcher`) has several pitfalls:
- Keeps a persistent background process consuming memory (typically 50–150 MB).
- Fires immediately when a file is initially touched, requiring debouncing logic, queue management, and lock retries.
- Can crash or become orphaned silently.

By contrast, invoking a lightweight script on startup and periodically (e.g. hourly) via Task Scheduler means:
- The script executes in < 200 ms, performs its sweep, and exits cleanly.
- Background resource usage between runs is literally **0.00% CPU and 0 MB RAM**.

### 3. Strict Boundary Enforcement (Root Files Only)
The organizer explicitly targets files located **directly** in the root of `%USERPROFILE%\Downloads`:

```powershell
Get-ChildItem -LiteralPath $Path -File
```

- **Directories are never inspected, moved, or altered.**
- This protects application folders (e.g. portable apps, game installations, unpackaged tools) and specialized folders like `Torrents` from being disrupted or reorganized.

### 4. Stability & Incomplete Download Detection
Downloads often take time and may write to disk incrementally. Moving a file while it is being downloaded corrupts the download stream. The organizer applies a two-tier defense:

1. **Known Temporary Extensions:**
   Files ending in `.crdownload` (Chrome / Edge), `.part` (Firefox), `.tmp`, `.opdownload` (Opera), or `.aria2` are immediately skipped.
2. **File Lock & Age Check (`Test-IsStable`):**
   - The file must have had no writes for at least `MinAgeSeconds` (default: 120 seconds).
   - An exclusive file stream open test (`[System.IO.File]::Open`) ensures that no active application holds an open write handle.

### 5. Collision Avoidance (Never Overwrite)
If `Documents\report.pdf` already exists and another `report.pdf` is being moved, the tool never overwrites the existing file. It determines the next available numbered suffix:

```text
report.pdf -> Documents\report.pdf (exists)
           -> Documents\report (1).pdf (exists)
           -> Documents\report (2).pdf (free -> moved here)
```

### 6. Dry-Run by Default
Running `.\Sort-Downloads.ps1` with no parameters defaults to `-DryRun` mode. Files are only moved when `-Apply` is explicitly provided.
