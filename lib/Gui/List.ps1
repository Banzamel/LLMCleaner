<#
    LLMCleaner - owner-drawn list (rows, sections, scrolling)
#>

# Scrollable list of rows of any height. A row is a hashtable with H (height), Section (group header)
# or Obj (data). Drawn by the Draw($g, $row, $rect, $hover) block; clicks go to Click/DoubleClick.
function New-RowList([scriptblock]$draw) {
    $p = New-Control Panel @{ Dock = 'Fill'; AutoScroll = $true; BackColor = $script:Style.Card }
    Enable-DoubleBuffer $p
    $p.Tag = @{ Rows = @(); Draw = $draw; Hover = -1; Click = $null; DoubleClick = $null; HandCursor = $null; Hint = $null; EmptyText = '' }
    $p.Add_Paint({
            $g = $_.Graphics; $t = $this.Tag; $s = $script:Style
            $g.Clear($this.BackColor)
            $width = $this.ClientSize.Width
            if (-not $t.Rows.Count) {
                Draw-WrappedText $g $t.EmptyText $s.Body $s.TextDim (Px 20) (Px 18) ($width - (Px 40)) (Px 80)
                return
            }
            $dy = $this.AutoScrollPosition.Y
            $top = - $dy; $bottom = $top + $this.ClientSize.Height
            for ($i = 0; $i -lt $t.Rows.Count; $i++) {
                $w = $t.Rows[$i]
                if ($w.Y + $w.H -lt $top) { continue }
                if ($w.Y -gt $bottom) { break }
                $r = New-Object Drawing.Rectangle(0, ($w.Y + $dy), $width, $w.H)
                & $t.Draw $g $w $r ($i -eq $t.Hover -and -not $w.Section)
            }
        })
    $p.Add_Resize({ $this.Invalidate() })
    $p.Add_MouseMove({
            $t = $this.Tag
            $i = Get-RowAt $this $_.Y
            $w = if ($i -ge 0) { $t.Rows[$i] }
            $hand = $false
            if ($w -and -not $w.Section -and $t.Click) {
                $hand = if ($t.HandCursor) { [bool](& $t.HandCursor $w $_.X (Get-RowRect $this $w)) } else { $true }
            }
            $this.Cursor = $(if ($hand) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default })
            if ($i -ne $t.Hover) {
                $t.Hover = $i
                $this.Invalidate()
                $text = if ($w -and -not $w.Section -and $t.Hint) { & $t.Hint $w } else { '' }
                $script:UI.Hint.SetToolTip($this, "$text")
            }
        })
    $p.Add_MouseLeave({ $this.Tag.Hover = -1; $this.Invalidate() })
    $p.Add_MouseClick({
            if ($_.Button -ne 'Left') { return }
            $t = $this.Tag
            $i = Get-RowAt $this $_.Y
            if ($i -lt 0 -or -not $t.Click) { return }
            $w = $t.Rows[$i]
            if (-not $w.Section) { & $t.Click $w $_.X (Get-RowRect $this $w) }
        })
    $p.Add_MouseDoubleClick({
            $t = $this.Tag
            $i = Get-RowAt $this $_.Y
            if ($i -ge 0 -and $t.DoubleClick -and -not $t.Rows[$i].Section) { & $t.DoubleClick $t.Rows[$i] }
        })
    $script:UI.Scrollables += $p
    $p
}

function Set-Rows($list, $rows) {
    $y = 0
    $tab = @($rows | Where-Object { $_ })
    foreach ($w in $tab) { $w.Y = $y; $y += $w.H }
    $list.Tag.Rows = $tab
    $list.Tag.Hover = -1
    $list.AutoScrollMinSize = New-Object Drawing.Size(0, $y)
    $list.Invalidate()
}

function Get-RowAt($list, [int]$y) {
    $yy = $y - $list.AutoScrollPosition.Y
    $i = 0
    foreach ($w in $list.Tag.Rows) {
        if ($yy -ge $w.Y -and $yy -lt $w.Y + $w.H) { return $i }
        $i++
    }
    -1
}
function Get-RowRect($list, $w) { New-Object Drawing.Rectangle(0, ($w.Y + $list.AutoScrollPosition.Y), $list.ClientSize.Width, $w.H) }

# Shared row elements: hover background, line above the row, group header
function Draw-RowBackground($g, $r, [bool]$hover) {
    $s = $script:Style
    if ($hover) { Draw-Rect $g 0 $r.Y $r.Width $r.Height $s.Row }
    Draw-Line $g $s.Line (Px 18) $r.Y ($r.Right - (Px 18)) $r.Y
}
function Draw-Section($g, $w, $r) {
    $s = $script:Style
    $rightPart = if ($w.RightText) { & $w.RightText } else { '' }
    $rightW = if ($rightPart) { (Measure-TextWidth $rightPart $s.Small) + (Px 4) } else { 0 }
    Draw-Text $g $w.Text $s.Bold $s.AccentText (Px 18) ($r.Y + (Px 8)) ($r.Width - (Px 50) - $rightW) ($r.Height - (Px 8))
    Draw-Text $g $rightPart $s.Small $s.TextDim ($r.Width - (Px 18) - $rightW) ($r.Y + (Px 8)) $rightW ($r.Height - (Px 8)) 'Right'
}
