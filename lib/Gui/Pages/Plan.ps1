<#
    LLMCleaner - strona Plan czyszczenia
#>

function Get-ConfidenceStyle([string]$p) {
    $s = $script:Style
    switch ($p) {
        'high' { @{ T = (Get-ConfidenceName $p); Background = $s.OkBack; Color = $s.OkText } }
        'medium' { @{ T = (Get-ConfidenceName $p); Background = $s.WarnBack; Color = $s.WarnText } }
        'low' { @{ T = (Get-ConfidenceName $p); Background = $s.ErrorBack; Color = $s.ErrorText } }
        default { @{ T = (L 'na życzenie' 'opt-in'); Background = $s.NeutralBack; Color = $s.NeutralText } }
    }
}

function Get-PlanBadge($o, [bool]$cat) {
    $s = $script:Style
    if ($cat) { return @{ T = (L 'KAT' 'CAT'); Background = $s.AccentLight; Color = $s.AccentText } }
    switch ($o.Type) {
        'folder' { @{ T = 'DIR'; Background = $s.WarnBack; Color = $s.WarnText } }
        'file' {
            if ($o.Path -like '*.lnk') { @{ T = 'LNK'; Background = $s.BlueBack; Color = $s.BlueText } }
            else { @{ T = (L 'PLIK' 'FILE'); Background = $s.BlueBack; Color = $s.BlueText } }
        }
        'task' { @{ T = (L 'ZAD' 'TASK'); Background = $s.OkBack; Color = $s.OkText } }
        default { @{ T = 'REG'; Background = $s.PurpleBack; Color = $s.PurpleText } }
    }
}

# Opis pozycji planu w drugiej linii: tekst i kolor
function Get-PlanDescription($o, [bool]$cat) {
    $s = $script:Style
    if ($cat) {
        if ($o.Blocker) { return @{ T = "! $($o.Blocker)"; K = $s.Warning } }
        if ($o.Note) { return @{ T = $o.Note; K = $s.TextDim } }
        return @{ T = $o.Description; K = $s.TextDim }
    }
    if ($o.Ai) { return @{ T = "$AiLabel`: $($o.Ai)"; K = $s.Ai } }
    @{ T = $o.Reason; K = $s.TextDim }
}

# Uklad kolumn listy planu (ten sam dla naglowka i wierszy)
function Get-PlanColumns([int]$width) {
    $conf = $width - (Px 18) - (Px 110)
    $sizeText = $conf - (Px 12) - (Px 190)
    @{ Field = (Px 20); Badge = (Px 54); Name = (Px 98); NameWidth = ($sizeText - (Px 16) - (Px 98)); Size = $sizeText; Confidence = $conf }
}

function Draw-PlanRow($g, $w, $r, [bool]$hover) {
    if ($w.Section) { Draw-Section $g $w $r; return }
    $s = $script:Style; $o = $w.Obj; $cat = [bool]$w.IsCategory
    Draw-RowBackground $g $r $hover
    $k = Get-PlanColumns $r.Width
    $mid = $r.Y + [int]($r.Height / 2)
    $disabled = [bool]($o.Blocker -and -not $o.Selected)
    Draw-CheckBox $g $k.Field ($mid - (Px 9)) ([bool]$o.Selected) ($disabled -or [bool]$script:Cleaned)
    $badge = Get-PlanBadge $o $cat
    Draw-Rect $g $k.Badge ($mid - (Px 16)) (Px 32) (Px 32) $badge.Background (Px 8)
    Draw-Text $g $badge.T $s.Badge $badge.Color $k.Badge ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter'
    $name = if ($cat) { $o.Name } else { Format-Leftover $o }
    $desc = Get-PlanDescription $o $cat
    Draw-Text $g $name $s.Bold $(if ($disabled) { $s.TextDim } else { $s.Text }) $k.Name ($mid - (Px 22)) $k.NameWidth (Px 22)
    Draw-Text $g $desc.T $s.Small $desc.K $k.Name ($mid + (Px 1)) $k.NameWidth (Px 20)
    $measurable = if ($cat) { Test-MeasurableCategory $o } else { Test-GoesToRecycleBin $o }
    $sizeText = if ($cat) { Format-CategorySize $o } else { Format-LeftoverSize $o }
    $barW = Px 100
    if ($measurable) {
        Draw-Rect $g $k.Size ($mid - (Px 3)) $barW (Px 6) $s.Track (Px 3)
        $len = [int][Math]::Max((Px 4), $barW * [double]$o.Bytes / [Math]::Max(1.0, [double]$w.Max))
        Draw-Rect $g $k.Size ($mid - (Px 3)) $len (Px 6) $(if ($o.Selected) { $s.Accent } else { $s.GreyBar }) (Px 3)
    }
    Draw-Text $g $sizeText $s.Bold $(if ($measurable) { $s.Text } else { $s.TextDim }) ($k.Size + $barW) ($mid - (Px 12)) (Px 90) (Px 24) 'Right'
    $conf = if ($cat) { if ($o.OptIn) { 'optin' } } else { $o.Confidence }
    if ($conf) { $p = Get-ConfidenceStyle $conf; [void](Draw-Pill $g $p.T $k.Confidence $mid $p.Background $p.Color) }
}

function Draw-PlanColumns($g, $p) {
    $s = $script:Style
    $k = Get-PlanColumns $script:UI.LvPlan.ClientSize.Width
    $h = $p.Height
    Draw-Text $g (L 'POZYCJA' 'ITEM') $s.Column $s.TextDim $k.Name 0 (Px 200) $h
    Draw-Text $g (L 'ROZMIAR' 'SIZE') $s.Column $s.TextDim $k.Size 0 (Px 190) $h
    Draw-Text $g (L 'PEWNOŚĆ' 'CONFIDENCE') $s.Column $s.TextDim $k.Confidence 0 (Px 110) $h
    Draw-Line $g $s.Border 0 ($h - 1) $p.Width ($h - 1)
}

function Test-PlanFilter($o, [bool]$cat) {
    switch ($script:PlanFilter) {
        'selected' { if (-not $o.Selected) { return $false } }
        'optin' { if (-not ($o.OptIn -or $o.Confidence -eq 'low')) { return $false } }
    }
    $q = $script:UI.Search.Text.Trim()
    if (-not $q) { return $true }
    $t = if ($cat) { "$($o.Name) $($o.Description) $($o.Note)" } else { "$(Format-Leftover $o) $($o.Reason) $($o.Ai)" }
    $t.IndexOf($q, [StringComparison]::CurrentCultureIgnoreCase) -ge 0
}

function Get-GroupTotal($list) {
    $z = @($list | Where-Object { $_.Selected })
    $b = [double]($z | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum
    if (-not $z.Count) { return L 'nic nie zaznaczono' 'nothing selected' }
    if ($b -gt 0) { (L 'zaznaczone {0}' '{0} selected') -f (Format-Size $b) } else { (L 'zaznaczone: {0}' 'selected: {0}') -f $z.Count }
}

function Update-PlanPage {
    $lv = $script:UI.LvPlan
    $cat = @($script:Categories | Where-Object { $_.Bytes -gt 0 -or $_.Selected -or ($_.Type -in 'dns', 'dism', 'docker', 'dockerall') } | Sort-Object { [double]$_.Bytes } -Descending)
    $leftoverList = @(@($script:Leftovers | Where-Object { Test-GoesToRecycleBin $_ } | Sort-Object { [double]$_.Bytes } -Descending) +
        @($script:Leftovers | Where-Object { -not (Test-GoesToRecycleBin $_) }))
    $max = [double](@($cat) + @($leftoverList) | ForEach-Object { [double]$_.Bytes } | Measure-Object -Maximum).Maximum
    $rows = [System.Collections.Generic.List[object]]::new()
    $catRows = @($cat | Where-Object { Test-PlanFilter $_ $true })
    if ($catRows.Count) {
        $rows.Add(@{ Section = $true; H = (Px 40); Text = (L 'Kategorie czyszczenia - odtwarzają się same' 'Cleanup categories - they rebuild themselves')
                RightText = { Get-GroupTotal $script:Categories }
            })
        foreach ($k in $catRows) { $rows.Add(@{ H = (Px 60); Obj = $k; IsCategory = $true; Max = $max }) }
    }
    $leftRows = @($leftoverList | Where-Object { Test-PlanFilter $_ $false })
    if ($leftRows.Count) {
        $rows.Add(@{ Section = $true; H = (Px 44); Text = (L 'Pozostałości po odinstalowanych programach i grach' 'Leftovers of uninstalled programs and games')
                RightText = { Get-GroupTotal $script:Leftovers }
            })
        foreach ($p in $leftRows) { $rows.Add(@{ H = (Px 60); Obj = $p; IsCategory = $false; Max = $max }) }
    }
    $lv.Tag.EmptyText = if (-not $script:Scanned) { L 'Plan pojawi się po skanie. Wróć do Przeglądu i kliknij „Skanuj”.' 'The plan appears after a scan. Go back to Overview and click "Scan".' }
    else { L 'Nic nie pasuje do wyszukiwania albo filtra.' 'Nothing matches the search or filter.' }
    Set-Rows $lv $rows
    Update-PlanTotal
}

function Update-PlanTotal {
    $u = $script:UI
    $selected = @(@($script:Categories) + @($script:Leftovers) | Where-Object { $_ -and $_.Selected })
    $u.Total.Text = (L 'Zaznaczone: {0}' 'Selected: {0}') -f (Format-Size (Get-SelectedTotal))
    $t = (L 'Pozycji: {0}' 'Items: {0}') -f $selected.Count
    $lockedSum = Get-LockedTotal
    if ($lockedSum) { $t += ' · ' + ((L '{0} zablokowane przez działające programy' '{0} locked by running programs') -f (Format-Size $lockedSum)) }
    $u.TotalNote.Text = $t
    $u.LvPlan.Invalidate()
    Update-Overview
}

function New-PlanPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Plan czyszczenia' 'Cleanup plan') (L 'Kliknij pozycję, żeby ją zaznaczyć lub odznaczyć. Pliki i foldery trafiają do Kosza, rejestr i zadania mają kopię i punkt przywracania. Najedź na pozycję, żeby zobaczyć pełny opis.' 'Click an item to tick or untick it. Files and folders go to the Recycle Bin; registry entries and tasks get a backup and a restore point. Hover over an item to see its full description.')

    # Pasek narzedzi: szukanie, filtr, przyciski zaznaczania
    $bar = New-Control Panel @{ Dock = 'Top'; Height = (Px 40) }
    $search = New-Card @{ Dock = 'Left'; Width = (Px 300); Padding = (New-Padding 12 10 10 6) }
    $script:UI.SearchCard = $search
    if ($s.Icons) { $search.Controls.Add((New-Label ([string][char]0xE721) @{ Dock = 'Left'; Width = (Px 26); Font = $s.Icons; ForeColor = $s.TextDim; BackColor = $s.Card })) }
    $field = New-Control TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Card; ForeColor = $s.Text; Font = $s.Body }
    $search.Controls.Add($field); $field.BringToFront()
    $field.Add_TextChanged({ if ($script:Scanned) { Update-PlanPage } })
    $script:UI.Search = $field

    $filter = New-Canvas @{ Dock = 'Left'; Width = (Px 300); BackColor = $s.Background; Cursor = [Windows.Forms.Cursors]::Hand } {
        param($g, $p)
        $s = $script:Style
        $options = $p.Tag.Options
        Draw-Rect $g 0 0 ($p.Width - 1) ($p.Height - 1) $s.Segment (Px 8)
        $w = [int](($p.Width - (Px 6)) / $options.Count)
        for ($i = 0; $i -lt $options.Count; $i++) {
            $x = (Px 3) + $i * $w
            $chosen = $options[$i].Id -eq $script:PlanFilter
            if ($chosen) { Draw-Rect $g $x (Px 3) $w ($p.Height - (Px 7)) $s.SegmentSelected (Px 6) }
            Draw-Text $g $options[$i].T $(if ($chosen) { $s.Bold } else { $s.Body }) $(if ($chosen) { $s.Text } else { $s.TextDim }) $x 0 $w $p.Height 'HorizontalCenter'
        }
    }
    $filter.Tag.Options = @(@{ Id = 'all'; T = (L 'Wszystko' 'All') }, @{ Id = 'selected'; T = (L 'Zaznaczone' 'Selected') }, @{ Id = 'optin'; T = (L 'Na życzenie' 'Opt-in') })
    $widest = ($filter.Tag.Options | ForEach-Object { Measure-TextWidth $_.T $s.Bold } | Measure-Object -Maximum).Maximum
    $filter.Width = [Math]::Max((Px 300), 3 * ([int]$widest + (Px 24)) + (Px 6))
    $filter.Add_MouseClick({
            $o = $this.Tag.Options
            $i = [Math]::Min($o.Count - 1, [Math]::Max(0, [int][Math]::Floor(($_.X - (Px 3)) / (($this.Width - (Px 6)) / $o.Count))))
            $script:PlanFilter = $o[$i].Id
            $this.Invalidate()
            if ($script:Scanned) { Update-PlanPage }
        })
    $btnRecommended = New-Button (L 'Zaznacz zalecane' 'Select recommended') 'outline' @{ Dock = 'Right'; Width = (Px 160) }
    $btnClear = New-Button (L 'Odznacz wszystko' 'Clear selection') 'outline' @{ Dock = 'Right'; Width = (Px 150) }
    Add-Docked $bar @($search, (New-Spacer 'Left' 12), $filter, $btnClear, (New-Spacer 'Right' 10), $btnRecommended)
    $bar.Add_Resize({ if ($script:UI.SearchCard) { $script:UI.SearchCard.Width = [Math]::Max((Px 160), [Math]::Min((Px 320), $this.Width - $script:UI.PlanFilter.Width - $script:UI.BtnRecommended.Width - $script:UI.BtnClearSelection.Width - (Px 34))) } })
    $script:UI.BtnRecommended = $btnRecommended; $script:UI.BtnClearSelection = $btnClear; $script:UI.PlanFilter = $filter

    # Lista z naglowkiem kolumn
    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 2 4 2 8) }
    $lv = New-RowList { param($g, $w, $r, $h) Draw-PlanRow $g $w $r $h }
    $col = New-Canvas @{ Dock = 'Top'; Height = (Px 34); BackColor = $s.Card } { param($g, $p) Draw-PlanColumns $g $p }
    $lv.Tag.Click = {
        param($w, $x, $r)
        if ($script:Working -or $script:Cleaned) { return }
        $o = $w.Obj
        if ($o.Blocker -and -not $o.Selected) { Set-WindowStatus $o.Blocker; return }
        $o.Selected = -not $o.Selected
        Update-PlanTotal
    }
    $lv.Tag.Hint = {
        param($w)
        $o = $w.Obj
        if ($w.IsCategory) { (@($o.Name, $o.Description, $o.Note, $o.Blocker) | Where-Object { $_ }) -join "`n" }
        else { (@((Format-Leftover $o), $o.Reason, $(if ($o.Ai) { "$AiLabel`: $($o.Ai)" })) | Where-Object { $_ }) -join "`n" }
    }
    $lv.Add_Resize({ if ($script:UI.PlanColumns) { $script:UI.PlanColumns.Invalidate() } })
    Add-Docked $k @($col, $lv)
    $script:UI.LvPlan = $lv; $script:UI.PlanColumns = $col

    # Pasek akcji pod lista
    $bottom = New-Card @{ Dock = 'Bottom'; Height = (Px 74); Padding = (New-Padding 20 14 14 14) }
    $btnClean = New-Button $(if ($Preview) { L 'Podgląd - czyszczenie wyłączone' 'Preview - cleaning disabled' } else { L 'Wyczyść zaznaczone...' 'Clean selected...' }) 'primary' @{ Dock = 'Right'; Width = (Px 220) }
    $btnExplain = New-Button (L 'AI: czym były pozostałości?' 'AI: what were the leftovers?') 'secondary' @{ Dock = 'Right'; Width = (Px 240) }
    $texts = New-Control Panel @{ Dock = 'Fill' }
    $total = New-Label '' @{ Dock = 'Top'; Height = (Px 26); Font = $s.Medium }
    $totalNote = New-Label '' @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small; AutoEllipsis = $true }
    Add-Docked $texts @($total, $totalNote)
    Add-Docked $bottom @($btnClean, (New-Spacer 'Right' 10), $btnExplain, $texts)
    $script:UI.Total = $total; $script:UI.TotalNote = $totalNote; $script:UI.BtnClean = $btnClean; $script:UI.BtnExplain = $btnExplain

    Add-Docked $page @($n.Panel, $bar, (New-Spacer 'Top' 14), $bottom, (New-Spacer 'Bottom' 14), $k)
    $page
}
