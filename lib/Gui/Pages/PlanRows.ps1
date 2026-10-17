<#
    LLMCleaner - plan page rows: badges, columns, sorting and the full description of an item
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
    # Icon: Segoe MDL2 Assets glyph (cache that rebuilds itself, folder, file, link, task, registry); T without the font
    if ($cat) { return @{ T = (L 'KAT' 'CAT'); Icon = 0xE895; Background = $s.AccentLight; Color = $s.AccentText } }
    switch ($o.Type) {
        'folder' { @{ T = 'DIR'; Icon = 0xE8B7; Background = $s.WarnBack; Color = $s.WarnText } }
        'file' {
            if ($o.Path -like '*.lnk') { @{ T = 'LNK'; Icon = 0xE71B; Background = $s.BlueBack; Color = $s.BlueText } }
            else { @{ T = (L 'PLIK' 'FILE'); Icon = 0xE8A5; Background = $s.BlueBack; Color = $s.BlueText } }
        }
        'task' { @{ T = (L 'ZAD' 'TASK'); Icon = 0xE823; Background = $s.OkBack; Color = $s.OkText } }
        default { @{ T = 'REG'; Icon = 0xE713; Background = $s.PurpleBack; Color = $s.PurpleText } }
    }
}

# Plan item description on the second line: text and color
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

# Plan list column layout (same for header and rows)
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
    if ($s.Icons) { Draw-Text $g ([string][char]$badge.Icon) $s.Icons $badge.Color $k.Badge ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
    else { Draw-Text $g $badge.T $s.Badge $badge.Color $k.Badge ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
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
    $o = $script:PlanSort
    foreach ($c in @(@{ Key = 'name'; T = (L 'POZYCJA' 'ITEM'); X = $k.Name; W = 200 }, @{ Key = 'size'; T = (L 'ROZMIAR' 'SIZE'); X = $k.Size; W = 190 },
            @{ Key = 'confidence'; T = (L 'PEWNOŚĆ' 'CONFIDENCE'); X = $k.Confidence; W = 110 })) {
        $t = $c.T
        if ($o.Key -eq $c.Key) { $t += $(if ($o.Desc) { ' ▼' } else { ' ▲' }) }
        Draw-Text $g $t $s.Column $(if ($o.Key -eq $c.Key) { $s.AccentText } else { $s.TextDim }) $c.X 0 (Px $c.W) $h
    }
    Draw-Line $g $s.Border 0 ($h - 1) $p.Width ($h - 1)
}

# Column header click: the same column flips the order, another one sorts by it
function Set-PlanSort([int]$x) {
    $k = Get-PlanColumns $script:UI.LvPlan.ClientSize.Width
    $key = if ($x -ge $k.Confidence) { 'confidence' } elseif ($x -ge $k.Size) { 'size' } elseif ($x -ge $k.Name) { 'name' } else { return }
    if ($script:PlanSort.Key -eq $key) { $script:PlanSort.Desc = -not $script:PlanSort.Desc }
    else { $script:PlanSort = @{ Key = $key; Desc = ($key -ne 'name') } }
    $script:UI.PlanColumns.Invalidate()
    if ($script:Scanned) { Update-PlanPage }
}

function Sort-PlanItems($list, [bool]$cat) {
    $o = $script:PlanSort
    $rank = @{ high = 3; medium = 2; low = 1 }
    $key = switch ($o.Key) {
        'name' { if ($cat) { { $_.Name } } else { { Format-Leftover $_ } } }
        'confidence' { if ($cat) { { if ($_.OptIn) { 0 } else { 4 } } } else { { [int]$rank["$($_.Confidence)"] } } }
        default { { [double]$_.Bytes } }
    }
    @($list | Sort-Object -Property @{ Expression = $key; Descending = $o.Desc }, @{ Expression = { [double]$_.Bytes }; Descending = $true })
}

# Full description shown after clicking the item name
function Get-PlanHint($w) {
    $o = $w.Obj
    if ($w.IsCategory) { return (@($o.Name, $o.Description, $o.Note, $o.Blocker) | Where-Object { $_ }) -join "`n" }
    $lines = @((Format-Leftover $o), $o.Reason)
    if ($o.Ai) { $lines += "$AiLabel`: $($o.Ai)" }
    $info = @("$(L 'Rozmiar' 'Size'): $(Format-LeftoverSize $o)")
    if ($o.Confidence) { $info += "$(L 'Pewność' 'Confidence'): $(Get-ConfidenceName $o.Confidence)" }
    if ($o.LastWrite) { $info += "$(L 'Ostatnia zmiana' 'Last changed'): $($o.LastWrite.ToString('yyyy-MM-dd'))" }
    $lines += ($info -join ' · ')
    if (Test-GoesToRecycleBin $o) { $lines += (L 'Dwuklik pokazuje pozycję w Eksploratorze.' 'Double-click shows the item in File Explorer.') }
    (@($lines) | Where-Object { $_ }) -join "`n"
}
