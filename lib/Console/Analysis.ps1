<#
    LLMCleaner - analiza dysku
#>

function Show-Analysis($a) {
    Write-Header ((L 'CO ZAJMUJE MIEJSCE NA {0}:   zajęte {1} z {2}, wolne {3}' 'WHAT TAKES UP SPACE ON {0}:   {1} used of {2}, {3} free') -f $a.Letter, (Format-Size ($a.Size - $a.Free)), (Format-Size $a.Size), (Format-Size $a.Free))
    Write-Host ((L '   Tylko do wglądu - nic stąd nie jest usuwane. Pokazane są najbardziej konkretne foldery od {0}.' '   Read-only - nothing here is deleted. The most specific folders from {0} up are shown.') -f (Format-Size $a.Threshold)) -ForegroundColor DarkGray
    $sections = @(@{ T = (L 'NAJWIĘKSZE FOLDERY' 'LARGEST FOLDERS'); L = $a.Folders }, @{ T = (L 'NAJWIĘKSZE PLIKI' 'LARGEST FILES'); L = $a.Files })
    foreach ($s in $sections) {
        if (-not $s.L.Count) { continue }
        Write-Host ""
        Write-Host "   $($s.T)" -ForegroundColor Cyan
        foreach ($p in $s.L) {
            $suffix = if ($p.Remainder) { L '  (pliki poza wymienionymi podfolderami)' '  (files outside the listed subfolders)' } else { '' }
            $dateText = if ($p.LastWrite -gt [datetime]'1980-01-01') { $p.LastWrite.ToString('yyyy-MM-dd') } else { '          ' }
            Write-Host ("  {0,4}. {1,10}  {2}  {3}{4}" -f $p.Id, (Format-Size $p.Bytes), $dateText, $p.Path, $suffix) -ForegroundColor Gray
            if ($p.Hint) { Write-Host "                            $($p.Hint)" -ForegroundColor DarkGray }
            if ($p.Ai) { Write-Host "                            $AiLabel`: $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    if ($a.ShadowCopies -gt 0) {
        Write-Host ""
        Write-Host ((L '   Punkty przywracania systemu: {0} (Ochrona systemu w Ustawieniach)' '   System Restore points: {0} (System Protection in Settings)') -f (Format-Size $a.ShadowCopies)) -ForegroundColor Gray
    }
    $unreadable = ($a.Size - $a.Free) - $a.ScannedBytes - $a.ShadowCopies
    if ($unreadable -gt 2GB) {
        Write-Host ((L '   Niedostępne dla skanera (pliki systemowe, chronione foldery): ok. {0}' '   Not readable by the scanner (system files, protected folders): about {0}') -f (Format-Size $unreadable)) -ForegroundColor DarkGray
    }
}

function Invoke-AnalysisConsole {
    $list = @(Get-SelectedDrives)
    Write-Host ""
    Write-Host ("   " + (($list | ForEach-Object { Format-Drive $_ }) -join ' | ')) -ForegroundColor Gray
    $defaultDrive = $Sys.TrimEnd(':')
    $l = (Read-Host ((L '   Który dysk przeanalizować? [{0}]' '   Which drive to analyse? [{0}]') -f $defaultDrive)).Trim().TrimEnd(':', '\').ToUpper()
    if (-not $l) { $l = $defaultDrive }
    if (-not ($list | Where-Object { $_.DeviceID -eq "$l`:" })) { Write-Host ((L '   Dysk {0}: nie jest wybrany do skanowania.' '   Drive {0}: is not selected for scanning.') -f $l) -ForegroundColor Yellow; return }
    $a = Get-DriveAnalysis $l
    while ($true) {
        Show-Analysis $a
        Write-Host ""
        $help = if ($NoAI) { L 'Enter = powrót do planu' 'Enter = back to the plan' } else { L 'w = AI opisze te pozycje i doradzi | Enter = powrót do planu' 'w = AI describes these items and advises | Enter = back to the plan' }
        Write-Host "   $help" -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($w -match '^[wW]$' -and -not $NoAI) { [void](Invoke-AnalysisAi $a); continue }
        return
    }
}
