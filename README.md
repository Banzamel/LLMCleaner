<p align="center">
  <img src="docs/icon.png" width="96" alt="LLMCleaner icon">
</p>

# LLMCleaner

**Smart Windows cleanup with a local AI assistant.** LLMCleaner finds junk files, caches and leftovers of uninstalled
programs and games, shows you a plan with exact sizes, and cleans only after you confirm. An optional local AI model
explains what the leftovers were and answers your questions. The AI engine ([Ollama](https://ollama.com)) is bundled
in the program folder, so everything runs on your machine. The only network request is an optional update check
against GitHub Releases (disable it with `-BezAktualizacji`).

> LLMCleaner has a **window** (default) and a **text mode** (`-Konsola`). The interface is in **English or Polish**,
> chosen from the Windows display language (`-Jezyk en` / `-Jezyk pl` to override).

---

## Features

- **Scan first, clean later.** You tick the drives to scan and click *Scan*. The plan appears as a checklist with sizes
  and descriptions. You change it, see a summary with the space to be freed, and confirm. The default answer is *no*.
- **Whitelist-based cleanup** of things that rebuild themselves: temp files, Windows Update cache, crash dumps,
  browser caches (Chrome, Edge, Brave, Firefox: all profiles; passwords, bookmarks and sessions are kept),
  npm/pip/yarn/uv/NuGet/Composer/Go caches, GPU shader caches, thumbnails, DNS cache, old NVIDIA/AMD driver installers,
  app caches (Discord, Slack, Teams, VS Code, Spotify, Steam; each app is skipped while it is running), JetBrains IDE caches and indexes (opt-in),
  and optionally DISM, the previous Windows version (`Windows.old`, removed through Windows Disk Cleanup) and the
  Docker build cache.
- **What takes up space (`a`).** A fast scan of any drive (about 45 s for 500,000 files) lists the most specific large
  folders and the largest files, with built-in hints (WinSxS, hiberfil, WSL disks, Steam games, `node_modules`…). The
  AI can describe each item and suggest what to do. Its advice comes from a fixed list of safe options, and for
  `Windows`, `ProgramData` and `Program Files` the advice is set by the program, not by the model. This view is
  read-only: nothing from it is deleted.
- **Leftovers of uninstalled software:**
  - folders in `AppData`, `LocalLow`, `ProgramData` and `Program Files` that match no installed program,
  - Steam games removed without cleanup (folders without a manifest, shader caches, Workshop content) and Epic Games leftovers,
  - dead entries in *Apps & features* and orphaned registry keys, listed with their subkeys
    (e.g. `Klei` → *contains: Oxygen Not Included*),
  - large files in Downloads (100 MB and more) and in the user profile (1 GB and more).
- **Safe by design:**
  - leftover folders and files go to the **Recycle Bin**,
  - every registry key is **exported to a `.reg` backup** before deletion (double-click the file to restore),
    and a **System Restore point** is created first,
  - junctions and symlinks are removed as links and never followed,
  - files in use are skipped,
  - save games, large files and leftover folders that still contain `.exe` files (possibly portable programs)
    are never preselected.
- **Works on other people's PCs too:**
  - Windows installed on a drive other than `C:` is supported,
  - moved user folders (Documents in OneDrive, Downloads on another drive) are found through the Windows settings,
  - on a standard account, where UAC asks for a **different administrator's** password, LLMCleaner still cleans the
    profile, registry and Recycle Bin of the person who started it, not the administrator's,
  - the AI installer picks the ARM64 engine on ARM PCs and adds AMD (ROCm) libraries when an AMD GPU is present.
- **AI on demand.** The model never decides what gets deleted and never runs commands. It loads only when you
  ask for it: to describe what each leftover was, to describe the largest folders on a drive and suggest what to do,
  or to chat about the plan, folders and programs. AI calls run in the background, so the window stays responsive.
- **Updates.** LLMCleaner checks GitHub Releases at start. When a new version is out, one click downloads and runs
  its installer.

## Installation

### Installer (recommended)

1. Download `LLMCleaner-Setup-<version>.exe` from [Releases](https://github.com/Banzamel/LLMCleaner/releases).
2. Run it. The wizard lets you choose:
   - the **install location** (per-user by default, no admin rights needed; choose *all users* if you prefer),
   - a **desktop shortcut**,
   - the optional **AI assistant** and its **model** (`qwen3:4b-instruct` or `qwen3:8b`). The installer downloads
     the Ollama engine (about 1.4 GB) and the model (2.5–5 GB) **into the program folder** (`ai\`).
3. Start **LLMCleaner** from the Start menu or the desktop.

Everything stays inside the install folder: no separate Ollama installation, no tray icon, no autostart, no
environment variables. The AI engine runs on a private port (`11435`) only while LLMCleaner is open, so it does not
conflict with an Ollama you may have installed yourself. **Uninstalling removes the program, the AI engine and the
models.**

The installer is not code-signed, so Windows SmartScreen may show a warning on the first run
(*More info → Run anyway*).

### Portable

Download `LLMCleaner-<version>-portable.zip`, extract it anywhere and run `LLMCleaner.bat`.
To enable the AI assistant, run `Install-AI.ps1` from the same folder. It downloads Ollama and the model into an
`ai` subfolder:

```powershell
powershell -ExecutionPolicy Bypass -File Install-AI.ps1 -Model qwen3:4b-instruct
```

### Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in).
- Administrator rights when cleaning. LLMCleaner asks for them through UAC.
- Optional, for the AI assistant: about 4–7 GB of disk space in the install folder. An NVIDIA GPU with 6 GB of
  VRAM or more is recommended, though it also runs (slower) on the CPU.

## Usage

Start **LLMCleaner** from the Start menu or the desktop. The Start menu also has *LLMCleaner (preview)*, which never
deletes anything, and *LLMCleaner (console)* for the text mode.

### The window

1. **Drives** at the top: tick the drives to scan and click **Scan**.
2. **Cleanup plan** tab: tick or untick categories and leftovers. Hover over an item for its full description.
   - **AI: what were the leftovers?** fills in what each leftover was (marked *AI (may be wrong)*),
   - **Clean selected...** shows a summary and asks for confirmation.
3. **What takes up space** tab: pick a drive, click **Analyse**, then **AI: describe and advise**. Double-click an
   item to open it in File Explorer.
4. **AI assistant** tab: ask about the plan, folders, programs or games.
5. **Log** tab: everything the program does, also written to the log file.

### Parameters

```
LLMCleaner.bat                     the window
LLMCleaner.bat -Konsola            text mode (alias -Console)
LLMCleaner.bat -Podglad            preview: scan and plan only, nothing is deleted (alias -Preview)
LLMCleaner.bat -BezLLM             without the AI assistant (alias -NoAI)
LLMCleaner.bat -Model qwen3:8b     another model
LLMCleaner.bat -Dyski C,P          pre-select these drives (alias -Drives)
LLMCleaner.bat -Jezyk en           interface language: en or pl (alias -Language)
LLMCleaner.bat -BezAktualizacji    no update check at start (alias -NoUpdateCheck)
```

### Drives

LLMCleaner lists local fixed drives with a letter. USB drives, memory cards, network drives and partitions without
a letter (EFI, Recovery) are skipped, as are BitLocker-locked volumes. All drives are ticked by default; the system
drive is always scanned (Windows caches, user profile, Program Files). The other ticked drives are used for the
Recycle Bin, Steam and Epic libraries, and the *what takes up space* view.

### Text mode keys

The first screen asks which drives to scan: `Enter` continues, numbers toggle drives. On the plan screen:

| Key | Action |
|---|---|
| `Enter` | go to the summary and the *start cleaning? [y/N]* question |
| `3` or `3 7 9` | toggle categories or leftovers by number |
| `w` | AI describes what each leftover was |
| `p` | chat with the assistant; an empty line returns to the plan |
| `a` | what takes up space on a drive; then `w` lets the AI describe the items |
| `u` | install the new version (shown only when an update is available) |
| `q` | quit without deleting anything |

### What gets preselected

| Item | Rule |
|---|---|
| Cleanup categories | any non-empty category, however small. The Recycle Bin (irreversible), DNS, JetBrains indexes, `Windows.old`, DISM and Docker are never preselected |
| Leftovers, *high* confidence | Steam/Epic leftovers, dead uninstall entries, folders unchanged for 180 days or more |
| Leftovers, *medium* confidence | folders unchanged for 30–180 days, orphaned registry keys |
| Leftovers, *low* confidence | save games, large files: **never preselected** |

A folder is **not** treated as a leftover when its name or path matches an installed program, a Microsoft Store app,
a service, a running process, a Start menu or desktop shortcut, or an installed Steam game. It is also skipped when it
was modified in the last 30 days or is on the built-in list of system and driver folders
(`$PomijaneNazwy` in the script).

## Files and logs

| Path | Contents |
|---|---|
| install folder | `LLMCleaner.ps1` (start), `lib\Rdzen.ps1` (scanning, plan, AI, cleaning), `lib\Okno.ps1` (window), `lib\Konsola.ps1` (text mode), `LLMCleaner.bat`, `Install-AI.ps1`, `config.json` (the model chosen in the installer) |
| `<install folder>\ai\ollama\` | the bundled Ollama engine |
| `<install folder>\ai\models\` | AI models |
| `%LOCALAPPDATA%\LLMCleaner\logs\` | one log per run: scan report, chosen plan, results, everything moved to the Recycle Bin |
| `%LOCALAPPDATA%\LLMCleaner\logs\kopie_rejestru\` | `.reg` backups of deleted registry keys |

Logs and registry backups are kept after you uninstall the program.

## About the AI part

The assistant is deliberately limited. During development a 4B model planned the cleanup by itself. The result
was almost identical to a simple size rule, but it took 50–100 seconds and some explanations were wrong. When asked
about game studios, the model also invented titles. That is why:

- the plan is built by rules and the scanner provides the facts (sizes, dates, registry subkeys),
- the model only describes and answers, and is told not to add facts that are not in the data,
- its descriptions are labelled *AI (may be wrong)*,
- its advice in the disk analysis comes from a fixed list of safe options, and for system and program folders the
  program sets the advice itself.

| Model | Notes (tested on a GTX 1060 6 GB) |
|---|---|
| `qwen3:4b-instruct` | **recommended**, runs fully on the GPU, `w` takes about 30–60 s |
| `qwen3:8b` | does not fit into 6 GB VRAM, about 3× slower; worth it with 8 GB or more |

## Troubleshooting

| Problem | Fix |
|---|---|
| *The AI assistant is not installed* (*Asystent AI nie jest zainstalowany*) | rerun the installer and tick the AI assistant, or run `Install-AI.ps1` from the install folder |
| *Could not start Ollama* (*Nie udało się uruchomić Ollamy*) | run `ai\ollama\ollama.exe serve` from the install folder and check the output |
| *Model … is missing* (*Brak modelu …*) | `Install-AI.ps1 -Model qwen3:4b-instruct` |
| AI answers take minutes | the model probably does not fit into the VRAM (check *Dedicated GPU memory* in Task Manager); close games or other GPU-heavy programs |
| Browser cache skipped | close the browser (also from the system tray) and run again |
| Garbled Polish characters | the `.ps1` files must be saved as **UTF-8 with BOM** |
| Taskbar did not come back | `Ctrl+Shift+Esc` → File → Run new task → `explorer.exe` |
| A registry key was needed after all | double-click its `.reg` file in `logs\kopie_rejestru\`, or use the *LLMCleaner* System Restore point |
| Restore point *skipped by Windows* (*pominięty przez Windows*) | Windows creates at most one restore point per 24 hours by default; the `.reg` backups are still made |
| App cache *skipped - running: …* (*pominięto - działa: …*) | close the app (also from the system tray) and run again |

## Building from source

The installer is built by GitHub Actions on every `v*` tag (see `.github/workflows/release.yml`). To build it locally:

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.0 installer\LLMCleaner.iss
```

To release, bump `$Wersja` in `LLMCleaner.ps1`, update `CHANGELOG.md`, then tag:

```powershell
git tag -a v1.0.1 -m "LLMCleaner 1.0.1"
git push origin main --tags
```

The workflow fails if the tag does not match `$Wersja`.

## License

[MIT](LICENSE)
