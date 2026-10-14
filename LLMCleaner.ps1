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
      lib\Rdzen\         skanowanie, plan, AI, czyszczenie (bez interfejsu)
      lib\Okno\          okno graficzne (domyslnie), strony w lib\Okno\Strony\
      lib\Konsola\       interfejs tekstowy (-Konsola)
      lib\*\cs\          wstawki C# kompilowane przez Add-Type

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

$Wersja = '1.6.3'
$ErrorActionPreference = 'SilentlyContinue'
$AppDir = $PSScriptRoot

# Ustawienia ze strony Ustawienia (ustawienia.json); parametry z wiersza polecen maja pierwszenstwo
. (Join-Path $AppDir 'lib\Rdzen\Konfiguracja.ps1')
$Konfiguracja = WczytajKonfiguracje
$PodgladZParametru = [bool]$Podglad   # skrot "podglad" - zostaje tez po ponownym uruchomieniu z Ustawien
if (-not $Jezyk -and $Konfiguracja.Jezyk -in 'pl', 'en') { $Jezyk = $Konfiguracja.Jezyk }
if (-not $Model -and $Konfiguracja.Model) { $Model = "$($Konfiguracja.Model)" }
if ($Konfiguracja.Asystent -eq $false) { $BezLLM = [switch]$true }
if ($Konfiguracja.Aktualizacje -eq $false) { $BezAktualizacji = [switch]$true }
if ($Konfiguracja.Podglad -eq $true) { $Podglad = [switch]$true }

# Jezyk interfejsu: polski dla polskiego Windows, w pozostalych przypadkach angielski
if (-not $Jezyk) { $Jezyk = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'pl') { 'pl' } else { 'en' } }

# Model wybrany w instalatorze (config.json obok skryptu), chyba ze podano -Model
if (-not $Model) { $Model = ModelInstalatora }

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

# Pliki programu w kolejnosci ladowania. Sa dolaczane kropka (dot-source) do tego skryptu, wiec
# dziela jego zmienne ($Jezyk, $Podglad, $script:...) - dlatego nie sa modulami .psm1.
$PlikiRdzenia = @(
    'Rdzen\Wyjscie.ps1', 'Rdzen\Uzytkownik.ps1', 'Rdzen\Ustawienia.ps1', 'Rdzen\Pliki.ps1', 'Rdzen\Kategorie.ps1',
    'Rdzen\Dyski.ps1', 'Rdzen\Skaner.ps1', 'Rdzen\Pozostalosci.ps1', 'Rdzen\Autostart.ps1', 'Rdzen\Plan.ps1',
    'Rdzen\Ollama.ps1', 'Rdzen\Asystent.ps1', 'Rdzen\AnalizaDysku.ps1', 'Rdzen\Aktualizacje.ps1', 'Rdzen\Sterowniki.ps1',
    'Rdzen\Czyszczenie.ps1'
)
$PlikiOkna = @(
    'Okno\Podstawy.ps1', 'Okno\Motyw.ps1', 'Okno\Wyjscie.ps1', 'Okno\Rysowanie.ps1', 'Okno\Kontrolki.ps1', 'Okno\Lista.ps1',
    'Okno\Stan.ps1', 'Okno\Strony\Przeglad.ps1', 'Okno\Strony\Plan.ps1', 'Okno\Strony\Analiza.ps1',
    'Okno\Strony\Autostart.ps1', 'Okno\Strony\Sterowniki.ps1', 'Okno\Strony\Czyszczenie.ps1', 'Okno\Strony\Czat.ps1',
    'Okno\Strony\Dziennik.ps1', 'Okno\Strony\Ustawienia.ps1', 'Okno\Nawigacja.ps1', 'Okno\Polozenie.ps1', 'Okno\Okno.ps1'
)
$PlikiKonsoli = @(
    'Konsola\Wspolne.ps1', 'Konsola\Dyski.ps1', 'Konsola\Plan.ps1', 'Konsola\Czat.ps1', 'Konsola\Analiza.ps1',
    'Konsola\Autostart.ps1', 'Konsola\Sterowniki.ps1', 'Konsola\Konsola.ps1'
)

foreach ($plikProgramu in $PlikiRdzenia) { . (Join-Path $AppDir "lib\$plikProgramu") }
if ($Konsola) {
    foreach ($plikProgramu in $PlikiKonsoli) { . (Join-Path $AppDir "lib\$plikProgramu") }
    UruchomKonsole
}
else {
    foreach ($plikProgramu in $PlikiOkna) { . (Join-Path $AppDir "lib\$plikProgramu") }
    PokazOkno
}
