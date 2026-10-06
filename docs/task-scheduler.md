# Windows Task Scheduler Setup Guide

This guide describes how to automate `Sort-Downloads.ps1` using Windows Task Scheduler.

---

## Quick Setup (Automated via Script)

Run the included registration script in PowerShell (no administrator privileges needed):

```powershell
.\scripts\Register-Task.ps1
```

By default, this configures:
- **Task Name:** `DownloadAutoSorter`
- **Schedule:** Triggers every 5 minutes indefinitely
- **Window:** Hidden (`-WindowStyle Hidden`) so no popups appear
- **User Context:** Current logged-in user account
- **Logging:** Enabled to `%LOCALAPPDATA%\DownloadAutoSorter\organizer.log`

### Custom Options

```powershell
# Run every 10 minutes instead of 5
.\scripts\Register-Task.ps1 -IntervalMinutes 10

# Test run immediately after registration
.\scripts\Register-Task.ps1 -RunNow

# Adjust stability window (e.g. wait 5 minutes before moving files)
.\scripts\Register-Task.ps1 -MinAgeSeconds 300
```

---

## Removing the Scheduled Task

To remove the scheduled task cleanly:

```powershell
.\scripts\Unregister-Task.ps1
```

---

## Manual Setup via Windows GUI (Task Scheduler)

If you prefer to configure the task through the graphical interface:

1. Press `Win + R`, type `taskschd.msc`, and press **Enter**.
2. Click **Create Task...** on the right sidebar.
3. Under the **General** tab:
   - **Name:** `DownloadAutoSorter`
   - **Security options:** Select *"Run only when user is logged on"* (requires no password).
4. Under the **Triggers** tab:
   - Click **New...**
   - **Begin the task:** *At log on* (or *On a schedule*)
   - Under **Advanced settings**, check **Repeat task every:** `5 minutes`
   - **for a duration of:** `Indefinitely`
   - Click **OK**.
5. Under the **Actions** tab:
   - Click **New...**
   - **Action:** *Start a program*
   - **Program/script:** `powershell.exe`
   - **Add arguments:**
     ```text
     -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Path\To\Sort-Downloads.ps1" -Apply -LogToFile -Quiet
     ```
   - Click **OK**.
6. Under the **Settings** tab:
   - Check *"Allow task to be run on demand"*
   - Check *"Run task as soon as possible after a scheduled start is missed"*
   - Under *"If the task is already running, then the following rule applies:"*, select **Do not start a new instance**.
7. Click **OK** to save.

---

## Verifying Task Execution

You can check whether the task is executing successfully:

1. **Check Task Status in Task Scheduler:**
   - Look for `DownloadAutoSorter` in the Task Scheduler Library.
   - Verify that **Last Run Result** shows `0x0` (success).

2. **Inspect the Activity Log:**
   ```powershell
   Get-Content "$env:LOCALAPPDATA\DownloadAutoSorter\organizer.log" -Tail 20
   ```
