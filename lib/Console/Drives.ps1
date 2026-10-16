<#
    LLMCleaner - drive selection
#>

function Select-DrivesConsole {
    $list = @(Get-FixedDrives)
    if ($Drives) { Set-SelectedDrives $Drives; return }
    $choice = @{}; foreach ($d in $list) { $choice[$d.DeviceID] = $true }
    while ($true) {
        Write-Header (L 'DYSKI DO SKANOWANIA' 'DRIVES TO SCAN')
        $i = 0
        foreach ($d in $list) {
            $i++
            $mark = if ($choice[$d.DeviceID]) { '[x]' } else { '[ ]' }
            $sys = if ($d.DeviceID -eq $Sys) { L '   (systemowy - zawsze)' '   (system - always)' } else { '' }
            Write-Host ("  {0} {1}. {2}{3}" -f $mark, $i, (Format-Drive $d), $sys) -ForegroundColor $(if ($choice[$d.DeviceID]) { 'Green' } else { 'DarkGray' })
        }
        Write-Host (L '   Wybrane dyski: Kosz, biblioteki Steam/Epic i analiza miejsca (a). Dyski USB i sieciowe są pomijane.' '   Ticked drives: Recycle Bin, Steam/Epic libraries and the space analysis (a). USB and network drives are skipped.') -ForegroundColor DarkGray
        Write-Host (L '   Enter = skanuj zaznaczone | numery (np. 2 3) = zaznacz/odznacz' '   Enter = scan ticked drives | numbers (e.g. 2 3) = tick/untick') -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($w -eq '') { break }
        foreach ($n in ($w -split '[\s,;]+')) {
            $idx = 0
            if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $list.Count) {
                $id = $list[$idx - 1].DeviceID
                if ($id -ne $Sys) { $choice[$id] = -not $choice[$id] }
            }
        }
    }
    Set-SelectedDrives @($list | Where-Object { $choice[$_.DeviceID] } | ForEach-Object { $_.DeviceID })
}
