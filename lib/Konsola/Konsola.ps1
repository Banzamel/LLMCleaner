<#
    LLMCleaner - glowna petla trybu tekstowego
#>

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
        $pomoc += L ' | a = co zajmuje miejsce na dysku | s = autostart | d = sterowniki' ' | a = what takes up space | s = startup apps | d = drivers'
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
        if ($w -match '^[sS]$') { AutostartKonsola; continue }
        if ($w -match '^[dD]$') { SterownikiKonsola; continue }
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
