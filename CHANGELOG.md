# Changelog

## 1.5.3 (2026-10-14)

- **Fixed: cleaning stopped with an error after the Docker step when it freed more than about 2.1 GB.** The cleanup
  itself ran, but the freed space could not be counted and the remaining steps did not run. The same fix covers the
  Windows.old and WinSxS steps.

## 1.5.2 (2026-10-14)

- **Fixed: the window crashed while drawing the cleanup plan when one item was larger than about 2.1 GB** (for example
  Docker images). The size bars and the taskbar progress now compute in 64-bit.

## 1.5.1 (2026-10-14)

- **Remove a startup entry permanently**: the bin next to the switch on the *Startup apps* page deletes the entry after
  a confirmation. A Run entry gets a `.reg` backup of just that value, a Startup folder shortcut goes to the Recycle Bin
  and a task gets an `.xml` backup. The program itself is not uninstalled.
- **Fixed: entries marked as dead that were not in the cleanup plan.** The *Startup apps* page called an entry dead
  whenever its target file was missing, including Windows Installer shortcuts with no target and commands without a
  full path. It now uses the same rule as the plan. The list also reloads after cleaning.
- **Docker - everything unused** (opt-in): `docker system prune -a --volumes` removes stopped containers, images
  without a container, unused volumes (including databases in them), networks and the build cache. Both Docker
  categories now show their size from `docker system df` (reclaimable space) and say when Docker is not running.

## 1.5.0 (2026-10-14)

- **Refreshed window, built from the accepted mockups.**
  - **Overview**: a large *can be freed* figure with **View the cleanup plan** and **Clean now...**, four tiles
    (categories with data, leftovers, locked, startup apps), a bar chart of what takes up the space (grey = not
    selected), drives with usage bars, and a *Windows startup* card that links to the startup apps.
  - **Cleanup plan**: search, an *All / Selected / Opt-in* filter, **Select recommended** and **Clear selection**,
    and rows with a type badge (category, folder, file, shortcut, registry, task), two lines of text, a size bar and a
    confidence label. Click a row to tick it. The bottom bar shows the selected total, the item count and the locked
    size.
  - **Startup apps**: a switch on every row that works at once, like Task Manager, with tiles for on, off and
    protected, and the AI description under each program. Protected items show a lock label and their switch is
    disabled.
  - **Cleaning progress screen**: every step with its status (done, in progress, waiting, skipped), the freed space
    and a progress bar, also on the taskbar icon. At the end it shows what was freed, free space before and after,
    backups, the restore point and what was skipped. The window cannot be closed while cleaning runs.
- **Dark mode** that follows the Windows app setting, including a dark title bar and scroll bars.
- **Sharp at 125–200% display scaling**: the window scales itself instead of being blurred by Windows.
- The window remembers its size, position and last page. **F5** scans, **Ctrl+1** to **Ctrl+6** switch pages.

## 1.4.0 (2026-10-14)

- **Startup apps page** (window) and `s` (text mode): programs that start at sign-in from the Run registry keys,
  the Startup folders and Task Scheduler tasks with a sign-in or boot trigger, with their publisher, source and
  command. Turning a program off works like Task Manager (the `StartupApproved` switch) or disables the task, so
  nothing is removed and *Turn on* restores it. Security software, drivers, hardware panels, updaters and parts of
  Windows are read-only. **AI: what is it?** describes each program; its advice comes from a fixed list, and for
  protected items the program sets it.
- **Dead startup entries are leftovers now**: Run entries, shortcuts (Startup folders, Start menu, desktop) and
  Task Scheduler tasks that point to a program that no longer exists. Shortcuts go to the Recycle Bin, Run entries
  get a `.reg` backup of just that value, tasks an `.xml` backup (Task Scheduler > Import Task). Paths on a missing
  drive, network paths and paths in the Windows folder are never treated as dead.
- **Older driver versions (DriverStore)**, opt-in: driver packages replaced by a newer version of the same driver,
  often old graphics drivers of 1-5 GB. The newest version and every driver in use are kept, and `pnputil` removes
  the rest without `/force`. A System Restore point is created first.
- New cleanup locations: `Windows\LiveKernelReports` (driver crash reports, often several GB) in *Error reports*,
  Gradle, Cargo and Bun caches in *Developer tool caches*, and Epic Games Launcher and Battle.net in *App caches*.
- The System Restore point is now created once at the start of cleaning whenever registry entries, tasks or
  drivers are about to change.
- After a scan, the AI chat also knows the startup apps once their page has been opened.

## 1.3.1 (2026-10-13)

- **Fixed: the plan counted files that cleaning cannot delete.** Category sizes now leave out files the cleanup skips:
  CBS/DISM logs from the last 7 days and files locked by another program, such as the WSL/Docker `swap.vhdx` in TEMP
  (often several GB).
- **Locked files are shown separately.** The plan has a *Locked* column next to *Deletable*, the description gives the
  total split into deletable and locked with the largest locked files, the overview has a *locked* tile and the summary
  before cleaning lists the locked size. Every file is checked the way deletion opens it (DELETE access only), which is
  fast and does not trigger the antivirus.
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
