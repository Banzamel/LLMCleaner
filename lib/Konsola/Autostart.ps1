<#
    LLMCleaner - menedzer autostartu
#>

function AutostartKonsola {
    [void](WpisyAutostartu)
    while ($true) {
        Naglowek (L 'AUTOSTART - PROGRAMY URUCHAMIANE PRZY LOGOWANIU' 'STARTUP APPS - PROGRAMS THAT START AT SIGN-IN')
        Write-Host (L '   Wyłączenie działa jak w Menedżerze zadań: nic nie jest usuwane, ponowne przełączenie przywraca wpis.' '   Turning off works like in Task Manager: nothing is removed, toggling again restores the entry.') -ForegroundColor DarkGray
        $i = 0
        foreach ($w in $script:Autostart) {
            $i++
            $znak = if ($w.Wlaczony) { L '[wł. ]' '[on ]' } else { L '[wył.]' '[off]' }
            $kolor = if ($w.Chroniony) { 'Gray' } elseif ($w.Wlaczony) { 'Green' } else { 'DarkGray' }
            Write-Host ("  {0} {1,2}. {2,-40} {3}" -f $znak, $i, $w.Nazwa, $w.Zrodlo) -ForegroundColor $kolor
            Write-Host ("           {0}{1}" -f $(if ($w.Wydawca) { "$($w.Wydawca): " }), $w.Polecenie) -ForegroundColor DarkGray
            if ($w.Martwy) { Write-Host (L '           plik programu nie istnieje - martwy wpis trafia do planu czyszczenia' '           the program file does not exist - a dead entry is listed in the cleanup plan') -ForegroundColor DarkYellow }
            if ($w.Chroniony) { Write-Host ("           {0}: {1}" -f (L 'chronione' 'protected'), $w.Chroniony) -ForegroundColor DarkYellow }
            if ($w.Ai) { Write-Host "           $EtykietaAi`: $($w.Ai)" -ForegroundColor DarkCyan }
        }
        Write-Host ""
        $pomoc = if ($Podglad) { L 'tryb podglądu - zmiany wyłączone' 'preview mode - changes disabled' } else { L 'numery (np. 2 5) = włącz/wyłącz' 'numbers (e.g. 2 5) = turn on/off' }
        if (-not $BezLLM) { $pomoc += L ' | w = AI opisze programy' ' | w = AI describes the programs' }
        $pomoc += L ' | Enter = powrót do planu' ' | Enter = back to the plan'
        Write-Host "   $pomoc" -ForegroundColor Yellow
        $odp = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($odp -eq '') { return }
        if ($odp -match '^[wW]$' -and -not $BezLLM) { [void](AutostartAi $script:Autostart); continue }
        if ($Podglad) { continue }
        $wybrane = @()
        foreach ($n in ($odp -split '[\s,;]+')) {
            $idx = 0
            if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:Autostart.Count) { $wybrane += $script:Autostart[$idx - 1] }
        }
        foreach ($w in @($wybrane | Where-Object { $_.Chroniony })) { Write-Host ("   {0}: {1}" -f $w.Nazwa, $w.Chroniony) -ForegroundColor Yellow }
        $wybrane = @($wybrane | Where-Object { -not $_.Chroniony })
        if (-not $wybrane.Count) { continue }
        foreach ($w in $wybrane) { Write-Host ("   {0} -> {1}" -f $w.Nazwa, $(if ($w.Wlaczony) { L 'wyłącz' 'turn off' } else { L 'włącz' 'turn on' })) -ForegroundColor White }
        $t = Read-Host (L '   Zmienić? [t/N]' '   Change? [y/N]')
        if ($t -notmatch '^[TtYy]') { continue }
        foreach ($w in $wybrane) {
            try { PrzelaczAutostart $w (-not $w.Wlaczony) }
            catch { Write-Host ("   {0}: {1}" -f $w.Nazwa, $_.Exception.Message) -ForegroundColor Yellow }
        }
        Write-Host (L '   Zmiana działa od następnego logowania.' '   The change takes effect at the next sign-in.') -ForegroundColor Green
    }
}
