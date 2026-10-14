<#
    LLMCleaner - punkt przywracania i wykonanie czyszczenia
#>

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

# Postep krok po kroku dla okna (ekran czyszczenia); w konsoli nic nie robi.
# Stan: trwa, ok, czesc (zrobione z pominieciami), pominieto, blad.
$script:NaKrok = $null
function ZglosKrok([string]$id, [string]$stan, [double]$bajty = 0, [string]$uwaga = '') {
    if ($script:NaKrok) { & $script:NaKrok $id $stan $bajty $uwaga }
}

# Punkt przywracania przed zmianami, ktorych nie cofnie Kosz: rejestr, zadania, sterowniki
function PotrzebnyPunkt {
    [bool](@($script:Pozostalosci | Where-Object { $_.Wybrana -and -not (NaKosz $_) }).Count -or
        @($script:Kategorie | Where-Object { $_.Wybrana -and $_.Typ -eq 'driverstore' }).Count)
}

# Czysci zaznaczone kategorie i pozostalosci. Zwraca podsumowanie.
function WykonajCzyszczenie {
    ZatrzymajOllama   # asystent nie jest juz potrzebny - zwalnia VRAM i RAM na czas czyszczenia
    Log ("Plan: kategorie [{0}], pozostalosci [{1}]" -f (($script:Kategorie | Where-Object { $_.Wybrana } | ForEach-Object { $_.Id }) -join ', '),
        (($script:Pozostalosci | Where-Object { $_.Wybrana } | ForEach-Object { $_.Id }) -join ', '))
    $zegar = [Diagnostics.Stopwatch]::StartNew()
    $suma = 0.0

    # Najpierw to, co idzie do Kosza, potem rejestr i zadania (osobne kroki na ekranie postepu)
    $wybranePoz = @(@($script:Pozostalosci | Where-Object { $_.Wybrana -and (NaKosz $_) }) +
        @($script:Pozostalosci | Where-Object { $_.Wybrana -and -not (NaKosz $_) }))
    if (PotrzebnyPunkt) {
        ZglosKrok 'punkt' 'trwa'
        Wypisz (L '  Tworzę punkt przywracania systemu (do 30 s)...' '  Creating a System Restore point (up to 30 s)...') 'Gray'
        $pp = PunktPrzywracania
        Wypisz ((L '  Punkt przywracania: {0}' '  Restore point: {0}') -f $pp.Opis) $(if ($pp.Ok) { 'Green' } else { 'Yellow' })
        Log "Punkt przywracania: $($pp.Opis)"
        ZglosKrok 'punkt' $(if ($pp.Ok) { 'ok' } else { 'czesc' }) 0 $pp.Opis
    }

    foreach ($k in ($script:Kategorie | Where-Object { $_.Wybrana })) {
        $zysk = 0.0; $bledy = 0
        Postep ("   {0}..." -f $k.Nazwa)
        ZglosKrok $k.Id 'trwa'
        if ($k.Procesy -and (Get-Process $k.Procesy)) {
            Wypisz ("  {0,-52} {1}" -f $k.Nazwa, (L 'pominięto (przeglądarka działa)' 'skipped (a browser is running)')) 'Yellow'
            Log "$($k.Id): pominieto - dziala przegladarka"
            ZglosKrok $k.Id 'pominieto' 0 (L 'pominięto: działa przeglądarka' 'skipped: a browser is running')
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
                $zysk = [math]::Max(0.0, (WolneC) - $przed)
            }
            'dism' {
                Wypisz (L '  DISM pracuje - to potrwa kilka minut...' '  DISM is working - this takes a few minutes...') 'Gray'
                $przed = WolneC
                $p = Start-Process Dism.exe -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase' -WindowStyle Hidden -PassThru
                while (-not $p.WaitForExit(500)) { Pauza 0 }
                $zysk = [math]::Max(0.0, (WolneC) - $przed)
            }
            'docker' {
                $przed = (DockerDoOdzyskania).Cache
                docker builder prune -a -f 2>&1 | Select-Object -Last 1 | ForEach-Object { Wypisz "  $_" 'DarkGray' }
                $zysk = [math]::Max(0.0, $przed - (DockerDoOdzyskania).Cache)
            }
            'dockerall' {
                $przed = (DockerDoOdzyskania).Zajete
                $kontenery = @(docker ps -aq 2>$null | Where-Object { $_ })
                if ($kontenery.Count) {
                    Wypisz ((L '  Docker zatrzymuje i usuwa kontenery: {0}...' '  Docker is stopping and removing containers: {0}...') -f $kontenery.Count) 'Gray'
                    docker rm -f -v @kontenery 2>&1 | Out-Null
                    Log "Docker: usunieto kontenery ($($kontenery.Count))"
                }
                Wypisz (L '  Docker usuwa obrazy, wolumeny, sieci i cache...' '  Docker is removing images, volumes, networks and cache...') 'Gray'
                docker system prune -a --volumes -f 2>&1 | Select-Object -Last 1 | ForEach-Object { Wypisz "  $_" 'DarkGray' }
                # Od Dockera 23 prune --volumes usuwa tylko wolumeny anonimowe, nazwane trzeba usunac osobno
                $wolumeny = @(docker volume ls -q 2>$null | Where-Object { $_ })
                if ($wolumeny.Count) {
                    Wypisz ((L '  Docker usuwa wolumeny: {0}...' '  Docker is removing volumes: {0}...') -f $wolumeny.Count) 'Gray'
                    docker volume rm -f @wolumeny 2>&1 | Out-Null
                    Log "Docker: usunieto wolumeny ($($wolumeny.Count))"
                }
                # Historia budowania (lista Builds w Docker Desktop) dla kazdego buildera; starsze buildx nie maja tej komendy
                $buildery = @(docker buildx ls --format '{{.Name}}' 2>$null | Where-Object { $_ -and $_ -notmatch '\s' } | Select-Object -Unique)
                if (-not $buildery.Count) { $buildery = @('') }
                foreach ($b in $buildery) {
                    $arg = @('buildx', 'history', 'rm', '--all') + $(if ($b) { '--builder', $b })
                    docker @arg 2>&1 | Out-Null
                }
                $zysk = [math]::Max(0.0, $przed - (DockerDoOdzyskania).Zajete)
            }
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
        $uwagi = @()
        if ($bledy) { $uwagi += (L '{0} w użyciu - pominięte' '{0} in use - skipped') -f $bledy }
        if ($pominieteAplikacje) { $uwagi += (L 'pominięto: działa {0}' 'skipped: {0} is running') -f ($pominieteAplikacje -join ', ') }
        $stan = if ($pominieteAplikacje -and -not $zysk) { 'pominieto' } elseif ($uwagi.Count) { 'czesc' } else { 'ok' }
        ZglosKrok $k.Id $stan $zysk ($uwagi -join '; ')
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $kopie = $null
    if ($wybranePoz.Count) {
        Wypisz ''
        Wypisz (L '  Pozostałości po odinstalowanych programach i grach:' '  Leftovers of uninstalled programs and games:') 'Cyan'
        $kopie = Join-Path $LogDir ("kopie_rejestru\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
        $doKosza = L '-> Kosz' '-> Recycle Bin'
        $krok = $null; $bajtyKroku = 0.0; $bledyKroku = 0
        $zakonczKrok = {
            ZglosKrok $krok $(if ($bledyKroku) { 'czesc' } else { 'ok' }) $bajtyKroku $(if ($bledyKroku) { (L 'nie udało się: {0} - szczegóły w Dzienniku' 'failed: {0} - see the Log') -f $bledyKroku } else { '' })
        }
        foreach ($p in $wybranePoz) {
            Pauza 0
            $id = if (NaKosz $p) { 'poz-kosz' } else { 'poz-kopia' }
            if ($id -ne $krok) {
                if ($krok) { & $zakonczKrok }
                $krok = $id; $bajtyKroku = 0.0; $bledyKroku = 0
                ZglosKrok $krok 'trwa'
            }
            try {
                if ($p.Typ -eq 'folder') {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p.Sciezka, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    Wypisz ("  {0,-60} {1,10}  {2}" -f $p.Sciezka, (Rozmiar $p.Bajty), $doKosza) 'Green'
                    Log "Do Kosza (folder): $($p.Sciezka) ($(Rozmiar $p.Bajty))"
                    $bajtyKroku += [double]$p.Bajty
                }
                elseif ($p.Typ -eq 'plik') {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p.Sciezka, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    Wypisz ("  {0,-60} {1,10}  {2}" -f $p.Sciezka, (Rozmiar $p.Bajty), $doKosza) 'Green'
                    Log "Do Kosza (plik): $($p.Sciezka) ($(Rozmiar $p.Bajty))"
                    $bajtyKroku += [double]$p.Bajty
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
                $bledyKroku++
            }
        }
        if ($krok) { & $zakonczKrok }
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
