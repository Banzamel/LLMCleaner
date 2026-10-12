<#
    LLMCleaner - interfejs tekstowy (parametr -Konsola). Logika jest w Rdzen.ps1.
#>

function Naglowek($t) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}

function WybierzDyskiKonsola {
    $lista = @(DyskiStale)
    if ($Dyski) { UstawDyski $Dyski; return }
    $wybor = @{}; foreach ($d in $lista) { $wybor[$d.DeviceID] = $true }
    while ($true) {
        Naglowek (L 'DYSKI DO SKANOWANIA' 'DRIVES TO SCAN')
        $i = 0
        foreach ($d in $lista) {
            $i++
            $znak = if ($wybor[$d.DeviceID]) { '[x]' } else { '[ ]' }
            $sys = if ($d.DeviceID -eq $Sys) { L '   (systemowy - zawsze)' '   (system - always)' } else { '' }
            Write-Host ("  {0} {1}. {2}{3}" -f $znak, $i, (OpisDysku $d), $sys) -ForegroundColor $(if ($wybor[$d.DeviceID]) { 'Green' } else { 'DarkGray' })
        }
        Write-Host (L '   Wybrane dyski: Kosz, biblioteki Steam/Epic i analiza miejsca (a). Dyski USB i sieciowe są pomijane.' '   Ticked drives: Recycle Bin, Steam/Epic libraries and the space analysis (a). USB and network drives are skipped.') -ForegroundColor DarkGray
        Write-Host (L '   Enter = skanuj zaznaczone | numery (np. 2 3) = zaznacz/odznacz' '   Enter = scan ticked drives | numbers (e.g. 2 3) = tick/untick') -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($w -eq '') { break }
        foreach ($n in ($w -split '[\s,;]+')) {
            $idx = 0
            if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $lista.Count) {
                $id = $lista[$idx - 1].DeviceID
                if ($id -ne $Sys) { $wybor[$id] = -not $wybor[$id] }
            }
        }
    }
    UstawDyski @($lista | Where-Object { $wybor[$_.DeviceID] } | ForEach-Object { $_.DeviceID })
}

function PokazPlan {
    Naglowek (L 'PLAN CZYSZCZENIA' 'CLEANUP PLAN')
    $i = 0
    foreach ($k in $script:Kategorie) {
        $i++
        $znak = if ($k.Wybrana) { '[x]' } else { '[ ]' }
        $kolor = if ($k.Wybrana) { 'Green' } elseif ($k.TylkoRecznie) { 'Gray' } else { 'DarkGray' }
        Write-Host ("  {0} {1,2}. {2,-52} {3,10}" -f $znak, $i, $k.Nazwa, (RozmiarKategorii $k)) -ForegroundColor $kolor
        if ($k.Blokada) { Write-Host "           ! $($k.Blokada)" -ForegroundColor Yellow }
        else { Write-Host "           $(if ($k.TylkoRecznie) { L '(tylko na Twoje życzenie) ' '(only if you choose it) ' })$($k.Opis)" -ForegroundColor DarkGray }
    }
    if ($script:Pozostalosci.Count) {
        Write-Host ""
        Write-Host (L '   POZOSTAŁOŚCI PO ODINSTALOWANYCH PROGRAMACH I GRACH' '   LEFTOVERS OF UNINSTALLED PROGRAMS AND GAMES') -ForegroundColor Cyan
        Write-Host (L '   (foldery i pliki idą do Kosza, klucze rejestru są wcześniej zapisywane do pliku .reg)' '   (folders and files go to the Recycle Bin, registry keys are first saved to a .reg file)') -ForegroundColor DarkGray
        foreach ($p in $script:Pozostalosci) {
            $i++
            $znak = if ($p.Wybrana) { '[x]' } else { '[ ]' }
            $kolor = if ($p.Wybrana) { 'Green' } elseif ($p.Pewnosc -eq 'niska') { 'DarkYellow' } else { 'DarkGray' }
            $roz = if ($p.Typ -ne 'rejestr') { Rozmiar $p.Bajty } else { L 'rejestr' 'registry' }
            $pokaz = if ($p.Typ -eq 'rejestr' -and $p.Nazwa -ne (Split-Path $p.Sciezka -Leaf)) { "$($p.Nazwa)  [$($p.Sciezka)]" } else { $p.Sciezka }
            Write-Host ("  {0} {1,2}. {2,-52} {3,10}  {4}: {5}" -f $znak, $i, $pokaz, $roz, (L 'pewność' 'confidence'), (NazwaPewnosci $p.Pewnosc)) -ForegroundColor $kolor
            Write-Host "           $($p.Dlaczego)" -ForegroundColor DarkGray
            if ($p.Ai) { Write-Host "           $EtykietaAi`: $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    Write-Host ""
    Write-Host ((L '   Zaznaczone razem: ok. {0}' '   Selected in total: about {0}') -f (Rozmiar (SumaZaznaczonych))) -ForegroundColor White
}

function CzatKonsola {
    if (-not (ZapewnijModel)) { return }
    ZacznijRozmowe
    Write-Host ""
    Write-Host (L '   Rozmowa z asystentem. Pusta linia = powrót do planu.' '   Chat with the assistant. An empty line returns to the plan.') -ForegroundColor Cyan
    while ($true) {
        Write-Host ""
        $q = Read-Host (L '   Ty' '   You')
        if (-not $q) { return }
        $a = Zapytaj $q
        if ($a) { Write-Host ""; Write-Host "   LLMCleaner: $a" -ForegroundColor White }
    }
}

function PokazAnalize($a) {
    Naglowek ((L 'CO ZAJMUJE MIEJSCE NA {0}:   zajęte {1} z {2}, wolne {3}' 'WHAT TAKES UP SPACE ON {0}:   {1} used of {2}, {3} free') -f $a.Litera, (Rozmiar ($a.Rozmiar - $a.Wolne)), (Rozmiar $a.Rozmiar), (Rozmiar $a.Wolne))
    Write-Host ((L '   Tylko do wglądu - nic stąd nie jest usuwane. Pokazane są najbardziej konkretne foldery od {0}.' '   Read-only - nothing here is deleted. The most specific folders from {0} up are shown.') -f (Rozmiar $a.Prog)) -ForegroundColor DarkGray
    $sekcje = @(@{ T = (L 'NAJWIĘKSZE FOLDERY' 'LARGEST FOLDERS'); L = $a.Foldery }, @{ T = (L 'NAJWIĘKSZE PLIKI' 'LARGEST FILES'); L = $a.Pliki })
    foreach ($s in $sekcje) {
        if (-not $s.L.Count) { continue }
        Write-Host ""
        Write-Host "   $($s.T)" -ForegroundColor Cyan
        foreach ($p in $s.L) {
            $dop = if ($p.Reszta) { L '  (pliki poza wymienionymi podfolderami)' '  (files outside the listed subfolders)' } else { '' }
            $data = if ($p.Ostatnio -gt [datetime]'1980-01-01') { $p.Ostatnio.ToString('yyyy-MM-dd') } else { '          ' }
            Write-Host ("  {0,4}. {1,10}  {2}  {3}{4}" -f $p.Id, (Rozmiar $p.Bajty), $data, $p.Sciezka, $dop) -ForegroundColor Gray
            if ($p.Podpowiedz) { Write-Host "                            $($p.Podpowiedz)" -ForegroundColor DarkGray }
            if ($p.Ai) { Write-Host "                            $EtykietaAi`: $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    if ($a.Cienie -gt 0) {
        Write-Host ""
        Write-Host ((L '   Punkty przywracania systemu: {0} (Ochrona systemu w Ustawieniach)' '   System Restore points: {0} (System Protection in Settings)') -f (Rozmiar $a.Cienie)) -ForegroundColor Gray
    }
    $niewidoczne = ($a.Rozmiar - $a.Wolne) - $a.Zeskanowane - $a.Cienie
    if ($niewidoczne -gt 2GB) {
        Write-Host ((L '   Niedostępne dla skanera (pliki systemowe, chronione foldery): ok. {0}' '   Not readable by the scanner (system files, protected folders): about {0}') -f (Rozmiar $niewidoczne)) -ForegroundColor DarkGray
    }
}

function AnalizaKonsola {
    $lista = @(DyskiWybrane)
    Write-Host ""
    Write-Host ("   " + (($lista | ForEach-Object { OpisDysku $_ }) -join ' | ')) -ForegroundColor Gray
    $dom = $Sys.TrimEnd(':')
    $l = (Read-Host ((L '   Który dysk przeanalizować? [{0}]' '   Which drive to analyse? [{0}]') -f $dom)).Trim().TrimEnd(':', '\').ToUpper()
    if (-not $l) { $l = $dom }
    if (-not ($lista | Where-Object { $_.DeviceID -eq "$l`:" })) { Write-Host ((L '   Dysk {0}: nie jest wybrany do skanowania.' '   Drive {0}: is not selected for scanning.') -f $l) -ForegroundColor Yellow; return }
    $a = Analizuj $l
    while ($true) {
        PokazAnalize $a
        Write-Host ""
        $pomoc = if ($BezLLM) { L 'Enter = powrót do planu' 'Enter = back to the plan' } else { L 'w = AI opisze te pozycje i doradzi | Enter = powrót do planu' 'w = AI describes these items and advises | Enter = back to the plan' }
        Write-Host "   $pomoc" -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($w -match '^[wW]$' -and -not $BezLLM) { [void](AnalizaAi $a); continue }
        return
    }
}

function PotwierdzKonsola {
    Naglowek (L 'PODSUMOWANIE PRZED CZYSZCZENIEM' 'SUMMARY BEFORE CLEANING')
    $linie = Podsumowanie
    if (-not $linie) { Write-Host (L '   Nic nie jest zaznaczone - nie ma czego czyścić.' '   Nothing is selected - there is nothing to clean.') -ForegroundColor Yellow; return $false }
    foreach ($x in $linie) { Write-Host "   $($x.T)" -ForegroundColor $x.K }
    Write-Host ""
    $t = Read-Host (L '   Uruchomić czyszczenie? [t/N]' '   Start cleaning? [y/N]')
    if ($t -match '^[TtYy]') { return $true }
    Write-Host (L '   Wracam do planu.' '   Back to the plan.') -ForegroundColor DarkGray
    $false
}

function Koniec([string]$tekst, [string]$kolor = 'Gray') {
    ZatrzymajOllama
    Write-Host "`n   $tekst`n" -ForegroundColor $kolor
    Read-Host (L '   Enter kończy' '   Press Enter to exit') | Out-Null
    exit
}

function UruchomKonsole {
    Clear-Host
    Write-Host ""
    Write-Host ((L '   LLMCleaner {0} - inteligentne czyszczenie komputera' '   LLMCleaner {0} - smart PC cleanup') -f $Wersja) -ForegroundColor White
    $asystent = if ($BezLLM) { L 'wyłączony' 'off' } else { (L '{0} (na żądanie)' '{0} (on demand)') -f $Model }
    Write-Host ((L '   {0}   asystent: {1}' '   {0}   assistant: {1}') -f (Get-Date -Format 'dd.MM.yyyy HH:mm'), $asystent) -ForegroundColor DarkGray
    if ($Podglad) { Write-Host (L '   TRYB PODGLĄDU - nic nie zostanie usunięte' '   PREVIEW MODE - nothing will be deleted') -ForegroundColor Yellow }
    Write-Host ""
    Log "Start (konsola). Model: $Model, Podglad: $Podglad, BezLLM: $BezLLM, Jezyk: $Jezyk"
    if (-not $BezAktualizacji) {
        SprawdzAktualizacje
        if ($script:Aktualizacja) {
            Write-Host ((L '   Dostępna nowa wersja {0} - klawisz u na ekranie planu ją zainstaluje.' '   New version {0} is available - press u on the plan screen to install it.') -f $script:Aktualizacja.Wersja) -ForegroundColor Yellow
            Write-Host ""
        }
    }

    WybierzDyskiKonsola
    Naglowek (L '1/2  Skanowanie' '1/2  Scanning')
    SkanujWszystko

    while ($true) {
        PokazPlan
        Write-Host ""
        $pomoc = if ($Podglad) { L 'Enter = zakończ' 'Enter = finish' } else { L 'Enter = dalej (podsumowanie i pytanie o czyszczenie)' 'Enter = next (summary and the cleaning question)' }
        $pomoc += L ' | numery (np. 3 7) = zaznacz/odznacz' ' | numbers (e.g. 3 7) = tick/untick'
        if (-not $BezLLM) { $pomoc += L ' | w = AI wyjaśni pozostałości | p = zapytaj asystenta' ' | w = AI explains leftovers | p = ask the assistant' }
        $pomoc += L ' | a = co zajmuje miejsce na dysku' ' | a = what takes up space'
        if ($script:Aktualizacja) { $pomoc += (L ' | u = zainstaluj wersję {0}' ' | u = install version {0}') -f $script:Aktualizacja.Wersja }
        $pomoc += L ' | q = wyjdź' ' | q = quit'
        Write-Host "   $pomoc" -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()

        if ($w -eq '') {
            if ($Podglad -or (PotwierdzKonsola)) { break }
            continue
        }
        if ($w -match '^[qQ]') { Log 'Przerwano przez uzytkownika.'; Koniec (L 'Przerwano - nic nie zostało usunięte.' 'Cancelled - nothing was deleted.') }
        if ($w -match '^[pP]$') { CzatKonsola; continue }
        if ($w -match '^[wW]$') { [void](WyjasnijPozostalosci); continue }
        if ($w -match '^[aA]$') { AnalizaKonsola; continue }
        if ($w -match '^[uU]$' -and $script:Aktualizacja) {
            if (ZainstalujAktualizacje) {
                ZatrzymajOllama
                Write-Host (L "`n   Instalator aktualizacji uruchomiony - LLMCleaner kończy pracę, nic nie zostało usunięte.`n" "`n   The update installer is running - LLMCleaner exits, nothing was deleted.`n") -ForegroundColor Green
                Start-Sleep -Seconds 3; exit
            }
            continue
        }
        foreach ($n in ($w -split '[\s,;]+')) {
            $idx = 0
            if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:Kategorie.Count) {
                $k = $script:Kategorie[$idx - 1]
                if ($k.Blokada) { Write-Host "   $($k.Nazwa): $($k.Blokada)" -ForegroundColor Yellow; continue }
                $k.Wybrana = -not $k.Wybrana
            }
            elseif ($idx -gt $script:Kategorie.Count -and $idx -le $script:Kategorie.Count + $script:Pozostalosci.Count) {
                $p = $script:Pozostalosci[$idx - $script:Kategorie.Count - 1]
                $p.Wybrana = -not $p.Wybrana
            }
        }
    }

    if ($Podglad) {
        Log 'Tryb podgladu - koniec bez usuwania.'
        Koniec ((L 'Tryb podglądu - nic nie zostało usunięte. Log: {0}' 'Preview mode - nothing was deleted. Log: {0}') -f $LogPlik) 'Yellow'
    }

    Naglowek (L '2/2  Czyszczenie' '2/2  Cleaning')
    $wynik = WykonajCzyszczenie
    Naglowek (L 'PODSUMOWANIE' 'SUMMARY')
    foreach ($x in TekstPoCzyszczeniu $wynik) { Write-Host "  $x" }
    Write-Host ""
    Write-Host "  Log: $LogPlik" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host (L '  Enter kończy' '  Press Enter to exit') | Out-Null
}
