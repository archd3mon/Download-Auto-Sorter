# Roadmap & Future Refinements

This document tracks planned features, enhancements, and design ideas for future development sessions.

---

## 1. One-Click Undo (`Undo-Sort.ps1`)
- **Concept:** Reversible mutations by recording moves in a lightweight JSON Lines log (`%LOCALAPPDATA%\DownloadAutoSorter\history.jsonl`).
- **Features:**
  - Record: `Timestamp`, `OriginalPath`, `DestinationPath`.
  - Provide `.\scripts\Undo-Sort.ps1` that moves the last batch of sorted files back to the `Downloads` root.
  - Support `-Batches <int>` (undo last N runs).
  - Safety check: ensure the file at `DestinationPath` hasn't been modified or deleted before moving it back.

---

## 2. External Configuration File (`config.json`)
- **Concept:** Decouple user customization from the core PowerShell script.
- **Features:**
  - Optional `config.json` in project directory or `%LOCALAPPDATA%\DownloadAutoSorter\config.json`.
  - Fallback to built-in default rules if the file is absent.
  - Allows easy customization of:
    - Target categories and extensions.
    - Ignored filenames and temporary extensions.
    - `MinAgeSeconds` threshold.
    - Custom download paths.

---

## 3. Whitelist / Ignore File (`.sorterignore`)
- **Concept:** Allow users to keep specific loose files in the `Downloads` root without getting sorted.
- **Features:**
  - Read from `%USERPROFILE%\Downloads\.sorterignore` or `.organizerignore`.
  - Support glob/wildcard patterns (e.g., `todo.txt`, `current_project*`, `*.keep`).
  - Safe parsing without external dependencies.

---

## 4. Windows Explorer Right-Click Context Menu
- **Concept:** Trigger an immediate sort from the Windows File Explorer GUI.
- **Features:**
  - Provide a setup script (`scripts/Install-ContextMenu.ps1`) and removal script (`scripts/Uninstall-ContextMenu.ps1`).
  - Adds a right-click option on the `Downloads` folder: *"Sort Downloads Now"*.
  - Runs with `-WindowStyle Hidden` and `-Apply` in the background.

---

## 5. Windows Native Toast Notifications (Optional)
- **Concept:** Provide subtle visual feedback when files are sorted in the background.
- **Features:**
  - Uses native Windows 10/11 WinRT / PowerShell notification API without third-party tools.
  - Triggered *only* when files were actually moved (silent when 0 files organized).
  - Shows count of organized files (e.g., *"Downloads Auto Sorter: 3 files organized"*).
  - Controlled by a `-Notify` switch or configuration setting.

---

## 6. Date-Based Subfolders (Year / Month Grouping)
- **Concept:** Prevent high-volume folders from cluttering over long periods.
- **Features:**
  - Option to route files to `Category\YYYY-MM` (e.g., `Documents\2026-10\report.pdf` or `Installers\2026\setup.exe`).
  - Configurable per category (e.g., enable for `Installers` and `Images`, keep flat for `Development`).
