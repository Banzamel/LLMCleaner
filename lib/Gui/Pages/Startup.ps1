<#
    LLMCleaner - strona Autostart
#>

$InitialColors = @('#5865F2', '#0A64AD', '#1A7F3C', '#B30B00', '#7C3AED', '#C2410C', '#0F766E', '#BE185D')
function Get-InitialColor([string]$n) {
    $h = 0; foreach ($c in $n.ToCharArray()) { $h = ($h * 31 + [int]$c) % 1000003 }
    ConvertTo-Color $InitialColors[$h % $InitialColors.Count]
}

function Draw-StartupRow($g, $w, $r, [bool]$hover) {
    $s = $script:Style; $a = $w.Obj
    Draw-RowBackground $g $r $hover
    $mid = $r.Y + [int]($r.Height / 2)
    $tileColor = if ($a.Protected) { $s.TileProtected } else { Get-InitialColor $a.Name }
    Draw-Rect $g (Px 20) ($mid - (Px 18)) (Px 36) (Px 36) $tileColor (Px 9)
    $initial = if ($a.Name) { $a.Name.Substring(0, 1).ToUpper() } else { '?' }
    Draw-Text $g $initial $s.Bold ([Drawing.Color]::White) (Px 20) ($mid - (Px 18)) (Px 36) (Px 36) 'HorizontalCenter'
    $xToggle = $r.Width - (Px 20) - (Px 48)
    $xBin = $xToggle - (Px 44)
    $xSource = $xBin - (Px 12) - (Px 170)
    $xName = Px 70
    $nameW = $xSource - (Px 14) - $xName
    $y1 = $mid - (Px 31)
    $nameTextW = [Math]::Min((Measure-TextWidth $a.Name $s.Bold), $nameW)
    Draw-Text $g $a.Name $s.Bold $(if ($a.IsEnabled) { $s.Text } else { $s.TextDim }) $xName $y1 $nameTextW (Px 22)
    if ($a.Protected) {
        $shortText = ($a.Protected -split ' - ')[0]
        if ($xName + $nameTextW + (Px 160) -lt $xSource) { [void](Draw-Pill $g $shortText ($xName + $nameTextW + (Px 8)) ($y1 + (Px 11)) $s.NeutralBack $s.NeutralText ([string][char]0xE72E)) }
    }
    $line2 = (@($a.Publisher, $a.Command) | Where-Object { $_ }) -join ' · '
    Draw-Text $g $line2 $s.Small $s.TextDim $xName ($mid - (Px 9)) $nameW (Px 20)
    $line3 = if ($a.Dead) { @{ T = (L 'Martwy wpis: programu już nie ma na dysku. Kosz obok przełącznika usuwa wpis.' 'Dead entry: the program is no longer on the drive. The bin next to the switch removes the entry.'); K = $s.Warning } }
    elseif ($a.Ai) { @{ T = "$AiLabel`: $($a.Ai)"; K = $s.Ai } }
    elseif ($a.Protected) { @{ T = $a.Protected; K = $s.TextDim } }
    if ($line3) { Draw-Text $g $line3.T $s.Small $line3.K $xName ($mid + (Px 11)) $nameW (Px 20) }
    Draw-Text $g $a.Source $s.Small $s.TextDim $xSource ($mid - (Px 11)) (Px 170) (Px 22)
    Draw-Toggle $g $xToggle ($mid - (Px 14)) ([bool]$a.IsEnabled) ([bool]$a.Protected -or [bool]$Preview)
    # Usuniecie wpisu na stale (z kopia) - tylko dla niechronionych
    if (-not $a.Protected -and -not $Preview) {
        $col = if ($a.Dead) { $s.Warning } else { $s.TextDim }
        if ($hover) { Draw-Rect $g $xBin ($mid - (Px 16)) (Px 32) (Px 32) $s.Tile (Px 8) }
        if ($s.Icons) { Draw-Text $g ([string][char]0xE74D) $s.Icons $col $xBin ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
        else { Draw-Text $g ([string][char]0x00D7) $s.CardTitle $col $xBin ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
    }
}

function Draw-StartupSummary($g, $p) {
    $entries = @($script:Startup | Where-Object { $_ })
    $enabled = @($entries | Where-Object { $_.IsEnabled }).Count
    $data = @(
        @{ W = $(if ($null -eq $script:Startup) { '-' } else { "$enabled" }); O = (L 'uruchamia się przy logowaniu' 'start at sign-in') }
        @{ W = $(if ($null -eq $script:Startup) { '-' } else { "$($entries.Count - $enabled)" }); O = (L 'wyłączone' 'turned off') }
        @{ W = $(if ($null -eq $script:Startup) { '-' } else { "$(@($entries | Where-Object { $_.Protected }).Count)" }); O = (L 'chronione (tylko podgląd)' 'protected (read-only)') })
    $t = if ($Preview) { L 'Tryb podglądu - przełączniki są tylko do wglądu.' 'Preview mode - the switches are read-only.' }
    else { L 'Zmiana działa od następnego logowania. Programy możesz dalej uruchamiać ręcznie.' 'Changes take effect at the next sign-in. You can still start the programs by hand.' }
    Draw-TilesWithNote $g $p $data $t
}

# Kafelki z liczbami i notka obok (strony Autostart i Sterowniki)
function Draw-TilesWithNote($g, $p, $data, [string]$t) {
    $s = $script:Style
    $width = Px 200; $gap = Px 12; $h = $p.Height - 1
    $x = 0
    foreach ($d in $data) {
        Draw-Rect $g $x 0 $width $h $s.Card (Px 12)
        Draw-Text $g $d.W $s.Number $s.Text ($x + (Px 18)) (Px 6) ($width - (Px 24)) (Px 32)
        Draw-Text $g $d.O $s.Small $s.TextDim ($x + (Px 18)) (Px 36) ($width - (Px 24)) (Px 22)
        $x += $width + $gap
    }
    $nameW = $p.Width - $x - 1
    if ($nameW -gt (Px 120)) {
        Draw-Rect $g $x 0 $nameW $h $s.NoteBack (Px 12) $s.NoteBorder
        [Windows.Forms.TextRenderer]::DrawText($g, $t, $s.Body, (New-Object Drawing.Rectangle(($x + (Px 18)), 0, ($nameW - (Px 30)), $h)), $s.NoteText,
            [Windows.Forms.TextFormatFlags]'Left, VerticalCenter, WordBreak, EndEllipsis, NoPrefix')
    }
}

function Update-StartupPage {
    $rows = @(@($script:Startup | Where-Object { $_ } | Sort-Object { -not $_.IsEnabled }, { [bool]$_.Protected }, { $_.Name }) |
            ForEach-Object { @{ H = (Px 74); Obj = $_ } })
    $script:UI.LvStartup.Tag.EmptyText = L 'Nie znaleziono programów uruchamianych przy logowaniu.' 'No programs that start at sign-in were found.'
    Set-Rows $script:UI.LvStartup $rows
    $script:UI.StartupSummary.Invalidate()
    Update-StartupCard
    if ($script:Scanned) { Update-Overview }
}

# Przelacznik w wierszu: dziala od razu, jak w Menedzerze zadan (wylaczenie niczego nie usuwa)
function Switch-StartupRow($a) {
    if ($script:Working) { return }
    if ($Preview) { Set-WindowStatus (L 'Tryb podglądu - autostart się nie zmienia.' 'Preview mode - startup apps are not changed.'); return }
    if ($a.Protected) { Set-WindowStatus ((L '{0}: chronione - {1}' '{0}: protected - {1}') -f $a.Name, $a.Protected); return }
    $enable = -not $a.IsEnabled
    try {
        Set-StartupEnabled $a $enable
        $state = if ($enable) { L 'włączony' 'on' } else { L 'wyłączony' 'off' }
        Write-WindowLog ("  Autostart: {0} -> {1}" -f $a.Name, $state) 'Green'
        Set-WindowStatus ((L '{0}: autostart {1}. Zmiana działa od następnego logowania.' '{0}: startup {1}. It takes effect at the next sign-in.') -f $a.Name, $state)
    }
    catch {
        Write-Log "Autostart - blad $($a.Name): $($_.Exception.Message)"
        Show-Message ((L 'Nie udało się zmienić {0}: {1}' 'Could not change {0}: {1}') -f $a.Name, $_.Exception.Message) 'Warning'
    }
    $script:UI.LvStartup.Invalidate()
    $script:UI.StartupSummary.Invalidate()
    Update-StartupCard
    if ($script:Scanned) { Update-Overview }
}

# Usuniecie wpisu na stale, po potwierdzeniu. Kopia .reg / .xml albo skrot w Koszu.
function Remove-StartupRow($a) {
    if ($script:Working -or $Preview -or $a.Protected) { return }
    $backupNote = switch ($a.Kind) { 'folder' { L 'Skrót trafi do Kosza.' 'The shortcut goes to the Recycle Bin.' } 'task' { L 'Zadanie dostanie kopię .xml (Harmonogram zadań > Importuj zadanie przywraca je).' 'The task gets an .xml backup (Task Scheduler > Import Task restores it).' } default { L 'Wpis dostanie kopię .reg (dwuklik na niej przywraca wpis).' 'The entry gets a .reg backup (double-clicking it restores the entry).' } }
    $text = (L "Usunąć z autostartu na stałe:`r`n`r`n  {0}`r`n  {1}`r`n`r`nProgram nie jest odinstalowywany, znika tylko wpis uruchamiania. {2}" "Remove from startup permanently:`r`n`r`n  {0}`r`n  {1}`r`n`r`nThe program is not uninstalled, only its startup entry is removed. {2}") -f $a.Name, $a.Command, $backupNote
    $answer = [Windows.Forms.MessageBox]::Show($script:UI.Window, $text, (L 'LLMCleaner - usuń z autostartu' 'LLMCleaner - remove from startup'), 'YesNo', 'Question', 'Button2')
    if ($answer -ne 'Yes') { return }
    try {
        $backupPlace = Remove-StartupEntry $a
        Write-WindowLog ((L '  Autostart: {0} usunięty (kopia: {1})' '  Startup: {0} removed (backup: {1})') -f $a.Name, $backupPlace) 'Green'
        Set-WindowStatus ((L '{0}: usunięty z autostartu. Kopia: {1}' '{0}: removed from startup. Backup: {1}') -f $a.Name, $backupPlace)
    }
    catch {
        Write-Log "Autostart - blad usuwania $($a.Name): $($_.Exception.Message)"
        Show-Message ((L 'Nie udało się usunąć {0}: {1}' 'Could not remove {0}: {1}') -f $a.Name, $_.Exception.Message) 'Warning'
    }
    Update-StartupPage
}

function New-StartupPage {
    $s = $script:Style
    $page = New-Page
    $btnRefresh = New-Button (L 'Odśwież' 'Refresh') 'outline' @{ Width = (Px 120) }
    $btnAi = New-Button (L 'AI: co to jest?' 'AI: what is it?') 'secondary' @{ Width = (Px 170) }
    $n = New-PageHeader (L 'Autostart' 'Startup apps') (L 'Programy uruchamiane przy logowaniu. Przełącznik działa jak w Menedżerze zadań: wyłączenie niczego nie usuwa. Kosz usuwa wpis na stałe, z kopią. Ochrona, sterowniki, aktualizacje i części Windows są tylko do wglądu.' 'Programs that start when you sign in. The switch works like in Task Manager: turning one off removes nothing. The bin removes the entry permanently, with a backup. Security software, drivers, updaters and parts of Windows are read-only.') @($btnRefresh, $btnAi)
    $script:UI.BtnStartupRefresh = $btnRefresh; $script:UI.BtnStartupAi = $btnAi

    $sumCanvas = New-Canvas @{ Dock = 'Top'; Height = (Px 66); BackColor = $s.Background } { param($g, $p) Draw-StartupSummary $g $p }
    $script:UI.StartupSummary = $sumCanvas

    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 2 4 2 8) }
    $lv = New-RowList { param($g, $w, $r, $h) Draw-StartupRow $g $w $r $h }
    $lv.Tag.EmptyText = L 'Lista wczytuje się przy wejściu na stronę.' 'The list loads when you open this page.'
    $lv.Tag.Click = {
        param($w, $x, $r)
        if ($x -ge $r.Width - (Px 76)) { Switch-StartupRow $w.Obj }
        elseif ($x -ge $r.Width - (Px 112)) { Remove-StartupRow $w.Obj }
    }
    $lv.Tag.HandCursor = { param($w, $x, $r) $x -ge $r.Width - (Px 112) -and -not $w.Obj.Protected -and -not $Preview }
    $lv.Tag.DoubleClick = { param($w) if ($w.Obj.Exists) { Start-Process explorer.exe -ArgumentList "/select,`"$($w.Obj.File)`"" } }
    $lv.Tag.Hint = {
        param($w)
        $a = $w.Obj
        (@($a.Name, $a.Command, $a.Source, $a.Protected, $(if ($a.Ai) { "$AiLabel`: $($a.Ai)" }), (L 'Dwuklik pokazuje plik w Eksploratorze.' 'Double-click shows the file in File Explorer.')) | Where-Object { $_ }) -join "`n"
    }
    $k.Controls.Add($lv)
    $script:UI.LvStartup = $lv

    Add-Docked $page @($n.Panel, $sumCanvas, (New-Spacer 'Top' 14), $k)
    $page
}
