# Troubleshooting Guide

Common scenarios and steps to resolve them.

---

## 1. PowerShell Execution Policy Restriction

### Symptom
When attempting to run the scripts manually, PowerShell shows:
```text
File ... cannot be loaded because running scripts is disabled on this system.
```

### Explanation
Windows defaults to a restrictive script execution policy for regular user sessions.

### Solution
You do not need administrator privileges to run scripts for your own user session. Pass `-ExecutionPolicy Bypass` when invoking the script:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Sort-Downloads.ps1 -DryRun
```

Or set the execution policy for your current user account:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

---

## 2. A Downloaded File Was Not Moved

### Possible Reasons & Checks

1. **File was modified recently:**
   The organizer waits at least 2 minutes (`MinAgeSeconds = 120`) after the last disk write before touching a file. Run the script with `-Verbose` or check the log file to see if the file is waiting for the stability window:
   ```powershell
   .\scripts\Sort-Downloads.ps1 -DryRun
   ```

2. **File is still being downloaded or locked:**
   If your browser, torrent client, or an application (such as Word or Adobe Reader) has an open handle to the file, the organizer skips it automatically to prevent file corruption. Once closed, the file will be organized on the next scheduled run.

3. **Incomplete file extension:**
   Files ending in `.crdownload`, `.part`, `.tmp`, or `.download` are intentionally ignored until the browser finishes writing and renames the file to its final extension.

4. **File is inside a subdirectory:**
   The organizer only sorts files directly in the root of `Downloads`. It intentionally never touches folders or files inside folders (such as `Downloads\Torrents\` or `Downloads\Unpacked\`).

---

## 3. Checking Logs

If `-LogToFile` is enabled (which is the default when registered via `Register-Task.ps1`), log files are written to:

```text
%LOCALAPPDATA%\DownloadAutoSorter\organizer.log
```

To view the most recent entries in PowerShell:

```powershell
Get-Content -Path "$env:LOCALAPPDATA\DownloadAutoSorter\organizer.log" -Tail 30
```

---

## 4. Testing What Will Happen (Dry-Run Preview)

Whenever you want to test what the script would do without making any changes to disk:

```powershell
.\scripts\Sort-Downloads.ps1 -DryRun
```

This previews all planned moves with zero filesystem mutations.
