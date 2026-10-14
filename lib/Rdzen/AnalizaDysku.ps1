<#
    LLMCleaner - analiza dysku: co zajmuje miejsce, porady stale i AI
#>

# Tylko do wgladu - nic stad nie trafia do planu. Skaner w C#, bo petla w PowerShellu
# przechodzi milion plikow kilka minut. Nie wchodzi w junctions/symlinki, pomija pliki
# tylko w chmurze (OneDrive). Twarde linki (WinSxS) sa liczone wielokrotnie, jak w Eksploratorze.
function KompilujSkaner {
    if ('LlmSkaner' -as [type]) { return }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Rdzen\cs\LlmSkaner.cs')))
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
                Ostatnio = $f.Ostatnio; Podpowiedz = (Podpowiedz $f.Sciezka)
            })
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
        Foldery = $foldery; Pliki = $pliki; Cienie = $cienie; Prog = $prog
    }
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
}
else {
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
    type       = 'object'
    properties = @{
        pozycje = @{ type = 'array'; items = @{ type = 'object'
                properties                           = @{ id = @{ type = 'string' }; opis = @{ type = 'string' }; rada = @{ type = 'string'; enum = $Rady } }
                required                             = @('id', 'opis', 'rada')
            }
        }
    }
    required   = @('pozycje')
}

$SysAnaliza = if ($Jezyk -eq 'en') {
    @'
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
'@
}
else {
    @'
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
'@
}

# Opisy i rady modelu dla analizy dysku. Zwraca liczbe opisanych pozycji (albo -1 przy bledzie).
function AnalizaAi($a) {
    if (-not (ZapewnijModel)) { return -1 }
    $lista = @(@($a.Foldery) + @($a.Pliki) | ForEach-Object {
            @{ id = $_.Id; typ = $_.Typ; sciezka = $_.Sciezka; rozmiar = (Rozmiar $_.Bajty); podpowiedz = $_.Podpowiedz
                ostatnia_zmiana = $(if ($_.Ostatnio -gt [datetime]'1980-01-01') { $_.Ostatnio.ToString('yyyy-MM-dd') })
            } })
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
