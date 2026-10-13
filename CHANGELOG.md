# Changelog

## Unreleased

- **Fixed: the plan counted files that cleaning cannot delete.** Category sizes now leave out files the cleanup skips:
  CBS/DISM logs from the last 7 days and large files used by another program, such as the WSL/Docker `swap.vhdx` in
  TEMP (often several GB). The plan says how much was left out and which files.
- TEMP is cleaned completely, not only files older than 24 hours. Files in use are still skipped.

## 1.3.0 (2026-10-13)

- **New, modern window.** A dark navigation bar on the left (Overview, Cleanup plan, What takes up space, AI assistant,
  Log) instead of tabs, pages built from cards with rounded corners, flat buttons and taller list rows.
- **Overview page**: drive tiles with a usage bar (click a tile to tick it), one big **Scan** button, the current scan
  step, and after the scan a summary: how much can be freed, categories with data and program leftovers.
  With many partitions the tiles wrap and scroll; nothing covers their names any more.
- The chat field shows a hint, and the Preview mode and AI status are shown in the navigation bar.
- **Fixed: the scan stopped with "Argument types do not match"** on some PCs. A PowerShell 5.1 quirk with lists
  created by `New-Object`; they are now created with `::new()`.
- An item that cannot be read (an odd folder, registry key or broken shortcut) is skipped and logged instead of
  stopping the whole scan. The Log page shows how many items were skipped.
- The AI chat works before a scan too (general answers); the chat page says that a scan is needed for questions about
  the files on this computer.

## 1.2.1 (2026-10-12)

- Small junk is no longer skipped: every non-empty cleanup category is preselected (previously 20 MB or more),
  leftover folders smaller than 1 MB are listed, and the lists of leftover folders and registry keys are no longer
  cut to 30 and 20 entries.

## 1.2.0 (2026-10-12)

- **Window interface** (Windows Forms, built into Windows) is now the default: drive selection, the cleanup plan as a
  checklist, *What takes up space*, the AI assistant and the log in tabs. AI calls run in the background, so the window
  stays responsive. The text interface is still available with `-Konsola`.
- **English interface.** The language follows the Windows display language; override it with `-Jezyk en` or `-Jezyk pl`.
  The AI answers in the same language. Parameters have English aliases (`-Console`, `-Preview`, `-NoAI`, `-Drives`,
  `-Language`, `-NoUpdateCheck`).
- The code is split into `lib\Rdzen.ps1` (scanning, plan, AI, cleaning), `lib\Okno.ps1` (window) and `lib\Konsola.ps1`
  (text mode).
- The AI chat gets the plan sorted by size, so it answers questions like *what is the largest item* correctly.
- The Start menu has three shortcuts: the window, preview mode and the text mode.

## 1.1.0 (2026-10-12)

- **What takes up space** (`a` on the plan screen): a fast scan of any drive lists the most specific large folders and
  the largest files with built-in hints. `w` lets the AI describe them and suggest what to do. The advice comes from a
  fixed list of safe options, and for system and program folders the program sets it. The view is read-only.
- New cleanup categories:
  - app caches: Discord, Slack, Teams, VS Code, Spotify and Steam, each skipped while it is running,
  - JetBrains IDE caches and indexes (opt-in, because the IDE has to re-index projects afterwards),
  - old NVIDIA and AMD driver installers,
  - the previous Windows version (`Windows.old`, `$WINDOWS.~BT`), removed through Windows Disk Cleanup and never
    preselected,
  - Composer and Go build caches in the developer category.
- A System Restore point is created before registry keys are deleted, in addition to the `.reg` backups.
- Update check at start (GitHub Releases); `u` downloads and runs the new installer. Disable it with `-BezAktualizacji`.
- Drive selection at start (or `-Dyski C,P`): the ticked drives are used for the Recycle Bin, Steam and Epic libraries
  and the disk analysis. The system drive is always scanned.
- Works on more PCs:
  - Windows on a drive other than `C:`,
  - moved user folders (OneDrive, Downloads on another drive),
  - standard accounts elevated with another administrator's password (the starting user's profile, registry and
    Recycle Bin are cleaned),
  - ARM64 and AMD GPU support in the AI installer.
- Only the current user's Recycle Bin is measured and emptied.
- Leftover folders that contain `.exe` files get *low* confidence and are not preselected (possible portable programs).

## 1.0.0 (2026-10-12)

First public release.

- Scan → plan → summary → confirmation flow; the default answer is *no*.
- Whitelist cleanup: temp files, Windows Update cache, crash dumps, CBS/DISM logs, browser caches
  (Chrome, Edge, Brave, Firefox), developer caches, GPU shader caches, thumbnails, DNS, and optionally DISM and Docker.
- Leftovers of uninstalled software: orphaned program folders, Steam and Epic game leftovers, dead uninstall entries,
  orphaned registry keys with their subkeys, and large files in Downloads.
- Leftover folders and files go to the Recycle Bin; registry keys are backed up to `.reg` before deletion.
- Optional local AI assistant, loaded on demand: `w` describes leftovers, `p` answers questions. The AI engine
  (Ollama) and the model live in the program's `ai` folder and run on a private port only while LLMCleaner is open.
- Installer with a setup wizard (install location, desktop shortcut, optional AI assistant with model choice)
  and a portable zip, both built by GitHub Actions. Uninstalling removes the AI engine and models too.
