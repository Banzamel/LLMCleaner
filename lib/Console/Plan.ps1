<#
    LLMCleaner - plan czyszczenia
#>

function Show-Plan {
    Write-Header (L 'PLAN CZYSZCZENIA' 'CLEANUP PLAN')
    $i = 0
    foreach ($k in $script:Categories) {
        $i++
        $mark = if ($k.Selected) { '[x]' } else { '[ ]' }
        $color = if ($k.Selected) { 'Green' } elseif ($k.OptIn) { 'Gray' } else { 'DarkGray' }
        Write-Host ("  {0} {1,2}. {2,-52} {3,10}" -f $mark, $i, $k.Name, (Format-CategorySize $k)) -ForegroundColor $color
        if ($k.Blocker) { Write-Host "           ! $($k.Blocker)" -ForegroundColor Yellow }
        else { Write-Host "           $(if ($k.OptIn) { L '(tylko na Twoje życzenie) ' '(only if you choose it) ' })$($k.Description)" -ForegroundColor DarkGray }
        if ($k.Note -and -not $k.Blocker) { Write-Host "           ! $($k.Note)" -ForegroundColor Yellow }
    }
    if ($script:Leftovers.Count) {
        Write-Host ""
        Write-Host (L '   POZOSTAŁOŚCI PO ODINSTALOWANYCH PROGRAMACH I GRACH' '   LEFTOVERS OF UNINSTALLED PROGRAMS AND GAMES') -ForegroundColor Cyan
        Write-Host (L '   (foldery i pliki idą do Kosza, wpisy rejestru i zadania są wcześniej zapisywane do pliku .reg / .xml)' '   (folders and files go to the Recycle Bin, registry entries and tasks are first saved to a .reg / .xml file)') -ForegroundColor DarkGray
        foreach ($p in $script:Leftovers) {
            $i++
            $mark = if ($p.Selected) { '[x]' } else { '[ ]' }
            $color = if ($p.Selected) { 'Green' } elseif ($p.Confidence -eq 'low') { 'DarkYellow' } else { 'DarkGray' }
            $sizeText = Format-LeftoverSize $p
            $display = Format-Leftover $p
            Write-Host ("  {0} {1,2}. {2,-52} {3,10}  {4}: {5}" -f $mark, $i, $display, $sizeText, (L 'pewność' 'confidence'), (Get-ConfidenceName $p.Confidence)) -ForegroundColor $color
            Write-Host "           $($p.Reason)" -ForegroundColor DarkGray
            if ($p.Ai) { Write-Host "           $AiLabel`: $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    Write-Host ""
    Write-Host ((L '   Zaznaczone razem: ok. {0}' '   Selected in total: about {0}') -f (Format-Size (Get-SelectedTotal))) -ForegroundColor White
}
