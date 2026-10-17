<#
    LLMCleaner - startup manager
#>

function Invoke-StartupConsole {
    [void](Get-StartupEntries)
    while ($true) {
        Write-Header (L 'AUTOSTART - PROGRAMY URUCHAMIANE PRZY LOGOWANIU' 'STARTUP APPS - PROGRAMS THAT START AT SIGN-IN')
        Write-Host (L '   Wyłączenie działa jak w Menedżerze zadań: nic nie jest usuwane, ponowne przełączenie przywraca wpis.' '   Turning off works like in Task Manager: nothing is removed, toggling again restores the entry.') -ForegroundColor DarkGray
        $i = 0
        foreach ($w in $script:Startup) {
            $i++
            $mark = if ($w.IsEnabled) { L '[wł. ]' '[on ]' } else { L '[wył.]' '[off]' }
            $color = if ($w.Protected) { 'Gray' } elseif ($w.IsEnabled) { 'Green' } else { 'DarkGray' }
            Write-Host ("  {0} {1,2}. {2,-40} {3}" -f $mark, $i, $w.Name, $w.Source) -ForegroundColor $color
            Write-Host ("           {0}{1}" -f $(if ($w.Publisher) { "$($w.Publisher): " }), $w.Command) -ForegroundColor DarkGray
            if ($w.Dead) { Write-Host (L '           plik programu nie istnieje - martwy wpis trafia do planu czyszczenia' '           the program file does not exist - a dead entry is listed in the cleanup plan') -ForegroundColor DarkYellow }
            if ($w.Protected) { Write-Host ("           {0}: {1}" -f (L 'chronione' 'protected'), $w.Protected) -ForegroundColor DarkYellow }
            if ($w.Ai) { Write-Host "           $AiLabel`: $($w.Ai)" -ForegroundColor DarkCyan }
        }
        Write-Host ""
        $help = if ($Preview) { L 'tryb podglądu - zmiany wyłączone' 'preview mode - changes disabled' } else { L 'numery (np. 2 5) = włącz/wyłącz' 'numbers (e.g. 2 5) = turn on/off' }
        if (-not $NoAI) { $help += L ' | w = AI opisze programy' ' | w = AI describes the programs' }
        $help += L ' | Enter = powrót do planu' ' | Enter = back to the plan'
        Write-Host "   $help" -ForegroundColor Yellow
        $answer = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($answer -eq '') { return }
        if ($answer -match '^[wW]$' -and -not $NoAI) { [void](Invoke-StartupAi $script:Startup); continue }
        if ($Preview) { continue }
        $selected = @()
        foreach ($n in ($answer -split '[\s,;]+')) {
            $idx = 0
            if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:Startup.Count) { $selected += $script:Startup[$idx - 1] }
        }
        foreach ($w in @($selected | Where-Object { $_.Protected })) { Write-Host ("   {0}: {1}" -f $w.Name, $w.Protected) -ForegroundColor Yellow }
        $selected = @($selected | Where-Object { -not $_.Protected })
        if (-not $selected.Count) { continue }
        foreach ($w in $selected) { Write-Host ("   {0} -> {1}" -f $w.Name, $(if ($w.IsEnabled) { L 'wyłącz' 'turn off' } else { L 'włącz' 'turn on' })) -ForegroundColor White }
        $t = Read-Host (L '   Zmienić? [t/N]' '   Change? [y/N]')
        if ($t -notmatch '^[TtYySs]') { continue }
        foreach ($w in $selected) {
            try { Set-StartupEnabled $w (-not $w.IsEnabled) }
            catch { Write-Host ("   {0}: {1}" -f $w.Name, $_.Exception.Message) -ForegroundColor Yellow }
        }
        Write-Host (L '   Zmiana działa od następnego logowania.' '   The change takes effect at the next sign-in.') -ForegroundColor Green
    }
}
