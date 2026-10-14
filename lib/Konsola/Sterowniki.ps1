<#
    LLMCleaner - aktualizacje sterownikow
#>

function SterownikiKonsola {
    Naglowek (L 'STEROWNIKI Z WINDOWS UPDATE' 'DRIVERS FROM WINDOWS UPDATE')
    Write-Host (L '   Szukam nowszych sterowników (zwykle 1-3 minuty)...' '   Looking for newer drivers (usually 1-3 minutes)...') -ForegroundColor DarkGray
    try { [void](SzukajSterownikow) }
    catch { Write-Host ((L '   Nie udało się sprawdzić Windows Update: {0}' '   Could not check Windows Update: {0}') -f $_.Exception.Message) -ForegroundColor Yellow; return }
    while ($true) {
        Naglowek (L 'STEROWNIKI Z WINDOWS UPDATE' 'DRIVERS FROM WINDOWS UPDATE')
        $lista = @($script:Sterowniki)
        if (-not $lista.Count) { Write-Host (L '   Windows Update nie ma nowszych sterowników dla tego komputera.' '   Windows Update has no newer drivers for this PC.') -ForegroundColor Green }
        $i = 0
        foreach ($d in $lista) {
            $i++
            $kolor = switch ($d.Stan) { 'nowy' { 'White' } 'ok' { 'Green' } 'restart' { 'Green' } default { 'Yellow' } }
            Write-Host ("  {0,2}. {1,-46} {2,10}  [{3}]" -f $i, $d.Nazwa, (Rozmiar $d.Bajty), (NazwaStanuSterownika $d.Stan)) -ForegroundColor $kolor
            $teraz = if ($d.ObecnaWersja) { OpisWersji $d.ObecnaWersja $d.ObecnaData } elseif ($d.Problem) { $d.Problem } else { L 'nieznany' 'unknown' }
            Write-Host ("      {0}" -f ((@($d.Dostawca, $d.Klasa) | Where-Object { $_ }) -join ' · ')) -ForegroundColor DarkGray
            Write-Host ((L '      teraz: {0}  ->  nowy: {1}' '      now: {0}  ->  new: {1}') -f $teraz, (OpisWersji $d.Wersja $d.Data)) -ForegroundColor Gray
            if ($d.Blad) { Write-Host "      $($d.Blad)" -ForegroundColor Yellow }
        }
        $pr = @($script:UrzadzeniaZProblemem | Where-Object { $_ })
        if ($pr.Count) {
            Write-Host ""
            Write-Host (L '   Urządzenia z problemem w Menedżerze urządzeń:' '   Devices with a problem in Device Manager:') -ForegroundColor White
            foreach ($p in $pr) { Write-Host ("      {0}: {1}" -f $p.Nazwa, $p.Opis) -ForegroundColor DarkYellow }
        }
        $doWyboru = @($lista | Where-Object { $_.Stan -in 'nowy', 'blad' })
        if ($Podglad -or -not $doWyboru.Count) {
            if ($Podglad -and $doWyboru.Count) { Write-Host (L "`n   Tryb podglądu - instalacja wyłączona." "`n   Preview mode - installing is disabled.") -ForegroundColor Yellow }
            Write-Host ""
            Read-Host (L '   Enter = powrót do planu' '   Enter = back to the plan') | Out-Null
            return
        }
        Write-Host ""
        Write-Host (L '   numery (np. 1 3) = zainstaluj te | * = wszystkie | Enter = powrót do planu' '   numbers (e.g. 1 3) = install these | * = all | Enter = back to the plan') -ForegroundColor Yellow
        $odp = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($odp -eq '') { return }
        $wyb = if ($odp -eq '*') { $doWyboru } else {
            @(foreach ($n in ($odp -split '[\s,;]+')) {
                    $idx = 0
                    if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $lista.Count -and $lista[$idx - 1].Stan -in 'nowy', 'blad') { $lista[$idx - 1] }
                })
        }
        if (-not @($wyb).Count) { continue }
        foreach ($d in $wyb) { Write-Host ("   {0}  {1}" -f $d.Nazwa, $d.Wersja) -ForegroundColor White }
        Write-Host (L '   Najpierw powstanie punkt przywracania. Przy sterowniku karty graficznej ekran może na chwilę zgasnąć.' '   A restore point is created first. With a graphics driver the screen may go blank for a moment.') -ForegroundColor DarkGray
        $t = Read-Host (L '   Zainstalować? [t/N]' '   Install? [y/N]')
        if ($t -notmatch '^[TtYy]') { continue }
        $pp = PunktPrzywracania
        Write-Host ((L '   Punkt przywracania: {0}' '   Restore point: {0}') -f $pp.Opis) -ForegroundColor $(if ($pp.Ok) { 'Green' } else { 'Yellow' })
        Write-Host (L '   Instaluję - nie wyłączaj komputera...' '   Installing - do not turn off the computer...') -ForegroundColor DarkGray
        [void](ZainstalujSterowniki $wyb ([hashtable]::Synchronized(@{})))
        if (@($wyb | Where-Object { $_.Stan -eq 'restart' }).Count) {
            Write-Host (L '   Uruchom ponownie komputer, żeby dokończyć instalację.' '   Restart the computer to finish installing.') -ForegroundColor Yellow
        }
    }
}
