<#
    LLMCleaner - overview page
#>

function Update-Overview {
    $u = $script:UI; $s = $script:Style
    if (-not $script:Scanned) { return }
    $total = Get-SelectedTotal
    if ($script:Cleaned) {
        $u.ResultSmall.Text = L 'Czyszczenie zakończone' 'Cleaning finished'
        $u.Result.Text = (L 'Zwolniono {0}' '{0} freed') -f (Format-Size ([double]$script:CleanupResult.Total))
        $u.Result.ForeColor = $s.Green
        $u.Stage.Text = L 'Kliknij „Skanuj ponownie”, żeby zobaczyć aktualny stan dysków.' 'Click "Scan again" to see the current state of your drives.'
    }
    elseif ($total -gt 0) {
        $u.ResultSmall.Text = L 'Można bezpiecznie zwolnić' 'Can be freed safely'
        $u.Result.Text = Format-Size $total
        $u.Result.ForeColor = $s.Accent
        $u.Stage.Text = L 'Zaznaczone są tylko rzeczy, które odtwarzają się same albo idą do Kosza. Nic nie jest usuwane bez potwierdzenia.' 'Only things that rebuild themselves or go to the Recycle Bin are selected. Nothing is deleted without your confirmation.'
    }
    else {
        $u.ResultSmall.Text = L 'Wynik skanu' 'Scan result'
        $u.Result.Text = L 'Komputer jest czysty' 'Your PC is clean'
        $u.Result.ForeColor = $s.Green
        $u.Stage.Text = L 'Nic nie jest zaznaczone. Plan czyszczenia pokazuje też pozycje na życzenie.' 'Nothing is selected. The cleanup plan also lists opt-in items.'
    }
    $u.StatsData = Get-OverviewTiles
    $u.Stats.Visible = $true
    $u.Stats.Invalidate()

    # Bars: largest categories, leftovers combined, the rest combined
    $el = @($script:Categories | Where-Object { $_.Bytes -gt 0 } | ForEach-Object { @{ Name = $_.Name; Bytes = [double]$_.Bytes; Selected = [bool]$_.Selected } })
    $leftoverList = @($script:Leftovers | Where-Object { Test-GoesToRecycleBin $_ })
    if ($leftoverList.Count) {
        $el += @{ Name = (L 'Pozostałości po programach' 'Program leftovers'); Bytes = [double]($leftoverList | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum
            Selected = [bool]@($leftoverList | Where-Object { $_.Selected }).Count
        }
    }
    $el = @($el | Sort-Object { $_.Bytes } -Descending)
    if ($el.Count -gt 7) {
        $rest = $el[6..($el.Count - 1)]
        $el = @($el[0..5]) + @(@{ Name = (L 'Pozostałe pozycje' 'Other items'); Bytes = [double]($rest | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum
                Selected = [bool]@($rest | Where-Object { $_.Selected }).Count
            })
    }
    $u.BarsData = $el
    $u.Bars.Invalidate()
    Update-StartupCard
}

function Update-StartupCard {
    $u = $script:UI
    if ($null -eq $script:Startup) {
        $u.StartupText.Text = L 'Sprawdź, które programy uruchamiają się przy logowaniu i spowalniają start Windows.' 'See which programs start when you sign in and slow down Windows startup.'
        return
    }
    $enabled = @($script:Startup | Where-Object { $_.IsEnabled })
    $t = (L 'Przy logowaniu uruchamia się programów: {0}.' 'Programs starting at sign-in: {0}.') -f $enabled.Count
    $optional = @($enabled | Where-Object { $_.Ai -and $_.Ai -like "*$($StartupAdvice[1])*" }).Count
    if ($optional) { $t += ' ' + ((L 'Według AI {0} z nich można wyłączyć.' 'According to AI, {0} of them can be turned off.') -f $optional) }
    elseif ($enabled.Count) { $t += ' ' + (L 'Wyłączenie niepotrzebnych przyspieszy start Windows.' 'Turning off the ones you do not need speeds up Windows startup.') }
    $u.StartupText.Text = $t
    $u.Stats.Invalidate()
}

# Three tiles next to the result: safe to delete, to review, large files. Each opens the plan where it belongs.
function Get-OverviewTiles {
    $all = @(@($script:Categories) + @($script:Leftovers) | Where-Object { $_ })
    $large = @(Get-LargeItems)
    $review = @(@($script:Categories) + @($script:Leftovers | Where-Object { $_ -and -not (Test-LargeItem $_) }) |
            Where-Object { $_ -and -not $_.Selected -and [double]$_.Bytes -gt 0 })
    $selected = @($all | Where-Object { $_.Selected })
    $sum = { param($l) [double](@($l) | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum }
    @(
        @{ T = (L 'Bezpieczne do usunięcia' 'Safe to delete'); W = (Format-Size (Get-SelectedTotal)); N = $selected.Count; K = $script:Style.Green; Tab = 'plan'; Filter = 'selected' }
        @{ T = (L 'Do przejrzenia' 'To review'); W = (Format-Size (& $sum $review)); N = $review.Count; K = $script:Style.Warning; Tab = 'plan'; Filter = 'all' }
        @{ T = (L 'Duże pliki i foldery' 'Large files and folders'); W = (Format-Size (& $sum $large)); N = $large.Count; K = $script:Style.AccentText; Tab = 'large'; Filter = 'all' }
    )
}

function Get-TileRect($p, [int]$i) {
    $gap = Px 8
    $h = [int](($p.Height - 2 * $gap) / 3)
    New-Object Drawing.Rectangle(0, ($i * ($h + $gap)), $p.Width, $h)
}

function Draw-Stats($g, $p) {
    $s = $script:Style
    $data = @($script:UI.StatsData)
    $go = L 'Pokaż ›' 'Show ›'
    $goW = (Measure-TextWidth $go $s.SmallBold) + (Px 8)
    for ($i = 0; $i -lt [Math]::Min(3, $data.Count); $i++) {
        $d = $data[$i]; $r = Get-TileRect $p $i
        Draw-Rect $g $r.X $r.Y $r.Width $r.Height $s.Tile (Px 10)
        Draw-Rect $g ($r.X + (Px 10)) ($r.Y + (Px 12)) (Px 4) ($r.Height - (Px 24)) $d.K (Px 2)
        $textW = $r.Width - (Px 30) - $goW - (Px 12)
        Draw-Text $g ('{0} · {1}' -f $d.T, ((L 'pozycji: {0}' 'items: {0}') -f $d.N)) $s.Small $s.TextDim ($r.X + (Px 26)) ($r.Y + (Px 6)) $textW (Px 20)
        Draw-Text $g $d.W $s.Medium $s.Text ($r.X + (Px 26)) ($r.Y + (Px 24)) $textW ($r.Height - (Px 26))
        Draw-Text $g $go $s.SmallBold $s.AccentText ($r.Right - $goW - (Px 12)) $r.Y $goW $r.Height 'Right'
    }
}

# Click on a tile: the plan page with the right tab and filter
function Open-OverviewTile($p, [int]$y) {
    if (-not $script:Scanned) { return }
    $data = @($script:UI.StatsData)
    for ($i = 0; $i -lt [Math]::Min(3, $data.Count); $i++) {
        $r = Get-TileRect $p $i
        if ($y -lt $r.Y -or $y -ge $r.Bottom) { continue }
        $script:PlanTab = $data[$i].Tab; $script:PlanFilter = $data[$i].Filter
        foreach ($key in 'categories', 'leftovers', 'registry', 'largefolders', 'largefiles') { $script:PlanExpanded[$key] = $true }
        Update-PlanPage
        $script:UI.PlanFilter.Invalidate()
        Show-Page 'plan'
        return
    }
}

function Draw-Bars($g, $p) {
    $s = $script:Style
    $w = $p.Width
    Draw-Text $g (L 'Co zajmuje miejsce do zwolnienia' 'What takes up space you can free') $s.CardTitle $s.Text 0 0 ($w - (Px 230)) (Px 28)
    $data = @($script:UI.BarsData)
    if (-not $script:Scanned -or -not $data.Count) {
        $t = if ($script:Scanned) { L 'Skan nie znalazł nic do zwolnienia.' 'The scan found nothing to free.' }
        else { L 'Po skanie zobaczysz tu największe pozycje planu czyszczenia, od największej.' 'After the scan you will see the largest cleanup plan items here, largest first.' }
        Draw-WrappedText $g $t $s.Body $s.TextDim 0 (Px 44) $w (Px 60)
        return
    }
    Draw-Text $g (L 'szary pasek = niezaznaczone w planie' 'grey bar = not selected in the plan') $s.Small $s.TextDim ($w - (Px 230)) 0 (Px 230) (Px 28) 'Right'
    $max = [Math]::Max(1.0, ($data | ForEach-Object { $_.Bytes } | Measure-Object -Maximum).Maximum)
    $nameW = [Math]::Min((Px 210), [int]($w * 0.38))
    $xTrack = $nameW + (Px 14); $sizeW = Px 76
    $trackW = $w - $xTrack - $sizeW - (Px 14)
    $y = Px 44
    foreach ($d in $data) {
        if ($y + (Px 26) -gt $p.Height) { break }
        Draw-Text $g $d.Name $s.Body $s.Text 0 $y $nameW (Px 26)
        Draw-Rect $g $xTrack ($y + (Px 7)) $trackW (Px 12) $s.Track (Px 6)
        $len = [int][Math]::Max((Px 6), $trackW * $d.Bytes / $max)
        Draw-Rect $g $xTrack ($y + (Px 7)) $len (Px 12) $(if ($d.Selected) { $s.Accent } else { $s.GreyBar }) (Px 6)
        Draw-Text $g (Format-Size $d.Bytes) $s.Bold $s.Text ($w - $sizeW) $y $sizeW (Px 26) 'Right'
        $y += Px 34
    }
}

function Draw-DriveRow($g, $w, $r, [bool]$hover) {
    $s = $script:Style; $d = $w.Obj
    $disabled = $d.Sys -or $script:Working
    $y = $r.Y + (Px 8)
    Draw-CheckBox $g (Px 2) ($y + (Px 2)) ([bool]$d.Ticked) $disabled
    $name = "$($d.D.DeviceID)  $(if ($d.D.VolumeName) { $d.D.VolumeName } else { L 'bez nazwy' 'no label' })"
    if ($d.Sys) { $name += L '  (systemowy)' '  (system)' }
    $free = (L 'wolne {0} z {1}' '{0} free of {1}') -f (Format-Size $d.D.FreeSpace), (Format-Size $d.D.Size)
    # Name on the first line, free space on the second, so the name gets the full width
    Draw-Text $g $name $s.Bold $s.Text (Px 30) $y ($r.Width - (Px 34)) (Px 22)
    Draw-Text $g $free $s.Small $s.TextDim (Px 30) ($y + (Px 21)) ($r.Width - (Px 34)) (Px 20)
    $usedBytes = if ($d.D.Size -gt 0) { 1 - [double]$d.D.FreeSpace / [double]$d.D.Size } else { 0 }
    $trackW = $r.Width - (Px 32)
    Draw-Rect $g (Px 30) ($y + (Px 46)) $trackW (Px 8) $s.Track (Px 4)
    $k = if ($usedBytes -gt 0.9) { $s.Red } elseif ($usedBytes -gt 0.75) { $s.Warning } else { $s.Accent }
    Draw-Rect $g (Px 30) ($y + (Px 46)) ([int][Math]::Max((Px 8), $trackW * $usedBytes)) (Px 8) $k (Px 4)
}

function New-OverviewPage {
    $s = $script:Style
    $page = New-Page
    $btnScan = New-Button (L 'Skanuj' 'Scan') 'outline' @{ Width = (Px 170) }
    $n = New-PageHeader (L 'Przegląd' 'Overview') (L 'Wybierz dyski i kliknij „Skanuj”. LLMCleaner sprawdzi śmieci systemowe, cache programów i pozostałości po odinstalowanych programach i grach.' 'Pick the drives and click "Scan". LLMCleaner checks system junk, app caches and leftovers of uninstalled programs and games.') @($btnScan)
    $script:UI.OverviewDesc = $n.Description

    # Result card: small caption, big number, description, buttons and stat tiles on the right
    $k = New-Card @{ Dock = 'Top'; Height = (Px 230); Padding = (New-Padding 28 22 28 22) }
    $stats = New-Canvas @{ Dock = 'Right'; Width = (Px 420); BackColor = $s.Card; Visible = $false } { param($g, $p) Draw-Stats $g $p }
    $stats.Cursor = [Windows.Forms.Cursors]::Hand
    $stats.Add_MouseClick({ Open-OverviewTile $this $_.Y })
    $left = New-Control Panel @{ Dock = 'Fill'; BackColor = $s.Card }
    $small = New-Label (L 'Pierwszy krok' 'First step') @{ Dock = 'Top'; Height = (Px 24); ForeColor = $s.TextDim }
    $result = New-Label (L 'Gotowy do skanu' 'Ready to scan') @{ Dock = 'Top'; Height = (Px 60); Font = $s.Large; AutoEllipsis = $true }
    $stage = New-Label (L 'Skan trwa zwykle 1-3 minuty i niczego nie usuwa. Potem zobaczysz plan czyszczenia do sprawdzenia.' 'A scan usually takes 1-3 minutes and deletes nothing. Then you get a cleanup plan to review.') @{
        Dock = 'Top'; Height = (Px 44); ForeColor = $s.TextDim; AutoEllipsis = $true
    }
    $row = New-Control Panel @{ Dock = 'Top'; Height = (Px 46) }
    $btnStart = New-Button (L 'Skanuj teraz' 'Scan now') 'primary' @{ Dock = 'Left'; Width = (Px 200) }
    $btnPlan = New-Button (L 'Zobacz plan czyszczenia' 'View the cleanup plan') 'primary' @{ Dock = 'Left'; Width = (Px 214); Visible = $false }
    $btnCleanNow = New-Button $(if ($Preview) { L 'Podgląd - bez czyszczenia' 'Preview - no cleaning' } else { L 'Wyczyść od razu...' 'Clean now...' }) 'secondary' @{ Dock = 'Left'; Width = (Px 176); Visible = $false }
    Add-Docked $row @($btnStart, $btnPlan, (New-Spacer 'Left' 10), $btnCleanNow)
    Add-Docked $left @($small, $result, $stage, (New-Spacer 'Top' 8), $row)
    Add-Docked $k @($stats, (New-Spacer 'Right' 24), $left)
    # Narrow window: stat tiles give way to the buttons
    $k.Add_Resize({ if ($script:UI.Stats) { $script:UI.Stats.Width = [Math]::Max((Px 220), [Math]::Min((Px 420), $this.Width - $this.Padding.Horizontal - (Px 424))) } })
    $script:UI.ResultSmall = $small; $script:UI.Result = $result; $script:UI.Stage = $stage; $script:UI.Stats = $stats
    $script:UI.BtnScan = $btnScan; $script:UI.BtnStart = $btnStart; $script:UI.BtnToPlan = $btnPlan; $script:UI.BtnCleanNow = $btnCleanNow

    # Bottom: bars on the left, disks and startup on the right (40% width)
    $bottom = New-Control Panel @{ Dock = 'Fill' }
    $cardBars = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 24 20 24 16) }
    $bars = New-Canvas @{ Dock = 'Fill'; BackColor = $s.Card } { param($g, $p) Draw-Bars $g $p }
    $cardBars.Controls.Add($bars)
    $script:UI.Bars = $bars

    $right = New-Control Panel @{ Dock = 'Right'; Width = (Px 380) }
    $cardDrives = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 22 16 22 8) }
    $titleDrives = New-Label (L 'Dyski do skanowania' 'Drives to scan') @{ Dock = 'Top'; Height = (Px 30); Font = $s.CardTitle }
    $lvDrives = New-RowList { param($g, $w, $r, $h) Draw-DriveRow $g $w $r $h }
    $lvDrives.Tag.Click = {
        param($w, $x, $r)
        $d = $w.Obj
        if ($d.Sys -or $script:Working) { return }
        $d.Ticked = -not $d.Ticked
        $script:UI.DriveList.Invalidate()
    }
    $lvDrives.Tag.HandCursor = { param($w, $x, $r) -not $w.Obj.Sys }
    $drives = @()
    $selected = @($Drives | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() } | Where-Object { $_ })
    foreach ($d in Get-FixedDrives) {
        $sys = $d.DeviceID -eq $Sys
        $ticked = $sys -or -not $selected.Count -or ($d.DeviceID.TrimEnd(':') -in $selected)
        $drives += @{ H = (Px 72); Obj = @{ D = $d; Sys = $sys; Ticked = $ticked; Id = $d.DeviceID } }
    }
    Set-Rows $lvDrives $drives
    $script:UI.DriveList = $lvDrives
    Add-Docked $cardDrives @($titleDrives, $lvDrives)

    $cardStartup = New-Card @{ Dock = 'Bottom'; Height = (Px 150); Padding = (New-Padding 22 16 22 12) }
    $titleStartup = New-Label (L 'Start Windows' 'Windows startup') @{ Dock = 'Top'; Height = (Px 30); Font = $s.CardTitle }
    $startupText = New-Label '' @{ Dock = 'Fill'; ForeColor = $s.TextDim; AutoEllipsis = $true }
    $btnStartup = New-Button (L 'Przejrzyj autostart' 'Review startup apps') 'link' @{ Dock = 'Bottom'; Height = (Px 30) }
    $btnStartup.Add_Click({ Show-Page 'startup' })
    Add-Docked $cardStartup @($titleStartup, $btnStartup, $startupText)
    $script:UI.StartupText = $startupText
    Add-Docked $right @($cardStartup, (New-Spacer 'Bottom' 18), $cardDrives)

    $script:UI.RightColumn = $right
    Add-Docked $bottom @($right, (New-Spacer 'Right' 18), $cardBars)
    $bottom.Add_Resize({ if ($script:UI.RightColumn) { $script:UI.RightColumn.Width = [Math]::Max((Px 320), [int](($this.Width - (Px 18)) * 0.4)) } })

    Add-Docked $page @($n.Panel, $k, (New-Spacer 'Top' 18), $bottom)
    $page
}
