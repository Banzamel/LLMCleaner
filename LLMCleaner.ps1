<#
    LLMCleaner - smart Windows cleanup with a local language model (Ollama)
    Started BY HAND (desktop shortcut). It never adds itself to startup.

    How it works:
      1. The user picks drives. The scanner measures whitelisted junk categories and looks for leftovers
         of uninstalled programs and games (folders, large files, registry keys).
      2. Rules build the plan: non-empty categories and leftovers with high/medium confidence.
      3. The local model loads only ON DEMAND: it describes leftovers and the disk analysis
         ("what takes up space") and answers questions. It never decides what to delete and runs nothing.
      4. Summary and confirmation. Folders and files go to the Recycle Bin; a system restore point
         and a .reg backup are made before registry keys are removed.

    Files:
      lib\Core\          scanning, plan, AI, cleanup (no user interface)
      lib\Gui\           graphical window (default), pages in lib\Gui\Pages\
      lib\Console\       text interface (-Console)
      lib\*\cs\          C# snippets compiled by Add-Type

    Parameters:
      -Console          text interface instead of the window (alias -Konsola)
      -Preview          scan and plan only, nothing is deleted (alias -Podglad)
      -NoAI             turns off the AI assistant (alias -BezLLM)
      -Model            Ollama model (default from config.json next to the script, else qwen3:4b-instruct)
      -Drives           drives to scan, e.g. -Drives C,P (alias -Dyski)
      -Language         pl or en (default: Windows language; alias -Jezyk)
      -NoUpdateCheck    skips the GitHub new-version check at startup (alias -BezAktualizacji)

    https://github.com/Banzamel/LLMCleaner - MIT license
#>
param(
    [Alias('Konsola')][switch]$Console,
    [Alias('Podglad')][switch]$Preview,
    [Alias('BezLLM')][switch]$NoAI,
    [string]$Model,
    [Alias('BezAktualizacji')][switch]$NoUpdateCheck,
    [Alias('Dyski')][string[]]$Drives,
    [Alias('Jezyk')][ValidateSet('', 'pl', 'en')][string]$Language = '',
    [string]$Sid      # account that started the program (set by elevation)
)

$Version = '1.6.4'
$ErrorActionPreference = 'SilentlyContinue'
$AppDir = $PSScriptRoot

# Settings page values (settings.json); command-line parameters win
. (Join-Path $AppDir 'lib\Core\Config.ps1')
$Config = Read-Config
$PreviewFromParam = [bool]$Preview   # "preview" shortcut - kept after a restart from Settings
if (-not $Language -and $Config.Language -in 'pl', 'en') { $Language = $Config.Language }
if (-not $Model -and $Config.Model) { $Model = "$($Config.Model)" }
if ($Config.Assistant -eq $false) { $NoAI = [switch]$true }
if ($Config.CheckUpdates -eq $false) { $NoUpdateCheck = [switch]$true }
if ($Config.Preview -eq $true) { $Preview = [switch]$true }

# UI language: Polish on Polish Windows, English otherwise
if (-not $Language) { $Language = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'pl') { 'pl' } else { 'en' } }

# Model chosen in the installer (config.json next to the script) unless -Model was given
if (-not $Model) { $Model = Get-InstallerModel }

# ---------- ELEVATION ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host $(if ($Language -eq 'en') { 'LLMCleaner needs administrator rights - elevating...' } else { 'LLMCleaner wymaga uprawnień administratora - podnoszę...' }) -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $Console) { $argList += '-WindowStyle', 'Hidden' }   # the window needs no console
    $argList += '-File', "`"$PSCommandPath`"", '-Model', "`"$Model`"", '-Language', $Language
    if ($Console) { $argList += '-Console' }
    if ($Preview) { $argList += '-Preview' }
    if ($NoAI) { $argList += '-NoAI' }
    if ($NoUpdateCheck) { $argList += '-NoUpdateCheck' }
    if ($Drives) { $argList += '-Drives', ($Drives -join ',') }
    # If UAC asks for ANOTHER admin account, the script must know whose profile to clean
    $argList += '-Sid', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

# Program files in load order. They are dot-sourced into this script, so they share
# its variables ($Language, $Preview, $script:...) - that is why they are not .psm1 modules.
$CoreFiles = @(
    'Core\Output.ps1', 'Core\User.ps1', 'Core\Common.ps1', 'Core\Files.ps1', 'Core\Categories.ps1', 'Core\Drives.ps1',
    'Core\Scanner.ps1', 'Core\Leftovers.ps1', 'Core\Games.ps1', 'Core\StartupDead.ps1', 'Core\LeftoverScan.ps1',
    'Core\Startup.ps1', 'Core\StartupAi.ps1', 'Core\Plan.ps1', 'Core\Ollama.ps1', 'Core\Assistant.ps1',
    'Core\DiskAnalysis.ps1', 'Core\Updates.ps1', 'Core\Drivers.ps1', 'Core\Cleanup.ps1'
)
$GuiFiles = @(
    'Gui\Base.ps1', 'Gui\Theme.ps1', 'Gui\Output.ps1', 'Gui\Drawing.ps1', 'Gui\Controls.ps1', 'Gui\List.ps1',
    'Gui\State.ps1', 'Gui\Pages\Overview.ps1', 'Gui\Pages\PlanRows.ps1', 'Gui\Pages\Plan.ps1', 'Gui\Pages\Analysis.ps1',
    'Gui\Pages\Startup.ps1', 'Gui\Pages\Drivers.ps1', 'Gui\Pages\Cleanup.ps1', 'Gui\Pages\Chat.ps1',
    'Gui\Pages\Log.ps1', 'Gui\Pages\Settings.ps1', 'Gui\Navigation.ps1', 'Gui\Placement.ps1', 'Gui\Window.ps1'
)
$ConsoleFiles = @(
    'Console\Common.ps1', 'Console\Drives.ps1', 'Console\Plan.ps1', 'Console\Chat.ps1', 'Console\Analysis.ps1',
    'Console\Startup.ps1', 'Console\Drivers.ps1', 'Console\Main.ps1'
)

foreach ($libFile in $CoreFiles) { . (Join-Path $AppDir "lib\$libFile") }
if ($Console) {
    foreach ($libFile in $ConsoleFiles) { . (Join-Path $AppDir "lib\$libFile") }
    Start-Console
}
else {
    foreach ($libFile in $GuiFiles) { . (Join-Path $AppDir "lib\$libFile") }
    Show-MainWindow
}
