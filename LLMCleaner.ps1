<#
    LLMCleaner - inteligentne czyszczenie Windows z lokalnym modelem jezykowym (Ollama)
    Uruchamiany RECZNIE (skrot na pulpicie). Nie dodaje sie do autostartu.

    Jak dziala:
      1. Skaner mierzy kategorie smieci z bialej listy i szuka pozostalosci po odinstalowanych
         programach i grach (foldery, duze pliki, klucze rejestru).
      2. Plan ukladaja reguly: kategorie od 20 MB oraz pozostalosci o pewnosci wysokiej/sredniej.
      3. Lokalny model laduje sie dopiero NA ZADANIE:
           w - wyjasnia, czym byly pozostalosci (np. "Klei - studio gier, Oxygen Not Included")
           p - rozmowa o planie, folderach i programach
      4. Podsumowanie i pytanie "Uruchomic czyszczenie? [t/N]".
      5. Kategorie sa czyszczone, foldery i pliki ida do Kosza, klucze rejestru sa
         przed usunieciem eksportowane do .reg.

    Model nie decyduje o usuwaniu i niczego nie wykonuje - tylko wyjasnia i odpowiada.

    Parametry:
      -Podglad   tylko skan i plan, nic nie jest usuwane
      -BezLLM    wylacza asystenta (w i p)
      -Model     model Ollama (domyslnie z config.json obok skryptu, inaczej qwen3:4b-instruct)

    https://github.com/Banzamel/LLMCleaner - licencja MIT
#>
param(
    [switch]$Podglad,
    [switch]$BezLLM,
    [string]$Model
)

$Wersja = '1.0.0'
$ErrorActionPreference = 'SilentlyContinue'

# Model wybrany w instalatorze (config.json obok skryptu), chyba ze podano -Model
if (-not $Model) {
    $cfg = Join-Path $PSScriptRoot 'config.json'
    if (Test-Path -LiteralPath $cfg) { $Model = (Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).model }
    if (-not $Model) { $Model = 'qwen3:4b-instruct' }
}

# ---------- UPRAWNIENIA ----------
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $adm) {
    Write-Host "LLMCleaner wymaga uprawnień administratora - podnoszę..." -ForegroundColor Yellow
    $argumenty = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Model', "`"$Model`"")
    if ($Podglad) { $argumenty += '-Podglad' }
    if ($BezLLM) { $argumenty += '-BezLLM' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argumenty
    exit
}

# ---------- USTAWIENIA ----------
# Wlasna Ollama w folderze programu (instaluje ja Install-AI.ps1); osobny port, zeby nie
# kolidowac z Ollama zainstalowana w systemie
$AiDir = Join-Path $PSScriptRoot 'ai'
$OllamaExe = Join-Path $AiDir 'ollama\ollama.exe'
$OllamaUrl = 'http://127.0.0.1:11435'
# Logi i kopie rejestru poza folderem programu - przetrwaja aktualizacje i odinstalowanie
$LogDir = Join-Path $env:LOCALAPPDATA 'LLMCleaner\logs'
$REPARSE = [IO.FileAttributes]::ReparsePoint

New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogPlik = Join-Path $LogDir ("LLMCleaner_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))

function Log($t) {
    Add-Content -LiteralPath $LogPlik -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) -Encoding UTF8
}

function Naglowek($t) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}

function Rozmiar([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    if ($b -gt 0) { return '{0:N0} KB' -f ($b / 1KB) }
    return '0'
}

function WolneC { [double](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace }

# ---------- PLIKI: POMIAR I USUWANIE ----------

# Wszystkie pliki pod katalogiem. Nie wchodzi w junctions ani symlinki.
function Pliki($sciezka) {
    $stos = New-Object System.Collections.Stack
    $stos.Push([IO.DirectoryInfo]$sciezka)
    while ($stos.Count) {
        $d = $stos.Pop()
        try { $elementy = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $elementy) {
            if ($e.Attributes -band $REPARSE) { continue }
            if ($e -is [IO.DirectoryInfo]) { $stos.Push($e) } else { $e }
        }
    }
}

function Zmierz($sciezki) {
    $bajty = 0.0; $n = 0
    foreach ($s in $sciezki) {
        if (Test-Path -LiteralPath $s -PathType Leaf) {
            $bajty += (Get-Item -LiteralPath $s -Force).Length; $n++
            continue
        }
        if (-not (Test-Path -LiteralPath $s -PathType Container)) { continue }
        if ((Get-Item -LiteralPath $s -Force).Attributes -band $REPARSE) { continue }
        foreach ($f in Pliki $s) { $bajty += $f.Length; $n++ }
    }
    @{ Bajty = $bajty; Pliki = $n }
}

# Usuwa ZAWARTOSC katalogu (nie sam katalog) albo pojedynczy plik.
# Lacza (junctions/symlinki) usuwa jako lacza, nigdy nie wchodzi do ich celu.
# Pliki w uzyciu pomija. Przy $minWiekDni > 0 usuwa tylko pliki starsze niz tyle dni
# - sprawdzane dla KAZDEGO pliku, nie tylko dla folderu najwyzszego poziomu.
function UsunZawartosc($sciezka, $minWiekDni = 0) {
    $zwolniono = 0.0; $bledy = 0

    if (Test-Path -LiteralPath $sciezka -PathType Leaf) {
        $f = Get-Item -LiteralPath $sciezka -Force
        try { $dl = $f.Length; $f.Attributes = 'Normal'; $f.Delete(); $zwolniono += $dl } catch { $bledy++ }
        return @{ Bajty = $zwolniono; Bledy = $bledy }
    }
    if (-not (Test-Path -LiteralPath $sciezka -PathType Container)) { return @{ Bajty = 0.0; Bledy = 0 } }

    $korzen = [IO.DirectoryInfo]$sciezka
    if ($korzen.Attributes -band $REPARSE) { return @{ Bajty = 0.0; Bledy = 0 } }

    $granica = (Get-Date).AddDays(-$minWiekDni)
    $katalogi = New-Object System.Collections.Generic.List[IO.DirectoryInfo]
    $stos = New-Object System.Collections.Stack
    $stos.Push($korzen)

    while ($stos.Count) {
        $d = $stos.Pop()
        try { $elementy = $d.GetFileSystemInfos() } catch { $bledy++; continue }
        foreach ($e in $elementy) {
            if ($e.Attributes -band $REPARSE) {
                if ($minWiekDni -eq 0) {
                    try {
                        if ($e -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($e.FullName, $false) } else { $e.Delete() }
                    } catch { $bledy++ }
                }
                continue
            }
            if ($e -is [IO.DirectoryInfo]) {
                $stos.Push($e)
                if ($minWiekDni -eq 0 -or $e.LastWriteTime -le $granica) { $katalogi.Add($e) }
                continue
            }
            if ($minWiekDni -gt 0 -and $e.LastWriteTime -gt $granica) { continue }
            try {
                $dl = $e.Length
                if ($e.Attributes -band [IO.FileAttributes]::ReadOnly) { $e.Attributes = 'Normal' }
                $e.Delete()
                $zwolniono += $dl
            } catch { $bledy++ }
        }
    }

    # Puste katalogi - od najglebszych. Niepuste (pliki w uzyciu, swieze) zostaja.
    $katalogi.Reverse()
    foreach ($k in $katalogi) { try { [IO.Directory]::Delete($k.FullName, $false) } catch { } }

    @{ Bajty = $zwolniono; Bledy = $bledy }
}

# ---------- BIALA LISTA KATEGORII ----------

function ProfilePrzegladarki($userData) {
    if (-not (Test-Path -LiteralPath $userData)) { return @() }
    Get-ChildItem -LiteralPath $userData -Directory -Force |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
        ForEach-Object { $_.FullName }
}

$cachePrzegladarek = @()
foreach ($ud in "$env:LOCALAPPDATA\Google\Chrome\User Data",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
                "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") {
    foreach ($p in ProfilePrzegladarki $ud) {
        $cachePrzegladarek += "$p\Cache", "$p\Code Cache", "$p\GPUCache", "$p\Service Worker\CacheStorage"
    }
    $cachePrzegladarek += "$ud\GrShaderCache", "$ud\ShaderCache"
}
Get-ChildItem "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -Force |
    ForEach-Object { $cachePrzegladarek += "$($_.FullName)\cache2" }

$Kategorie = @(
    @{ Id = 'temp'; Nazwa = 'Pliki tymczasowe (TEMP)'; MinWiek = 1
       Sciezki = @($env:TEMP, 'C:\Windows\Temp')
       Opis = 'Pliki tymczasowe programów i instalatorów. Pliki z ostatniej doby są pomijane.' }
    @{ Id = 'inet'; Nazwa = 'Cache internetowy Windows (INetCache)'
       Sciezki = @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache")
       Opis = 'Cache silnika WebView/IE. Odtwarza się sam.' }
    @{ Id = 'kosz'; Nazwa = 'Kosz'; Typ = 'kosz'
       Opis = 'Pliki usunięte przez użytkownika. Po opróżnieniu nie da się ich przywrócić.'
       Uwagi = 'nieodwracalne' }
    @{ Id = 'wer'; Nazwa = 'Raporty błędów i zrzuty pamięci'
       Sciezki = @("$env:LOCALAPPDATA\Microsoft\Windows\WER",
                   'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
                   'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
                   "$env:LOCALAPPDATA\CrashDumps", 'C:\Windows\Minidump', 'C:\Windows\MEMORY.DMP')
       Opis = 'Raporty awarii programów i zrzuty pamięci po bluescreenach. Potrzebne tylko do diagnozy awarii.' }
    @{ Id = 'wu'; Nazwa = 'Cache Windows Update'
       Sciezki = @('C:\Windows\SoftwareDistribution\Download',
                   'C:\Windows\SoftwareDistribution\DeliveryOptimization')
       Uslugi = @('wuauserv', 'bits')
       Opis = 'Pobrane już pliki aktualizacji. Windows pobierze je ponownie, jeśli będą potrzebne.' }
    @{ Id = 'logi'; Nazwa = 'Logi systemowe CBS/DISM (starsze niż 7 dni)'; MinWiek = 7
       Sciezki = @('C:\Windows\Logs\CBS', 'C:\Windows\Logs\DISM')
       Opis = 'Logi instalacji komponentów Windows.' }
    @{ Id = 'www'; Nazwa = 'Cache przeglądarek (Chrome, Edge, Brave, Firefox)'
       Sciezki = $cachePrzegladarek
       Procesy = @('chrome', 'msedge', 'brave', 'firefox')
       Opis = 'Tylko cache stron i shaderów. Hasła, zakładki, historia i zalogowane sesje zostają.' }
    @{ Id = 'dev'; Nazwa = 'Cache narzędzi programistycznych'
       Sciezki = @("$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip\cache", "$env:LOCALAPPDATA\node-gyp\Cache",
                   "$env:LOCALAPPDATA\Yarn\Cache", "$env:LOCALAPPDATA\uv\cache", "$env:LOCALAPPDATA\NuGet\v3-cache")
       Opis = 'Pobrane paczki npm/pip/yarn/uv/NuGet. Pobiorą się ponownie przy następnej instalacji.' }
    @{ Id = 'shadery'; Nazwa = 'Cache shaderów GPU (NVIDIA, DirectX)'
       Sciezki = @("$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache", "$env:LOCALAPPDATA\D3DSCache")
       Opis = 'Skompilowane shadery. Pierwsze uruchomienie gier po czyszczeniu może się dłużej ładować.' }
    @{ Id = 'miniatury'; Nazwa = 'Miniaturki i cache ikon'; Typ = 'miniatury'
       Opis = 'Podglądy zdjęć i ikon w Eksploratorze. Wymaga restartu Eksploratora (pasek zadań zniknie na kilka sekund).' }
    @{ Id = 'dns'; Nazwa = 'Cache DNS'; Typ = 'dns'
       Opis = 'Zapamiętane adresy stron. Nie zwalnia miejsca, pomaga przy problemach z siecią.' }
    @{ Id = 'dism'; Nazwa = 'Magazyn komponentów WinSxS (DISM)'; Typ = 'dism'; TylkoRecznie = $true
       Opis = 'Usuwa zastąpione wersje komponentów Windows, zwykle 1-3 GB. Trwa kilka minut. Potem nie da się odinstalować wcześniejszych aktualizacji.' }
)
if (Get-Command docker) {
    $Kategorie += @{ Id = 'docker'; Nazwa = 'Docker - cache budowania'; Typ = 'docker'; TylkoRecznie = $true
                     Opis = 'Tylko build cache. Obrazy, kontenery i wolumeny (w tym bazy danych) zostają.' }
}
foreach ($k in $Kategorie) { if (-not $k.Typ) { $k.Typ = 'folder' } }

$sciezkaExplorer = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
function PlikiMiniatur {
    Get-ChildItem -LiteralPath $sciezkaExplorer -Force -File |
        Where-Object { $_.Name -like 'thumbcache_*.db' -or $_.Name -like 'iconcache_*.db' }
}

function DyskiStale { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' }

# ---------- SKANER ----------

function SkanujKategorie {
    foreach ($k in $Kategorie) {
        Write-Host ("   {0}..." -f $k.Nazwa) -ForegroundColor DarkGray
        switch ($k.Typ) {
            'folder' { $m = Zmierz $k.Sciezki; $k.Bajty = $m.Bajty; $k.Pliki = $m.Pliki }
            'kosz' {
                $b = 0.0
                foreach ($d in DyskiStale) { $b += (Zmierz @("$($d.DeviceID)\`$Recycle.Bin")).Bajty }
                $k.Bajty = $b
            }
            'miniatury' { $k.Bajty = [double](PlikiMiniatur | Measure-Object Length -Sum).Sum }
            default { $k.Bajty = 0.0 }
        }
        if ($k.Procesy -and (Get-Process $k.Procesy)) { $k.Blokada = 'uruchomiona przeglądarka - zamknij ją przed czyszczeniem' }
    }
}

function KatalogPobranych {
    $p = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    "$env:USERPROFILE\Downloads"
}

function SkanujDysk {
    $profil = $env:USERPROFILE
    $gorne = @{}; $appdata = @{}
    $duze = New-Object System.Collections.Generic.List[object]
    $n = 0

    foreach ($f in Pliki $profil) {
        $n++
        if ($n % 25000 -eq 0) { Write-Host ("`r   przejrzano {0:N0} plików..." -f $n) -NoNewline -ForegroundColor DarkGray }
        if ([int]$f.Attributes -band 0x401000) { continue }   # pliki tylko w chmurze (OneDrive)
        $czesci = $f.FullName.Substring($profil.Length + 1).Split('\')
        if ($czesci.Count -lt 2) { continue }
        $gorne[$czesci[0]] += $f.Length
        if ($czesci[0] -eq 'AppData') {
            if ($czesci.Count -gt 3 -and $czesci[1] -in 'Local', 'Roaming') { $appdata["AppData\$($czesci[1])\$($czesci[2])"] += $f.Length }
        }
        elseif ($f.Length -ge 1GB) { $duze.Add($f) }
    }
    Write-Host ("`r   przejrzano {0:N0} plików w profilu.        " -f $n) -ForegroundColor DarkGray

    # Kandydaci do recznego usuniecia: duze pliki w Pobranych + pliki > 1 GB poza AppData.
    $pobrane = KatalogPobranych
    $kandydaci = @()
    $z_pobranych = @(Pliki $pobrane | Where-Object { $_.Length -ge 100MB } | Sort-Object Length -Descending | Select-Object -First 15)
    $reszta = @($duze | Where-Object { $_.FullName -notlike "$pobrane\*" } | Sort-Object Length -Descending | Select-Object -First 12)
    $i = 0
    foreach ($f in @($z_pobranych) + @($reszta)) {
        $i++
        $kandydaci += @{
            Id = "P$i"; Sciezka = $f.FullName; Bajty = [double]$f.Length
            Zmodyfikowany = $f.LastWriteTime.ToString('yyyy-MM-dd')
            Pobrane = ($f.FullName -like "$pobrane\*")
        }
    }

    $programy = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object { $_.DisplayName -and $_.EstimatedSize } |
        Sort-Object { [double]$_.EstimatedSize } -Descending | Select-Object -First 12 |
        ForEach-Object { @{ nazwa = $_.DisplayName; rozmiar = (Rozmiar ([double]$_.EstimatedSize * 1KB)); zainstalowano = $_.InstallDate } }

    $hib = Get-Item -LiteralPath 'C:\hiberfil.sys' -Force
    @{
        Kandydaci = $kandydaci
        Profil = @($gorne.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
                   ForEach-Object { @{ folder = $_.Key; rozmiar = (Rozmiar $_.Value) } })
        AppData = @($appdata.GetEnumerator() | Where-Object { $_.Value -ge 300MB } | Sort-Object Value -Descending |
                    Select-Object -First 12 | ForEach-Object { @{ folder = $_.Key; rozmiar = (Rozmiar $_.Value) } })
        Programy = @($programy)
        System = @{
            hiberfil = $(if ($hib) { Rozmiar $hib.Length } else { 'brak (hibernacja wyłączona)' })
            windows_old = (Test-Path -LiteralPath 'C:\Windows.old')
            stara_instalacja_bt = (Test-Path -LiteralPath 'C:\$WINDOWS.~BT')
        }
        Dyski = @(DyskiStale | ForEach-Object { @{ dysk = $_.DeviceID; wolne = (Rozmiar $_.FreeSpace); calosc = (Rozmiar $_.Size) } })
    }
}

# ---------- POZOSTALOSCI PO ODINSTALOWANYCH PROGRAMACH I GRACH ----------
# Wykrywanie jest ostrozne: folder trafia na liste tylko wtedy, gdy nie pasuje do ZADNEGO
# zainstalowanego programu, aplikacji ze Sklepu, uslugi, procesu ani skrotu w menu Start.
# Foldery ida do Kosza, klucze rejestru sa przed usunieciem eksportowane do .reg.

$SlowaOgolne = @('app', 'apps', 'data', 'studio', 'software', 'soft', 'games', 'game', 'the', 'inc', 'ltd', 'llc',
    'gmbh', 'corp', 'corporation', 'company', 'technologies', 'technology', 'systems', 'group', 'limited', 'edition',
    'launcher', 'client', 'free', 'pro', 'update', 'updater', 'helper', 'service', 'services', 'tools', 'tool',
    'common', 'files', 'program', 'programs', 'user', 'local', 'roaming', 'cache', 'x64', 'x86', 'win', 'windows',
    'desktop', 'setup', 'install', 'installer', 'version', 'sro', 'foundation', 'entertainment', 'interactive', 'digital')

# Foldery i klucze systemowe, sterowniki oraz narzedzia, ktorych nigdy nie proponujemy
$PomijaneNazwy = @('microsoft*', 'windows*', 'packages', 'temp', 'tmp', 'programs', 'package cache', 'common files',
    'installshield*', 'd3dscache', 'crashdumps', 'connecteddevicesplatform', 'peerdistrepub', 'placeholdertilelogofolder',
    'comms', 'publishers', 'virtualstore', 'isolatedstorage', 'elevateddiagnostics', 'squirreltemp', 'history',
    'temporary internet files', 'application data', 'fontcache', 'identities', 'msbuild', 'reference assemblies',
    'uninstall information', 'internet explorer', 'modifiablewindowsapps', 'dotnet', 'ssh', 'regid.*', 'uso*',
    'softwaredistribution', 'desktop', 'documents', 'start menu', 'templates', 'favorites', 'npm', 'npm-cache', 'pip',
    'uv', 'yarn', 'nuget', 'node-gyp', 'pnpm*', 'fontconfig', 'nvidia*', 'intel*', 'amd', 'ati*', 'realtek', 'dell',
    'hp', 'lenovo', 'asus*', 'msi', 'gigabyte', 'claude*', 'anthropic*', 'chocolatey', 'scoop', 'classes', 'policies',
    'wow6432node', 'clients', 'registeredapplications', 'odbc', 'khronos', 'partner', 'defaultuserenvironment', 'setup',
    'oem', 'appdatalow', 'description', 'hardware', 'system', 'mozillaplugins', 'chromium', 'dolby', 'waves*',
    'conexant', 'synaptics', 'elantech', 'llmcleaner', 'ollama', 'ms-playwright', 'gtk*', 'cache', 'logs', 'crashpad',
    'javasoft', 'steam controller configs', 'steamworks shared', '.*')

function Tokeny([string]$t) {
    if (-not $t) { return @() }
    $t = [regex]::Replace($t, '([a-z])([A-Z])', '$1 $2')
    @(($t.ToLower() -split '[^a-z0-9]+') | Where-Object { $_.Length -ge 3 -and $_ -notin $SlowaOgolne -and $_ -notmatch '^\d+$' })
}
function Normalizuj([string]$t) { ($t.ToLower() -replace '[^a-z0-9]', '') }
function Pomijana([string]$nazwa) { $n = $nazwa.ToLower(); foreach ($w in $PomijaneNazwy) { if ($n -like $w) { return $true } }; $false }

# Sciezka pliku z polecenia typu '"C:\X\unins.exe" /S' albo 'C:\X\app.exe,0'
function SciezkaPliku([string]$s) {
    if (-not $s) { return $null }
    $s = [Environment]::ExpandEnvironmentVariables($s.Trim())
    if ($s.StartsWith('"')) { $e = $s.IndexOf('"', 1); if ($e -gt 1) { return $s.Substring(1, $e - 1) } }
    $m = [regex]::Match($s, '^(.+?\.(exe|dll|ico|bat|cmd))', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    ($s -split ',')[0]
}

function KluczeOdinstalowania {
    foreach ($r in 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                   'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                   'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in Get-ChildItem "Registry::$r") {
            $v = Get-ItemProperty -LiteralPath $k.PSPath
            if ($v.DisplayName) { @{ Klucz = "$r\$($k.PSChildName)"; V = $v } }
        }
    }
}

# Martwe wpisy na liscie programow: deinstalator i folder instalacji nie istnieja.
# Wpisy MSI pomijamy - ich usuniecie rozspojniloby baze Instalatora Windows.
function MartweWpisy($wpisy) {
    foreach ($w in $wpisy) {
        $v = $w.V
        if ($v.SystemComponent -eq 1 -or $v.WindowsInstaller -eq 1 -or "$($v.UninstallString)" -match 'msiexec') { continue }
        $exe = SciezkaPliku $v.UninstallString
        if (-not $exe -or (Test-Path -LiteralPath $exe)) { continue }
        $loc = "$($v.InstallLocation)".Trim('"', ' ')
        if ($loc -and (Test-Path -LiteralPath $loc)) { continue }
        @{ Typ = 'rejestr'; Sciezka = $w.Klucz; Nazwa = $v.DisplayName; Bajty = 0.0
           Pewnosc = $(if ($loc) { 'wysoka' } else { 'srednia' })
           Dlaczego = "Martwy wpis na liście programów: deinstalator nie istnieje$(if ($loc) { ', folder instalacji też nie' })." }
    }
}

function ZainstalowaneProgramy($wpisy) {
    $tokeny = New-Object 'System.Collections.Generic.HashSet[string]'
    $nazwy = New-Object System.Collections.Generic.List[string]
    $sciezki = New-Object System.Collections.Generic.List[string]
    function Dodaj([string]$tekst) { foreach ($x in Tokeny $tekst) { [void]$tokeny.Add($x) }; $n = Normalizuj $tekst; if ($n.Length -ge 4) { $nazwy.Add($n) } }
    function DodajSciezke([string]$p) {
        if (-not $p) { return }
        $p = $p.Trim('"', ' ').TrimEnd('\')
        if ($p -match '\.\w{2,4}$') { $p = Split-Path $p -Parent }
        if ($p.Length -gt 3) { $sciezki.Add($p.ToLower()) }
    }
    foreach ($w in $wpisy) {
        Dodaj $w.V.DisplayName; Dodaj $w.V.Publisher
        DodajSciezke $w.V.InstallLocation
        DodajSciezke (SciezkaPliku $w.V.DisplayIcon)
        DodajSciezke (SciezkaPliku $w.V.UninstallString)
    }
    foreach ($a in Get-AppxPackage) { Dodaj $a.Name; DodajSciezke $a.InstallLocation }
    foreach ($g in SteamGry) { Dodaj $g }
    foreach ($p in Get-Process) { if ($p.Path) { DodajSciezke $p.Path; Dodaj ([IO.Path]::GetFileNameWithoutExtension($p.Path)) } }
    foreach ($s in Get-CimInstance Win32_Service) { DodajSciezke (SciezkaPliku $s.PathName) }
    # Skroty w menu Start i na pulpicie - lapia programy przenosne bez wpisu w rejestrze
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:ProgramData\Microsoft\Windows\Start Menu",
                   [Environment]::GetFolderPath('Desktop'), "$env:PUBLIC\Desktop") {
        foreach ($l in Get-ChildItem -LiteralPath $d -Recurse -Filter *.lnk -Force) {
            Dodaj $l.BaseName
            $t = $sh.CreateShortcut($l.FullName).TargetPath
            if ($t) { DodajSciezke $t }
        }
    }
    @{ Tokeny = $tokeny; Nazwy = $nazwy; Sciezki = $sciezki }
}

function NalezyDoProgramu([string]$nazwa, [string]$sciezka, $zainst) {
    foreach ($t in Tokeny $nazwa) { if ($zainst.Tokeny.Contains($t)) { return $true } }
    $n = Normalizuj $nazwa
    if ($n.Length -ge 4) { foreach ($z in $zainst.Nazwy) { if ($z.Contains($n) -or ($z.Length -ge 5 -and $n.Contains($z))) { return $true } } }
    if ($sciezka) {
        $s = $sciezka.ToLower().TrimEnd('\')
        foreach ($p in $zainst.Sciezki) { if ($p -eq $s -or $p.StartsWith("$s\") -or $s.StartsWith("$p\")) { return $true } }
    }
    $false
}

function ZmierzFolder($p) {
    $b = 0.0; $ost = [datetime]::MinValue
    foreach ($f in Pliki $p) { $b += $f.Length; if ($f.LastWriteTime -gt $ost) { $ost = $f.LastWriteTime } }
    if ($ost -eq [datetime]::MinValue) { $ost = (Get-Item -LiteralPath $p -Force).LastWriteTime }
    @{ Bajty = $b; Ostatnio = $ost }
}

function SteamBiblioteki {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath
    if (-not $steam) { return }
    $steam = $steam -replace '/', '\'
    $biblioteki = @($steam)
    $vdf = "$steam\steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) { $biblioteki += $m.Groups[1].Value -replace '\\\\', '\' }
    }
    $biblioteki | Sort-Object -Unique
}

# Nazwy zainstalowanych gier Steam (z manifestow) - zeby nie brac ich ustawien za pozostalosci
function SteamGry {
    foreach ($b in SteamBiblioteki) {
        foreach ($acf in Get-ChildItem -LiteralPath "$b\steamapps" -Filter 'appmanifest_*.acf') {
            $t = Get-Content -LiteralPath $acf.FullName -Raw
            foreach ($pole in 'name', 'installdir') { $m = [regex]::Match($t, """$pole""\s+""([^""]+)"""); if ($m.Success) { $m.Groups[1].Value } }
        }
    }
}

function SteamOsierocone {
    foreach ($b in SteamBiblioteki) {
        $sa = "$b\steamapps"
        if (-not (Test-Path -LiteralPath $sa)) { continue }
        $katalogi = @{}; $ids = @{}
        foreach ($acf in Get-ChildItem -LiteralPath $sa -Filter 'appmanifest_*.acf') {
            $t = Get-Content -LiteralPath $acf.FullName -Raw
            $m = [regex]::Match($t, '"installdir"\s+"([^"]+)"'); if ($m.Success) { $katalogi[$m.Groups[1].Value.ToLower()] = 1 }
            $m = [regex]::Match($t, '"appid"\s+"(\d+)"'); if ($m.Success) { $ids[$m.Groups[1].Value] = 1 }
        }
        foreach ($d in Get-ChildItem -LiteralPath "$sa\common" -Directory -Force) {
            if (-not $katalogi[$d.Name.ToLower()] -and -not (Pomijana $d.Name)) {
                @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = $d.Name; Pewnosc = 'wysoka'; Gra = $true
                   Dlaczego = 'Folder gry Steam bez manifestu - gra została odinstalowana, pliki zostały.' }
            }
        }
        foreach ($sub in 'shadercache', 'workshop\content') {
            foreach ($d in Get-ChildItem -LiteralPath "$sa\$sub" -Directory -Force) {
                if ($d.Name -match '^\d+$' -and -not $ids[$d.Name]) {
                    @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = "Steam $sub $($d.Name)"; Pewnosc = 'wysoka'; Gra = $true
                       Dlaczego = "Steam $sub dla gry (appid $($d.Name)), której już nie ma." }
                }
            }
        }
    }
}

function EpicOsierocone {
    $man = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path -LiteralPath $man)) { return }
    $zainst = @{}; $rodzice = @{ "$env:ProgramFiles\Epic Games".ToLower() = 1 }
    foreach ($i in Get-ChildItem -LiteralPath $man -Filter *.item) {
        $loc = (Get-Content -LiteralPath $i.FullName -Raw | ConvertFrom-Json).InstallLocation
        if ($loc) { $loc = $loc.TrimEnd('\').ToLower(); $zainst[$loc] = 1; $rodzice[(Split-Path $loc -Parent)] = 1 }
    }
    foreach ($r in $rodzice.Keys) {
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force) {
            if ($zainst[$d.FullName.ToLower()] -or $d.Name -in 'Launcher', 'DirectXRedist' -or $d.Name -like 'UE_*') { continue }
            @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = $d.Name; Pewnosc = 'wysoka'; Gra = $true
               Dlaczego = 'Folder gry Epic, której nie ma na liście zainstalowanych w Epic Games Launcher.' }
        }
    }
}

function SkanujPozostalosci {
    $wpisy = @(KluczeOdinstalowania)
    $martwe = @(MartweWpisy $wpisy)
    $martweKlucze = @($martwe | ForEach-Object { $_.Sciezka })
    $zainst = ZainstalowaneProgramy @($wpisy | Where-Object { $_.Klucz -notin $martweKlucze })
    $teraz = Get-Date
    $wyniki = New-Object System.Collections.Generic.List[object]

    # Foldery programow
    $korzenie = @(
        @{ P = $env:APPDATA; Gra = $false }, @{ P = $env:LOCALAPPDATA; Gra = $false },
        @{ P = "$env:LOCALAPPDATA\Programs"; Gra = $false }, @{ P = "$env:USERPROFILE\AppData\LocalLow"; Gra = $false },
        @{ P = $env:ProgramData; Gra = $false }, @{ P = $env:ProgramFiles; Gra = $false }, @{ P = ${env:ProgramFiles(x86)}; Gra = $false },
        @{ P = "$env:USERPROFILE\Documents\My Games"; Gra = $true }, @{ P = "$env:USERPROFILE\Saved Games"; Gra = $true })
    $wszystkieNazwy = New-Object 'System.Collections.Generic.HashSet[string]'
    $doSprawdzenia = @()
    foreach ($k in $korzenie) {
        foreach ($d in Get-ChildItem -LiteralPath $k.P -Directory -Force) {
            [void]$wszystkieNazwy.Add((Normalizuj $d.Name))
            if ($d.Attributes -band $REPARSE -or $d.Attributes -band [IO.FileAttributes]::System) { continue }
            if (Pomijana $d.Name) { continue }
            if (NalezyDoProgramu $d.Name $d.FullName $zainst) { continue }
            $doSprawdzenia += @{ D = $d; Zapisy = $k.Gra }
        }
    }
    foreach ($c in $doSprawdzenia) {
        $m = ZmierzFolder $c.D.FullName
        $dni = ($teraz - $m.Ostatnio).TotalDays
        if ($dni -lt 30 -or $m.Bajty -lt 1MB) { continue }   # cos tam jeszcze pisze albo nie warto
        $wyniki.Add(@{ Typ = 'folder'; Sciezka = $c.D.FullName; Nazwa = $c.D.Name; Bajty = $m.Bajty; Ostatnio = $m.Ostatnio
            Pewnosc = $(if ($c.Zapisy) { 'niska' } elseif ($dni -ge 180) { 'wysoka' } else { 'srednia' })
            Dlaczego = $(if ($c.Zapisy) { 'Zapisy/ustawienia gry - może chcesz je zachować.' } else { 'Brak zainstalowanego programu o tej nazwie.' }) })
    }

    # Gry
    foreach ($g in @(SteamOsierocone) + @(EpicOsierocone)) {
        $m = ZmierzFolder $g.Sciezka
        $g.Bajty = $m.Bajty; $g.Ostatnio = $m.Ostatnio
        $wyniki.Add($g)
    }

    # Rejestr: klucze producentow bez programu i bez folderu o tej nazwie
    $rej = New-Object System.Collections.Generic.List[object]
    foreach ($r in 'HKEY_CURRENT_USER\Software', 'HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node') {
        foreach ($k in Get-ChildItem "Registry::$r") {
            $n = $k.PSChildName
            if (Pomijana $n) { continue }
            if (NalezyDoProgramu $n $null $zainst) { continue }
            if ($wszystkieNazwy.Contains((Normalizuj $n))) { continue }
            # Klucz studia (np. Klei) moze nalezec do wciaz zainstalowanej gry (Klei\Don't Starve)
            $podklucze = @(Get-ChildItem -LiteralPath $k.PSPath | ForEach-Object { $_.PSChildName })
            if ($podklucze | Where-Object { (NalezyDoProgramu $_ $null $zainst) -or $wszystkieNazwy.Contains((Normalizuj $_)) }) { continue }
            $zawiera = @($podklucze | Select-Object -First 3)
            $rej.Add(@{ Typ = 'rejestr'; Sciezka = "$r\$n"; Nazwa = $n; Bajty = 0.0; Pewnosc = 'srednia'; Zawiera = $zawiera
                        Dlaczego = "Klucz producenta bez zainstalowanego programu i folderu.$(if ($zawiera) { ' Zawiera: ' + ($zawiera -join ', ') + '.' })" })
        }
    }

    $foldery = @($wyniki | Sort-Object { $_.Bajty } -Descending | Select-Object -First 30)
    $klucze = @(@($martwe) + @($rej | Select-Object -First 20))
    $i = 0
    foreach ($p in @($foldery) + @($klucze)) { $i++; $p.Id = "R$i" }
    @($foldery) + @($klucze)
}

# ---------- OLLAMA ----------

function OllamaDziala {
    try { Invoke-RestMethod "$OllamaUrl/api/version" -TimeoutSec 2 -ErrorAction Stop | Out-Null; $true } catch { $false }
}

# Job Object z KILL_ON_JOB_CLOSE: serwer (i jego procesy runner) ginie razem z LLMCleanerem,
# takze gdy okno zostanie zamkniete krzyzykiem
function PrzypnijDoZadania([Diagnostics.Process]$proces) {
    if (-not ('LlmJob' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LlmJob {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attr, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct Basic { public long a, b; public uint LimitFlags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
    [StructLayout(LayoutKind.Sequential)] struct Io { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic B; public Io I; public UIntPtr a, b, c, d; }
    static IntPtr job = IntPtr.Zero;
    public static bool Attach(IntPtr process) {
        if (job == IntPtr.Zero) {
            job = CreateJobObject(IntPtr.Zero, null);
            var info = new Extended();
            info.B.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            int len = Marshal.SizeOf(typeof(Extended));
            IntPtr p = Marshal.AllocHGlobal(len);
            Marshal.StructureToPtr(info, p, false);
            SetInformationJobObject(job, 9, p, (uint)len); // JobObjectExtendedLimitInformation
            Marshal.FreeHGlobal(p);
        }
        return AssignProcessToJobObject(job, process);
    }
    public static void Close() { if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; } }
}
'@
    }
    [LlmJob]::Attach($proces.Handle)
}

function UruchomOllama {
    if (OllamaDziala) { return $true }
    if (-not (Test-Path -LiteralPath $OllamaExe)) { return $false }
    # Modele i klucze Ollamy zostaja w folderze ai\ - nic nie trafia do profilu uzytkownika
    $psi = New-Object Diagnostics.ProcessStartInfo $OllamaExe, 'serve'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['OLLAMA_HOST'] = $OllamaUrl -replace '^http://', ''
    $psi.EnvironmentVariables['OLLAMA_MODELS'] = Join-Path $AiDir 'models'
    $psi.EnvironmentVariables['USERPROFILE'] = $AiDir
    $proces = [Diagnostics.Process]::Start($psi)
    if (-not (PrzypnijDoZadania $proces)) { Log 'Job Object: nie udalo sie przypiac serwera' }
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 500; if (OllamaDziala) { return $true } }
    $false
}

function ZatrzymajOllama { if ('LlmJob' -as [type]) { [LlmJob]::Close() } }

function MaModel {
    try { $t = Invoke-RestMethod "$OllamaUrl/api/tags" -TimeoutSec 5 -ErrorAction Stop } catch { return $false }
    [bool]($t.models | Where-Object { $_.name -eq $Model -or $_.name -eq "$Model`:latest" })
}

function Ollama($wiadomosci, $format) {
    $body = @{ model = $Model; messages = @($wiadomosci); stream = $false; keep_alive = '5m'
               options = @{ temperature = 0.2; num_ctx = 12288 } }
    if ($format) { $body.format = $format }
    $json = ConvertTo-Json -InputObject $body -Depth 20 -Compress
    $r = Invoke-RestMethod "$OllamaUrl/api/chat" -Method Post -TimeoutSec 600 -ErrorAction Stop `
         -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8'
    $r.message.content
}

# Model ladowany dopiero przy pierwszym uzyciu (p = rozmowa, w = wyjasnienia).
$script:llmStan = $null
function ZapewnijModel {
    if ($BezLLM) { Write-Host "   Model jest wyłączony (uruchomiono z -BezLLM)." -ForegroundColor Yellow; return $false }
    if ($null -ne $script:llmStan) { return $script:llmStan }
    Write-Host "   Uruchamiam model $Model (pierwsze użycie trwa ok. 10-20 s)..." -ForegroundColor DarkGray
    if (-not (Test-Path -LiteralPath $OllamaExe)) {
        Write-Host "   Asystent AI nie jest zainstalowany. Uruchom ponownie instalator i zaznacz asystenta AI" -ForegroundColor Yellow
        Write-Host "   (albo Install-AI.ps1 z folderu programu)." -ForegroundColor Yellow
        $script:llmStan = $false
    }
    elseif (-not (UruchomOllama)) {
        Write-Host "   Nie udało się uruchomić Ollamy z folderu ai\ - asystent niedostępny." -ForegroundColor Yellow
        $script:llmStan = $false
    }
    elseif (-not (MaModel)) {
        Write-Host "   Brak modelu $Model w folderze ai\models (Install-AI.ps1 -Model $Model) - asystent niedostępny." -ForegroundColor Yellow
        $script:llmStan = $false
    }
    else { $script:llmStan = $true }
    Log "Model: $($script:llmStan)"
    $script:llmStan
}

$SchematWyjasnien = @{
    type = 'object'
    properties = @{
        wyjasnienia = @{ type = 'array'; items = @{ type = 'object'
            properties = @{ id = @{ type = 'string' }; opis = @{ type = 'string' } }
            required = @('id', 'opis') } }
    }
    required = @('wyjasnienia')
}

$SysWyjasnij = @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę pozostałości po odinstalowanych programach i grach
(foldery, pliki i klucze rejestru). Dla KAŻDEJ pozycji napisz w polu "opis", czym był ten program, gra albo producent.
Zasady:
- Opieraj się PRZEDE WSZYSTKIM na polu "zawiera" (nazwy podkluczy rejestru - zwykle to nazwy gier lub programów)
  i na samej nazwie. Przykład: nazwa "Studio X", zawiera ["Gra Y"] -> "Studio X - gra Gra Y".
- NIE dopisuj tytułów gier ani produktów, których nie ma w danych, chyba że jesteś absolutnie pewien.
  Lepiej "producent gier" niż zmyślony tytuł.
- Jeśli nic nie wiadomo, napisz dokładnie: "nieznany program".
- Maks. 12 słów, po polsku. Nie oceniasz, czy usuwać.
'@

$SysCzat = @'
Jesteś LLMCleaner - asystentem sprzątania systemu Windows działającym lokalnie.
Poniżej masz raport skanera i aktualny plan czyszczenia. Odpowiadaj krótko i konkretnie po polsku na pytania
użytkownika o pliki, foldery, programy, gry i plan. Nie możesz niczego usuwać ani uruchamiać - plan zmienia
użytkownik numerami. Jeśli chce usunąć coś spoza planu, wyjaśnij, jak zrobić to bezpiecznie ręcznie
(np. odinstalowanie programu w Ustawieniach). Używaj tylko liczb z raportu. Jeśli czegoś nie wiesz, powiedz to wprost.
'@

# ---------- START ----------
Clear-Host
Write-Host ""
Write-Host "   LLMCleaner $Wersja - inteligentne czyszczenie komputera" -ForegroundColor White
Write-Host "   $(Get-Date -Format 'dd.MM.yyyy HH:mm')   asystent: $(if ($BezLLM) { 'wyłączony' } else { "$Model (na żądanie)" })" -ForegroundColor DarkGray
if ($Podglad) { Write-Host "   TRYB PODGLĄDU - nic nie zostanie usunięte" -ForegroundColor Yellow }
Write-Host ""
Log "Start. Model: $Model, Podglad: $Podglad, BezLLM: $BezLLM"

$wolnePrzed = WolneC
Naglowek "1/2  Skanowanie"
SkanujKategorie
Write-Host "   Przeglądam profil użytkownika (duże pliki, AppData)..." -ForegroundColor DarkGray
$dysk = SkanujDysk
Write-Host "   Szukam pozostałości po odinstalowanych programach i grach..." -ForegroundColor DarkGray
$Pozostalosci = @(SkanujPozostalosci)

# Duze pliki z Pobranych i spoza AppData - do decyzji uzytkownika, nigdy zaznaczone z gory
foreach ($c in $dysk.Kandydaci) {
    $Pozostalosci += @{ Typ = 'plik'; Sciezka = $c.Sciezka; Nazwa = (Split-Path $c.Sciezka -Leaf); Bajty = $c.Bajty
        Ostatnio = [datetime]$c.Zmodyfikowany; Pewnosc = 'niska'
        Dlaczego = $(if ($c.Pobrane) { 'Duży plik w Pobranych - stary instalator albo archiwum?' } else { 'Duży plik (ponad 1 GB) w profilu użytkownika.' }) }
}
$n = 0; foreach ($p in $Pozostalosci) { $n++; $p.Id = "R$n" }

Write-Host ("   Znaleziono pozostałości: {0} folderów, {1} plików, {2} wpisów rejestru." -f
    @($Pozostalosci | Where-Object { $_.Typ -eq 'folder' }).Count, @($Pozostalosci | Where-Object { $_.Typ -eq 'plik' }).Count,
    @($Pozostalosci | Where-Object { $_.Typ -eq 'rejestr' }).Count) -ForegroundColor DarkGray

# ---------- PLAN (reguly, bez modelu) ----------
# Kategorie: zaznaczone, gdy maja co najmniej 20 MB. Kosz (nieodwracalny), DNS i kategorie
# "tylko recznie" zawsze odznaczone. Pozostalosci: zaznaczone przy pewnosci wysokiej i sredniej.
foreach ($k in $Kategorie) {
    $k.Wybrana = -not $k.TylkoRecznie -and -not $k.Blokada -and $k.Typ -in 'folder', 'miniatury' -and $k.Bajty -ge 20MB
}
foreach ($p in $Pozostalosci) { $p.Wybrana = $p.Pewnosc -in 'wysoka', 'srednia' }

function RaportJson {
    $raport = @{
        dyski = $dysk.Dyski
        kategorie = @($Kategorie | ForEach-Object {
            @{ id = $_.Id; nazwa = $_.Nazwa; opis = $_.Opis; zaznaczona = [bool]$_.Wybrana
               rozmiar = $(if ($_.Typ -in 'folder', 'kosz', 'miniatury') { Rozmiar $_.Bajty } else { 'nie dotyczy' })
               tylko_recznie = [bool]$_.TylkoRecznie; blokada = $_.Blokada } })
        pozostalosci = @($Pozostalosci | ForEach-Object {
            @{ id = $_.Id; typ = $_.Typ; sciezka = $_.Sciezka; zaznaczona = [bool]$_.Wybrana
               rozmiar = $(if ($_.Typ -ne 'rejestr') { Rozmiar $_.Bajty } else { '-' })
               ostatnia_zmiana = $(if ($_.Ostatnio) { $_.Ostatnio.ToString('yyyy-MM-dd') }); pewnosc = $_.Pewnosc
               dlaczego = $_.Dlaczego; czym_jest = $_.Ai } })
        najwieksze_foldery_profilu = $dysk.Profil
        duze_foldery_appdata = $dysk.AppData
        najwieksze_programy = $dysk.Programy
        system = $dysk.System
    }
    ConvertTo-Json -InputObject $raport -Depth 10 -Compress
}
Log "Raport: $(RaportJson)"

function PokazPlan {
    Naglowek "PLAN CZYSZCZENIA"
    $i = 0
    foreach ($k in $Kategorie) {
        $i++
        $znak = if ($k.Wybrana) { '[x]' } else { '[ ]' }
        $kolor = if ($k.Wybrana) { 'Green' } elseif ($k.TylkoRecznie) { 'Gray' } else { 'DarkGray' }
        $roz = if ($k.Typ -in 'folder', 'kosz', 'miniatury') { Rozmiar $k.Bajty } else { '-' }
        Write-Host ("  {0} {1,2}. {2,-52} {3,10}" -f $znak, $i, $k.Nazwa, $roz) -ForegroundColor $kolor
        if ($k.Blokada) { Write-Host "           ! $($k.Blokada)" -ForegroundColor Yellow }
        else { Write-Host "           $(if ($k.TylkoRecznie) { '(tylko na Twoje życzenie) ' })$($k.Opis)" -ForegroundColor DarkGray }
    }
    if ($Pozostalosci.Count) {
        Write-Host ""
        Write-Host "   POZOSTAŁOŚCI PO ODINSTALOWANYCH PROGRAMACH I GRACH" -ForegroundColor Cyan
        Write-Host "   (foldery i pliki idą do Kosza, klucze rejestru są wcześniej zapisywane do pliku .reg)" -ForegroundColor DarkGray
        foreach ($p in $Pozostalosci) {
            $i++
            $znak = if ($p.Wybrana) { '[x]' } else { '[ ]' }
            $kolor = if ($p.Wybrana) { 'Green' } elseif ($p.Pewnosc -eq 'niska') { 'DarkYellow' } else { 'DarkGray' }
            $roz = if ($p.Typ -ne 'rejestr') { Rozmiar $p.Bajty } else { 'rejestr' }
            $pokaz = if ($p.Typ -eq 'rejestr' -and $p.Nazwa -ne (Split-Path $p.Sciezka -Leaf)) { "$($p.Nazwa)  [$($p.Sciezka)]" } else { $p.Sciezka }
            Write-Host ("  {0} {1,2}. {2,-52} {3,10}  pewność: {4}" -f $znak, $i, $pokaz, $roz, $p.Pewnosc) -ForegroundColor $kolor
            Write-Host "           $($p.Dlaczego)" -ForegroundColor DarkGray
            if ($p.Ai) { Write-Host "           AI (może się mylić): $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    $suma = (@($Kategorie) + @($Pozostalosci) | Where-Object { $_.Wybrana } | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
    Write-Host ""
    Write-Host ("   Zaznaczone razem: ok. {0}" -f (Rozmiar $suma)) -ForegroundColor White
}

function Wyjasnij {
    if (-not $Pozostalosci.Count) { Write-Host "   Brak pozostałości do wyjaśnienia." -ForegroundColor DarkGray; return }
    if (-not (ZapewnijModel)) { return }
    $lista = @($Pozostalosci | ForEach-Object { @{ id = $_.Id; typ = $_.Typ; nazwa = $_.Nazwa; sciezka = $_.Sciezka; zawiera = @($_.Zawiera) } })
    Write-Host "   Model opisuje $($lista.Count) pozycji (ok. 20-40 s)..." -ForegroundColor DarkGray
    try {
        $odp = Ollama @(@{ role = 'system'; content = $SysWyjasnij },
                        @{ role = 'user'; content = (ConvertTo-Json -InputObject $lista -Depth 5 -Compress) }) $SchematWyjasnien
        $n = 0
        foreach ($w in @(($odp | ConvertFrom-Json -ErrorAction Stop).wyjasnienia)) {
            $p = $Pozostalosci | Where-Object { $_.Id -eq $w.id } | Select-Object -First 1
            if ($p -and $w.opis) { $p.Ai = $w.opis; $n++ }
        }
        Write-Host "   Gotowe - opisano $n pozycji (dopisek AI w planie)." -ForegroundColor Green
        Log "Wyjasnienia modelu: $odp"
    }
    catch { Write-Host "   Błąd modelu: $($_.Exception.Message)" -ForegroundColor Yellow }
}

function Czat {
    if (-not (ZapewnijModel)) { return }
    $rozmowa = New-Object System.Collections.ArrayList
    [void]$rozmowa.Add(@{ role = 'system'; content = "$SysCzat`n`nRAPORT I PLAN:`n$(RaportJson)" })
    Write-Host ""
    Write-Host "   Rozmowa z asystentem. Pusta linia = powrót do planu." -ForegroundColor Cyan
    while ($true) {
        Write-Host ""
        $q = Read-Host "   Ty"
        if (-not $q) { return }
        [void]$rozmowa.Add(@{ role = 'user'; content = $q })
        try {
            $a = Ollama $rozmowa.ToArray()
            [void]$rozmowa.Add(@{ role = 'assistant'; content = $a })
            Write-Host ""
            Write-Host "   LLMCleaner: $a" -ForegroundColor White
        }
        catch { Write-Host "   Błąd modelu: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# Ostatnie podsumowanie przed czyszczeniem. Zwraca $true, gdy uzytkownik potwierdzi.
function Potwierdz {
    $wybrane = @($Kategorie | Where-Object { $_.Wybrana })
    $wybranePoz = @($Pozostalosci | Where-Object { $_.Wybrana })
    Naglowek "PODSUMOWANIE PRZED CZYSZCZENIEM"
    if (-not $wybrane.Count -and -not $wybranePoz.Count) {
        Write-Host "   Nic nie jest zaznaczone - nie ma czego czyścić." -ForegroundColor Yellow
        return $false
    }
    if ($wybrane.Count) {
        Write-Host "   Zostanie wyczyszczone:" -ForegroundColor White
        foreach ($k in $wybrane) {
            $roz = if ($k.Typ -in 'folder', 'kosz', 'miniatury') { Rozmiar $k.Bajty } elseif ($k.Typ -eq 'dns') { '-' } else { 'nieznane' }
            Write-Host ("     - {0,-52} {1,10}" -f $k.Nazwa, $roz) -ForegroundColor Gray
        }
        $suma = ($wybrane | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
        Write-Host ""
        Write-Host ("   Zwolnione miejsce   : ok. {0}" -f (Rozmiar $suma)) -ForegroundColor Green
        Write-Host ("   Wolne na C: teraz   : {0}" -f (Rozmiar $wolnePrzed)) -ForegroundColor Gray
        Write-Host ("   Wolne na C: po      : ok. {0}" -f (Rozmiar ($wolnePrzed + $suma))) -ForegroundColor Gray
        Write-Host "   (część plików może być w użyciu - wtedy zostaną pominięte i zysk będzie mniejszy)" -ForegroundColor DarkGray
    }

    $doKosza = @($wybranePoz | Where-Object { $_.Typ -ne 'rejestr' })
    $pozRejestr = @($wybranePoz | Where-Object { $_.Typ -eq 'rejestr' })
    if ($wybranePoz.Count) {
        Write-Host ""
        Write-Host "   Pozostałości po odinstalowanych programach i grach:" -ForegroundColor White
        foreach ($p in $wybranePoz) {
            $roz = if ($p.Typ -ne 'rejestr') { Rozmiar $p.Bajty } else { 'rejestr' }
            Write-Host ("     - {0,-52} {1,10}" -f $p.Sciezka, $roz) -ForegroundColor Gray
        }
        if ($doKosza.Count) {
            $sp = ($doKosza | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
            Write-Host ("   Do Kosza            : {0} ({1}) - miejsce zwolni się po opróżnieniu Kosza" -f $doKosza.Count, (Rozmiar $sp)) -ForegroundColor Gray
        }
        if ($pozRejestr.Count) {
            Write-Host ("   Klucze rejestru     : {0} - kopia .reg w logs\kopie_rejestru" -f $pozRejestr.Count) -ForegroundColor Gray
        }
    }

    $uwagi = @()
    if ($wybrane | Where-Object { $_.Id -eq 'kosz' }) { $uwagi += 'Kosz zostanie opróżniony NIEODWRACALNIE (przed przeniesieniem pozostałości).' }
    if ($wybrane | Where-Object { $_.Typ -eq 'miniatury' }) { $uwagi += 'Eksplorator zostanie zrestartowany - pasek zadań zniknie na kilka sekund.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'dism' }) { $uwagi += 'DISM potrwa kilka minut; potem nie odinstalujesz starszych aktualizacji.' }
    if ($wybrane | Where-Object { $_.Procesy }) { $uwagi += 'Nie otwieraj przeglądarki w trakcie czyszczenia.' }
    if ($wybranePoz | Where-Object { $_.Pewnosc -eq 'niska' }) { $uwagi += 'Zaznaczono pozycje o niskiej pewności (zapisy gier / duże pliki) - upewnij się, że ich nie potrzebujesz.' }
    if ($uwagi.Count) {
        Write-Host ""
        foreach ($u in $uwagi) { Write-Host "   ! $u" -ForegroundColor Yellow }
    }
    Write-Host ""
    $t = Read-Host "   Uruchomić czyszczenie? [t/N]"
    if ($t -match '^[TtYy]') { return $true }
    Write-Host "   Wracam do planu." -ForegroundColor DarkGray
    $false
}

# ---------- ZATWIERDZENIE ----------
while ($true) {
    PokazPlan
    Write-Host ""
    $pomoc = if ($Podglad) { 'Enter = zakończ' } else { 'Enter = dalej (podsumowanie i pytanie o czyszczenie)' }
    $pomoc += ' | numery (np. 3 7) = zaznacz/odznacz'
    if (-not $BezLLM) { $pomoc += ' | w = AI wyjaśni pozostałości | p = zapytaj asystenta' }
    $pomoc += ' | q = wyjdź'
    Write-Host "   $pomoc" -ForegroundColor Yellow
    $w = (Read-Host "   Wybór").Trim()

    if ($w -eq '') {
        if ($Podglad -or (Potwierdz)) { break }
        continue
    }
    if ($w -match '^[qQ]') { Log 'Przerwano przez uzytkownika.'; Write-Host "`n   Przerwano - nic nie zostało usunięte.`n"; ZatrzymajOllama; Read-Host "   Enter kończy"; exit }
    if ($w -match '^[pP]$') { Czat; continue }
    if ($w -match '^[wW]$') { Wyjasnij; continue }
    foreach ($n in ($w -split '[\s,;]+')) {
        $idx = 0
        if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $Kategorie.Count) {
            $k = $Kategorie[$idx - 1]
            if ($k.Blokada) { Write-Host "   $($k.Nazwa): $($k.Blokada)" -ForegroundColor Yellow; continue }
            $k.Wybrana = -not $k.Wybrana
        }
        elseif ($idx -gt $Kategorie.Count -and $idx -le $Kategorie.Count + $Pozostalosci.Count) {
            $p = $Pozostalosci[$idx - $Kategorie.Count - 1]
            $p.Wybrana = -not $p.Wybrana
        }
    }
}

if ($Podglad) {
    Log 'Tryb podgladu - koniec bez usuwania.'
    Write-Host "`n   Tryb podglądu - nic nie zostało usunięte. Log: $LogPlik`n" -ForegroundColor Yellow
    ZatrzymajOllama
    Read-Host "   Enter kończy"
    exit
}

# ---------- WYKONANIE ----------
ZatrzymajOllama   # asystent nie jest juz potrzebny - zwalnia VRAM i RAM na czas czyszczenia
Naglowek "2/2  Czyszczenie"
Log ("Plan: kategorie [{0}], pozostalosci [{1}]" -f (($Kategorie | Where-Object { $_.Wybrana } | ForEach-Object { $_.Id }) -join ', '),
    (($Pozostalosci | Where-Object { $_.Wybrana } | ForEach-Object { $_.Id }) -join ', '))
$zegar = [Diagnostics.Stopwatch]::StartNew()
$suma = 0.0

foreach ($k in ($Kategorie | Where-Object { $_.Wybrana })) {
    $zysk = 0.0; $bledy = 0
    if ($k.Procesy -and (Get-Process $k.Procesy)) {
        Write-Host ("  {0,-52} {1}" -f $k.Nazwa, 'pominięto (przeglądarka działa)') -ForegroundColor Yellow
        Log "$($k.Id): pominieto - dziala przegladarka"
        continue
    }
    switch ($k.Typ) {
        'folder' {
            foreach ($u in $k.Uslugi) { Stop-Service $u -Force }
            if ($k.Uslugi) { Start-Sleep -Seconds 2 }
            foreach ($s in $k.Sciezki) {
                $r = UsunZawartosc $s ([int]$k.MinWiek)
                $zysk += $r.Bajty; $bledy += $r.Bledy
            }
            foreach ($u in $k.Uslugi) { Start-Service $u }
        }
        'kosz' { $zysk = $k.Bajty; Clear-RecycleBin -Force -Confirm:$false }
        'miniatury' {
            Stop-Process -Name explorer -Force
            Start-Sleep -Seconds 3
            foreach ($f in PlikiMiniatur) { try { $dl = $f.Length; $f.Delete(); $zysk += $dl } catch { $bledy++ } }
            if (-not (Get-Process explorer)) { Start-Process explorer.exe }
            Start-Sleep -Seconds 2
        }
        'dns' { ipconfig /flushdns | Out-Null }
        'dism' {
            Write-Host "  DISM pracuje - to potrwa kilka minut..." -ForegroundColor Gray
            $przed = WolneC
            Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
            $zysk = [math]::Max(0, (WolneC) - $przed)
        }
        'docker' { docker builder prune -a -f 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
    }
    $suma += $zysk
    $kolor = if ($zysk -gt 50MB) { 'Green' } else { 'Gray' }
    $dop = if ($bledy) { "  ($bledy w użyciu, pominięte)" } else { '' }
    Write-Host ("  {0,-52} {1,10}{2}" -f $k.Nazwa, (Rozmiar $zysk), $dop) -ForegroundColor $kolor
    Log ("{0}: {1} zwolnione, {2} pominietych" -f $k.Id, (Rozmiar $zysk), $bledy)
}

Add-Type -AssemblyName Microsoft.VisualBasic
$wybranePoz = @($Pozostalosci | Where-Object { $_.Wybrana })
if ($wybranePoz.Count) {
    Write-Host ""
    Write-Host "  Pozostałości po odinstalowanych programach i grach:" -ForegroundColor Cyan
    $kopie = Join-Path $LogDir ("kopie_rejestru\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    foreach ($p in $wybranePoz) {
        try {
            if ($p.Typ -eq 'folder') {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p.Sciezka, 'OnlyErrorDialogs', 'SendToRecycleBin')
                Write-Host ("  {0,-60} {1,10}  -> Kosz" -f $p.Sciezka, (Rozmiar $p.Bajty)) -ForegroundColor Green
                Log "Do Kosza (folder): $($p.Sciezka) ($(Rozmiar $p.Bajty))"
            }
            elseif ($p.Typ -eq 'plik') {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p.Sciezka, 'OnlyErrorDialogs', 'SendToRecycleBin')
                Write-Host ("  {0,-60} {1,10}  -> Kosz" -f $p.Sciezka, (Rozmiar $p.Bajty)) -ForegroundColor Green
                Log "Do Kosza (plik): $($p.Sciezka) ($(Rozmiar $p.Bajty))"
            }
            else {
                New-Item -ItemType Directory -Force $kopie | Out-Null
                $plik = Join-Path $kopie ("{0}_{1}.reg" -f $p.Id, ($p.Nazwa -replace '[^\w\-\. ]', '_'))
                & reg.exe export $p.Sciezka $plik /y 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $plik)) { throw 'nie udało się zrobić kopii - klucz zostawiony' }
                Remove-Item -LiteralPath "Registry::$($p.Sciezka)" -Recurse -Force -ErrorAction Stop
                Write-Host ("  {0,-60} {1,10}" -f $p.Sciezka, 'usunięty') -ForegroundColor Green
                Log "Rejestr usuniety: $($p.Sciezka) (kopia: $plik)"
            }
        }
        catch {
            Write-Host ("  {0}: {1}" -f $p.Sciezka, $_.Exception.Message) -ForegroundColor Yellow
            Log "Blad pozostalosci $($p.Sciezka): $($_.Exception.Message)"
        }
    }
    if (@($wybranePoz | Where-Object { $_.Typ -eq 'rejestr' }).Count) {
        Write-Host "  Kopie rejestru: $kopie (dwuklik na pliku .reg przywraca klucz)" -ForegroundColor DarkGray
    }
}

# ---------- PODSUMOWANIE ----------
$zegar.Stop()
$wolnePo = WolneC
Naglowek "PODSUMOWANIE"
Write-Host ("  Usunięte dane       : {0}" -f (Rozmiar $suma))
Write-Host ("  Czas                : {0}m {1}s" -f $zegar.Elapsed.Minutes, $zegar.Elapsed.Seconds)
Write-Host ("  Wolne na C: przed   : {0}" -f (Rozmiar $wolnePrzed))
Write-Host ("  Wolne na C: po      : {0}" -f (Rozmiar $wolnePo)) -ForegroundColor Green
Write-Host ""
Write-Host "  Log: $LogPlik" -ForegroundColor DarkGray
Log ("Koniec. Usunieto {0}, wolne C: {1} -> {2}" -f (Rozmiar $suma), (Rozmiar $wolnePrzed), (Rozmiar $wolnePo))
Write-Host ""
Read-Host "  Enter kończy"
