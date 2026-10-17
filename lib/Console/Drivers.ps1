<#
    LLMCleaner - driver updates
#>

function Invoke-DriversConsole {
    Write-Header (L 'STEROWNIKI Z WINDOWS UPDATE' 'DRIVERS FROM WINDOWS UPDATE')
    Write-Host (L '   Szukam nowszych sterowników (zwykle 1-3 minuty)...' '   Looking for newer drivers (usually 1-3 minutes)...') -ForegroundColor DarkGray
    try { [void](Find-DriverUpdates) }
    catch { Write-Host ((L '   Nie udało się sprawdzić Windows Update: {0}' '   Could not check Windows Update: {0}') -f $_.Exception.Message) -ForegroundColor Yellow; return }
    while ($true) {
        Write-Header (L 'STEROWNIKI Z WINDOWS UPDATE' 'DRIVERS FROM WINDOWS UPDATE')
        $list = @($script:Drivers)
        if (-not $list.Count) { Write-Host (L '   Windows Update nie ma nowszych sterowników dla tego komputera.' '   Windows Update has no newer drivers for this PC.') -ForegroundColor Green }
        $i = 0
        foreach ($d in $list) {
            $i++
            $color = switch ($d.State) { 'new' { 'White' } 'ok' { 'Green' } 'restart' { 'Green' } default { 'Yellow' } }
            Write-Host ("  {0,2}. {1,-46} {2,10}  [{3}]" -f $i, $d.Name, (Format-Size $d.Bytes), (Get-DriverStateName $d.State)) -ForegroundColor $color
            $now = if ($d.CurrentVersion) { Format-DriverVersion $d.CurrentVersion $d.CurrentDate } elseif ($d.Problem) { $d.Problem } else { L 'nieznany' 'unknown' }
            Write-Host ("      {0}" -f ((@($d.Provider, $d.Class) | Where-Object { $_ }) -join ' · ')) -ForegroundColor DarkGray
            Write-Host ((L '      teraz: {0}  ->  nowy: {1}' '      now: {0}  ->  new: {1}') -f $now, (Format-DriverVersion $d.Version $d.NewDate)) -ForegroundColor Gray
            if ($d.Error) { Write-Host "      $($d.Error)" -ForegroundColor Yellow }
        }
        $problems = @($script:ProblemDevices | Where-Object { $_ })
        if ($problems.Count) {
            Write-Host ""
            Write-Host (L '   Urządzenia z problemem w Menedżerze urządzeń:' '   Devices with a problem in Device Manager:') -ForegroundColor White
            foreach ($p in $problems) { Write-Host ("      {0}: {1}" -f $p.Name, $p.Description) -ForegroundColor DarkYellow }
        }
        $selectable = @($list | Where-Object { $_.State -in 'new', 'fail' })
        if ($Preview -or -not $selectable.Count) {
            if ($Preview -and $selectable.Count) { Write-Host (L "`n   Tryb podglądu - instalacja wyłączona." "`n   Preview mode - installing is disabled.") -ForegroundColor Yellow }
            Write-Host ""
            Read-Host (L '   Enter = powrót do planu' '   Enter = back to the plan') | Out-Null
            return
        }
        Write-Host ""
        Write-Host (L '   numery (np. 1 3) = zainstaluj te | * = wszystkie | Enter = powrót do planu' '   numbers (e.g. 1 3) = install these | * = all | Enter = back to the plan') -ForegroundColor Yellow
        $answer = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($answer -eq '') { return }
        $chosen = if ($answer -eq '*') { $selectable } else {
            @(foreach ($n in ($answer -split '[\s,;]+')) {
                    $idx = 0
                    if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $list.Count -and $list[$idx - 1].State -in 'new', 'fail') { $list[$idx - 1] }
                })
        }
        if (-not @($chosen).Count) { continue }
        foreach ($d in $chosen) { Write-Host ("   {0}  {1}" -f $d.Name, $d.Version) -ForegroundColor White }
        Write-Host (L '   Najpierw powstanie punkt przywracania. Przy sterowniku karty graficznej ekran może na chwilę zgasnąć.' '   A restore point is created first. With a graphics driver the screen may go blank for a moment.') -ForegroundColor DarkGray
        $t = Read-Host (L '   Zainstalować? [t/N]' '   Install? [y/N]')
        if ($t -notmatch '^[TtYySs]') { continue }
        $restore = New-RestorePoint
        Write-Host ((L '   Punkt przywracania: {0}' '   Restore point: {0}') -f $restore.Description) -ForegroundColor $(if ($restore.Ok) { 'Green' } else { 'Yellow' })
        Write-Host (L '   Instaluję - nie wyłączaj komputera...' '   Installing - do not turn off the computer...') -ForegroundColor DarkGray
        [void](Install-Drivers $chosen ([hashtable]::Synchronized(@{})))
        if (@($chosen | Where-Object { $_.State -eq 'restart' }).Count) {
            Write-Host (L '   Uruchom ponownie komputer, żeby dokończyć instalację.' '   Restart the computer to finish installing.') -ForegroundColor Yellow
        }
    }
}
