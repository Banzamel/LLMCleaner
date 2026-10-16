<#
    LLMCleaner - strona Czyszczenie (postep i wynik)
#>

function Initialize-Steps {
    $steps = @()
    if (Test-RestorePointNeeded) { $steps += @{ Id = 'restorepoint'; Name = (L 'Punkt przywracania systemu' 'System Restore point') } }
    foreach ($k in ($script:Categories | Where-Object { $_.Selected })) {
        $u = if ($k.Type -eq 'thumbnails') { L 'pasek zadań zniknie na chwilę' 'the taskbar disappears for a moment' } elseif ($k.Type -in 'dism', 'winold') { L 'potrwa kilka minut' 'takes a few minutes' } else { '' }
        $steps += @{ Id = $k.Id; Name = $k.Name; Description = $u }
    }
    $leftRows = @($script:Leftovers | Where-Object { $_.Selected })
    $binCount = @($leftRows | Where-Object { Test-GoesToRecycleBin $_ }).Count
    if ($binCount) { $steps += @{ Id = 'leftovers-bin'; Name = ((L 'Pozostałości do Kosza: {0}' 'Leftovers to the Recycle Bin: {0}') -f $binCount) } }
    $backupCount = $leftRows.Count - $binCount
    if ($backupCount) { $steps += @{ Id = 'leftovers-backup'; Name = ((L 'Rejestr i zadania z kopią: {0}' 'Registry and tasks with a backup: {0}') -f $backupCount) } }
    foreach ($k in $steps) { $k.State = 'waiting'; $k.Bytes = 0.0; $k.Note = '' }
    $script:Steps = $steps
    $script:CleanupResult = $null
    $script:UI.ResultInfo.Text = L 'Kopie rejestru i zadań, punkt przywracania i pominięte pliki pojawią się tutaj po ostatnim kroku.' 'Registry and task backups, the restore point and skipped files appear here after the last step.'
    $script:UI.ResultTitle.Text = L 'Po zakończeniu zobaczysz' 'When it finishes you will see'
    $script:UI.ResultButtons.Visible = $false
    Set-Rows $script:UI.LvSteps @($steps | ForEach-Object { @{ H = (Px 52); Obj = $_ } })
    Update-Steps
}

# Wywolywane z rdzenia (ZglosKrok) w trakcie czyszczenia
function Update-WindowStep([string]$id, [string]$state, [double]$bytes, [string]$note) {
    $k = $script:Steps | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if (-not $k) { return }
    $k.State = $state
    if ($state -ne 'running') { $k.Bytes = $bytes; $k.Note = $note }
    Update-Steps
    # Biezacy krok zawsze widoczny na liscie
    if ($state -eq 'running') {
        $lv = $script:UI.LvSteps
        $w = $lv.Tag.Rows | Where-Object { $_.Obj -eq $k } | Select-Object -First 1
        if ($w) { $lv.AutoScrollPosition = New-Object Drawing.Point(0, [Math]::Max(0, $w.Y - $lv.ClientSize.Height + 2 * $w.H)) }
    }
    [Windows.Forms.Application]::DoEvents()
}

function Get-FreedSoFar { [double](@($script:Steps | Where-Object { $_.Id -ne 'leftovers-bin' } | ForEach-Object { [double]$_.Bytes }) | Measure-Object -Sum).Sum }

function Update-Steps {
    $u = $script:UI
    $u.LvSteps.Invalidate(); $u.ProgressCanvas.Invalidate(); $u.ResultCanvas.Invalidate()
    $n = @($script:Steps).Count
    $done = @($script:Steps | Where-Object { $_.State -notin 'waiting', 'running' }).Count
    if ($script:Cleaning -and $n) { Set-TaskbarProgress 2 $done $n }
}

function Draw-CleanupProgress($g, $p) {
    $s = $script:Style
    $steps = @($script:Steps)
    $n = $steps.Count
    $done = @($steps | Where-Object { $_.State -notin 'waiting', 'running' }).Count
    $current = $steps | Where-Object { $_.State -eq 'running' } | Select-Object -First 1
    $t = if ($script:CleanupResult) { L 'Gotowe - wszystkie kroki zakończone' 'Done - all steps finished' }
    elseif ($current) { (L 'Krok {0} z {1} · {2}' 'Step {0} of {1} · {2}') -f ($done + 1), $n, $current.Name }
    else { (L 'Krok {0} z {1}' 'Step {0} of {1}') -f [Math]::Min($n, $done + 1), $n }
    $rightPart = (L 'zwolniono {0}' '{0} freed') -f (Format-Size (Get-FreedSoFar))
    $rightW = (Measure-TextWidth $rightPart $s.Body) + (Px 4)
    Draw-Text $g $t $s.CardTitle $s.Text 0 0 ($p.Width - $rightW - (Px 12)) (Px 30)
    Draw-Text $g $rightPart $s.Body $s.TextDim ($p.Width - $rightW) 0 $rightW (Px 30) 'Right'
    $y = Px 42
    Draw-Rect $g 0 $y $p.Width (Px 10) $s.Track (Px 5)
    if ($n) { Draw-Rect $g 0 $y ([int][Math]::Max((Px 10), $p.Width * $done / $n)) (Px 10) $(if ($script:CleanupResult) { $s.Green } else { $s.Accent }) (Px 5) }
}

function Draw-StepRow($g, $w, $r, [bool]$hover) {
    $s = $script:Style; $k = $w.Obj
    Draw-RowBackground $g $r $false
    $mid = $r.Y + [int]($r.Height / 2)
    $d = Px 24; $x = Px 20; $y = $mid - [int]($d / 2)
    switch ($k.State) {
        'ok' { Draw-Rect $g $x $y $d $d $s.OkBack ([int]($d / 2)); $mark = [string][char]0x2713; $markColor = $s.OkText; $noteColor = $s.TextDim }
        'partial' { Draw-Rect $g $x $y $d $d $s.OkBack ([int]($d / 2)); $mark = [string][char]0x2713; $markColor = $s.OkText; $noteColor = $s.Warning }
        'running' { Draw-Rect $g $x $y $d $d $s.Accent ([int]($d / 2)); $mark = [string][char]0x2026; $markColor = [Drawing.Color]::White; $noteColor = $s.AccentText }
        'skipped' { Draw-Rect $g $x $y $d $d $s.WarnBack ([int]($d / 2)); $mark = '!'; $markColor = $s.WarnText; $noteColor = $s.Warning }
        'fail' { Draw-Rect $g $x $y $d $d $s.ErrorBack ([int]($d / 2)); $mark = '!'; $markColor = $s.ErrorText; $noteColor = $s.Red }
        default { Draw-Rect $g $x $y ($d - 1) ($d - 1) $s.Card ([int]($d / 2)) $s.Field; $mark = ''; $markColor = $s.Text; $noteColor = $s.TextDim }
    }
    Draw-Text $g $mark $s.SmallBold $markColor $x $y $d $d 'HorizontalCenter'
    $note = switch ($k.State) {
        'waiting' { if ($k.Description) { (L 'czeka - {0}' 'waiting - {0}') -f $k.Description } else { L 'czeka' 'waiting' } }
        'running' { if ($k.Description) { (L 'w toku - {0}' 'in progress - {0}') -f $k.Description } else { L 'w toku...' 'in progress...' } }
        default { $k.Note }
    }
    $xName = Px 60; $width = $r.Width - $xName - (Px 120)
    Draw-Text $g $k.Name $s.Bold $s.Text $xName ($mid - (Px 20)) $width (Px 21)
    Draw-Text $g $note $s.Small $noteColor $xName ($mid + (Px 1)) $width (Px 19)
    if ($k.Bytes -gt 0) { Draw-Text $g (Format-Size $k.Bytes) $s.Bold $s.Text ($r.Width - (Px 110)) ($mid - (Px 12)) (Px 90) (Px 24) 'Right' }
}

function Draw-CleanupResult($g, $p) {
    $s = $script:Style
    $w = $script:CleanupResult
    $h = $p.Height - 1
    if ($w) {
        Draw-Rect $g 0 0 ($p.Width - 1) $h $s.SuccessBack (Px 12) $s.SuccessBorder
        $color = $s.SuccessText
        $small = L 'Zwolniono' 'Freed'
        $bigText = Format-Size $w.Total
        $bottom = (L 'Wolne na {0} {1} → {2} · {3} min {4} s' 'Free on {0} {1} → {2} · {3} min {4} s') -f $Sys, (Format-Size $w.FreeBefore), (Format-Size $w.FreeAfter), [int][Math]::Floor($w.Duration.TotalMinutes), $w.Duration.Seconds
    }
    else {
        Draw-Rect $g 0 0 ($p.Width - 1) $h $s.Tile (Px 12)
        $color = $s.Text
        $small = L 'Zwolniono do tej pory' 'Freed so far'
        $bigText = Format-Size (Get-FreedSoFar)
        $bottom = L 'Wolne miejsce przed i po pojawi się po ostatnim kroku.' 'Free space before and after appears after the last step.'
    }
    Draw-Text $g $small $s.Small $color (Px 18) (Px 10) ($p.Width - (Px 36)) (Px 20)
    Draw-Text $g $bigText $s.Large $color (Px 14) (Px 30) ($p.Width - (Px 30)) (Px 56)
    Draw-Text $g $bottom $s.Small $color (Px 18) (Px 88) ($p.Width - (Px 36)) (Px 20)
}

# Czyszczenie z ekranem postepu: kroki, pasek, wynik. Potwierdzenie jest wczesniej (przycisk).
function Start-WindowCleanup {
    Initialize-Steps
    $lockedBytes = Get-LockedTotal
    Lock-Navigation $true
    Show-Page 'cleanup'
    Write-WindowLog ''
    Write-WindowLog (L '2/2  Czyszczenie' '2/2  Cleaning') 'Cyan'
    $script:OnStep = { param($id, $state, $bytes, $note) Update-WindowStep $id $state $bytes $note }
    $ok = $false
    try { $w = Invoke-Cleanup; $ok = $true }
    finally {
        $script:OnStep = $null
        Lock-Navigation $false
        Set-TaskbarProgress $(if ($ok) { 0 } else { 4 }) 1 1
        if (-not $ok) { foreach ($k in $script:Steps) { if ($k.State -eq 'running') { $k.State = 'fail'; $k.Note = L 'przerwane - szczegóły w Dzienniku' 'interrupted - see the Log' } }; Update-Steps }
    }
    $script:Cleaned = $true
    $pointStep = $script:Steps | Where-Object { $_.Id -eq 'restorepoint' } | Select-Object -First 1
    $backups = if ($w.Backups -and (Test-Path -LiteralPath $w.Backups)) { @(Get-ChildItem -LiteralPath $w.Backups -File).Count } else { 0 }
    $w.BackupCount = $backups
    $script:CleanupResult = $w
    $info = @(
        $(if ($backups) { (L 'Kopie rejestru i zadań: {0} plików ({1})' 'Registry and task backups: {0} files ({1})') -f $backups, $w.Backups } else { L 'Kopie rejestru i zadań: nie były potrzebne' 'Registry and task backups: not needed' })
        $(if ($pointStep) { (L 'Punkt przywracania: {0}' 'Restore point: {0}') -f $pointStep.Note } else { L 'Punkt przywracania: nie był potrzebny' 'Restore point: not needed' }))
    if ($lockedBytes) { $info += (L 'Pominięte: {0} w użyciu' 'Skipped: {0} in use') -f (Format-Size $lockedBytes) }
    $toBin = $script:Steps | Where-Object { $_.Id -eq 'leftovers-bin' } | Select-Object -First 1
    if ($toBin -and $toBin.Bytes) { $info += (L 'W Koszu: {0} - zwolni się po opróżnieniu Kosza' 'In the Recycle Bin: {0} - freed when you empty it') -f (Format-Size $toBin.Bytes) }
    $script:UI.ResultInfo.Text = $info -join "`r`n"
    $script:UI.ResultTitle.Text = L 'Gotowe' 'Done'
    $script:UI.ResultButtons.Visible = $true
    Update-Steps
    Write-WindowLog ''
    foreach ($x in (Get-CleanupSummary $w)) { Write-WindowLog "  $x" 'White' }
    Write-WindowLog "  Log: $LogFile" 'DarkGray'
    # Martwe wpisy mogly zniknac - lista autostartu od nowa
    try { [void](Get-StartupEntries); Update-StartupPage } catch { Add-ScanError 'startup' $_ }
    Update-Overview
    Update-PlanPage
    Set-WindowStatus (L 'Czyszczenie zakończone. Kliknij „Skanuj ponownie”, żeby zobaczyć aktualny stan.' 'Cleaning finished. Click "Scan again" to see the current state.')
    if ($script:UI.Window.WindowState -eq 'Minimized') { $script:UI.Window.WindowState = 'Normal' }
}

function New-CleanupPage {
    $s = $script:Style
    $page = New-Page
    $aside = New-Control Panel @{ Dock = 'Right'; Width = (Px 380) }
    $left = New-Control Panel @{ Dock = 'Fill' }
    $n = New-PageHeader (L 'Czyszczenie' 'Cleaning') (L 'Nie wyłączaj komputera. Pliki w użyciu są pomijane, foldery i skróty trafiają do Kosza.' 'Do not turn off the computer. Files in use are skipped; folders and shortcuts go to the Recycle Bin.')
    $cardProgress = New-Card @{ Dock = 'Top'; Height = (Px 96); Padding = (New-Padding 24 20 24 16) }
    $progressCanvas = New-Canvas @{ Dock = 'Fill'; BackColor = $s.Card } { param($g, $p) Draw-CleanupProgress $g $p }
    $cardProgress.Controls.Add($progressCanvas)
    $cardSteps = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 2 4 2 8) }
    $lv = New-RowList { param($g, $w, $r, $h) Draw-StepRow $g $w $r $h }
    $cardSteps.Controls.Add($lv)
    Add-Docked $left @($n.Panel, $cardProgress, (New-Spacer 'Top' 16), $cardSteps)
    $script:UI.ProgressCanvas = $progressCanvas; $script:UI.LvSteps = $lv

    $cardResult = New-Card @{ Dock = 'Top'; Height = (Px 380); Padding = (New-Padding 24 20 24 20) }
    $titleResult = New-Label '' @{ Dock = 'Top'; Height = (Px 34); Font = $s.CardTitle }
    $field = New-Canvas @{ Dock = 'Top'; Height = (Px 116); BackColor = $s.Card } { param($g, $p) Draw-CleanupResult $g $p }
    $info = New-Label '' @{ Dock = 'Fill'; AutoEllipsis = $true }
    $buttonPanel = New-Control Panel @{ Dock = 'Bottom'; Height = (Px 44); Visible = $false }
    $btnRescan = New-Button (L 'Skanuj ponownie' 'Scan again') 'primary' @{ Dock = 'Left'; Width = (Px 170) }
    $btnLog = New-Button (L 'Otwórz log' 'Open the log') 'secondary' @{ Dock = 'Left'; Width = (Px 140) }
    Add-Docked $buttonPanel @($btnRescan, (New-Spacer 'Left' 10), $btnLog)
    Add-Docked $cardResult @($titleResult, $field, (New-Spacer 'Top' 14), $buttonPanel, $info)
    $btnRescan.Add_Click({ $script:UI.BtnScan.PerformClick() })
    $btnLog.Add_Click({ if (Test-Path -LiteralPath $LogFile) { Start-Process notepad.exe -ArgumentList "`"$LogFile`"" } })
    $script:UI.ResultTitle = $titleResult; $script:UI.ResultCanvas = $field; $script:UI.ResultInfo = $info; $script:UI.ResultButtons = $buttonPanel; $script:UI.BtnResultScan = $btnRescan

    $cardNote = New-Card @{ Dock = 'Top'; Height = (Px 86); Padding = (New-Padding 24 16 24 14) }
    $cardNote.Controls.Add((New-Label (L 'Postęp jest też widoczny na ikonie LLMCleanera na pasku zadań, więc okno może pracować w tle.' 'Progress is also shown on the LLMCleaner taskbar icon, so the window can work in the background.') @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small }))
    Add-Docked $aside @($cardResult, (New-Spacer 'Top' 16), $cardNote)

    $script:UI.Aside = $aside
    Add-Docked $page @($aside, (New-Spacer 'Right' 18), $left)
    $page.Add_Resize({ if ($script:UI.Aside) { $script:UI.Aside.Width = [Math]::Max((Px 320), [int](($this.ClientSize.Width - $this.Padding.Horizontal - (Px 18)) * 0.4)) } })
    $page
}
