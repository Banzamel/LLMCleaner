<#
    LLMCleaner - pozostalosci po odinstalowanych programach i grach (foldery, pliki, rejestr, Steam, Epic)
#>

function NazwaPewnosci([string]$p) {
    switch ($p) { 'wysoka' { L 'wysoka' 'high' } 'srednia' { L 'średnia' 'medium' } 'niska' { L 'niska' 'low' } default { $p } }
}

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
    foreach ($w in $wpisy) {
        try {
            $v = $w.V
            if ($v.SystemComponent -eq 1 -or $v.WindowsInstaller -eq 1 -or "$($v.UninstallString)" -match 'msiexec') { continue }
            $exe = SciezkaPliku $v.UninstallString
            if (-not $exe -or (Test-Path -LiteralPath $exe)) { continue }
            $loc = "$($v.InstallLocation)".Trim('"', ' ')
            if ($loc -and (Test-Path -LiteralPath $loc)) { continue }
            @{ Typ = 'rejestr'; Sciezka = $w.Klucz; Nazwa = $v.DisplayName; Bajty = 0.0
                Pewnosc = $(if ($loc) { 'wysoka' } else { 'srednia' })
                Dlaczego = $(if ($loc) { L 'Martwy wpis na liście programów: deinstalator nie istnieje, folder instalacji też nie.' 'Dead entry in the program list: the uninstaller and the install folder are both gone.' }
                    else { L 'Martwy wpis na liście programów: deinstalator nie istnieje.' 'Dead entry in the program list: the uninstaller is gone.' })
            }
        }
        catch { BladSkanu "wpis $($w.Klucz)" $_ }
    }
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
                    Dlaczego = (L 'Folder gry Steam bez manifestu - gra została odinstalowana, pliki zostały.' 'Steam game folder without a manifest - the game was uninstalled but its files remain.')
                }
            }
        }
        foreach ($sub in 'shadercache', 'workshop\content') {
            foreach ($d in Get-ChildItem -LiteralPath "$sa\$sub" -Directory -Force) {
                if ($d.Name -match '^\d+$' -and -not $ids[$d.Name]) {
                    @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = "Steam $sub $($d.Name)"; Pewnosc = 'wysoka'; Gra = $true
                        Dlaczego = ((L 'Steam {0} dla gry (appid {1}), której już nie ma.' 'Steam {0} for a game (appid {1}) that is no longer installed.') -f $sub, $d.Name)
                    }
                }
            }
        }
    }
}

# Folder, ktorego nigdy nie proponujemy do usuniecia, bez wzgledu na to, co znalazla regula: korzen dysku,
# foldery systemowe w korzeniu (Kosz, System Volume Information...), foldery Windows, profilu i samego LLMCleanera
$SystemoweWKorzeniu = @('$recycle.bin', 'system volume information', 'recovery', 'config.msi', 'msocache', 'perflogs',
    'boot', 'windows', 'windows.old', 'program files', 'program files (x86)', 'programdata', 'users', 'documents and settings',
    'onedrivetemp', 'intel', 'amd', 'nvidia', 'drivers', 'efi')
function FolderChroniony([string]$sciezka) {
    if (-not $sciezka) { return $true }
    $s = $sciezka.Trim().TrimEnd('\').ToLower()
    if ($s -notmatch '^[a-z]:\\.') { return $true }                      # korzen dysku albo dziwna sciezka
    $czesci = $s -split '\\'
    if ($czesci.Count -eq 2 -and ($czesci[1] -in $SystemoweWKorzeniu -or $czesci[1].StartsWith('$'))) { return $true }
    foreach ($c in $WinDir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, $env:APPDATA,
        $env:LOCALAPPDATA, "$env:USERPROFILE\AppData\LocalLow", (Split-Path $env:USERPROFILE -Parent), $AppDir) {
        if (-not $c) { continue }
        $c = $c.TrimEnd('\').ToLower()
        # Sam folder chroniony albo jego folder nadrzedny (np. P:\LLMCleaner, gdy program stoi w P:\LLMCleaner\app)
        if ($c -eq $s -or $c.StartsWith("$s\")) { return $true }
    }
    $false
}

# Folder zawiera zainstalowany program, biblioteke Steam albo gre Epic (np. G:\Steam, P:\Git) - wtedy nie jest pozostaloscia
function ZawieraZainstalowane([string]$sciezka, $zainst, $chronione) {
    $s = $sciezka.TrimEnd('\').ToLower()
    foreach ($p in @($zainst.Sciezki) + @($chronione)) {
        if (-not $p) { continue }
        $p = "$p".TrimEnd('\').ToLower()
        if ($p -eq $s -or $p.StartsWith("$s\")) { return $true }
    }
    $false
}

# Gra z Epic Games Launcher ma w swoim folderze podfolder .egstore. Folder nadrzedny gry (np. G:\ albo
# Program Files) NIE jest biblioteka Epic - stoja w nim zwykle inne programy i gry. Dlatego folder spoza
# folderu "Epic Games" trafia na liste tylko wtedy, gdy ma .egstore, a korzen dysku nigdy nie jest traktowany
# jak biblioteka (wczesniej regula proponowala do usuniecia cale G:\Steam czy P:\Git).
function EpicOsierocone {
    $man = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (-not (Test-Path -LiteralPath $man)) { return }
    $zainst = @{}; $rodzice = @{ "$env:ProgramFiles\Epic Games".ToLower() = 1 }
    foreach ($i in Get-ChildItem -LiteralPath $man -Filter *.item) {
        try { $loc = (Get-Content -LiteralPath $i.FullName -Raw | ConvertFrom-Json).InstallLocation } catch { BladSkanu "manifest Epic $($i.Name)" $_; continue }
        if (-not $loc) { continue }
        $loc = $loc.Replace('/', '\').TrimEnd('\').ToLower()
        $zainst[$loc] = 1
        $r = Split-Path $loc -Parent
        if ($r) { $rodzice[$r] = 1 }   # korzen zostaje jako G:\ (samo G: to biezacy folder dysku)
    }
    $script:EpicZainstalowane = @($zainst.Keys)
    foreach ($r in @($rodzice.Keys | Where-Object { NaWybranymDysku $_ })) {
        $folderEpic = (Split-Path $r -Leaf) -like '*epic*'
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force) {
            if ($zainst[$d.FullName.ToLower()] -or $d.Name -in 'Launcher', 'DirectXRedist' -or $d.Name -like 'UE_*') { continue }
            if ($d.Attributes -band $REPARSE -or $d.Attributes -band [IO.FileAttributes]::System -or (FolderChroniony $d.FullName)) { continue }
            $egstore = Test-Path -LiteralPath (Join-Path $d.FullName '.egstore')
            if (-not $egstore -and -not $folderEpic) { continue }
            @{ Typ = 'folder'; Sciezka = $d.FullName; Nazwa = $d.Name; Gra = $true
                Pewnosc = $(if ($egstore) { 'wysoka' } else { 'srednia' })
                Dlaczego = (L 'Folder gry Epic, której nie ma na liście zainstalowanych w Epic Games Launcher.' 'Epic game folder that is not on the Epic Games Launcher list of installed games.')
            }
        }
    }
}

function SkanujPozostalosci {
    $script:EpicZainstalowane = @()
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
                if ((Pomijana $d.Name) -or (FolderChroniony $d.FullName)) { continue }
                if (NalezyDoProgramu $d.Name $d.FullName $zainst) { continue }
                $doSprawdzenia += @{ D = $d; Zapisy = $k.Gra }
            }
            catch { BladSkanu "folder $($d.FullName)" $_ }
        }
    }
    foreach ($c in $doSprawdzenia) {
        try {
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
                        else { L 'Brak zainstalowanego programu o tej nazwie.' 'No installed program with this name.' })
                })
        }
        catch { BladSkanu "folder $($c.D.FullName)" $_ }
    }

    # Gry
    $gry = @()
    try { $gry += @(SteamOsierocone) } catch { BladSkanu 'Steam' $_ }
    try { $gry += @(EpicOsierocone) } catch { BladSkanu 'Epic' $_ }
    # Bezpiecznik: folder gry nie moze zawierac zainstalowanego programu, biblioteki Steam ani gry Epic
    $chronione = @(SteamBiblioteki) + @($script:EpicZainstalowane)
    foreach ($g in $gry) {
        if ((FolderChroniony $g.Sciezka) -or (ZawieraZainstalowane $g.Sciezka $zainst $chronione)) { Log "Pominieto chroniony folder gry: $($g.Sciezka)"; continue }
        try { $m = ZmierzFolder $g.Sciezka; $g.Bajty = $m.Bajty; $g.Ostatnio = $m.Ostatnio; $wyniki.Add($g) }
        catch { BladSkanu "gra $($g.Sciezka)" $_ }
    }

    # Rejestr: klucze producentow bez programu i bez folderu o tej nazwie
    $rej = [System.Collections.Generic.List[object]]::new()
    foreach ($r in "$HKCUNazwa\Software", 'HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node') {
        foreach ($k in Get-ChildItem "Registry::$r") {
            try {
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
            }
            catch { BladSkanu "klucz $r\$($k.PSChildName)" $_ }
        }
    }

    $start = @()
    try { $start = @(MartweAutostarty) } catch { BladSkanu 'autostart' $_ }

    @($wyniki | Sort-Object { $_.Bajty } -Descending) + @($martwe) + @($start) + @($rej)
}
