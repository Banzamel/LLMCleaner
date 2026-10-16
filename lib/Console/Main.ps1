<#
    LLMCleaner - main loop of the text mode
#>

function Start-Console {
    Clear-Host
    Write-Host ""
    Write-Host ((L '   LLMCleaner {0} - inteligentne czyszczenie komputera' '   LLMCleaner {0} - smart PC cleanup') -f $Version) -ForegroundColor White
    $assistant = if ($NoAI) { L 'wyłączony' 'off' } else { (L '{0} (na żądanie)' '{0} (on demand)') -f $Model }
    Write-Host ((L '   {0}   asystent: {1}' '   {0}   assistant: {1}') -f (Get-Date -Format 'dd.MM.yyyy HH:mm'), $assistant) -ForegroundColor DarkGray
    if ($Preview) { Write-Host (L '   TRYB PODGLĄDU - nic nie zostanie usunięte' '   PREVIEW MODE - nothing will be deleted') -ForegroundColor Yellow }
    Write-Host ""
    Write-Log "Start (console). Model: $Model, Preview: $Preview, NoAI: $NoAI, Language: $Language"
    if (-not $NoUpdateCheck) {
        Find-AppUpdate
        if ($script:AppUpdate) {
            Write-Host ((L '   Dostępna nowa wersja {0} - klawisz u na ekranie planu ją zainstaluje.' '   New version {0} is available - press u on the plan screen to install it.') -f $script:AppUpdate.Version) -ForegroundColor Yellow
            Write-Host ""
        }
    }

    Select-DrivesConsole
    Write-Header (L '1/2  Skanowanie' '1/2  Scanning')
    Invoke-FullScan

    while ($true) {
        Show-Plan
        Write-Host ""
        $help = if ($Preview) { L 'Enter = zakończ' 'Enter = finish' } else { L 'Enter = dalej (podsumowanie i pytanie o czyszczenie)' 'Enter = next (summary and the cleaning question)' }
        $help += L ' | numery (np. 3 7) = zaznacz/odznacz' ' | numbers (e.g. 3 7) = tick/untick'
        if (-not $NoAI) { $help += L ' | w = AI wyjaśni pozostałości | p = zapytaj asystenta' ' | w = AI explains leftovers | p = ask the assistant' }
        $help += L ' | a = co zajmuje miejsce na dysku | s = autostart | d = sterowniki' ' | a = what takes up space | s = startup apps | d = drivers'
        if ($script:AppUpdate) { $help += (L ' | u = zainstaluj wersję {0}' ' | u = install version {0}') -f $script:AppUpdate.Version }
        $help += L ' | q = wyjdź' ' | q = quit'
        Write-Host "   $help" -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()

        if ($w -eq '') {
            if ($Preview -or (Confirm-Cleanup)) { break }
            continue
        }
        if ($w -match '^[qQ]') { Write-Log 'Cancelled by user.'; Exit-Console (L 'Przerwano - nic nie zostało usunięte.' 'Cancelled - nothing was deleted.') }
        if ($w -match '^[pP]$') { Invoke-ChatConsole; continue }
        if ($w -match '^[wW]$') { [void](Invoke-LeftoverAi); continue }
        if ($w -match '^[aA]$') { Invoke-AnalysisConsole; continue }
        if ($w -match '^[sS]$') { Invoke-StartupConsole; continue }
        if ($w -match '^[dD]$') { Invoke-DriversConsole; continue }
        if ($w -match '^[uU]$' -and $script:AppUpdate) {
            if (Install-AppUpdate) {
                Stop-Ollama
                Write-Host (L "`n   Instalator aktualizacji uruchomiony - LLMCleaner kończy pracę, nic nie zostało usunięte.`n" "`n   The update installer is running - LLMCleaner exits, nothing was deleted.`n") -ForegroundColor Green
                Start-Sleep -Seconds 3; exit
            }
            continue
        }
        foreach ($n in ($w -split '[\s,;]+')) {
            $idx = 0
            if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $script:Categories.Count) {
                $k = $script:Categories[$idx - 1]
                if ($k.Blocker) { Write-Host "   $($k.Name): $($k.Blocker)" -ForegroundColor Yellow; continue }
                $k.Selected = -not $k.Selected
            }
            elseif ($idx -gt $script:Categories.Count -and $idx -le $script:Categories.Count + $script:Leftovers.Count) {
                $p = $script:Leftovers[$idx - $script:Categories.Count - 1]
                $p.Selected = -not $p.Selected
            }
        }
    }

    if ($Preview) {
        Write-Log 'Preview mode - finished without deleting.'
        Exit-Console ((L 'Tryb podglądu - nic nie zostało usunięte. Log: {0}' 'Preview mode - nothing was deleted. Log: {0}') -f $LogFile) 'Yellow'
    }

    Write-Header (L '2/2  Czyszczenie' '2/2  Cleaning')
    $result = Invoke-Cleanup
    Write-Header (L 'PODSUMOWANIE' 'SUMMARY')
    foreach ($x in Get-CleanupSummary $result) { Write-Host "  $x" }
    Write-Host ""
    Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host (L '  Enter kończy' '  Press Enter to exit') | Out-Null
}
