<#
    LLMCleaner - control builders: cards, canvases, labels, page headers
#>

# Anchor and Dock go last: an anchor stores the distances to the parent's edges when it is set,
# so size and location must already be known (hashtable key order is random)
function New-Control([string]$type, [hashtable]$props) {
    $c = New-Object "Windows.Forms.$type"
    foreach ($k in $props.Keys) { if ($k -notin 'Anchor', 'Dock') { $c.$k = $props[$k] } }
    foreach ($k in 'Dock', 'Anchor') { if ($props.ContainsKey($k)) { $c.$k = $props[$k] } }
    $c
}

# Icon frame as an image. LLMCleaner.ico has PNG frames, which Icon.ToBitmap() in .NET Framework can't handle.
function Get-IconImage([string]$file, [int]$size) {
    $b = [IO.File]::ReadAllBytes($file)
    $best = $null
    for ($i = 0; $i -lt [BitConverter]::ToUInt16($b, 4); $i++) {
        $o = 6 + 16 * $i
        $w = if ($b[$o] -eq 0) { 256 } else { [int]$b[$o] }
        if ($w -ge $size -and (-not $best -or $w -lt $best.W)) {
            $best = @{ W = $w; Len = [BitConverter]::ToInt32($b, $o + 8); Offset = [BitConverter]::ToInt32($b, $o + 12) }
        }
    }
    if (-not $best) { return (New-Object Drawing.Icon($file, $size, $size)).ToBitmap() }
    $ms = New-Object IO.MemoryStream($b, $best.Offset, $best.Len)
    try { New-Object Drawing.Bitmap($ms) } catch { (New-Object Drawing.Icon($file, $size, $size)).ToBitmap() }
}

# DoubleBuffered is protected - without it custom drawing flickers on resize
function Enable-DoubleBuffer($c) {
    [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($c, $true, $null)
}

# Card: panel with rounded corners. Corners are painted in the parent's color, the inside in its own BackColor.
# No border - the card stands out by color alone. -Border adds a thin border.
function New-Card([hashtable]$w = @{}, [switch]$Border) {
    $k = New-Control Panel $w
    if (-not $w.ContainsKey('BackColor')) { $k.BackColor = $script:Style.Card }
    if (-not $w.ContainsKey('Padding')) { $k.Padding = New-Padding 18 16 18 16 }
    Enable-DoubleBuffer $k
    $k.AccessibleDescription = $(if ($Border) { 'outline' } else { '' })
    $k.Add_Paint({
            $_.Graphics.Clear($this.Parent.BackColor)
            $r = New-Object Drawing.Rectangle(0, 0, ($this.Width - 1), ($this.Height - 1))
            Draw-RoundedFill $_.Graphics $r (Px 12) $this.BackColor $(if ($this.AccessibleDescription -eq 'outline') { $script:Style.Border })
        })
    $k.Add_Resize({ $this.Invalidate() })
    $k
}

# Panel drawn entirely by the given block (Paint gets Graphics and the panel)
function New-Canvas([hashtable]$w, [scriptblock]$draw) {
    $p = New-Control Panel $w
    Enable-DoubleBuffer $p
    $p.Tag = @{ Draw = $draw }
    $p.Add_Paint({ $_.Graphics.Clear($this.BackColor); & $this.Tag.Draw $_.Graphics $this })
    $p.Add_Resize({ $this.Invalidate() })
    $p
}

# Owner-drawn button. Styles: primary (blue), green, secondary (light blue), outline (white with border),
# link (text only), nav (left bar).
function New-Button([string]$text, [string]$style = 'primary', [hashtable]$w = @{}) {
    $b = New-Control Button $w
    $b.Text = $text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.UseVisualStyleBackColor = $false
    $b.UseMnemonic = $false
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    if (-not $w.ContainsKey('Font')) { $b.Font = $script:Style.ButtonFont }
    $b.Tag = @{ Style = $style; Hover = $false; Pressed = $false; Selected = $false; Icon = $w.AccessibleName }
    if ($style -notin 'nav', 'link') { Resize-ToText $b; $b.Add_TextChanged({ Resize-ToText $this }) }
    $b.Add_MouseEnter({ $this.Tag.Hover = $true; $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Tag.Pressed = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Tag.Pressed = $true; $this.Invalidate() })
    $b.Add_MouseUp({ $this.Tag.Pressed = $false; $this.Invalidate() })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({ Draw-Button $this $_.Graphics })
    $b
}

# Adds docked controls - list from the outermost (first = closest to the edge), Fill last.
# WinForms docks from the end of the collection, so they are added in reverse order.
function Add-Docked($parentDir, [object[]]$list) {
    [array]::Reverse($list)
    foreach ($c in $list) { $parentDir.Controls.Add($c) }
}
function New-Spacer([string]$dock = 'Top', [double]$amount = 16) { New-Control Panel @{ Dock = $dock; Height = (Px $amount); Width = (Px $amount) } }

function New-Label([string]$text, [hashtable]$w = @{}) {
    $l = New-Control Label $w
    $l.Text = $text
    $l.UseMnemonic = $false
    if (-not $w.ContainsKey('Font')) { $l.Font = $script:Style.Body }
    if (-not $w.ContainsKey('ForeColor')) { $l.ForeColor = $script:Style.Text }
    if (-not $w.ContainsKey('AutoSize') -and -not $w.ContainsKey('Dock')) { $l.AutoSize = $true }
    # A label docked top or bottom always fits its text (different system font, different DPI)
    if ($w.ContainsKey('Height') -and "$($l.Dock)" -in 'Top', 'Bottom') {
        $sample = if ($text) { $text } else { 'Ąg' }
        $min = [Windows.Forms.TextRenderer]::MeasureText($sample, $l.Font).Height + $l.Padding.Vertical
        if ($l.Height -lt $min) { $l.Height = $min }
    }
    $l
}

# Page header: title, description below it and buttons on the right (in left-to-right order)
function New-PageHeader([string]$title, [string]$desc, [object[]]$buttons = @()) {
    $n = New-Control Panel @{ Dock = 'Top'; Height = (Px 84) }
    $leftPart = New-Control Panel @{ Dock = 'Fill' }
    $o = New-Label $desc @{ Dock = 'Fill'; ForeColor = $script:Style.TextDim; AutoEllipsis = $true }
    $t = New-Label $title @{ Dock = 'Top'; Height = (Px 44); Font = $script:Style.Title }
    Add-Docked $leftPart @($t, $o)
    $el = @()
    if ($buttons.Count) {
        $rightPart = New-Control Panel @{ Dock = 'Right'; Padding = (New-Padding 16 20 0 20) }
        $inner = @(); $width = Px 16
        for ($i = $buttons.Count - 1; $i -ge 0; $i--) {
            $b = $buttons[$i]; $b.Dock = 'Right'; $inner += $b; $width += $b.Width
            if ($i) { $inner += (New-Spacer 'Right' 10); $width += Px 10 }
        }
        $rightPart.Width = $width
        Add-Docked $rightPart $inner
        $el += $rightPart
    }
    Add-Docked $n ($el + @($leftPart))
    @{ Panel = $n; Description = $o; Title = $t }
}

function New-Page {
    New-Control Panel @{ Dock = 'Fill'; BackColor = $script:Style.Background; Padding = (New-Padding 30 22 30 14) }
}

function Show-Message([string]$text, [string]$icon = 'Information') {
    [void][Windows.Forms.MessageBox]::Show($script:UI.Window, $text, 'LLMCleaner', 'OK', $icon)
}
