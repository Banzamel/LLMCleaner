<#
    LLMCleaner - skan kategorii i dysku, Docker, caly skan
#>

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
                'docker' { $k.Bajty = [double](DockerDoOdzyskania).Cache; if (-not $script:DockerDziala) { $k.Uwaga = L 'Docker nie działa - uruchom go, żeby zmierzyć i wyczyścić.' 'Docker is not running - start it to measure and clean.' } }
                'dockerall' {
                    $d = DockerDoOdzyskania
                    $k.Bajty = [double]$d.Zajete
                    if (-not $script:DockerDziala) { $k.Uwaga = L 'Docker nie działa - uruchom go, żeby zmierzyć i wyczyścić.' 'Docker is not running - start it to measure and clean.' }
                    elseif ($d.Zajete -gt 0) { $k.Uwaga = (L 'Zajęte: obrazy {0}, kontenery {1}, wolumeny {2}, cache budowania {3}. W tym nieużywane: {4}.' 'Used: images {0}, containers {1}, volumes {2}, build cache {3}. Unused part: {4}.') -f (Rozmiar $d.Zaj.Obrazy), (Rozmiar $d.Zaj.Kontenery), (Rozmiar $d.Zaj.Wolumeny), (Rozmiar $d.Zaj.Cache), (Rozmiar $d.Razem) }
                }
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

# Docker: ile da sie odzyskac wedlug "docker system df" (kolumna RECLAIMABLE). Pusto, gdy Docker nie dziala.
$script:DockerDziala = $false
function DockerBajty([string]$s) {
    $m = [regex]::Match("$s", '^\s*([\d\.]+)\s*([kKMGT]?)B')
    if (-not $m.Success) { return 0.0 }
    $mn = @{ '' = 1.0; 'k' = 1e3; 'M' = 1e6; 'G' = 1e9; 'T' = 1e12 }[$m.Groups[2].Value]   # klucze bez rozroznienia wielkosci liter
    [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) * $mn
}
function DockerDoOdzyskania {
    $w = @{ Obrazy = 0.0; Kontenery = 0.0; Wolumeny = 0.0; Cache = 0.0; Razem = 0.0; Zajete = 0.0; Zaj = @{ Obrazy = 0.0; Kontenery = 0.0; Wolumeny = 0.0; Cache = 0.0 } }
    $linie = @(docker system df --format '{{json .}}' 2>$null)
    $script:DockerDziala = $LASTEXITCODE -eq 0 -and $linie.Count
    foreach ($l in $linie) {
        try {
            $o = $l | ConvertFrom-Json -ErrorAction Stop
            $b = DockerBajty $o.Reclaimable
            $z = DockerBajty $o.Size
            $w.Zajete += $z
            $t = switch -Wildcard ($o.Type) { 'Images' { 'Obrazy' } 'Containers' { 'Kontenery' } '*Volumes' { 'Wolumeny' } 'Build Cache' { 'Cache' } }
            if ($t) { $w[$t] = $b; $w.Zaj[$t] = $z }
        }
        catch { }
    }
    $w.Razem = $w.Obrazy + $w.Kontenery + $w.Wolumeny + $w.Cache
    $w
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
            Pobrane = ($f.FullName -like "$pobrane\*")
        }
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
        Profil    = @($gorne.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
                ForEach-Object { @{ folder = $_.Key; rozmiar = (Rozmiar $_.Value) } })
        AppData   = @($appdata.GetEnumerator() | Where-Object { $_.Value -ge 300MB } | Sort-Object Value -Descending |
                Select-Object -First 12 | ForEach-Object { @{ folder = $_.Key; rozmiar = (Rozmiar $_.Value) } })
        Programy  = @($programy)
        System    = @{
            hiberfil            = $(if ($hib) { Rozmiar $hib.Length } else { L 'brak (hibernacja wyłączona)' 'none (hibernation off)' })
            windows_old         = (Test-Path -LiteralPath "$Sys\Windows.old")
            stara_instalacja_bt = (Test-Path -LiteralPath "$Sys\`$WINDOWS.~BT")
        }
        Dyski     = @(DyskiWybrane | ForEach-Object { @{ dysk = $_.DeviceID; wolne = (Rozmiar $_.FreeSpace); calosc = (Rozmiar $_.Size) } })
    }
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
                else { L 'Duży plik (ponad 1 GB) w profilu użytkownika.' 'Large file (over 1 GB) in the user profile.' })
        }
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
