<#
    LLMCleaner - rdzen: uzytkownik, kategorie, skanery, plan, AI, aktualizacje i czyszczenie.
    Bez interfejsu: wszystko, co widzi uzytkownik, idzie przez Wypisz/Postep, a interfejs
    (Konsola.ps1 albo Okno.ps1) decyduje, gdzie to pokazac. Ladowany przez LLMCleaner.ps1.
#>

# ---------- JEZYK I WYJSCIE ----------
function L([string]$pl, [string]$en) { if ($Jezyk -eq 'en') { $en } else { $pl } }

$script:Tryb = 'konsola'   # albo 'okno' - ustawia Okno.ps1

function Wypisz([string]$t = '', [string]$kolor = 'Gray') {
    if ($script:Tryb -eq 'okno') { OknoWypisz $t $kolor } else { Write-Host $t -ForegroundColor $kolor }
}
# Linia postepu nadpisywana w miejscu
function Postep([string]$t) {
    if ($script:Tryb -eq 'okno') { OknoStatus $t } else { Write-Host "`r$t" -NoNewline -ForegroundColor DarkGray }
}
function KoniecPostepu([string]$t) {
    if ($script:Tryb -eq 'okno') { OknoStatus $t; OknoWypisz $t 'DarkGray' } else { Write-Host "`r$t" -ForegroundColor DarkGray }
}
function Pauza([int]$ms) {
    if ($script:Tryb -ne 'okno') { Start-Sleep -Milliseconds $ms; return }
    $koniec = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $koniec) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
}
# Dlugie wywolanie bez dostepu do funkcji skryptu (HTTP do modelu, GitHub): w oknie w osobnym
# watku, zeby okno nie zamarzalo; w konsoli zwyczajnie.
function CzekajNa([scriptblock]$sb, [object[]]$argumenty) {
    if ($script:Tryb -ne 'okno') { return & $sb @argumenty }
    $ps = [PowerShell]::Create().AddScript($sb.ToString())
    foreach ($a in $argumenty) { [void]$ps.AddArgument($a) }
    $h = $ps.BeginInvoke()
    while (-not $h.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
    try { $wynik = $ps.EndInvoke($h) }
    catch { throw $(if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }) }
    finally { $ps.Dispose() }
    if ($wynik.Count -eq 1) { $wynik[0] } else { $wynik }
}

# ---------- UZYTKOWNIK ----------
# Na koncie standardowym UAC prosi o haslo innego konta (administratora) i skrypt dziala wtedy
# jako ono. Sprzatamy jednak profil osoby, ktora program uruchomila: jej foldery, rejestr i Kosz.
$mojSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$InnyUzytkownik = $false
if ($Sid -and $Sid -ne $mojSid) {
    $profilSid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid").ProfileImagePath
    if ($profilSid -and (Test-Path -LiteralPath $profilSid) -and (Test-Path "Registry::HKEY_USERS\$Sid")) {
        $InnyUzytkownik = $true
        $env:USERPROFILE = $profilSid
    }
}
$UzytkownikSid = if ($InnyUzytkownik) { $Sid } else { $mojSid }
$HKCUNazwa = if ($InnyUzytkownik) { "HKEY_USERS\$Sid" } else { 'HKEY_CURRENT_USER' }
$HKCU = "Registry::$HKCUNazwa"

# Folder powloki uzytkownika (moze byc przeniesiony, np. Dokumenty do OneDrive albo Pobrane na D:)
function FolderUzytkownika([string]$nazwa, [string]$domyslny) {
    $v = (Get-ItemProperty "$HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders").$nazwa
    if ($v) {
        $v = [Environment]::ExpandEnvironmentVariables($v.Replace('%USERPROFILE%', $env:USERPROFILE))
        if (Test-Path -LiteralPath $v) { return $v.TrimEnd('\') }
    }
    $domyslny
}
if ($InnyUzytkownik) {
    $env:APPDATA = FolderUzytkownika 'AppData' "$env:USERPROFILE\AppData\Roaming"
    $env:LOCALAPPDATA = FolderUzytkownika 'Local AppData' "$env:USERPROFILE\AppData\Local"
    $env:TEMP = $env:TMP = "$env:LOCALAPPDATA\Temp"
}

# ---------- USTAWIENIA ----------
$Sys = $env:SystemDrive          # zwykle C:, ale Windows moze stac na innym dysku
$WinDir = $env:windir
$script:Analizy = @{}            # wyniki analizy dyskow, tez dla czatu
$script:Kategorie = @()
$script:Pozostalosci = @()
$script:Dysk = $null
# Wlasna Ollama w folderze programu (instaluje ja Install-AI.ps1); osobny port, zeby nie
# kolidowac z Ollama zainstalowana w systemie
$AiDir = Join-Path $AppDir 'ai'
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

# Element skanu, ktorego nie da sie odczytac (dziwny folder, wpis rejestru, uszkodzony skrot), jest
# pomijany zamiast przerywac caly skan. Szczegoly z miejscem bledu ida do logu.
$script:BledySkanu = 0
function BladSkanu([string]$co, $blad) {
    $script:BledySkanu++
    Log "Pominieto ($co): $($blad.Exception.Message) $($blad.ScriptStackTrace)"
}

function Rozmiar([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    if ($b -gt 0) { return '{0:N0} KB' -f ($b / 1KB) }
    return '0'
}

function WolneC { [double](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Sys'").FreeSpace }

function NazwaPewnosci([string]$p) {
    switch ($p) { 'wysoka' { L 'wysoka' 'high' } 'srednia' { L 'średnia' 'medium' } 'niska' { L 'niska' 'low' } default { $p } }
}

# Rozmiar do pokazania (kategorie bez mierzalnego rozmiaru maja '-')
function RozmiarKategorii($k) { if ($k.Typ -in 'folder', 'kosz', 'miniatury', 'winold', 'driverstore') { Rozmiar $k.Bajty } else { '-' } }

# Pozostalosci: foldery i pliki ida do Kosza; klucze i wartosci rejestru oraz zadania Harmonogramu
# maja kopie (.reg / .xml) i punkt przywracania
function NaKosz($p) { $p.Typ -in 'folder', 'plik' }
function RozmiarPozostalosci($p) {
    switch ($p.Typ) { 'rejestr' { L 'rejestr' 'registry' } 'wartosc' { L 'rejestr' 'registry' } 'zadanie' { L 'zadanie' 'task' } default { Rozmiar $p.Bajty } }
}
function PokazPozostalosc($p) {
    if ($p.Typ -eq 'zadanie') { return "$(L 'Harmonogram zadań' 'Task Scheduler'): $($p.Sciezka)" }
    if ($p.Typ -in 'rejestr', 'wartosc' -and $p.Nazwa -ne (Split-Path $p.Sciezka -Leaf)) { return "$($p.Nazwa)  [$($p.Sciezka)]" }
    $p.Sciezka
}

# Punkt przywracania systemu przed zmianami w rejestrze (obok kopii .reg). Zwraca opis wyniku.
function PunktPrzywracania {
    $ostatni = { Get-ComputerRestorePoint | Sort-Object SequenceNumber | Select-Object -Last 1 }
    $przed = & $ostatni
    try {
        Checkpoint-Computer -Description "LLMCleaner $Wersja" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
    }
    catch { return @{ Ok = $false; Opis = ((L 'nie utworzono ({0}) - ochrona systemu może być wyłączona' 'not created ({0}) - System Protection may be turned off') -f $_.Exception.Message.Trim()) } }
    $po = & $ostatni
    if ($po -and (-not $przed -or $po.SequenceNumber -ne $przed.SequenceNumber)) {
        return @{ Ok = $true; Opis = ((L 'utworzony (nr {0})' 'created (no. {0})') -f $po.SequenceNumber) }
    }
    $kiedy = if ($przed) { $przed.ConvertToDateTime($przed.CreationTime).ToString('dd.MM HH:mm') } else { '?' }
    @{ Ok = $false; Opis = ((L 'pominięty przez Windows - limit jednego punktu na dobę (ostatni: {0})' 'skipped by Windows - one restore point per day (last: {0})') -f $kiedy) }
}

# ---------- PLIKI: POMIAR I USUWANIE ----------

# Wszystkie pliki pod katalogiem. Nie wchodzi w junctions ani symlinki.
function Pliki($sciezka) {
    $stos = [System.Collections.Stack]::new()
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

# Czy pliku nie da sie teraz usunac: otwarty przez inny program bez zgody na usuniecie
# (np. swap.vhdx dzialajacego WSL) albo brak uprawnien. Otwiera z samym prawem DELETE - tak jak
# usuwanie - wiec nie czyta danych i antywirus go nie skanuje (~0,1 ms na plik zamiast ~2 ms).
function KompilujBlokade {
    if ('LlmBlokada' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LlmBlokada {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateFileW(string path, uint access, uint share, IntPtr sec, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static bool Zablokowany(string path) {
        // DELETE, FILE_SHARE_READ|WRITE|DELETE, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT
        IntPtr h = CreateFileW(@"\\?\" + path, 0x10000, 7, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
        if (h == new IntPtr(-1)) return true;
        CloseHandle(h);
        return false;
    }
}
'@
}

# Bajty - to, co UsunZawartosc faktycznie usunie; Zajete - pliki, ktorych teraz usunac sie nie da.
# Pliki mlodsze niz $minWiekDni nie naleza do kategorii i nie sa liczone wcale.
function Zmierz($sciezki, $minWiekDni = 0) {
    KompilujBlokade
    $bajty = 0.0; $n = 0; $zajete = 0.0; $zajetePliki = [System.Collections.Generic.List[object]]::new()
    $granica = (Get-Date).AddDays(-$minWiekDni)
    foreach ($s in $sciezki) {
        if (Test-Path -LiteralPath $s -PathType Leaf) { $pliki = @(Get-Item -LiteralPath $s -Force) }
        elseif (-not (Test-Path -LiteralPath $s -PathType Container)) { continue }
        elseif ((Get-Item -LiteralPath $s -Force).Attributes -band $REPARSE) { continue }
        else { $pliki = Pliki $s }
        foreach ($f in $pliki) {
            if ($minWiekDni -gt 0 -and $f.LastWriteTime -gt $granica) { continue }
            if ([LlmBlokada]::Zablokowany($f.FullName)) { $zajete += $f.Length; $zajetePliki.Add($f); continue }
            $bajty += $f.Length; $n++
        }
    }
    @{ Bajty = $bajty; Pliki = $n; Zajete = $zajete; ZajetePliki = $zajetePliki }
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
    $katalogi = [System.Collections.Generic.List[IO.DirectoryInfo]]::new()
    $stos = [System.Collections.Stack]::new()
    $stos.Push($korzen)
    $licznik = 0

    while ($stos.Count) {
        $d = $stos.Pop()
        if ((++$licznik % 200) -eq 0 -and $script:Tryb -eq 'okno') { [Windows.Forms.Application]::DoEvents() }
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

# Windows.old i pliki instalatora aktualizacji usuwa Oczyszczanie dysku Windows (cleanmgr /sagerun),
# tak jak "Wyczysc pliki systemowe". Recznie byloby niebezpiecznie: junctions w Windows.old
# wskazuja na biezace C:\Users, a przejmowanie uprawnien mogloby je zmienic.
$SageId = 'StateFlags0777'
$SageKlucz = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$SageHandlery = @('Previous Installations', 'Temporary Setup Files')
function UsunPoprzedniWindows {
    foreach ($h in $SageHandlery) {
        if (Test-Path "$SageKlucz\$h") { Set-ItemProperty "$SageKlucz\$h" -Name $SageId -Value 2 -Type DWord }
    }
    $p = Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -PassThru
    if ($p) { while (-not $p.WaitForExit(500)) { Pauza 0 } }
    foreach ($h in $SageHandlery) { Remove-ItemProperty "$SageKlucz\$h" -Name $SageId }
}

# ---------- BIALA LISTA KATEGORII ----------

function ProfilePrzegladarki($userData) {
    if (-not (Test-Path -LiteralPath $userData)) { return @() }
    Get-ChildItem -LiteralPath $userData -Directory -Force |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
        ForEach-Object { $_.FullName }
}

function CacheElectron($d) { "$d\Cache", "$d\Code Cache", "$d\GPUCache", "$d\DawnCache", "$d\Service Worker\CacheStorage" }

function ZbudujKategorie {
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

    # Cache aplikacji - kazda grupa jest pomijana osobno, gdy jej program dziala
    $steam = (Get-ItemProperty "$HKCU\Software\Valve\Steam").SteamPath
    $grupy = @(
        @{ Nazwa = 'Discord'; Procesy = @('discord'); Sciezki = @(CacheElectron "$env:APPDATA\discord") }
        @{ Nazwa = 'Slack'; Procesy = @('slack'); Sciezki = @(CacheElectron "$env:APPDATA\Slack") }
        @{ Nazwa = (L 'Teams (klasyczny)' 'Teams (classic)'); Procesy = @('teams'); Sciezki = @(CacheElectron "$env:APPDATA\Microsoft\Teams") }
        @{ Nazwa = 'VS Code'; Procesy = @('code'); Sciezki = @((CacheElectron "$env:APPDATA\Code") + "$env:APPDATA\Code\CachedData", "$env:APPDATA\Code\CachedExtensionVSIXs") }
        @{ Nazwa = 'Spotify'; Procesy = @('spotify'); Sciezki = @("$env:LOCALAPPDATA\Spotify\Data") }
        @{ Nazwa = 'Steam'; Procesy = @('steam', 'steamwebhelper')
           Sciezki = @($(if ($steam) { $s = $steam -replace '/', '\'; "$s\appcache\httpcache", "$s\appcache\librarycache" }) + "$env:LOCALAPPDATA\Steam\htmlcache") }
        @{ Nazwa = 'Epic Games Launcher'; Procesy = @('epicgameslauncher')
           Sciezki = @(Get-ChildItem "$env:LOCALAPPDATA\EpicGamesLauncher\Saved" -Directory -Force -Filter 'webcache*' | ForEach-Object { $_.FullName }) }
        @{ Nazwa = 'Battle.net'; Procesy = @('battle.net'); Sciezki = @("$env:LOCALAPPDATA\Battle.net\BrowserCaches", "$env:LOCALAPPDATA\Battle.net\Cache") }
    )
    # Zostaja tylko aplikacje, ktore sa na tym komputerze
    foreach ($g in $grupy) { $g.Sciezki = @($g.Sciezki | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) }
    $grupy = @($grupy | Where-Object { $_.Sciezki.Count })
    # IDE JetBrains osobno: po usunieciu indeksow projekty indeksuja sie od nowa (kilka minut)
    $jetbrains = @{ Nazwa = 'JetBrains'; Procesy = @('phpstorm64', 'webstorm64', 'idea64', 'pycharm64', 'rider64', 'clion64', 'goland64', 'datagrip64', 'rubymine64', 'rustrover64')
        Sciezki = @(Get-ChildItem "$env:LOCALAPPDATA\JetBrains" -Directory -Force | ForEach-Object { "$($_.FullName)\caches", "$($_.FullName)\index" } | Where-Object { Test-Path -LiteralPath $_ }) }
    $znalezione = if ($grupy) { ($grupy | ForEach-Object { $_.Nazwa }) -join ', ' } else { L 'brak' 'none' }

    $k = @(
        @{ Id = 'temp'; Nazwa = (L 'Pliki tymczasowe (TEMP)' 'Temporary files (TEMP)')
           Sciezki = @($env:TEMP, "$WinDir\Temp")
           Opis = (L 'Pliki tymczasowe programów i instalatorów. Pliki w użyciu są pomijane.' 'Temporary files of programs and installers. Files in use are skipped.') }
        @{ Id = 'inet'; Nazwa = (L 'Cache internetowy Windows (INetCache)' 'Windows internet cache (INetCache)')
           Sciezki = @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache")
           Opis = (L 'Cache silnika WebView/IE. Odtwarza się sam.' 'WebView/IE engine cache. Rebuilds itself.') }
        @{ Id = 'kosz'; Nazwa = (L 'Kosz' 'Recycle Bin'); Typ = 'kosz'
           Opis = (L 'Pliki usunięte przez użytkownika. Po opróżnieniu nie da się ich przywrócić.' 'Files you deleted. They cannot be restored after emptying.') }
        @{ Id = 'wer'; Nazwa = (L 'Raporty błędów i zrzuty pamięci' 'Error reports and memory dumps')
           Sciezki = @("$env:LOCALAPPDATA\Microsoft\Windows\WER",
                       "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                       "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                       "$env:LOCALAPPDATA\CrashDumps", "$WinDir\Minidump", "$WinDir\MEMORY.DMP", "$WinDir\LiveKernelReports")
           Opis = (L 'Raporty awarii programów, zrzuty pamięci po bluescreenach i raporty sterowników (LiveKernelReports, potrafią mieć kilka GB). Potrzebne tylko do diagnozy awarii.' 'Crash reports, blue screen memory dumps and driver reports (LiveKernelReports, can take several GB). Only needed to diagnose crashes.') }
        @{ Id = 'wu'; Nazwa = (L 'Cache Windows Update' 'Windows Update cache')
           Sciezki = @("$WinDir\SoftwareDistribution\Download", "$WinDir\SoftwareDistribution\DeliveryOptimization")
           Uslugi = @('wuauserv', 'bits')
           Opis = (L 'Pobrane już pliki aktualizacji. Windows pobierze je ponownie, jeśli będą potrzebne.' 'Already downloaded update files. Windows downloads them again if needed.') }
        @{ Id = 'logi'; Nazwa = (L 'Logi systemowe CBS/DISM (starsze niż 7 dni)' 'CBS/DISM system logs (older than 7 days)'); MinWiek = 7
           Sciezki = @("$WinDir\Logs\CBS", "$WinDir\Logs\DISM")
           Opis = (L 'Logi instalacji komponentów Windows.' 'Windows component installation logs.') }
        @{ Id = 'www'; Nazwa = (L 'Cache przeglądarek (Chrome, Edge, Brave, Firefox)' 'Browser caches (Chrome, Edge, Brave, Firefox)')
           Sciezki = $cachePrzegladarek
           Procesy = @('chrome', 'msedge', 'brave', 'firefox')
           Opis = (L 'Tylko cache stron i shaderów. Hasła, zakładki, historia i zalogowane sesje zostają.' 'Page and shader caches only. Passwords, bookmarks, history and sessions are kept.') }
        @{ Id = 'dev'; Nazwa = (L 'Cache narzędzi programistycznych' 'Developer tool caches')
           Sciezki = @("$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip\cache", "$env:LOCALAPPDATA\node-gyp\Cache",
                       "$env:LOCALAPPDATA\Yarn\Cache", "$env:LOCALAPPDATA\uv\cache", "$env:LOCALAPPDATA\NuGet\v3-cache",
                       "$env:LOCALAPPDATA\Composer\cache", "$env:LOCALAPPDATA\go-build",
                       "$env:USERPROFILE\.gradle\caches", "$env:USERPROFILE\.cargo\registry\cache", "$env:USERPROFILE\.bun\install\cache")
           Opis = (L 'Pobrane paczki npm/pip/yarn/uv/NuGet/Composer/Gradle/Cargo/Bun i cache Go. Pobiorą się ponownie przy następnej instalacji lub budowaniu.' 'Downloaded npm/pip/yarn/uv/NuGet/Composer/Gradle/Cargo/Bun packages and the Go build cache. They are downloaded again on the next install or build.') }
        @{ Id = 'apki'; Nazwa = (L 'Cache aplikacji' 'App caches'); Grupy = $grupy
           Sciezki = @($grupy | ForEach-Object { $_.Sciezki })
           Opis = ((L 'Tylko cache, konta i ustawienia zostają. Uruchomione aplikacje są pomijane. Znalezione: {0}.' 'Cache only; accounts and settings are kept. Running apps are skipped. Found: {0}.') -f $znalezione) }
        @{ Id = 'ide'; Nazwa = (L 'Cache i indeksy IDE JetBrains' 'JetBrains IDE caches and indexes'); Grupy = @($jetbrains); Sciezki = $jetbrains.Sciezki; TylkoRecznie = $true
           Opis = (L 'Cache i indeksy PhpStorm, WebStorm, IntelliJ itd. (także starych wersji). Po czyszczeniu IDE indeksuje projekty od nowa. Pomijane, gdy IDE działa.' 'Caches and indexes of PhpStorm, WebStorm, IntelliJ etc. (old versions too). The IDE re-indexes projects afterwards. Skipped while the IDE is running.') }
        @{ Id = 'sterowniki'; Nazwa = (L 'Stare instalatory sterowników (NVIDIA, AMD)' 'Old driver installers (NVIDIA, AMD)')
           Sciezki = @("$Sys\NVIDIA", "$Sys\AMD", "$env:ProgramData\NVIDIA Corporation\Downloader")
           Opis = (L 'Rozpakowane i pobrane instalatory sterowników. Zainstalowany sterownik działa bez nich.' 'Extracted and downloaded driver installers. The installed driver works without them.') }
        @{ Id = 'shadery'; Nazwa = (L 'Cache shaderów GPU (NVIDIA, DirectX)' 'GPU shader caches (NVIDIA, DirectX)')
           Sciezki = @("$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache", "$env:LOCALAPPDATA\D3DSCache")
           Opis = (L 'Skompilowane shadery. Pierwsze uruchomienie gier po czyszczeniu może się dłużej ładować.' 'Compiled shaders. Games may load longer the first time after cleaning.') }
        @{ Id = 'miniatury'; Nazwa = (L 'Miniaturki i cache ikon' 'Thumbnails and icon cache'); Typ = 'miniatury'
           Opis = (L 'Podglądy zdjęć i ikon w Eksploratorze. Wymaga restartu Eksploratora (pasek zadań zniknie na kilka sekund).' 'Picture and icon previews in File Explorer. Explorer restarts (the taskbar disappears for a few seconds).') }
        @{ Id = 'dns'; Nazwa = (L 'Cache DNS' 'DNS cache'); Typ = 'dns'
           Opis = (L 'Zapamiętane adresy stron. Nie zwalnia miejsca, pomaga przy problemach z siecią.' 'Remembered website addresses. Frees no space; helps with network problems.') }
        @{ Id = 'winold'; Nazwa = (L 'Poprzednia wersja Windows (Windows.old)' 'Previous Windows version (Windows.old)'); Typ = 'winold'; TylkoRecznie = $true
           Sciezki = @("$Sys\Windows.old", "$Sys\`$WINDOWS.~BT", "$Sys\`$WINDOWS.~WS")
           Opis = (L 'Kopia systemu sprzed dużej aktualizacji, zwykle 10-30 GB. Po usunięciu nie da się wrócić do poprzedniej wersji Windows.' 'A copy of the system from before a major update, usually 10-30 GB. Afterwards you cannot go back to the previous Windows version.') }
        @{ Id = 'dism'; Nazwa = (L 'Magazyn komponentów WinSxS (DISM)' 'WinSxS component store (DISM)'); Typ = 'dism'; TylkoRecznie = $true
           Opis = (L 'Usuwa zastąpione wersje komponentów Windows, zwykle 1-3 GB. Trwa kilka minut. Potem nie da się odinstalować wcześniejszych aktualizacji.' 'Removes superseded Windows components, usually 1-3 GB. Takes a few minutes. Older updates can no longer be uninstalled afterwards.') }
    )
    if (Get-Command Get-WindowsDriver) {
        $k += @{ Id = 'driverstore'; Nazwa = (L 'Starsze wersje sterowników (DriverStore)' 'Older driver versions (DriverStore)'); Typ = 'driverstore'; TylkoRecznie = $true
                 Opis = (L 'Wersje sterowników zastąpione nowszymi, np. stare sterowniki karty graficznej (często 1-5 GB). Sterowniki używane i najnowsza wersja każdego zostają. Potem nie da się wrócić do starszej wersji w Menedżerze urządzeń.' 'Driver versions replaced by newer ones, e.g. old graphics drivers (often 1-5 GB). Drivers in use and the newest version of each are kept. Afterwards you cannot roll back to an older version in Device Manager.') }
    }
    if (Get-Command docker) {
        $k += @{ Id = 'docker'; Nazwa = (L 'Docker - cache budowania' 'Docker build cache'); Typ = 'docker'; TylkoRecznie = $true
                 Opis = (L 'Tylko build cache. Obrazy, kontenery i wolumeny (w tym bazy danych) zostają.' 'Build cache only. Images, containers and volumes (including databases) are kept.') }
    }
    foreach ($x in $k) { if (-not $x.Typ) { $x.Typ = 'folder' } }
    $k
}

$sciezkaExplorer = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
function PlikiMiniatur {
    Get-ChildItem -LiteralPath $sciezkaExplorer -Force -File |
        Where-Object { $_.Name -like 'thumbcache_*.db' -or $_.Name -like 'iconcache_*.db' }
}

# Starsze wersje sterownikow w magazynie (DriverStore). Pakiety grupujemy po nazwie oryginalnego .inf,
# dostawcy i klasie; w grupie zostaje najnowsza wersja i kazda uzywana przez urzadzenie. Pozostale usuwa
# pnputil bez /force, wiec i tak odmowi pakietu w uzyciu. Tak samo dziala DriverStore Explorer.
function WersjaSterownika($v) { $x = $null; if ([version]::TryParse("$v", [ref]$x)) { $x } else { [version]'0.0' } }
function StareSterowniki {
    $uzywane = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver) { if ($d.InfName) { $uzywane[$d.InfName.ToLower()] = 1 } }
    $grupy = @{}
    foreach ($d in Get-WindowsDriver -Online) {
        if (-not $d.Driver -or -not $d.OriginalFileName) { continue }
        $klucz = '{0}|{1}|{2}' -f (Split-Path $d.OriginalFileName -Leaf).ToLower(), $d.ProviderName, $d.ClassName
        if (-not $grupy[$klucz]) { $grupy[$klucz] = [System.Collections.Generic.List[object]]::new() }
        $grupy[$klucz].Add($d)
    }
    foreach ($g in $grupy.Values) {
        if ($g.Count -lt 2) { continue }
        $odNajnowszej = @($g | Sort-Object @{ Expression = { WersjaSterownika $_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        foreach ($d in @($odNajnowszej | Select-Object -Skip 1)) {
            if ($uzywane[$d.Driver.ToLower()]) { continue }
            $folder = Split-Path $d.OriginalFileName -Parent
            # Zwykla suma: pliki magazynu naleza do systemu, test blokady uznalby je wszystkie za zablokowane
            @{ Inf = $d.Driver; Nazwa = (Split-Path $d.OriginalFileName -Leaf); Dostawca = $d.ProviderName; Wersja = $d.Version
               Folder = $folder; Bajty = [double](Pliki $folder | Measure-Object Length -Sum).Sum }
        }
    }
}

# ---------- DYSKI ----------
# Lokalne dyski stale z litera. Pomijane: USB/karty (DriveType 2), sieciowe (4), CD (5), partycje bez litery
# (EFI, Recovery) i woluminy niedostepne, np. zablokowane BitLockerem (brak rozmiaru).
function DyskiStale { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.Size -gt 0 } }

# Dyski wybrane przez uzytkownika. Dysk systemowy jest zawsze skanowany (cache Windows, profil,
# Program Files); pozostale wplywaja na Kosz, biblioteki Steam/Epic i analize miejsca.
$script:WybraneDyski = @($Sys)
function DyskiWybrane { DyskiStale | Where-Object { $_.DeviceID -in $script:WybraneDyski } }
function NaWybranymDysku([string]$p) { $p.Length -ge 2 -and $p.Substring(0, 2).ToUpper() -in $script:WybraneDyski }
function UstawDyski([string[]]$litery) {
    $wszystkie = @(DyskiStale | ForEach-Object { $_.DeviceID })
    $script:WybraneDyski = @(@($Sys) + @($litery | ForEach-Object { $_ -split ',' } | Where-Object { $_ } |
        ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() + ':' }) | Where-Object { $_ -in $wszystkie } | Select-Object -Unique)
}
function OpisDysku($d) {
    $nazwa = if ($d.VolumeName) { $d.VolumeName } else { L 'bez nazwy' 'no label' }
    (L '{0} {1} - wolne {2} z {3}' '{0} {1} - {2} free of {3}') -f $d.DeviceID, $nazwa, (Rozmiar $d.FreeSpace), (Rozmiar $d.Size)
}

# Kosz uzytkownika na kazdym wybranym dysku: X:\$Recycle.Bin\<SID>
function FolderyKosza { foreach ($d in DyskiWybrane) { $p = "$($d.DeviceID)\`$Recycle.Bin\$UzytkownikSid"; if (Test-Path -LiteralPath $p) { $p } } }

# ---------- SKANER ----------

function SkanujKategorie {
    foreach ($k in $script:Kategorie) {
        Wypisz ("   {0}..." -f $k.Nazwa) 'DarkGray'
        $k.Blokada = $null; $k.Uwaga = $null
        $k.Bajty = 0.0; $k.Zablokowane = 0.0
        try {
            switch ($k.Typ) {
                'folder' {
                    $m = Zmierz $k.Sciezki ([int]$k.MinWiek); $k.Bajty = $m.Bajty; $k.Pliki = $m.Pliki; $k.Zablokowane = $m.Zajete
                    if ($m.Zajete) {
                        $najwieksze = @($m.ZajetePliki | Sort-Object Length -Descending)
                        $nazwy = ($najwieksze | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
                        if ($najwieksze.Count -gt 3) { $nazwy += (L ' i {0} innych' ' and {0} more') -f ($najwieksze.Count - 3) }
                        $k.Uwaga = (L 'Razem {0}: do usunięcia {1}, zablokowane {2} - pliki używane przez działające programy ({3}). Zamknij je, żeby usunąć resztę.' 'Total {0}: {1} can be deleted, {2} is locked - files used by running programs ({3}). Close them to delete the rest.') -f (Rozmiar ($m.Bajty + $m.Zajete)), (Rozmiar $m.Bajty), (Rozmiar $m.Zajete), $nazwy
                        Log "$($k.Id): zablokowane $(Rozmiar $m.Zajete) w $($najwieksze.Count) plikach, najwieksze: $nazwy"
                    }
                }
                'winold' { $m = Zmierz $k.Sciezki; $k.Bajty = $m.Bajty; $k.Pliki = $m.Pliki }
                'kosz' { $k.Bajty = (Zmierz @(FolderyKosza)).Bajty }
                'miniatury' { $k.Bajty = [double](PlikiMiniatur | Measure-Object Length -Sum).Sum }
                'driverstore' {
                    $k.Pakiety = @(StareSterowniki | Sort-Object { $_.Bajty } -Descending)
                    $k.Bajty = [double]($k.Pakiety | ForEach-Object { $_.Bajty } | Measure-Object -Sum).Sum; $k.Pliki = $k.Pakiety.Count
                    if ($k.Pakiety.Count) {
                        $k.Uwaga = (L 'Do usunięcia {0} pakietów, największe: {1}.' '{0} packages to remove, the largest: {1}.') -f $k.Pakiety.Count,
                            (($k.Pakiety | Select-Object -First 3 | ForEach-Object { '{0} {1} ({2}, {3})' -f $_.Nazwa, $_.Wersja, $_.Dostawca, (Rozmiar $_.Bajty) }) -join ', ')
                        Log "driverstore: $(($k.Pakiety | ForEach-Object { "$($_.Inf)=$($_.Nazwa) $($_.Wersja)" }) -join ', ')"
                    }
                }
            }
        }
        catch { BladSkanu "kategoria $($k.Id)" $_ }
        if ($k.Procesy -and (Get-Process $k.Procesy)) { $k.Blokada = L 'uruchomiona przeglądarka - zamknij ją przed czyszczeniem' 'a browser is running - close it before cleaning' }
    }
}

function KatalogPobranych { FolderUzytkownika '{374DE290-123F-4565-9164-39C4925E467B}' "$env:USERPROFILE\Downloads" }

function SkanujDysk {
    $profil = $env:USERPROFILE
    $gorne = @{}; $appdata = @{}
    $duze = [System.Collections.Generic.List[object]]::new()
    $n = 0

    foreach ($f in Pliki $profil) {
        $n++
        if ($n % 5000 -eq 0) { Postep ((L '   przejrzano {0:N0} plików...' '   scanned {0:N0} files...') -f $n) }
        if ([int]$f.Attributes -band 0x401000) { continue }   # pliki tylko w chmurze (OneDrive)
        $czesci = $f.FullName.Substring($profil.Length + 1).Split('\')
        if ($czesci.Count -lt 2) { continue }
        $gorne[$czesci[0]] += $f.Length
        if ($czesci[0] -eq 'AppData') {
            if ($czesci.Count -gt 3 -and $czesci[1] -in 'Local', 'Roaming') { $appdata["AppData\$($czesci[1])\$($czesci[2])"] += $f.Length }
        }
        elseif ($f.Length -ge 1GB) { $duze.Add($f) }
    }
    KoniecPostepu ((L '   przejrzano {0:N0} plików w profilu.           ' '   scanned {0:N0} files in the profile.           ') -f $n)

    # Kandydaci do recznego usuniecia: duze pliki w Pobranych + pliki > 1 GB poza AppData.
    $pobrane = KatalogPobranych
    $kandydaci = @()
    $z_pobranych = @(Pliki $pobrane | Where-Object { $_.Length -ge 100MB } | Sort-Object Length -Descending | Select-Object -First 15)
    $reszta = @($duze | Where-Object { $_.FullName -notlike "$pobrane\*" } | Sort-Object Length -Descending | Select-Object -First 12)
    foreach ($f in @($z_pobranych) + @($reszta)) {
        $kandydaci += @{ Sciezka = $f.FullName; Bajty = [double]$f.Length; Zmodyfikowany = $f.LastWriteTime
                         Pobrane = ($f.FullName -like "$pobrane\*") }
    }

    $programy = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                 "$HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -and ($_.EstimatedSize -as [double]) } |
        Sort-Object { $_.EstimatedSize -as [double] } -Descending | Select-Object -First 12 |
        ForEach-Object { @{ nazwa = $_.DisplayName; rozmiar = (Rozmiar (($_.EstimatedSize -as [double]) * 1KB)); zainstalowano = $_.InstallDate } }

    $hib = Get-Item -LiteralPath "$Sys\hiberfil.sys" -Force
    @{
        Kandydaci = $kandydaci
        Profil = @($gorne.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
                   ForEach-Object { @{ folder = $_.Key; rozmiar = (Rozmiar $_.Value) } })
        AppData = @($appdata.GetEnumerator() | Where-Object { $_.Value -ge 300MB } | Sort-Object Value -Descending |
                    Select-Object -First 12 | ForEach-Object { @{ folder = $_.Key; rozmiar = (Rozmiar $_.Value) } })
        Programy = @($programy)
        System = @{
            hiberfil = $(if ($hib) { Rozmiar $hib.Length } else { L 'brak (hibernacja wyłączona)' 'none (hibernation off)' })
            windows_old = (Test-Path -LiteralPath "$Sys\Windows.old")
            stara_instalacja_bt = (Test-Path -LiteralPath "$Sys\`$WINDOWS.~BT")
        }
        Dyski = @(DyskiWybrane | ForEach-Object { @{ dysk = $_.DeviceID; wolne = (Rozmiar $_.FreeSpace); calosc = (Rozmiar $_.Size) } })
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
                   "$HKCUNazwa\Software\Microsoft\Windows\CurrentVersion\Uninstall") {
        foreach ($k in Get-ChildItem "Registry::$r") {
            $v = Get-ItemProperty -LiteralPath $k.PSPath
            if ($v.DisplayName) { @{ Klucz = "$r\$($k.PSChildName)"; V = $v } }
        }
    }
}

# Martwe wpisy na liscie programow: deinstalator i folder instalacji nie istnieja.
# Wpisy MSI pomijamy - ich usuniecie rozspojniloby baze Instalatora Windows.
function MartweWpisy($wpisy) {
    foreach ($w in $wpisy) { try {
        $v = $w.V
        if ($v.SystemComponent -eq 1 -or $v.WindowsInstaller -eq 1 -or "$($v.UninstallString)" -match 'msiexec') { continue }
        $exe = SciezkaPliku $v.UninstallString
        if (-not $exe -or (Test-Path -LiteralPath $exe)) { continue }
        $loc = "$($v.InstallLocation)".Trim('"', ' ')
        if ($loc -and (Test-Path -LiteralPath $loc)) { continue }
        @{ Typ = 'rejestr'; Sciezka = $w.Klucz; Nazwa = $v.DisplayName; Bajty = 0.0
           Pewnosc = $(if ($loc) { 'wysoka' } else { 'srednia' })
           Dlaczego = $(if ($loc) { L 'Martwy wpis na liście programów: deinstalator nie istnieje, folder instalacji też nie.' 'Dead entry in the program list: the uninstaller and the install folder are both gone.' }
                        else { L 'Martwy wpis na liście programów: deinstalator nie istnieje.' 'Dead entry in the program list: the uninstaller is gone.' }) }
    } catch { BladSkanu "wpis $($w.Klucz)" $_ } }
}

function ZainstalowaneProgramy($wpisy) {
    $tokeny = [System.Collections.Generic.HashSet[string]]::new()
    $nazwy = [System.Collections.Generic.List[string]]::new()
    $sciezki = [System.Collections.Generic.List[string]]::new()
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
    $appx = if ($InnyUzytkownik) { Get-AppxPackage -User $UzytkownikSid } else { Get-AppxPackage }
    foreach ($a in $appx) { Dodaj $a.Name; DodajSciezke $a.InstallLocation }
    foreach ($g in SteamGry) { Dodaj $g }
    foreach ($p in Get-Process) {
        if ($p.Path) { try { DodajSciezke $p.Path; Dodaj ([IO.Path]::GetFileNameWithoutExtension($p.Path)) } catch { BladSkanu "proces $($p.Path)" $_ } }
    }
    foreach ($s in Get-CimInstance Win32_Service) { DodajSciezke (SciezkaPliku $s.PathName) }
    # Skroty w menu Start i na pulpicie - lapia programy przenosne bez wpisu w rejestrze
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:ProgramData\Microsoft\Windows\Start Menu",
                   (FolderUzytkownika 'Desktop' "$env:USERPROFILE\Desktop"), "$env:PUBLIC\Desktop") {
        foreach ($l in Get-ChildItem -LiteralPath $d -Recurse -Filter *.lnk -Force) {
            Dodaj $l.BaseName
            try { $t = $sh.CreateShortcut($l.FullName).TargetPath; if ($t) { DodajSciezke $t } }
            catch { BladSkanu "skrot $($l.FullName)" $_ }
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
    $b = 0.0; $ost = [datetime]::MinValue; $exe = $false
    foreach ($f in Pliki $p) {
        $b += $f.Length; if ($f.LastWriteTime -gt $ost) { $ost = $f.LastWriteTime }
        if (-not $exe -and $f.Extension -eq '.exe') { $exe = $true }
    }
    if ($ost -eq [datetime]::MinValue) {
        # Folder pusty albo nieczytelny. Gdy nie da sie odczytac nawet jego daty, traktujemy go jak
        # swiezy - nieznany folder nie moze trafic do planu jako stary
        $ost = (Get-Item -LiteralPath $p -Force).LastWriteTime
        if ($ost -isnot [datetime]) { $ost = Get-Date }
    }
    @{ Bajty = $b; Ostatnio = $ost; MaExe = $exe }
}

function SteamBiblioteki {
    $steam = (Get-ItemProperty "$HKCU\Software\Valve\Steam").SteamPath
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
    foreach ($b in @(SteamBiblioteki | Where-Object { NaWybranymDysku $_ })) {
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
                   Dlaczego = (L 'Folder gry Steam bez manifestu - gra została odinstalowana, pliki zostały.' 'Steam game folder without a manifest - the game was uninstalled but its files remain.') }
            }
        }
        foreach ($sub in 'shadercache', 'workshop\content') {
            foreach ($d in Get-ChildItem -LiteralPath "$sa\$sub" -Directory -Force) {
                if ($d.Name -match '^\d+$' -and -not $ids[$d.Name]) {
                    @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = "Steam $sub $($d.Name)"; Pewnosc = 'wysoka'; Gra = $true
                       Dlaczego = ((L 'Steam {0} dla gry (appid {1}), której już nie ma.' 'Steam {0} for a game (appid {1}) that is no longer installed.') -f $sub, $d.Name) }
                }
            }
        }
    }
}

function EpicOsierocone {
    $man = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (-not (Test-Path -LiteralPath $man)) { return }
    $zainst = @{}; $rodzice = @{ "$env:ProgramFiles\Epic Games".ToLower() = 1 }
    foreach ($i in Get-ChildItem -LiteralPath $man -Filter *.item) {
        $loc = (Get-Content -LiteralPath $i.FullName -Raw | ConvertFrom-Json).InstallLocation
        if ($loc) { $loc = $loc.TrimEnd('\').ToLower(); $zainst[$loc] = 1; $rodzice[(Split-Path $loc -Parent)] = 1 }
    }
    foreach ($r in @($rodzice.Keys | Where-Object { NaWybranymDysku $_ })) {
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force) {
            if ($zainst[$d.FullName.ToLower()] -or $d.Name -in 'Launcher', 'DirectXRedist' -or $d.Name -like 'UE_*') { continue }
            @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = $d.Name; Pewnosc = 'wysoka'; Gra = $true
               Dlaczego = (L 'Folder gry Epic, której nie ma na liście zainstalowanych w Epic Games Launcher.' 'Epic game folder that is not on the Epic Games Launcher list of installed games.') }
        }
    }
}

# ---------- MARTWE WPISY STARTOWE, SKROTY I ZADANIA ----------
# Wskazuja na program, ktorego juz nie ma. Liczy sie tylko pewny brak: sciezka bezwzgledna na dysku,
# ktory istnieje (odlaczony dysk USB to nie martwy wpis), poza folderem Windows (przekierowanie
# System32/SysWOW64 dawaloby falszywe braki) i poza udzialami sieciowymi.
function BrakujacyPlik([string]$p) {
    if (-not $p -or $p.StartsWith('\\') -or -not [IO.Path]::IsPathRooted($p)) { return $false }
    if ($p -like "$WinDir\*") { return $false }
    try { if (-not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($p)))) { return $false } } catch { return $false }
    if (Test-Path -LiteralPath $p) { return $false }
    # Skroty 32-bitowych programow potrafia zwracac Program Files zamiast Program Files (x86) i odwrotnie
    if ($p -match '\\Program Files\\' -and (Test-Path -LiteralPath ($p -replace '\\Program Files\\', '\Program Files (x86)\'))) { return $false }
    if ($p -match '\\Program Files \(x86\)\\' -and (Test-Path -LiteralPath ($p -replace '\\Program Files \(x86\)\\', '\Program Files\'))) { return $false }
    $true
}

# Klucze Run z ich odpowiednikami StartupApproved (tam Windows i Menedzer zadan zapisuja wylaczenie)
$AutostartKlucz = 'Software\Microsoft\Windows\CurrentVersion'
function KluczeRun {
    @{ Klucz = "$HKCUNazwa\$AutostartKlucz\Run"; Zgoda = "$HKCUNazwa\$AutostartKlucz\Explorer\StartupApproved\Run"; Zrodlo = (L 'Rejestr (użytkownik)' 'Registry (user)') }
    @{ Klucz = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Run"; Zgoda = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Explorer\StartupApproved\Run"; Zrodlo = (L 'Rejestr (wszyscy)' 'Registry (all users)') }
    @{ Klucz = "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Zgoda = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Explorer\StartupApproved\Run32"; Zrodlo = (L 'Rejestr (wszyscy, 32-bit)' 'Registry (all users, 32-bit)') }
}
function FolderyAutostartu {
    @{ Folder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Zgoda = "$HKCUNazwa\$AutostartKlucz\Explorer\StartupApproved\StartupFolder"; Zrodlo = (L 'Folder Autostart (użytkownik)' 'Startup folder (user)') }
    @{ Folder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"; Zgoda = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Explorer\StartupApproved\StartupFolder"; Zrodlo = (L 'Folder Autostart (wszyscy)' 'Startup folder (all users)') }
}

# Zadania Harmonogramu poza \Microsoft\ (tamte sa czescia Windows)
function ZadaniaInnychFirm { Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } }
function ProgramyZadania($t) { @($t.Actions | Where-Object { $_.Execute } | ForEach-Object { SciezkaPliku $_.Execute }) }

function MartweAutostarty {
    foreach ($r in KluczeRun) {
        $k = Get-Item -LiteralPath "Registry::$($r.Klucz)"
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) { try {
            if (-not $n) { continue }
            $cel = SciezkaPliku ([string]$k.GetValue($n))
            if (-not (BrakujacyPlik $cel)) { continue }
            @{ Typ = 'wartosc'; Sciezka = $r.Klucz; Wartosc = $n; Nazwa = $n; Bajty = 0.0; Pewnosc = 'wysoka'
               Dlaczego = ((L 'Martwy wpis autostartu: program {0} nie istnieje.' 'Dead startup entry: the program {0} no longer exists.') -f $cel) }
        } catch { BladSkanu "autostart $($r.Klucz)\$n" $_ } }
    }

    # Skroty: w Autostarcie i menu Start pewne, na pulpicie srednie (moze je ktos sam zrobil)
    $sh = New-Object -ComObject WScript.Shell
    $miejsca = @(FolderyAutostartu | ForEach-Object { @{ D = $_.Folder; P = 'wysoka'; Rek = $false } }) + @(
        @{ D = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"; P = 'wysoka'; Rek = $true }
        @{ D = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"; P = 'wysoka'; Rek = $true }
        @{ D = (FolderUzytkownika 'Desktop' "$env:USERPROFILE\Desktop"); P = 'srednia'; Rek = $false }
        @{ D = "$env:PUBLIC\Desktop"; P = 'srednia'; Rek = $false })
    $widziane = @{}
    foreach ($m in $miejsca) {
        foreach ($l in Get-ChildItem -LiteralPath $m.D -Filter *.lnk -Force -File -Recurse:$m.Rek) { try {
            if ($widziane[$l.FullName]) { continue }
            $widziane[$l.FullName] = 1
            $cel = $sh.CreateShortcut($l.FullName).TargetPath   # pusty u skrotow MSI i aplikacji ze Sklepu
            if (-not (BrakujacyPlik $cel)) { continue }
            @{ Typ = 'plik'; Sciezka = $l.FullName; Nazwa = $l.BaseName; Bajty = [double]$l.Length; Ostatnio = $l.LastWriteTime; Pewnosc = $m.P
               Dlaczego = ((L 'Skrót do programu, którego już nie ma ({0}).' 'Shortcut to a program that no longer exists ({0}).') -f $cel) }
        } catch { BladSkanu "skrot $($l.FullName)" $_ } }
    }

    # Zadania: martwe, gdy zaden z ich programow nie istnieje
    foreach ($t in ZadaniaInnychFirm) { try {
        $progs = ProgramyZadania $t
        if (-not $progs.Count -or @($progs | Where-Object { -not (BrakujacyPlik $_) }).Count) { continue }
        @{ Typ = 'zadanie'; Sciezka = "$($t.TaskPath)$($t.TaskName)"; Nazwa = $t.TaskName; Folder = $t.TaskPath; Bajty = 0.0; Pewnosc = 'wysoka'
           Dlaczego = ((L 'Zadanie Harmonogramu uruchamia program, którego już nie ma ({0}).' 'Scheduled task runs a program that no longer exists ({0}).') -f ($progs -join ', ')) }
    } catch { BladSkanu "zadanie $($t.TaskPath)$($t.TaskName)" $_ } }
}

# ---------- MENEDZER AUTOSTARTU ----------
# Programy uruchamiane przy logowaniu. Niczego tu nie usuwamy: wpisy Run i folderu Autostart wylaczamy
# tak jak Menedzer zadan (wartosc w StartupApproved, nieparzysty pierwszy bajt = wylaczony), zadania
# Harmonogramu - Disable-ScheduledTask. Wlaczenie przywraca dokladnie poprzedni stan.

# Ochrona, sterowniki i panele sprzetu: wylaczenie potrafi zepsuc touchpad, dzwiek albo ochrone
$ChronioneAutostart = @('securityhealth*', '*defender*', 'msmpeng*', '*antivirus*', 'avast*', 'avg*', 'egui*', 'eset*',
    'avp*', 'kaspersky*', 'bdagent*', 'bitdefender*', 'norton*', 'mcafee*', 'mbam*', 'malwarebytes*', 'sophos*',
    'rthdvcpl*', 'rtkaud*', 'rtkngui*', 'realtek*', 'igfx*', 'synaptics*', 'syntp*', 'etdctrl*', 'elan*', 'waves*',
    'maxxaudio*', 'dolby*')
$script:Autostart = $null

function OchronaAutostartu($w) {
    if ($w.Plik -like "$WinDir\*") { return L 'część Windows' 'part of Windows' }
    foreach ($x in @($w.Nazwa, $(if ($w.Plik) { [IO.Path]::GetFileNameWithoutExtension($w.Plik) })) | Where-Object { $_ }) {
        foreach ($wz in $ChronioneAutostart) {
            if ($x -like $wz) { return L 'ochrona, sterownik albo panel sprzętu - wyłączenie może coś zepsuć' 'security software, a driver or a hardware panel - turning it off may break something' }
        }
    }
    if ($w.Nazwa -match 'update') { return L 'aktualizacje programu - bez nich nie dostanie poprawek bezpieczeństwa' 'program updates - without them it gets no security fixes' }
    $null
}

function WpisAutostartu([hashtable]$w) {
    $w.Istnieje = [bool]($w.Plik -and (Test-Path -LiteralPath $w.Plik))
    $w.Wydawca = if ($w.Istnieje) { (Get-Item -LiteralPath $w.Plik -Force).VersionInfo.CompanyName } else { '' }
    $w.Chroniony = OchronaAutostartu $w
    $w
}

# Wylaczony przez uzytkownika (Menedzer zadan, Ustawienia > Aplikacje > Uruchamianie albo LLMCleaner)
function StanZgody([string]$klucz, [string]$nazwa) {
    $b = (Get-ItemProperty -LiteralPath "Registry::$klucz" -Name $nazwa).$nazwa
    -not ($b -is [byte[]] -and $b.Length -and ($b[0] -band 1))
}
function UstawZgode([string]$klucz, [string]$nazwa, [bool]$wlacz) {
    if (-not (Test-Path -LiteralPath "Registry::$klucz")) { New-Item -Path "Registry::$klucz" -Force -ErrorAction Stop | Out-Null }
    $b = [byte[]]::new(12)
    if ($wlacz) { $b[0] = 2 } else { $b[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4) }
    Set-ItemProperty -LiteralPath "Registry::$klucz" -Name $nazwa -Value $b -Type Binary -ErrorAction Stop
}

function WpisyAutostartu {
    $wyn = [System.Collections.Generic.List[object]]::new()
    foreach ($r in KluczeRun) {
        $k = Get-Item -LiteralPath "Registry::$($r.Klucz)"
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) { try {
            if (-not $n) { continue }
            $pol = [string]$k.GetValue($n)
            $wyn.Add((WpisAutostartu @{ Rodzaj = 'run'; Nazwa = $n; Polecenie = $pol; Plik = (SciezkaPliku $pol); Zrodlo = $r.Zrodlo
                                        Zgoda = $r.Zgoda; ZgodaNazwa = $n; Wlaczony = (StanZgody $r.Zgoda $n) }))
        } catch { BladSkanu "autostart $($r.Klucz)\$n" $_ } }
    }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($f in FolderyAutostartu) {
        foreach ($l in Get-ChildItem -LiteralPath $f.Folder -File -Force | Where-Object { $_.Name -ne 'desktop.ini' }) { try {
            $cel = if ($l.Extension -eq '.lnk') { $sh.CreateShortcut($l.FullName).TargetPath } else { $l.FullName }
            $wyn.Add((WpisAutostartu @{ Rodzaj = 'folder'; Nazwa = $l.BaseName; Polecenie = $l.FullName; Plik = $cel; Zrodlo = $f.Zrodlo
                                        Zgoda = $f.Zgoda; ZgodaNazwa = $l.Name; Wlaczony = (StanZgody $f.Zgoda $l.Name) }))
        } catch { BladSkanu "autostart $($l.FullName)" $_ } }
    }
    foreach ($t in ZadaniaInnychFirm) { try {
        if (-not @($t.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' }).Count) { continue }
        $progs = ProgramyZadania $t
        $wyn.Add((WpisAutostartu @{ Rodzaj = 'zadanie'; Nazwa = $t.TaskName; Folder = $t.TaskPath; Plik = $(if ($progs.Count) { $progs[0] })
            Polecenie = (@($t.Actions | Where-Object { $_.Execute } | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; ')
            Zrodlo = (L 'Harmonogram zadań' 'Task Scheduler'); Wlaczony = ($t.State -ne 'Disabled') }))
    } catch { BladSkanu "zadanie $($t.TaskPath)$($t.TaskName)" $_ } }
    $n = 0; foreach ($w in $wyn) { $n++; $w.Id = "S$n" }
    Log ("Autostart: {0} wpisow, wlaczonych {1}" -f $wyn.Count, @($wyn | Where-Object { $_.Wlaczony }).Count)
    $script:Autostart = $wyn.ToArray()
    $script:Rozmowa = $null   # nowe dane dla czatu
    $script:Autostart
}

function PrzelaczAutostart($w, [bool]$wlacz) {
    if ($w.Chroniony) { throw ((L '{0}: nie zmieniam ({1})' '{0}: not changed ({1})') -f $w.Nazwa, $w.Chroniony) }
    if ($w.Rodzaj -eq 'zadanie') {
        if ($wlacz) { Enable-ScheduledTask -TaskName $w.Nazwa -TaskPath $w.Folder -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskName $w.Nazwa -TaskPath $w.Folder -ErrorAction Stop | Out-Null }
    }
    else { UstawZgode $w.Zgoda $w.ZgodaNazwa $wlacz }
    $w.Wlaczony = $wlacz
    $script:Rozmowa = $null
    Log ("Autostart {0}: {1} ({2}, {3})" -f $(if ($wlacz) { 'wlaczony' } else { 'wylaczony' }), $w.Nazwa, $w.Zrodlo, $w.Polecenie)
}

# Kopia jednej wartosci rejestru jako .reg - dwuklik przywraca tylko ja, a nie caly klucz Run.
# Nietypowe rodzaje (binarne, liczby) eksportuje reg.exe razem z kluczem.
function KopiaWartosci([string]$klucz, [string]$nazwa, [string]$plik) {
    $k = Get-Item -LiteralPath "Registry::$klucz" -ErrorAction Stop
    $rodzaj = $k.GetValueKind($nazwa)
    $tekst = [string]$k.GetValue($nazwa, $null, 'DoNotExpandEnvironmentNames')
    $n = $nazwa.Replace('\', '\\').Replace('"', '\"')
    $wpis = switch ($rodzaj) {
        'String' { '"{0}"="{1}"' -f $n, $tekst.Replace('\', '\\').Replace('"', '\"') }
        'ExpandString' { '"{0}"=hex(2):{1}' -f $n, (([Text.Encoding]::Unicode.GetBytes($tekst) + 0, 0 | ForEach-Object { '{0:x2}' -f $_ }) -join ',') }
        default { $null }
    }
    if ($wpis) {
        [IO.File]::WriteAllText($plik, "Windows Registry Editor Version 5.00`r`n`r`n[$klucz]`r`n$wpis`r`n", [Text.Encoding]::Unicode)
    }
    else { & reg.exe export $klucz $plik /y 2>&1 | Out-Null }
    if (-not (Test-Path -LiteralPath $plik)) { throw (L 'nie udało się zrobić kopii - wpis zostawiony' 'backup failed - entry kept') }
}

function SkanujPozostalosci {
    $wpisy = @(KluczeOdinstalowania)
    $martwe = @(MartweWpisy $wpisy)
    $martweKlucze = @($martwe | ForEach-Object { $_.Sciezka })
    $zainst = ZainstalowaneProgramy @($wpisy | Where-Object { $_.Klucz -notin $martweKlucze })
    $teraz = Get-Date
    $wyniki = [System.Collections.Generic.List[object]]::new()

    # Foldery programow
    $korzenie = @(
        @{ P = $env:APPDATA; Gra = $false }, @{ P = $env:LOCALAPPDATA; Gra = $false },
        @{ P = "$env:LOCALAPPDATA\Programs"; Gra = $false }, @{ P = "$env:USERPROFILE\AppData\LocalLow"; Gra = $false },
        @{ P = $env:ProgramData; Gra = $false }, @{ P = $env:ProgramFiles; Gra = $false }, @{ P = ${env:ProgramFiles(x86)}; Gra = $false },
        @{ P = "$(FolderUzytkownika 'Personal' "$env:USERPROFILE\Documents")\My Games"; Gra = $true }
        @{ P = (FolderUzytkownika '{4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4}' "$env:USERPROFILE\Saved Games"); Gra = $true })
    $wszystkieNazwy = [System.Collections.Generic.HashSet[string]]::new()
    $doSprawdzenia = @()
    foreach ($k in $korzenie) {
        foreach ($d in Get-ChildItem -LiteralPath $k.P -Directory -Force) {
            try {
                [void]$wszystkieNazwy.Add((Normalizuj $d.Name))
                if ($d.Attributes -band $REPARSE -or $d.Attributes -band [IO.FileAttributes]::System) { continue }
                if (Pomijana $d.Name) { continue }
                if (NalezyDoProgramu $d.Name $d.FullName $zainst) { continue }
                $doSprawdzenia += @{ D = $d; Zapisy = $k.Gra }
            }
            catch { BladSkanu "folder $($d.FullName)" $_ }
        }
    }
    foreach ($c in $doSprawdzenia) { try {
        Postep ("   {0}" -f $c.D.FullName)
        $m = ZmierzFolder $c.D.FullName
        $dni = ($teraz - $m.Ostatnio).TotalDays
        if ($dni -lt 30) { continue }   # cos tam jeszcze pisze
        $wyniki.Add(@{ Typ = 'folder'; Sciezka = $c.D.FullName; Nazwa = $c.D.Name; Bajty = $m.Bajty; Ostatnio = $m.Ostatnio
            # Odinstalowany program zwykle zostawia ustawienia i logi, nie pliki .exe - folder z .exe moze byc
            # programem przenosnym bez wpisu w rejestrze, wiec nie zaznaczamy go z gory
            Pewnosc = $(if ($c.Zapisy -or $m.MaExe) { 'niska' } elseif ($dni -ge 180) { 'wysoka' } else { 'srednia' })
            Dlaczego = $(if ($c.Zapisy) { L 'Zapisy/ustawienia gry - może chcesz je zachować.' 'Game saves/settings - you may want to keep them.' }
                        elseif ($m.MaExe) { L 'Brak zainstalowanego programu o tej nazwie, ale folder zawiera pliki .exe - może to program przenośny.' 'No installed program with this name, but the folder contains .exe files - it may be a portable program.' }
                        else { L 'Brak zainstalowanego programu o tej nazwie.' 'No installed program with this name.' }) })
    } catch { BladSkanu "folder $($c.D.FullName)" $_ } }

    # Gry
    $gry = @()
    try { $gry += @(SteamOsierocone) } catch { BladSkanu 'Steam' $_ }
    try { $gry += @(EpicOsierocone) } catch { BladSkanu 'Epic' $_ }
    foreach ($g in $gry) {
        try { $m = ZmierzFolder $g.Sciezka; $g.Bajty = $m.Bajty; $g.Ostatnio = $m.Ostatnio; $wyniki.Add($g) }
        catch { BladSkanu "gra $($g.Sciezka)" $_ }
    }

    # Rejestr: klucze producentow bez programu i bez folderu o tej nazwie
    $rej = [System.Collections.Generic.List[object]]::new()
    foreach ($r in "$HKCUNazwa\Software", 'HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node') {
        foreach ($k in Get-ChildItem "Registry::$r") { try {
            $n = $k.PSChildName
            if (Pomijana $n) { continue }
            if (NalezyDoProgramu $n $null $zainst) { continue }
            if ($wszystkieNazwy.Contains((Normalizuj $n))) { continue }
            # Klucz studia (np. Klei) moze nalezec do wciaz zainstalowanej gry (Klei\Don't Starve)
            $podklucze = @(Get-ChildItem -LiteralPath $k.PSPath | ForEach-Object { $_.PSChildName })
            if ($podklucze | Where-Object { (NalezyDoProgramu $_ $null $zainst) -or $wszystkieNazwy.Contains((Normalizuj $_)) }) { continue }
            $zawiera = @($podklucze | Select-Object -First 3)
            $dlaczego = L 'Klucz producenta bez zainstalowanego programu i folderu.' 'Vendor key with no installed program or folder.'
            if ($zawiera) { $dlaczego += ((L ' Zawiera: {0}.' ' Contains: {0}.') -f ($zawiera -join ', ')) }
            $rej.Add(@{ Typ = 'rejestr'; Sciezka = "$r\$n"; Nazwa = $n; Bajty = 0.0; Pewnosc = 'srednia'; Zawiera = $zawiera; Dlaczego = $dlaczego })
        } catch { BladSkanu "klucz $r\$($k.PSChildName)" $_ } }
    }

    $start = @()
    try { $start = @(MartweAutostarty) } catch { BladSkanu 'autostart' $_ }

    @($wyniki | Sort-Object { $_.Bajty } -Descending) + @($martwe) + @($start) + @($rej)
}

# Caly skan: kategorie, profil, pozostalosci i plan. Wynik w $script:Kategorie/Pozostalosci/Dysk.
function SkanujWszystko {
    Log "Dyski: $($script:WybraneDyski -join ', '), uzytkownik: $UzytkownikSid$(if ($InnyUzytkownik) { ' (inne konto niz administrator)' })"
    $script:BledySkanu = 0
    $script:WolnePrzed = WolneC
    try { $script:Kategorie = @(ZbudujKategorie) } catch { BladSkanu 'kategorie' $_; $script:Kategorie = @() }
    SkanujKategorie
    Wypisz (L '   Przeglądam profil użytkownika (duże pliki, AppData)...' '   Scanning the user profile (large files, AppData)...') 'DarkGray'
    try { $script:Dysk = SkanujDysk }
    catch { BladSkanu 'profil' $_; $script:Dysk = @{ Kandydaci = @(); Profil = @(); AppData = @(); Programy = @(); System = @{}; Dyski = @() } }
    Wypisz (L '   Szukam pozostałości po odinstalowanych programach i grach...' '   Looking for leftovers of uninstalled programs and games...') 'DarkGray'
    try { $poz = @(SkanujPozostalosci) } catch { BladSkanu 'pozostalosci' $_; $poz = @() }
    # Duze pliki z Pobranych i spoza AppData - do decyzji uzytkownika, nigdy zaznaczone z gory
    foreach ($c in $script:Dysk.Kandydaci) {
        $poz += @{ Typ = 'plik'; Sciezka = $c.Sciezka; Nazwa = (Split-Path $c.Sciezka -Leaf); Bajty = $c.Bajty
            Ostatnio = $c.Zmodyfikowany; Pewnosc = 'niska'
            Dlaczego = $(if ($c.Pobrane) { L 'Duży plik w Pobranych - stary instalator albo archiwum?' 'Large file in Downloads - an old installer or archive?' }
                         else { L 'Duży plik (ponad 1 GB) w profilu użytkownika.' 'Large file (over 1 GB) in the user profile.' }) }
    }
    $n = 0; foreach ($p in $poz) { $n++; $p.Id = "R$n" }
    $script:Pozostalosci = $poz
    KoniecPostepu ((L '   Znaleziono pozostałości: {0} folderów, {1} plików, {2} wpisów rejestru, {3} zadań.' '   Leftovers found: {0} folders, {1} files, {2} registry entries, {3} tasks.') -f
        @($poz | Where-Object { $_.Typ -eq 'folder' }).Count, @($poz | Where-Object { $_.Typ -eq 'plik' }).Count,
        @($poz | Where-Object { $_.Typ -in 'rejestr', 'wartosc' }).Count, @($poz | Where-Object { $_.Typ -eq 'zadanie' }).Count)
    if ($script:BledySkanu) {
        Wypisz ((L '   Pominięto elementy, których nie dało się odczytać: {0} (szczegóły w logu: {1})' '   Skipped items that could not be read: {0} (details in the log: {1})') -f $script:BledySkanu, $LogPlik) 'Yellow'
    }
    UlozPlan
    Log "Raport: $(RaportJson)"
}

# ---------- PLAN (reguly, bez modelu) ----------
# Kategorie: zaznaczone, gdy cokolwiek zawieraja. Kosz (nieodwracalny), DNS i kategorie
# "tylko recznie" zawsze odznaczone. Pozostalosci: zaznaczone przy pewnosci wysokiej i sredniej.
function UlozPlan {
    foreach ($k in $script:Kategorie) {
        $k.Wybrana = -not $k.TylkoRecznie -and -not $k.Blokada -and $k.Typ -in 'folder', 'miniatury' -and $k.Bajty -gt 0
    }
    foreach ($p in $script:Pozostalosci) { $p.Wybrana = $p.Pewnosc -in 'wysoka', 'srednia' }
}

function SumaZablokowanych { [double](@($script:Kategorie | Where-Object { $_.Wybrana } | ForEach-Object { [double]$_.Zablokowane }) | Measure-Object -Sum).Sum }

function SumaZaznaczonych { [double](@($script:Kategorie) + @($script:Pozostalosci) | Where-Object { $_.Wybrana } | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum }

function RaportJson {
    # Gotowa lista od najwiekszej - maly model zle porownuje rozmiary zapisane tekstem w roznych sekcjach
    $odNajwiekszej = @(@($script:Kategorie) + @($script:Pozostalosci) | Where-Object { $_.Bajty -gt 0 } |
        Sort-Object { [double]$_.Bajty } -Descending | Select-Object -First 15 | ForEach-Object {
            @{ pozycja = $(if ($_.Sciezka -and -not $_.Opis) { $_.Sciezka } else { $_.Nazwa }); rozmiar = (Rozmiar $_.Bajty); zaznaczona = [bool]$_.Wybrana } })
    $raport = @{
        plan_od_najwiekszej = $odNajwiekszej
        zaznaczone_razem = (Rozmiar (SumaZaznaczonych))
        dyski = $script:Dysk.Dyski
        kategorie = @($script:Kategorie | ForEach-Object {
            @{ id = $_.Id; nazwa = $_.Nazwa; opis = $_.Opis; zaznaczona = [bool]$_.Wybrana
               rozmiar = (RozmiarKategorii $_); tylko_recznie = [bool]$_.TylkoRecznie; blokada = $_.Blokada } })
        pozostalosci = @($script:Pozostalosci | ForEach-Object {
            @{ id = $_.Id; typ = $_.Typ; sciezka = $_.Sciezka; zaznaczona = [bool]$_.Wybrana
               rozmiar = $(if (NaKosz $_) { Rozmiar $_.Bajty } else { '-' })
               ostatnia_zmiana = $(if ($_.Ostatnio) { $_.Ostatnio.ToString('yyyy-MM-dd') }); pewnosc = $_.Pewnosc
               dlaczego = $_.Dlaczego; czym_jest = $_.Ai } })
        najwieksze_foldery_profilu = $script:Dysk.Profil
        duze_foldery_appdata = $script:Dysk.AppData
        najwieksze_programy = $script:Dysk.Programy
        system = $script:Dysk.System
        analiza_dyskow = @($script:Analizy.Values | ForEach-Object {
            @{ dysk = "$($_.Litera):"; pozycje = @(@($_.Foldery) + @($_.Pliki) | ForEach-Object {
                @{ sciezka = $_.Sciezka; rozmiar = (Rozmiar $_.Bajty); podpowiedz = $_.Podpowiedz; czym_jest = $_.Ai } }) } })
        autostart = @($script:Autostart | Where-Object { $_ } | ForEach-Object {
            @{ nazwa = $_.Nazwa; wlaczony = [bool]$_.Wlaczony; wydawca = $_.Wydawca; zrodlo = $_.Zrodlo; polecenie = $_.Polecenie
               chroniony = $_.Chroniony; czym_jest = $_.Ai } })
    }
    ConvertTo-Json -InputObject $raport -Depth 10 -Compress
}

# Podsumowanie przed czyszczeniem: lista linii @{ T = tekst; K = kolor } albo $null, gdy nic nie zaznaczono
function Podsumowanie {
    $wybrane = @($script:Kategorie | Where-Object { $_.Wybrana })
    $wybranePoz = @($script:Pozostalosci | Where-Object { $_.Wybrana })
    if (-not $wybrane.Count -and -not $wybranePoz.Count) { return $null }
    $linie = [System.Collections.Generic.List[object]]::new()
    function Dodaj($t, $k = 'Gray') { $linie.Add(@{ T = $t; K = $k }) }
    if ($wybrane.Count) {
        Dodaj (L 'Zostanie wyczyszczone:' 'To be cleaned:') 'White'
        foreach ($k in $wybrane) {
            $roz = if ($k.Typ -in 'folder', 'kosz', 'miniatury', 'winold', 'driverstore') { Rozmiar $k.Bajty } elseif ($k.Typ -eq 'dns') { '-' } else { L 'nieznane' 'unknown' }
            Dodaj ("  - {0,-52} {1,10}" -f $k.Nazwa, $roz)
        }
        $suma = ($wybrane | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
        Dodaj ''
        Dodaj ((L 'Zwolnione miejsce   : ok. {0}' 'Space freed         : about {0}') -f (Rozmiar $suma)) 'Green'
        Dodaj ((L 'Wolne na {1} teraz  : {0}' 'Free on {1} now     : {0}') -f (Rozmiar $script:WolnePrzed), $Sys)
        Dodaj ((L 'Wolne na {1} po     : ok. {0}' 'Free on {1} after   : about {0}') -f (Rozmiar ($script:WolnePrzed + $suma)), $Sys)
        $zablokowane = SumaZablokowanych
        if ($zablokowane) { Dodaj ((L 'Zablokowane         : {0} (pliki w użyciu - nie zostaną usunięte, nie są wliczone)' 'Locked              : {0} (files in use - not deleted, not included)') -f (Rozmiar $zablokowane)) 'Yellow' }
        Dodaj (L '(część plików może być w użyciu - wtedy zostaną pominięte i zysk będzie mniejszy)' '(some files may be in use - they are skipped and the gain will be smaller)') 'DarkGray'
    }
    $doKosza = @($wybranePoz | Where-Object { NaKosz $_ })
    $pozRejestr = @($wybranePoz | Where-Object { $_.Typ -in 'rejestr', 'wartosc' })
    $pozZadania = @($wybranePoz | Where-Object { $_.Typ -eq 'zadanie' })
    if ($wybranePoz.Count) {
        Dodaj ''
        Dodaj (L 'Pozostałości po odinstalowanych programach i grach:' 'Leftovers of uninstalled programs and games:') 'White'
        foreach ($p in $wybranePoz) {
            Dodaj ("  - {0,-52} {1,10}" -f (PokazPozostalosc $p), (RozmiarPozostalosci $p))
        }
        if ($doKosza.Count) {
            $sp = ($doKosza | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
            Dodaj ((L 'Do Kosza            : {0} ({1}) - miejsce zwolni się po opróżnieniu Kosza' 'To the Recycle Bin  : {0} ({1}) - the space is freed when you empty the Recycle Bin') -f $doKosza.Count, (Rozmiar $sp))
        }
        if ($pozRejestr.Count) {
            Dodaj ((L 'Klucze rejestru     : {0} - kopia .reg w logs\kopie_rejestru + punkt przywracania systemu' 'Registry keys       : {0} - .reg backup in logs\kopie_rejestru + System Restore point') -f $pozRejestr.Count)
        }
        if ($pozZadania.Count) {
            Dodaj ((L 'Zadania Harmonogramu: {0} - kopia .xml w logs\kopie_rejestru' 'Scheduled tasks     : {0} - .xml backup in logs\kopie_rejestru') -f $pozZadania.Count)
        }
    }
    $uwagi = @()
    if ($wybrane | Where-Object { $_.Id -eq 'kosz' }) { $uwagi += L 'Kosz zostanie opróżniony NIEODWRACALNIE (przed przeniesieniem pozostałości).' 'The Recycle Bin is emptied PERMANENTLY (before leftovers are moved to it).' }
    if ($wybrane | Where-Object { $_.Typ -eq 'miniatury' }) { $uwagi += L 'Eksplorator zostanie zrestartowany - pasek zadań zniknie na kilka sekund.' 'File Explorer restarts - the taskbar disappears for a few seconds.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'dism' }) { $uwagi += L 'DISM potrwa kilka minut; potem nie odinstalujesz starszych aktualizacji.' 'DISM takes a few minutes; older updates can no longer be uninstalled afterwards.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'driverstore' }) { $uwagi += L 'Usunięte starsze wersje sterowników nie wrócą - przed usunięciem powstanie punkt przywracania.' 'Removed older driver versions cannot be brought back - a System Restore point is created first.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'winold' }) { $uwagi += L 'Po usunięciu Windows.old nie da się wrócić do poprzedniej wersji Windows.' 'After removing Windows.old you cannot go back to the previous Windows version.' }
    if ($wybrane | Where-Object { $_.Procesy }) { $uwagi += L 'Nie otwieraj przeglądarki w trakcie czyszczenia.' 'Do not open a browser while cleaning.' }
    if ($wybranePoz | Where-Object { $_.Pewnosc -eq 'niska' }) { $uwagi += L 'Zaznaczono pozycje o niskiej pewności (zapisy gier / duże pliki) - upewnij się, że ich nie potrzebujesz.' 'Low-confidence items are selected (game saves / large files) - make sure you do not need them.' }
    if ($uwagi.Count) { Dodaj ''; foreach ($u in $uwagi) { Dodaj "! $u" 'Yellow' } }
    , $linie
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
    for ($i = 0; $i -lt 40; $i++) { Pauza 500; if (OllamaDziala) { return $true } }
    $false
}

function ZatrzymajOllama { if ('LlmJob' -as [type]) { [LlmJob]::Close() }; $script:llmStan = $null }

function MaModel {
    try { $t = Invoke-RestMethod "$OllamaUrl/api/tags" -TimeoutSec 5 -ErrorAction Stop } catch { return $false }
    [bool]($t.models | Where-Object { $_.name -eq $Model -or $_.name -eq "$Model`:latest" })
}

function Ollama($wiadomosci, $format) {
    $body = @{ model = $Model; messages = @($wiadomosci); stream = $false; keep_alive = '5m'
               options = @{ temperature = 0.2; num_ctx = 12288 } }
    if ($format) { $body.format = $format }
    $json = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 20 -Compress))
    $r = CzekajNa {
        param($url, $json)
        Invoke-RestMethod $url -Method Post -TimeoutSec 600 -ErrorAction Stop -Body $json -ContentType 'application/json; charset=utf-8'
    } @("$OllamaUrl/api/chat", $json)
    $r.message.content
}

# Model ladowany dopiero przy pierwszym uzyciu
$script:llmStan = $null
function ZapewnijModel {
    if ($BezLLM) { Wypisz (L '   Model jest wyłączony (uruchomiono z -BezLLM).' '   The AI model is disabled (started with -BezLLM).') 'Yellow'; return $false }
    if ($null -ne $script:llmStan) { return $script:llmStan }
    Wypisz ((L '   Uruchamiam model {0} (pierwsze użycie trwa ok. 10-20 s)...' '   Starting model {0} (the first use takes about 10-20 s)...') -f $Model) 'DarkGray'
    if (-not (Test-Path -LiteralPath $OllamaExe)) {
        Wypisz (L '   Asystent AI nie jest zainstalowany. Uruchom ponownie instalator i zaznacz asystenta AI (albo Install-AI.ps1 z folderu programu).' '   The AI assistant is not installed. Run the installer again and tick the AI assistant (or run Install-AI.ps1 from the program folder).') 'Yellow'
        $script:llmStan = $false
    }
    elseif (-not (UruchomOllama)) {
        Wypisz (L '   Nie udało się uruchomić Ollamy z folderu ai\ - asystent niedostępny.' '   Could not start Ollama from the ai\ folder - the assistant is unavailable.') 'Yellow'
        $script:llmStan = $false
    }
    elseif (-not (MaModel)) {
        Wypisz ((L '   Brak modelu {0} w folderze ai\models (Install-AI.ps1 -Model {0}) - asystent niedostępny.' '   Model {0} is missing in ai\models (Install-AI.ps1 -Model {0}) - the assistant is unavailable.') -f $Model) 'Yellow'
        $script:llmStan = $false
    }
    else { $script:llmStan = $true }
    Log "Model: $($script:llmStan)"
    $script:llmStan
}

$EtykietaAi = L 'AI (może się mylić)' 'AI (may be wrong)'

$SchematWyjasnien = @{
    type = 'object'
    properties = @{
        wyjasnienia = @{ type = 'array'; items = @{ type = 'object'
            properties = @{ id = @{ type = 'string' }; opis = @{ type = 'string' } }
            required = @('id', 'opis') } }
    }
    required = @('wyjasnienia')
}

$SysWyjasnij = if ($Jezyk -eq 'en') { @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of leftovers of uninstalled programs and games
(folders, files and registry keys). For EACH item write in the "opis" field what the program, game or vendor was.
Rules:
- Rely FIRST on the "zawiera" field (registry subkey names - usually names of games or programs) and on the name
  itself. Example: name "Studio X", zawiera ["Game Y"] -> "Studio X - the game Game Y".
- Do NOT add game or product titles that are not in the data unless you are absolutely sure.
  "game developer" is better than an invented title.
- If nothing is known, write exactly: "unknown program".
- Max. 12 words, in English. Do not judge whether to delete.
'@ } else { @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę pozostałości po odinstalowanych programach i grach
(foldery, pliki i klucze rejestru). Dla KAŻDEJ pozycji napisz w polu "opis", czym był ten program, gra albo producent.
Zasady:
- Opieraj się PRZEDE WSZYSTKIM na polu "zawiera" (nazwy podkluczy rejestru - zwykle to nazwy gier lub programów)
  i na samej nazwie. Przykład: nazwa "Studio X", zawiera ["Gra Y"] -> "Studio X - gra Gra Y".
- NIE dopisuj tytułów gier ani produktów, których nie ma w danych, chyba że jesteś absolutnie pewien.
  Lepiej "producent gier" niż zmyślony tytuł.
- Jeśli nic nie wiadomo, napisz dokładnie: "nieznany program".
- Maks. 12 słów, po polsku. Nie oceniasz, czy usuwać.
'@ }

$SysCzat = if ($Jezyk -eq 'en') { @'
You are LLMCleaner, a Windows cleanup assistant running locally.
Below is the scanner report and the current cleanup plan. Answer the user's questions about files, folders, programs,
games and the plan briefly and specifically, in English. You cannot delete or run anything - the user changes the plan.
If they want to remove something outside the plan, explain how to do it safely by hand (e.g. uninstalling a program
in Settings). Use only numbers from the report. If you do not know something, say so.
'@ } else { @'
Jesteś LLMCleaner - asystentem sprzątania systemu Windows działającym lokalnie.
Poniżej masz raport skanera i aktualny plan czyszczenia. Odpowiadaj krótko i konkretnie po polsku na pytania
użytkownika o pliki, foldery, programy, gry i plan. Nie możesz niczego usuwać ani uruchamiać - plan zmienia
użytkownik. Jeśli chce usunąć coś spoza planu, wyjaśnij, jak zrobić to bezpiecznie ręcznie
(np. odinstalowanie programu w Ustawieniach). Używaj tylko liczb z raportu. Jeśli czegoś nie wiesz, powiedz to wprost.
'@ }

# Opisy pozostalosci przez model. Zwraca liczbe opisanych pozycji (albo -1 przy bledzie).
function WyjasnijPozostalosci {
    if (-not $script:Pozostalosci.Count) { Wypisz (L '   Brak pozostałości do wyjaśnienia.' '   No leftovers to explain.') 'DarkGray'; return 0 }
    if (-not (ZapewnijModel)) { return -1 }
    $lista = @($script:Pozostalosci | ForEach-Object { @{ id = $_.Id; typ = $_.Typ; nazwa = $_.Nazwa; sciezka = $_.Sciezka; zawiera = @($_.Zawiera) } })
    Wypisz ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $lista.Count) 'DarkGray'
    try {
        $odp = Ollama @(@{ role = 'system'; content = $SysWyjasnij },
                        @{ role = 'user'; content = (ConvertTo-Json -InputObject $lista -Depth 5 -Compress) }) $SchematWyjasnien
        $n = 0
        foreach ($w in @(($odp | ConvertFrom-Json -ErrorAction Stop).wyjasnienia)) {
            $p = $script:Pozostalosci | Where-Object { $_.Id -eq $w.id } | Select-Object -First 1
            if ($p -and $w.opis) { $p.Ai = $w.opis; $n++ }
        }
        Wypisz ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        Log "Wyjasnienia modelu: $odp"
        $n
    }
    catch { Wypisz ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}

# Rozmowa: $script:Rozmowa trzyma historie; Zapytaj zwraca odpowiedz albo $null
$script:Rozmowa = $null
function ZacznijRozmowe {
    $script:Rozmowa = [System.Collections.ArrayList]::new()
    # Czat dziala tez przed skanem - model wie wtedy, ze nie zna jeszcze plikow komputera
    $raport = if ($script:Dysk) { RaportJson } else {
        L 'Skan nie został jeszcze wykonany - nie znasz plików tego komputera. Odpowiadaj ogólnie, a przy pytaniach o konkretne pliki, foldery lub plan poproś użytkownika, żeby najpierw kliknął „Skanuj”.' 'No scan has been run yet - you do not know the files on this computer. Answer in general terms; for questions about specific files, folders or the plan, ask the user to click "Scan" first.'
    }
    [void]$script:Rozmowa.Add(@{ role = 'system'; content = "$SysCzat`n`n$(L 'RAPORT I PLAN' 'REPORT AND PLAN'):`n$raport" })
}
function Zapytaj([string]$pytanie) {
    if (-not (ZapewnijModel)) { return $null }
    if (-not $script:Rozmowa) { ZacznijRozmowe }
    [void]$script:Rozmowa.Add(@{ role = 'user'; content = $pytanie })
    try {
        $a = Ollama $script:Rozmowa.ToArray()
        [void]$script:Rozmowa.Add(@{ role = 'assistant'; content = $a })
        $a
    }
    catch { [void]$script:Rozmowa.RemoveAt($script:Rozmowa.Count - 1); Wypisz ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; $null }
}

# ---------- ANALIZA DYSKU: CO ZAJMUJE MIEJSCE ----------
# Tylko do wgladu - nic stad nie trafia do planu. Skaner w C#, bo petla w PowerShellu
# przechodzi milion plikow kilka minut. Nie wchodzi w junctions/symlinki, pomija pliki
# tylko w chmurze (OneDrive). Twarde linki (WinSxS) sa liczone wielokrotnie, jak w Eksploratorze.

function KompilujSkaner {
    if ('LlmSkaner' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public class LlmFolder { public string Sciezka; public long Bajty; public long Pliki; public DateTime Ostatnio; }
public class LlmPlik { public string Sciezka; public long Bajty; public DateTime Ostatnio; }
public class LlmWynik { public List<LlmFolder> Foldery = new List<LlmFolder>(); public List<LlmPlik> Pliki = new List<LlmPlik>(); public long Bajty; public long LiczbaPlikow; public int Odmowy; }
public static class LlmSkaner {
    static long licznik;
    public static long Licznik { get { return Interlocked.Read(ref licznik); } }
    const FileAttributes Chmura = (FileAttributes)0x400000 | (FileAttributes)0x40000 | FileAttributes.Offline;
    public static Task<LlmWynik> Start(string root, int maxGlebokosc, long minFolder, long minPlik) {
        Interlocked.Exchange(ref licznik, 0);
        return Task.Run(() => {
            var w = new LlmWynik(); long n; DateTime o;
            w.Bajty = Skanuj(new DirectoryInfo(root), 0, maxGlebokosc, minFolder, minPlik, w, out n, out o);
            w.LiczbaPlikow = n;
            return w;
        });
    }
    static long Skanuj(DirectoryInfo d, int gl, int maxGl, long minFolder, long minPlik, LlmWynik w, out long pliki, out DateTime ostatnio) {
        long suma = 0; pliki = 0; ostatnio = DateTime.MinValue;
        FileSystemInfo[] el;
        try { el = d.GetFileSystemInfos(); } catch { w.Odmowy++; return 0; }
        foreach (var e in el) {
            try {
                if ((e.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                var sd = e as DirectoryInfo;
                if (sd != null) {
                    long p; DateTime o;
                    suma += Skanuj(sd, gl + 1, maxGl, minFolder, minPlik, w, out p, out o);
                    pliki += p; if (o > ostatnio) ostatnio = o;
                    continue;
                }
                var f = (FileInfo)e;
                if ((f.Attributes & Chmura) != 0) continue;
                long b = f.Length; DateTime t = f.LastWriteTime;
                suma += b; pliki++; Interlocked.Increment(ref licznik);
                if (t > ostatnio) ostatnio = t;
                if (b >= minPlik) w.Pliki.Add(new LlmPlik { Sciezka = f.FullName, Bajty = b, Ostatnio = t });
            } catch { }
        }
        if (gl >= 1 && gl <= maxGl && suma >= minFolder)
            w.Foldery.Add(new LlmFolder { Sciezka = d.FullName, Bajty = suma, Pliki = pliki, Ostatnio = ostatnio });
        return suma;
    }
}
'@
}

# Znane miejsca - podpowiedz bez modelu
$ZnaneMiejsca = @(
    @{ W = '\\Windows\\WinSxS$'; P = (L 'Magazyn komponentów Windows. Zmniejsza go tylko DISM (kategoria w planie); rozmiar zawyżony przez twarde linki.' 'Windows component store. Only DISM shrinks it (a plan category); the size is inflated by hard links.') }
    @{ W = '\\Windows\\Installer$'; P = (L 'Pamięć instalatorów MSI - nie usuwaj ręcznie, psuje odinstalowywanie programów.' 'MSI installer cache - do not delete by hand, it breaks uninstalling programs.') }
    @{ W = '\\Windows\\SoftwareDistribution$'; P = (L 'Aktualizacje Windows - kategoria „Cache Windows Update” w planie.' 'Windows updates - the "Windows Update cache" plan category.') }
    @{ W = '\\Windows\\System32\\DriverStore'; P = (L 'Magazyn sterowników (np. sterownik karty graficznej). Nie usuwaj ręcznie - stare wersje usuwa kategoria „Starsze wersje sterowników” w planie.' 'Driver store (e.g. the graphics driver). Do not delete by hand - the "Older driver versions" plan category removes old versions.') }
    @{ W = '\\Windows\\servicing'; P = (L 'Pliki obsługi aktualizacji Windows - zarządza nimi system.' 'Windows update servicing files - managed by the system.') }
    @{ W = '\\Windows\.old$'; P = (L 'Poprzednia wersja Windows - kategoria w planie.' 'Previous Windows version - a plan category.') }
    @{ W = '^[A-Z]:\\pagefile\.sys$'; P = (L 'Plik stronicowania (pamięć wirtualna). Rozmiar ustawia się w Ustawieniach systemu.' 'Page file (virtual memory). Its size is set in the system settings.') }
    @{ W = '^[A-Z]:\\hiberfil\.sys$'; P = (L 'Hibernacja i szybkie uruchamianie. „powercfg /h off” usuwa go, ale wyłącza hibernację.' 'Hibernation and fast startup. "powercfg /h off" removes it but turns hibernation off.') }
    @{ W = '^[A-Z]:\\swapfile\.sys$'; P = (L 'Plik wymiany aplikacji ze Sklepu - zarządza nim Windows.' 'Swap file for Store apps - managed by Windows.') }
    @{ W = '\\steamapps\\common\\[^\\]+$'; P = (L 'Gra ze Steama - odinstaluj ją w Steamie.' 'Steam game - uninstall it in Steam.') }
    @{ W = '\\steamapps\\(workshop|shadercache|downloading)'; P = (L 'Dane Steama (Workshop, shadery, pobieranie).' 'Steam data (Workshop, shaders, downloads).') }
    @{ W = '\\Epic Games\\[^\\]+$'; P = (L 'Gra z Epic Games - odinstaluj ją w launcherze Epic.' 'Epic Games game - uninstall it in the Epic launcher.') }
    @{ W = '\\swap\.vhdx$'; P = (L 'Plik wymiany WSL - znika po „wsl --shutdown”.' 'WSL swap file - removed by "wsl --shutdown".') }
    @{ W = '\\AppData\\Local\\Temp(\\[^\\]+)?$'; P = (L 'Pliki tymczasowe - kategoria TEMP w planie (pliki w użyciu są pomijane).' 'Temporary files - the TEMP plan category (files in use are skipped).') }
    @{ W = '(ext4|docker_data)\.vhdx$|DockerDesktopWSL|\\Docker\\wsl'; P = (L 'Dysk WSL/Docker. Miejsce zwalnia „docker system prune”, a potem kompaktowanie dysku VHDX.' 'WSL/Docker disk. "docker system prune" and then compacting the VHDX frees space.') }
    @{ W = '\\AppData\\Local\\Packages\\[^\\]+$'; P = (L 'Dane aplikacji ze Sklepu Microsoft - wyczyść lub odinstaluj w Ustawieniach > Aplikacje.' 'Microsoft Store app data - reset or uninstall it in Settings > Apps.') }
    @{ W = '\\node_modules$'; P = (L 'Zależności projektu Node.js - „npm install” odtworzy je w razie potrzeby.' 'Node.js project dependencies - "npm install" restores them when needed.') }
    @{ W = '\\\.(gradle|m2|nuget|cargo|rustup)$'; P = (L 'Cache narzędzi programistycznych.' 'Developer tool cache.') }
    @{ W = '\\(Downloads|Pobrane)$'; P = (L 'Pobrane pliki - często stare instalatory i archiwa.' 'Downloaded files - often old installers and archives.') }
    @{ W = '\\LLMCleaner\\ai$'; P = (L 'Silnik AI i modele LLMCleanera.' 'The LLMCleaner AI engine and models.') }
    @{ W = '\.(iso|vhdx?|vmdk|qcow2)$'; P = (L 'Obraz dysku lub maszyny wirtualnej.' 'Disk or virtual machine image.') }
)
function Podpowiedz([string]$s) { foreach ($z in $ZnaneMiejsca) { if ($s -match $z.W) { return $z.P } }; $null }

function SkanujDyskAnaliza([string]$litera) {
    KompilujSkaner
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$litera`:'"
    $zajete = [double]$d.Size - [double]$d.FreeSpace
    $prog = if ($zajete -gt 1TB) { 2GB } else { 1GB }
    $zegar = [Diagnostics.Stopwatch]::StartNew()
    $zadanie = [LlmSkaner]::Start("$litera`:\", 6, $prog, 1GB)
    while (-not $zadanie.Wait(200)) {
        Postep ((L '   przejrzano {0:N0} plików ({1:N0} s)...' '   scanned {0:N0} files ({1:N0} s)...') -f [LlmSkaner]::Licznik, $zegar.Elapsed.TotalSeconds)
        if ($script:Tryb -eq 'okno') { [Windows.Forms.Application]::DoEvents() }
    }
    $w = $zadanie.Result
    KoniecPostepu ((L '   przejrzano {0:N0} plików w {1:N0} s.                 ' '   scanned {0:N0} files in {1:N0} s.                 ') -f $w.LiczbaPlikow, $zegar.Elapsed.TotalSeconds)

    # Najbardziej konkretne duze foldery: bez duzego podfolderu, albo z duza "reszta" poza nimi
    $wg = @{}; foreach ($f in $w.Foldery) { $wg[$f.Sciezka] = $f }
    $duzeDzieci = @{}
    foreach ($f in $w.Foldery) {
        $rodzic = [IO.Path]::GetDirectoryName($f.Sciezka)
        if ($rodzic -and $wg.ContainsKey($rodzic)) { $duzeDzieci[$rodzic] += [double]$f.Bajty }
    }
    $pozycje = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $w.Foldery) {
        $dzieci = [double]$duzeDzieci[$f.Sciezka]
        if ($dzieci -eq 0) { $b = [double]$f.Bajty; $reszta = $false }
        elseif ($f.Bajty - $dzieci -ge $prog) { $b = $f.Bajty - $dzieci; $reszta = $true }
        else { continue }
        $pozycje.Add(@{ Typ = 'folder'; Sciezka = $f.Sciezka; Bajty = $b; Reszta = $reszta; Pliki = $f.Pliki
                        Ostatnio = $f.Ostatnio; Podpowiedz = (Podpowiedz $f.Sciezka) })
    }
    $foldery = @($pozycje | Sort-Object { $_.Bajty } -Descending | Select-Object -First 20)
    $pliki = @($w.Pliki | Sort-Object Bajty -Descending | Select-Object -First 10 | ForEach-Object {
        @{ Typ = 'plik'; Sciezka = $_.Sciezka; Bajty = [double]$_.Bajty; Ostatnio = $_.Ostatnio; Podpowiedz = (Podpowiedz $_.Sciezka) } })

    # Punkty przywracania i kopie w tle - niewidoczne dla skanera (System Volume Information)
    $cienie = 0.0
    $wol = Get-CimInstance Win32_Volume | Where-Object { $_.DriveLetter -eq "$litera`:" } | Select-Object -First 1
    foreach ($s in Get-CimInstance Win32_ShadowStorage) { if ($wol -and $s.Volume.DeviceID -eq $wol.DeviceID) { $cienie += [double]$s.UsedSpace } }

    $i = 0
    foreach ($p in @($foldery) + @($pliki)) { $i++; $p.Id = "A$i" }
    Log ("Analiza {0}: {1:N0} plikow, {2} folderow, {3} plikow >1GB, odmowy dostepu: {4}" -f $litera, $w.LiczbaPlikow, $foldery.Count, $pliki.Count, $w.Odmowy)
    @{ Litera = $litera; Rozmiar = [double]$d.Size; Wolne = [double]$d.FreeSpace; Zeskanowane = [double]$w.Bajty
       Foldery = $foldery; Pliki = $pliki; Cienie = $cienie; Prog = $prog }
}

function Analizuj([string]$litera) {
    if (-not $script:Analizy.ContainsKey($litera)) {
        Wypisz ((L '   Skanuję dysk {0}: (zwykle 30 s - 3 min)...' '   Scanning drive {0}: (usually 30 s - 3 min)...') -f $litera) 'DarkGray'
        $script:Analizy[$litera] = SkanujDyskAnaliza $litera
        $script:Rozmowa = $null   # nowe dane dla czatu
    }
    $script:Analizy[$litera]
}

# Model wybiera rade tylko z tej listy (enum w schemacie) - nie moze doradzic recznego usuwania
$Rady = if ($Jezyk -eq 'en') {
    @('leave it - part of Windows', 'uninstall in Settings > Apps', 'uninstall the game in its launcher',
      'clean it in the program settings', 'review and move to another drive', 'review the contents manually',
      'the TEMP plan category cleans it')
} else {
    @('zostaw - część systemu', 'odinstaluj w Ustawieniach > Aplikacje', 'odinstaluj grę w jej launcherze',
      'wyczyść w ustawieniach programu', 'przejrzyj i przenieś na inny dysk', 'przejrzyj zawartość ręcznie',
      'oczyści to kategoria TEMP w planie')
}

# Foldery systemowe, programow i TEMP: rade ustala program, nie model
function RadaStala([string]$s) {
    if ($s -match '\\AppData\\Local\\Temp(\\|$)') { return $Rady[6] }
    if ($s -match '^[A-Z]:\\(Windows|ProgramData)(\\|$)' -or $s -match '^[A-Z]:\\[^\\]+\.sys$') { return $Rady[0] }
    if ($s -match '^[A-Z]:\\Program Files( \(x86\))?(\\(Microsoft[^\\]*|Windows[^\\]*|Common Files))?$') { return $Rady[0] }
    if ($s -match '^[A-Z]:\\Program Files( \(x86\))?\\') { return $Rady[1] }
    $null
}

$SchematAnalizy = @{
    type = 'object'
    properties = @{
        pozycje = @{ type = 'array'; items = @{ type = 'object'
            properties = @{ id = @{ type = 'string' }; opis = @{ type = 'string' }; rada = @{ type = 'string'; enum = $Rady } }
            required = @('id', 'opis', 'rada') } }
    }
    required = @('pozycje')
}

$SysAnaliza = if ($Jezyk -eq 'en') { @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of the largest folders and files on a drive
(path, size, last change date, sometimes a hint from the program). For EACH item give:
- "opis": what it is (program, game, user data, cache, part of Windows) - based on the path and the hint,
- "rada": one of the allowed values - what the user can safely do.
Rules:
- Everything in C:\Windows, C:\ProgramData and .sys files is part of Windows: "leave it - part of Windows".
- Games (steamapps, Epic Games) -> "uninstall the game in its launcher"; programs -> "uninstall in Settings > Apps".
- User data (documents, projects, downloads, unknown profile folders) -> "review the contents manually"
  or "review and move to another drive".
- If there is a hint from the program, the description must agree with it.
- An old last change date may mean an unused program or game - you may mention it in the description.
- Do not invent program names that are not in the path. If you do not know, write "unknown data".
- Description max. 12 words, in English.
'@ } else { @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę największych folderów i plików na dysku
(ścieżka, rozmiar, data ostatniej zmiany, czasem podpowiedź programu). Dla KAŻDEJ pozycji podaj:
- "opis": czym to jest (program, gra, dane użytkownika, cache, część systemu) - na podstawie ścieżki i podpowiedzi,
- "rada": jedna z dozwolonych wartości - co użytkownik może bezpiecznie zrobić.
Zasady:
- Wszystko w C:\Windows, C:\ProgramData i plikach .sys to część systemu: rada "zostaw - część systemu".
- Gry (steamapps, Epic Games) -> "odinstaluj grę w jej launcherze"; programy -> "odinstaluj w Ustawieniach > Aplikacje".
- Dane użytkownika (dokumenty, projekty, pobrane, nieznane foldery w profilu) -> "przejrzyj zawartość ręcznie"
  albo "przejrzyj i przenieś na inny dysk".
- Jeśli jest podpowiedź programu, opis musi być z nią zgodny.
- Stara data ostatniej zmiany może oznaczać nieużywany program lub grę - możesz o tym wspomnieć w opisie.
- Nie zmyślaj nazw programów, których nie ma w ścieżce. Jeśli nie wiesz, napisz "nieznane dane".
- Opis maks. 12 słów, po polsku.
'@ }

# Opisy i rady modelu dla analizy dysku. Zwraca liczbe opisanych pozycji (albo -1 przy bledzie).
function AnalizaAi($a) {
    if (-not (ZapewnijModel)) { return -1 }
    $lista = @(@($a.Foldery) + @($a.Pliki) | ForEach-Object {
        @{ id = $_.Id; typ = $_.Typ; sciezka = $_.Sciezka; rozmiar = (Rozmiar $_.Bajty); podpowiedz = $_.Podpowiedz
           ostatnia_zmiana = $(if ($_.Ostatnio -gt [datetime]'1980-01-01') { $_.Ostatnio.ToString('yyyy-MM-dd') }) } })
    Wypisz ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $lista.Count) 'DarkGray'
    try {
        $odp = Ollama @(@{ role = 'system'; content = $SysAnaliza },
                        @{ role = 'user'; content = (ConvertTo-Json -InputObject $lista -Depth 5 -Compress) }) $SchematAnalizy
        $n = 0
        foreach ($w in @(($odp | ConvertFrom-Json -ErrorAction Stop).pozycje)) {
            $p = @(@($a.Foldery) + @($a.Pliki)) | Where-Object { $_.Id -eq $w.id } | Select-Object -First 1
            if ($p -and $w.opis) {
                $rada = RadaStala $p.Sciezka
                if (-not $rada) { $rada = if ($w.rada -in $Rady) { $w.rada } else { $Rady[5] } }
                $p.Ai = "$($w.opis.Trim().TrimEnd('.;')). $(L 'Rada' 'Advice'): $rada."; $n++
            }
        }
        Wypisz ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        Log "Analiza - opisy modelu: $odp"
        $script:Rozmowa = $null
        $n
    }
    catch { Wypisz ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}

# ---------- AUTOSTART: OPISY AI ----------
# Jak w analizie dysku: rada tylko z tej listy, a dla wpisow chronionych ustala ja program
$RadyAutostartu = if ($Jezyk -eq 'en') {
    @('keep it on', 'can be turned off - start it by hand when needed', 'check whether you use it')
} else {
    @('zostaw włączone', 'można wyłączyć - uruchomisz ręcznie, gdy potrzebne', 'sprawdź, czy go używasz')
}

$SchematAutostartu = @{
    type = 'object'
    properties = @{
        pozycje = @{ type = 'array'; items = @{ type = 'object'
            properties = @{ id = @{ type = 'string' }; opis = @{ type = 'string' }; rada = @{ type = 'string'; enum = $RadyAutostartu } }
            required = @('id', 'opis', 'rada') } }
    }
    required = @('pozycje')
}

$SysAutostart = if ($Jezyk -eq 'en') { @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of programs that start when the user signs in
(name, command, publisher, source). For EACH item give:
- "opis": what the program is and why it starts with Windows - based on the name, command and publisher,
- "rada": one of the allowed values.
Rules:
- Chat apps, game launchers, cloud storage clients, update helpers of apps the user opens by hand and
  "helper"/"tray" tools usually do not need to start with Windows: "can be turned off - start it by hand when needed".
- Security software, drivers, audio, touchpad, keyboard or graphics panels: "keep it on".
- If you do not know the program, write "unknown program" and choose "check whether you use it".
- Do not invent program names that are not in the data. Description max. 12 words, in English.
'@ } else { @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę programów uruchamianych przy logowaniu
(nazwa, polecenie, wydawca, źródło). Dla KAŻDEJ pozycji podaj:
- "opis": czym jest program i po co startuje z Windows - na podstawie nazwy, polecenia i wydawcy,
- "rada": jedna z dozwolonych wartości.
Zasady:
- Komunikatory, launchery gier, klienty chmury, pomocniki aplikacji otwieranych ręcznie i narzędzia
  w zasobniku zwykle nie muszą startować z Windows: "można wyłączyć - uruchomisz ręcznie, gdy potrzebne".
- Ochrona antywirusowa, sterowniki, panele dźwięku, touchpada, klawiatury i grafiki: "zostaw włączone".
- Jeśli nie znasz programu, napisz "nieznany program" i wybierz "sprawdź, czy go używasz".
- Nie zmyślaj nazw programów, których nie ma w danych. Opis maks. 12 słów, po polsku.
'@ }

# Opisy i rady modelu dla autostartu. Zwraca liczbe opisanych pozycji (albo -1 przy bledzie).
function AutostartAi($wpisy) {
    if (-not @($wpisy).Count) { return 0 }
    if (-not (ZapewnijModel)) { return -1 }
    $lista = @($wpisy | ForEach-Object { @{ id = $_.Id; nazwa = $_.Nazwa; polecenie = $_.Polecenie; wydawca = $_.Wydawca; zrodlo = $_.Zrodlo } })
    Wypisz ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $lista.Count) 'DarkGray'
    try {
        $odp = Ollama @(@{ role = 'system'; content = $SysAutostart },
                        @{ role = 'user'; content = (ConvertTo-Json -InputObject $lista -Depth 5 -Compress) }) $SchematAutostartu
        $n = 0
        foreach ($o in @(($odp | ConvertFrom-Json -ErrorAction Stop).pozycje)) {
            $w = $wpisy | Where-Object { $_.Id -eq $o.id } | Select-Object -First 1
            if ($w -and $o.opis) {
                $rada = if ($w.Chroniony) { $RadyAutostartu[0] } elseif ($o.rada -in $RadyAutostartu) { $o.rada } else { $RadyAutostartu[2] }
                $w.Ai = "$($o.opis.Trim().TrimEnd('.;')). $(L 'Rada' 'Advice'): $rada."; $n++
            }
        }
        Wypisz ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        Log "Autostart - opisy modelu: $odp"
        $script:Rozmowa = $null
        $n
    }
    catch { Wypisz ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}

# ---------- AKTUALIZACJE ----------
# Jedno zapytanie do GitHuba przy starcie (bez danych o komputerze); wylacza je -BezAktualizacji.
$Repo = 'Banzamel/LLMCleaner'
$script:Aktualizacja = $null

function SprawdzAktualizacje {
    try {
        $r = CzekajNa {
            param($url, $ua)
            Invoke-RestMethod $url -TimeoutSec 4 -ErrorAction Stop -Headers @{ 'User-Agent' = $ua }
        } @("https://api.github.com/repos/$Repo/releases/latest", "LLMCleaner/$Wersja")
        $nowa = [version]($r.tag_name.TrimStart('v'))
        if ($nowa -le [version]$Wersja) { return }
        $setup = $r.assets | Where-Object { $_.name -like 'LLMCleaner-Setup-*.exe' } | Select-Object -First 1
        $script:Aktualizacja = @{ Wersja = "$nowa"; Strona = $r.html_url; Instalator = $setup.browser_download_url; Nazwa = $setup.name }
        Log "Dostepna aktualizacja: $nowa"
    }
    catch { Log "Sprawdzanie aktualizacji: $($_.Exception.Message)" }
}

# Pobiera instalator i uruchamia go jako zwykly uzytkownik (przez Eksplorator), zeby
# aktualizacja trafila w ten sam tryb instalacji co poprzednio. Zwraca $true, gdy wystartowal.
function ZainstalujAktualizacje {
    $a = $script:Aktualizacja
    $zainstalowany = Test-Path -LiteralPath (Join-Path $AppDir 'unins000.exe')
    if (-not $zainstalowany -or -not $a.Instalator) {
        Wypisz ((L '   Wersja portable - pobierz nową wersję ze strony: {0}' '   Portable version - download the new version from: {0}') -f $a.Strona) 'Yellow'
        return $false
    }
    $plik = Join-Path $env:TEMP $a.Nazwa
    Wypisz ((L '   Pobieram {0}...' '   Downloading {0}...') -f $a.Nazwa) 'Gray'
    try {
        CzekajNa {
            param($url, $plik)
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest $url -OutFile $plik -UseBasicParsing -ErrorAction Stop
        } @($a.Instalator, $plik) | Out-Null
    }
    catch { Wypisz ((L '   Nie udało się pobrać: {0}' '   Download failed: {0}') -f $_.Exception.Message) 'Yellow'; return $false }
    Log "Aktualizacja: uruchamiam $plik"
    Start-Process explorer.exe -ArgumentList "`"$plik`""
    $true
}

# ---------- WYKONANIE ----------
# Czysci zaznaczone kategorie i pozostalosci. Zwraca podsumowanie.
function WykonajCzyszczenie {
    ZatrzymajOllama   # asystent nie jest juz potrzebny - zwalnia VRAM i RAM na czas czyszczenia
    Log ("Plan: kategorie [{0}], pozostalosci [{1}]" -f (($script:Kategorie | Where-Object { $_.Wybrana } | ForEach-Object { $_.Id }) -join ', '),
        (($script:Pozostalosci | Where-Object { $_.Wybrana } | ForEach-Object { $_.Id }) -join ', '))
    $zegar = [Diagnostics.Stopwatch]::StartNew()
    $suma = 0.0

    # Punkt przywracania przed zmianami, ktorych nie cofnie Kosz: rejestr, zadania, sterowniki
    $wybranePoz = @($script:Pozostalosci | Where-Object { $_.Wybrana })
    if (@($wybranePoz | Where-Object { -not (NaKosz $_) }).Count -or @($script:Kategorie | Where-Object { $_.Wybrana -and $_.Typ -eq 'driverstore' }).Count) {
        Wypisz (L '  Tworzę punkt przywracania systemu (do 30 s)...' '  Creating a System Restore point (up to 30 s)...') 'Gray'
        $pp = PunktPrzywracania
        Wypisz ((L '  Punkt przywracania: {0}' '  Restore point: {0}') -f $pp.Opis) $(if ($pp.Ok) { 'Green' } else { 'Yellow' })
        Log "Punkt przywracania: $($pp.Opis)"
    }

    foreach ($k in ($script:Kategorie | Where-Object { $_.Wybrana })) {
        $zysk = 0.0; $bledy = 0
        Postep ("   {0}..." -f $k.Nazwa)
        if ($k.Procesy -and (Get-Process $k.Procesy)) {
            Wypisz ("  {0,-52} {1}" -f $k.Nazwa, (L 'pominięto (przeglądarka działa)' 'skipped (a browser is running)')) 'Yellow'
            Log "$($k.Id): pominieto - dziala przegladarka"
            continue
        }
        $pominieteAplikacje = @()
        switch ($k.Typ) {
            'folder' {
                foreach ($u in $k.Uslugi) { Stop-Service $u -Force }
                if ($k.Uslugi) { Pauza 2000 }
                $sciezki = $k.Sciezki
                if ($k.Grupy) {
                    $sciezki = @()
                    foreach ($g in $k.Grupy) {
                        if (Get-Process $g.Procesy) { $pominieteAplikacje += $g.Nazwa } else { $sciezki += $g.Sciezki }
                    }
                }
                foreach ($s in $sciezki) {
                    $r = UsunZawartosc $s ([int]$k.MinWiek)
                    $zysk += $r.Bajty; $bledy += $r.Bledy
                }
                foreach ($u in $k.Uslugi) { Start-Service $u }
            }
            'kosz' {
                $zysk = $k.Bajty
                if ($InnyUzytkownik) { foreach ($s in FolderyKosza) { [void](UsunZawartosc $s) } } else { Clear-RecycleBin -Force -Confirm:$false }
            }
            'miniatury' {
                Stop-Process -Name explorer -Force
                Pauza 3000
                foreach ($f in PlikiMiniatur) { try { $dl = $f.Length; $f.Delete(); $zysk += $dl } catch { $bledy++ } }
                # Windows sam wznawia powloke; recznie tylko na wlasnym koncie (inaczej ruszylaby jako administrator)
                for ($i = 0; $i -lt 10 -and -not (Get-Process explorer); $i++) { Pauza 1000 }
                if (-not (Get-Process explorer) -and -not $InnyUzytkownik) { Start-Process explorer.exe }
            }
            'dns' { ipconfig /flushdns | Out-Null }
            'winold' {
                Wypisz (L '  Oczyszczanie dysku Windows usuwa poprzednią wersję systemu - to potrwa kilka minut...' '  Windows Disk Cleanup is removing the previous Windows version - this takes a few minutes...') 'Gray'
                $przed = WolneC
                UsunPoprzedniWindows
                $bledy = @($k.Sciezki | Where-Object { Test-Path -LiteralPath $_ }).Count
                $zysk = [math]::Max(0, (WolneC) - $przed)
            }
            'dism' {
                Wypisz (L '  DISM pracuje - to potrwa kilka minut...' '  DISM is working - this takes a few minutes...') 'Gray'
                $przed = WolneC
                $p = Start-Process Dism.exe -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase' -WindowStyle Hidden -PassThru
                while (-not $p.WaitForExit(500)) { Pauza 0 }
                $zysk = [math]::Max(0, (WolneC) - $przed)
            }
            'docker' { docker builder prune -a -f 2>&1 | Select-Object -Last 1 | ForEach-Object { Wypisz "  $_" 'DarkGray' } }
            'driverstore' {
                foreach ($d in $k.Pakiety) {
                    Pauza 0
                    $wy = & pnputil.exe /delete-driver $d.Inf 2>&1
                    if ($LASTEXITCODE -eq 0) { $zysk += $d.Bajty; Log "Sterownik usuniety: $($d.Inf) $($d.Nazwa) $($d.Wersja) ($(Rozmiar $d.Bajty))" }
                    else { $bledy++; Log "Sterownik zostawiony: $($d.Inf) $($d.Nazwa) $($d.Wersja): $($wy -join ' ')" }
                }
            }
        }
        $suma += $zysk
        $kolor = if ($zysk -gt 50MB) { 'Green' } else { 'Gray' }
        $dop = if ($bledy) { (L '  ({0} w użyciu, pominięte)' '  ({0} in use, skipped)') -f $bledy } else { '' }
        if ($pominieteAplikacje) {
            $dop += (L '  (pominięto - działa: {0})' '  (skipped - running: {0})') -f ($pominieteAplikacje -join ', ')
            Log "$($k.Id): pominieto dzialajace $($pominieteAplikacje -join ', ')"
        }
        Wypisz ("  {0,-52} {1,10}{2}" -f $k.Nazwa, (Rozmiar $zysk), $dop) $kolor
        Log ("{0}: {1} zwolnione, {2} pominietych" -f $k.Id, (Rozmiar $zysk), $bledy)
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $kopie = $null
    if ($wybranePoz.Count) {
        Wypisz ''
        Wypisz (L '  Pozostałości po odinstalowanych programach i grach:' '  Leftovers of uninstalled programs and games:') 'Cyan'
        $kopie = Join-Path $LogDir ("kopie_rejestru\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
        $doKosza = L '-> Kosz' '-> Recycle Bin'
        foreach ($p in $wybranePoz) {
            Pauza 0
            try {
                if ($p.Typ -eq 'folder') {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p.Sciezka, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    Wypisz ("  {0,-60} {1,10}  {2}" -f $p.Sciezka, (Rozmiar $p.Bajty), $doKosza) 'Green'
                    Log "Do Kosza (folder): $($p.Sciezka) ($(Rozmiar $p.Bajty))"
                }
                elseif ($p.Typ -eq 'plik') {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p.Sciezka, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    Wypisz ("  {0,-60} {1,10}  {2}" -f $p.Sciezka, (Rozmiar $p.Bajty), $doKosza) 'Green'
                    Log "Do Kosza (plik): $($p.Sciezka) ($(Rozmiar $p.Bajty))"
                }
                elseif ($p.Typ -eq 'rejestr') {
                    New-Item -ItemType Directory -Force $kopie | Out-Null
                    $plik = Join-Path $kopie ("{0}_{1}.reg" -f $p.Id, ($p.Nazwa -replace '[^\w\-\. ]', '_'))
                    & reg.exe export $p.Sciezka $plik /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $plik)) { throw (L 'nie udało się zrobić kopii - klucz zostawiony' 'backup failed - key kept') }
                    Remove-Item -LiteralPath "Registry::$($p.Sciezka)" -Recurse -Force -ErrorAction Stop
                    Wypisz ("  {0,-60} {1,10}" -f $p.Sciezka, (L 'usunięty' 'deleted')) 'Green'
                    Log "Rejestr usuniety: $($p.Sciezka) (kopia: $plik)"
                }
                elseif ($p.Typ -eq 'wartosc') {
                    New-Item -ItemType Directory -Force $kopie | Out-Null
                    $plik = Join-Path $kopie ("{0}_{1}.reg" -f $p.Id, ($p.Nazwa -replace '[^\w\-\. ]', '_'))
                    KopiaWartosci $p.Sciezka $p.Wartosc $plik
                    Remove-ItemProperty -LiteralPath "Registry::$($p.Sciezka)" -Name $p.Wartosc -Force -ErrorAction Stop
                    Wypisz ("  {0,-60} {1,10}" -f (PokazPozostalosc $p), (L 'usunięty' 'deleted')) 'Green'
                    Log "Rejestr usuniety: $($p.Sciezka) -> $($p.Wartosc) (kopia: $plik)"
                }
                elseif ($p.Typ -eq 'zadanie') {
                    New-Item -ItemType Directory -Force $kopie | Out-Null
                    $plik = Join-Path $kopie ("{0}_{1}.xml" -f $p.Id, ($p.Nazwa -replace '[^\w\-\. ]', '_'))
                    $xml = Export-ScheduledTask -TaskName $p.Nazwa -TaskPath $p.Folder
                    if (-not $xml) { throw (L 'nie udało się zrobić kopii - zadanie zostawione' 'backup failed - task kept') }
                    [IO.File]::WriteAllText($plik, $xml, [Text.Encoding]::Unicode)
                    Unregister-ScheduledTask -TaskName $p.Nazwa -TaskPath $p.Folder -Confirm:$false -ErrorAction Stop
                    Wypisz ("  {0,-60} {1,10}" -f (PokazPozostalosc $p), (L 'usunięte' 'deleted')) 'Green'
                    Log "Zadanie usuniete: $($p.Sciezka) (kopia: $plik)"
                }
            }
            catch {
                Wypisz ("  {0}: {1}" -f $p.Sciezka, $_.Exception.Message) 'Yellow'
                Log "Blad pozostalosci $($p.Sciezka): $($_.Exception.Message)"
            }
        }
        if (@($wybranePoz | Where-Object { $_.Typ -in 'rejestr', 'wartosc' }).Count) {
            Wypisz ((L '  Kopie rejestru: {0} (dwuklik na pliku .reg przywraca klucz)' '  Registry backups: {0} (double-click a .reg file to restore the key)') -f $kopie) 'DarkGray'
        }
        if (@($wybranePoz | Where-Object { $_.Typ -eq 'zadanie' }).Count) {
            Wypisz ((L '  Kopie zadań: {0} (Harmonogram zadań > Importuj zadanie przywraca zadanie z pliku .xml)' '  Task backups: {0} (Task Scheduler > Import Task restores a task from its .xml file)') -f $kopie) 'DarkGray'
        }
    }

    $zegar.Stop()
    $wolnePo = WolneC
    Log ("Koniec. Usunieto {0}, wolne {1}: {2} -> {3}" -f (Rozmiar $suma), $Sys, (Rozmiar $script:WolnePrzed), (Rozmiar $wolnePo))
    @{ Suma = $suma; Czas = $zegar.Elapsed; WolnePrzed = $script:WolnePrzed; WolnePo = $wolnePo; Kopie = $kopie }
}

# Tekst podsumowania po czyszczeniu (linie)
function TekstPoCzyszczeniu($w) {
    @(
        (L 'Usunięte dane       : {0}' 'Data removed        : {0}') -f (Rozmiar $w.Suma)
        (L 'Czas                : {0}m {1}s' 'Time                : {0}m {1}s') -f $w.Czas.Minutes, $w.Czas.Seconds
        (L 'Wolne na {1} przed  : {0}' 'Free on {1} before  : {0}') -f (Rozmiar $w.WolnePrzed), $Sys
        (L 'Wolne na {1} po     : {0}' 'Free on {1} after   : {0}') -f (Rozmiar $w.WolnePo), $Sys
    )
}
