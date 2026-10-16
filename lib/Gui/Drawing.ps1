<#
    LLMCleaner - drawing: shapes, text, pills, checkboxes, toggles, buttons
#>

function New-RoundedPath([Drawing.Rectangle]$r, [int]$radius) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Max(1, [Math]::Min($radius * 2, [Math]::Min($r.Width, $r.Height)))
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

function Draw-RoundedFill($g, [Drawing.Rectangle]$r, [int]$radius, $bg, $border) {
    $g.SmoothingMode = 'AntiAlias'
    $p = New-RoundedPath $r $radius
    $b = New-Object Drawing.SolidBrush($bg); $g.FillPath($b, $p); $b.Dispose()
    if ($border) { $pen = New-Object Drawing.Pen($border); $g.DrawPath($pen, $p); $pen.Dispose() }
    $p.Dispose()
}

function Draw-Rect($g, [int]$x, [int]$y, [int]$w, [int]$h, $color, [int]$radius = 0, $border = $null) {
    if ($w -le 0 -or $h -le 0) { return }
    if ($radius -le 0 -and -not $border) { $b = New-Object Drawing.SolidBrush($color); $g.FillRectangle($b, $x, $y, $w, $h); $b.Dispose(); return }
    Draw-RoundedFill $g (New-Object Drawing.Rectangle($x, $y, $w, $h)) $radius $color $border
}

function Draw-Line($g, $color, [int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    $pen = New-Object Drawing.Pen($color); $g.DrawLine($pen, $x1, $y1, $x2, $y2); $pen.Dispose()
}

# Single-line text with ellipsis; alignment: Left, Right or HorizontalCenter
function Draw-Text($g, [string]$t, $font, $color, [int]$x, [int]$y, [int]$w, [int]$h, [string]$align = 'Left') {
    if (-not $t -or $w -le 0) { return }
    [Windows.Forms.TextRenderer]::DrawText($g, $t, $font, (New-Object Drawing.Rectangle($x, $y, $w, $h)), $color,
        [Windows.Forms.TextFormatFlags]"$align, VerticalCenter, EndEllipsis, SingleLine, NoPrefix")
}
function Draw-WrappedText($g, [string]$t, $font, $color, [int]$x, [int]$y, [int]$w, [int]$h) {
    if (-not $t -or $w -le 0) { return }
    [Windows.Forms.TextRenderer]::DrawText($g, $t, $font, (New-Object Drawing.Rectangle($x, $y, $w, $h)), $color,
        [Windows.Forms.TextFormatFlags]'Left, Top, WordBreak, EndEllipsis, NoPrefix')
}
function Measure-TextWidth([string]$t, $font) {
    [Windows.Forms.TextRenderer]::MeasureText($t, $font, (New-Object Drawing.Size(9999, 999)), [Windows.Forms.TextFormatFlags]'SingleLine, NoPrefix').Width
}

# Rounded pill (confidence, protection). Returns its width.
function Draw-Pill($g, [string]$t, [int]$x, [int]$midY, $bg, $color, [string]$icon = '') {
    $s = $script:Style
    $iconW = if ($icon -and $s.IconsSmall) { Px 16 } else { 0 }
    $w = (Measure-TextWidth $t $s.SmallBold) + (Px 16) + $iconW
    $h = Px 22
    $y = $midY - [int]($h / 2)
    Draw-Rect $g $x $y $w $h $bg ([int]($h / 2))
    if ($iconW) { Draw-Text $g $icon $s.IconsSmall $color ($x + (Px 8)) $y $iconW $h }
    Draw-Text $g $t $s.SmallBold $color ($x + (Px 8) + $iconW) $y ($w - (Px 16) - $iconW + (Px 2)) $h
    $w
}

# Owner-drawn checkbox (18 px at 100%)
function Draw-CheckBox($g, [int]$x, [int]$y, [bool]$ticked, [bool]$disabled) {
    $s = $script:Style; $b = Px 18
    if ($ticked) {
        Draw-Rect $g $x $y $b $b $(if ($disabled) { $s.TextDisabled } else { $s.Accent }) (Px 4)
        $pen = New-Object Drawing.Pen([Drawing.Color]::White, [float](Px 2))
        $g.DrawLines($pen, [Drawing.Point[]]@(
            (New-Object Drawing.Point(($x + (Px 4)), ($y + (Px 9)))),
            (New-Object Drawing.Point(($x + (Px 8)), ($y + (Px 13)))),
            (New-Object Drawing.Point(($x + (Px 14)), ($y + (Px 5))))))
        $pen.Dispose()
    }
    else { Draw-Rect $g $x $y ($b - 1) ($b - 1) $(if ($disabled) { $s.Disabled } else { $s.Card }) (Px 4) $s.Field }
}

# Toggle like in Windows Settings (48 x 28 px at 100%)
function Draw-Toggle($g, [int]$x, [int]$y, [bool]$enabled, [bool]$disabled) {
    $s = $script:Style
    $track = if ($enabled) { $s.Accent } else { $s.ToggleOff }
    $knob = [Drawing.Color]::White
    if ($disabled) { $track = [Drawing.Color]::FromArgb(110, $track); $knob = [Drawing.Color]::FromArgb(170, $knob) }
    Draw-Rect $g $x $y (Px 48) (Px 28) $track (Px 14)
    $gx = if ($enabled) { $x + (Px 23) } else { $x + (Px 3) }
    Draw-Rect $g $gx ($y + (Px 3)) (Px 22) (Px 22) $knob (Px 11)
}

# A fixed-width button grows when its text would not fit (instead of cutting it with an ellipsis)
function Resize-ToText($b) {
    if ("$($b.Dock)" -in 'Fill', 'Top', 'Bottom' -or -not $b.Text) { return }
    $min = (Measure-TextWidth $b.Text $b.Font) + (Px 32)
    if ($b.Width -lt $min) { $b.Width = $min }
}

function Draw-Button($b, $g) {
    $s = $script:Style; $t = $b.Tag
    $g.Clear($b.Parent.BackColor)
    $r = New-Object Drawing.Rectangle(0, 0, ($b.Width - 1), ($b.Height - 1))
    $border = $null
    $font = $b.Font
    switch ($t.Style) {
        'nav' {
            $bg = if ($t.Selected) { $s.NavSelectedBack } elseif ($t.Hover) { $s.NavHover } else { $s.NavBack }
            $color = if ($t.Selected) { [Drawing.Color]::White } else { $s.NavText }
            if ($t.Selected) { $font = $s.NavSelected }
        }
        'secondary' {
            $bg = if (-not $b.Enabled) { $s.Disabled } elseif ($t.Pressed -or $t.Hover) { $s.AccentLightHover } else { $s.AccentLight }
            $color = if ($b.Enabled) { $s.AccentText } else { $s.TextDisabled }
        }
        'outline' {
            $bg = if ($b.Enabled -and ($t.Pressed -or $t.Hover)) { $s.Tile } else { $s.Card }
            $color = if ($b.Enabled) { $s.Text } else { $s.TextDisabled }
            $border = $s.ButtonBorder
        }
        'link' {
            $bg = $b.Parent.BackColor
            $color = if (-not $b.Enabled) { $s.TextDisabled } elseif ($t.Hover) { $s.AccentHover } else { $s.AccentText }
        }
        default {
            $green = $t.Style -eq 'green'
            $bg = if (-not $b.Enabled) { $s.Disabled }
            elseif ($t.Pressed) { if ($green) { $s.GreenHover } else { $s.AccentPressed } }
            elseif ($t.Hover) { if ($green) { $s.GreenHover } else { $s.AccentHover } }
            else { if ($green) { $s.Green } else { $s.Accent } }
            $color = if ($b.Enabled) { [Drawing.Color]::White } else { $s.TextDisabled }
        }
    }
    if ($t.Style -ne 'link') { Draw-RoundedFill $g $r (Px 8) $bg $border }
    if ($t.Style -eq 'nav') {
        if ($t.Selected) { Draw-Rect $g 0 (Px 12) (Px 3) ($b.Height - (Px 24)) $s.Accent }
        $x = Px 16
        if ($s.Icons -and $t.Icon) {
            [Windows.Forms.TextRenderer]::DrawText($g, $t.Icon, $s.Icons, (New-Object Drawing.Rectangle((Px 14), 0, (Px 24), $b.Height)), $color, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter')
            $x = Px 48
        }
        Draw-Text $g $b.Text $font $color $x 0 ($b.Width - $x - (Px 6)) $b.Height
    }
    elseif ($t.Style -eq 'link') { Draw-Text $g $b.Text $font $color 0 0 $b.Width $b.Height }
    else { Draw-Text $g $b.Text $font $color (Px 6) 0 ($b.Width - (Px 12)) $b.Height 'HorizontalCenter' }
}
