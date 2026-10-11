<p align="center">
  <img src="docs/icon.png" width="96" alt="LLMCleaner icon">
</p>

# LLMCleaner

**Smart Windows cleanup with a local AI assistant.** LLMCleaner finds junk files, caches and leftovers of uninstalled
programs and games, shows you a plan with exact sizes, and cleans only after you confirm. An optional local AI model
(via [Ollama](https://ollama.com)) explains what the leftovers were and answers your questions. Everything runs on
your machine, and nothing is sent to the internet.

> The program interface is in **Polish**. This README is in English.

---

## Features

- **Scan first, clean later.** A plan appears about 10 seconds after start. You review it, change it, see a summary
  with the space to be freed, and confirm with `t` (yes). The default answer is *no*.
- **Whitelist-based cleanup** of things that rebuild themselves: temp files, Windows Update cache, crash dumps,
  browser caches (Chrome, Edge, Brave, Firefox: all profiles; passwords, bookmarks and sessions are kept),
  npm/pip/yarn/uv/NuGet caches, GPU shader caches, thumbnails, DNS cache, and optionally DISM and the Docker build cache.
- **Leftovers of uninstalled software:**
  - folders in `AppData`, `LocalLow`, `ProgramData` and `Program Files` that match no installed program,
  - Steam games removed without cleanup (folders without a manifest, shader caches, Workshop content) and Epic Games leftovers,
  - dead entries in *Apps & features* and orphaned registry keys, listed with their subkeys
    (e.g. `Klei` → *contains: Oxygen Not Included*),
  - large files in Downloads (100 MB and more) and in the user profile (1 GB and more).
- **Safe by design:**
  - leftover folders and files go to the **Recycle Bin**,
  - every registry key is **exported to a `.reg` backup** before deletion (double-click the file to restore),
  - junctions and symlinks are removed as links and never followed,
  - files in use are skipped,
  - save games and large files are never preselected.
- **AI on demand.** The model never decides what gets deleted and never runs commands. It loads only when you
  ask for it:
  - `w`: describe what each leftover was,
  - `p`: chat about the plan, folders and programs.

## Installation

### Installer (recommended)

1. Download `LLMCleaner-Setup-<version>.exe` from [Releases](https://github.com/Banzamel/LLMCleaner/releases).
2. Run it. The wizard lets you choose:
   - the **install location** (per-user by default, no admin rights needed; choose *all users* if you prefer),
   - a **desktop shortcut**,
   - the optional **AI assistant**: installs Ollama if missing, lets you pick the **model**
     (`qwen3:4b-instruct` or `qwen3:8b`) and the **folder for models** (sets `OLLAMA_MODELS`).
3. Start **LLMCleaner** from the Start menu or the desktop.

The installer is not code-signed, so Windows SmartScreen may show a warning on the first run
(*More info → Run anyway*).

### Portable

Download `LLMCleaner-<version>-portable.zip`, extract it anywhere and run `LLMCleaner.bat`.
To enable the AI assistant, run `Install-AI.ps1` from the same folder:

```powershell
powershell -ExecutionPolicy Bypass -File Install-AI.ps1 -Model qwen3:4b-instruct -ModelDir D:\Ollama\models
```

### Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in).
- Administrator rights when cleaning. LLMCleaner asks for them through UAC.
- Optional, for the AI assistant: [Ollama](https://ollama.com) and about 3–6 GB of disk space. A GPU with 6 GB of
  VRAM or more is recommended, though it also runs (slower) on the CPU.

## Usage

```
LLMCleaner.bat              normal run: scan → plan → summary → confirm
LLMCleaner.bat -Podglad     preview: scan and plan only, nothing is deleted
LLMCleaner.bat -BezLLM      without the AI assistant
LLMCleaner.bat -Model qwen3:8b
```

### The plan screen

| Key | Action |
|---|---|
| `Enter` | go to the summary and the *Uruchomić czyszczenie? [t/N]* (start cleaning?) question |
| `3` or `3 7 9` | toggle categories or leftovers by number |
| `w` | AI describes what each leftover was (marked *AI (może się mylić)*, "AI, may be wrong") |
| `p` | chat with the assistant; an empty line returns to the plan |
| `q` | quit without deleting anything |

### What gets preselected

| Item | Rule |
|---|---|
| Cleanup categories | 20 MB or more. The Recycle Bin (irreversible), DNS, DISM and Docker are never preselected |
| Leftovers, *high* confidence | Steam/Epic leftovers, dead uninstall entries, folders unchanged for 180 days or more |
| Leftovers, *medium* confidence | folders unchanged for 30–180 days, orphaned registry keys |
| Leftovers, *low* confidence | save games, large files: **never preselected** |

A folder is **not** treated as a leftover when its name or path matches an installed program, a Microsoft Store app,
a service, a running process, a Start menu or desktop shortcut, or an installed Steam game. It is also skipped when it
was modified in the last 30 days, is smaller than 1 MB, or is on the built-in list of system and driver folders
(`$PomijaneNazwy` in the script).

## Files and logs

| Path | Contents |
|---|---|
| install folder | `LLMCleaner.ps1`, `LLMCleaner.bat`, `Install-AI.ps1`, `config.json` (the model chosen in the installer) |
| `%LOCALAPPDATA%\LLMCleaner\logs\` | one log per run: scan report, chosen plan, results, everything moved to the Recycle Bin |
| `%LOCALAPPDATA%\LLMCleaner\logs\kopie_rejestru\` | `.reg` backups of deleted registry keys |

Logs and registry backups are kept after you uninstall the program.

## About the AI part

The assistant is deliberately limited. During development a 4B model planned the cleanup by itself. The result
was almost identical to a simple size rule, but it took 50–100 seconds and some explanations were wrong. When asked
about game studios, the model also invented titles. That is why:

- the plan is built by rules and the scanner provides the facts (sizes, dates, registry subkeys),
- the model only describes and answers, and is told not to add facts that are not in the data,
- its descriptions are labelled *AI (może się mylić)*.

| Model | Notes (tested on a GTX 1060 6 GB) |
|---|---|
| `qwen3:4b-instruct` | **recommended**, runs fully on the GPU, `w` takes about 30–60 s |
| `qwen3:8b` | does not fit into 6 GB VRAM, about 3× slower; worth it with 8 GB or more |

## Troubleshooting

| Problem | Fix |
|---|---|
| *Nie udało się uruchomić Ollamy* (Ollama failed to start) | run `ollama serve` manually and check the output; logs are in `%LOCALAPPDATA%\Ollama\` |
| *Brak modelu …* (model missing) | `ollama pull qwen3:4b-instruct` |
| `w` / `p` takes minutes | run `ollama ps`; if the PROCESSOR column shows CPU, something else is using the VRAM |
| Browser cache skipped | close the browser (also from the system tray) and run again |
| Garbled Polish characters | `LLMCleaner.ps1` must be saved as **UTF-8 with BOM** |
| Taskbar did not come back | `Ctrl+Shift+Esc` → File → Run new task → `explorer.exe` |
| A registry key was needed after all | double-click its `.reg` file in `logs\kopie_rejestru\` |

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
