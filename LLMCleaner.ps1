<#
    LLMCleaner - inteligentne czyszczenie Windows z lokalnym modelem jezykowym (Ollama)
    Uruchamiany RECZNIE (skrot na pulpicie). Nie dodaje sie do autostartu.

    Jak dziala:
      1. Uzytkownik wybiera dyski. Skaner mierzy kategorie smieci z bialej listy i szuka pozostalosci
         po odinstalowanych programach i grach (foldery, duze pliki, klucze rejestru).
      2. Plan ukladaja reguly: niepuste kategorie oraz pozostalosci o pewnosci wysokiej/sredniej.
      3. Lokalny model laduje sie dopiero NA ZADANIE: opisuje pozostalosci, analize dysku
         ("co zajmuje miejsce") i odpowiada na pytania. Nie decyduje o usuwaniu i niczego nie wykonuje.
      4. Podsumowanie i potwierdzenie. Foldery i pliki ida do Kosza, przed usunieciem kluczy rejestru
         powstaje punkt przywracania systemu i kopia .reg.

    Pliki:
      lib\Rdzen.ps1     skanowanie, plan, AI, czyszczenie
      lib\Okno.ps1      okno graficzne (domyslnie)
      lib\Konsola.ps1   interfejs tekstowy (-Konsola)

    Parametry:
      -Konsola          interfejs tekstowy zamiast okna (alias -Console)
      -Podglad          tylko skan i plan, nic nie jest usuwane (alias -Preview)
      -BezLLM           wylacza asystenta AI (alias -NoAI)
      -Model            model Ollama (domyslnie z config.json obok skryptu, inaczej qwen3:4b-instruct)
      -Dyski            dyski do skanowania, np. -Dyski C,P (alias -Drives)
      -Jezyk            pl albo en (domyslnie jezyk Windows; alias -Language)
      -BezAktualizacji  nie sprawdza przy starcie, czy jest nowa wersja na GitHubie (alias -NoUpdateCheck)

    https://github.com/Banzamel/LLMCleaner - licencja MIT
#>
param(
    [Alias('Console')][switch]$Konsola,
    [Alias('Preview')][switch]$Podglad,
    [Alias('NoAI')][switch]$BezLLM,
    [string]$Model,
    [Alias('NoUpdateCheck')][switch]$BezAktualizacji,
    [Alias('Drives')][string[]]$Dyski,
    [Alias('Language')][ValidateSet('', 'pl', 'en')][string]$Jezyk = '',
    [string]$Sid      # konto, ktore uruchomilo program (ustawia samo podnoszenie uprawnien)
)

$Wersja = '1.6.0'
$ErrorActionPreference = 'SilentlyContinue'
$AppDir = $PSScriptRoot

# Jezyk interfejsu: polski dla polskiego Windows, w pozostalych przypadkach angielski
if (-not $Jezyk) { $Jezyk = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'pl') { 'pl' } else { 'en' } }

# Model wybrany w instalatorze (config.json obok skryptu), chyba ze podano -Model
if (-not $Model) {
    $cfg = Join-Path $AppDir 'config.json'
    if (Test-Path -LiteralPath $cfg) { $Model = (Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).model }
    if (-not $Model) { $Model = 'qwen3:4b-instruct' }
}

# ---------- UPRAWNIENIA ----------
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $adm) {
    Write-Host $(if ($Jezyk -eq 'en') { 'LLMCleaner needs administrator rights - elevating...' } else { 'LLMCleaner wymaga uprawnień administratora - podnoszę...' }) -ForegroundColor Yellow
    $argumenty = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $Konsola) { $argumenty += '-WindowStyle', 'Hidden' }   # okno graficzne nie potrzebuje konsoli
    $argumenty += '-File', "`"$PSCommandPath`"", '-Model', "`"$Model`"", '-Jezyk', $Jezyk
    if ($Konsola) { $argumenty += '-Konsola' }
    if ($Podglad) { $argumenty += '-Podglad' }
    if ($BezLLM) { $argumenty += '-BezLLM' }
    if ($BezAktualizacji) { $argumenty += '-BezAktualizacji' }
    if ($Dyski) { $argumenty += '-Dyski', ($Dyski -join ',') }
    # Gdy UAC poprosi o haslo INNEGO konta administratora, skrypt musi wiedziec, czyj profil sprzatac
    $argumenty += '-Sid', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argumenty
    exit
}

. (Join-Path $AppDir 'lib\Rdzen.ps1')
if ($Konsola) {
    . (Join-Path $AppDir 'lib\Konsola.ps1')
    UruchomKonsole
}
else {
    . (Join-Path $AppDir 'lib\Okno.ps1')
    PokazOkno
}
