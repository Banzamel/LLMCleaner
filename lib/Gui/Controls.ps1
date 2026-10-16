<#
    LLMCleaner - budowa kontrolek: karty, plotna, etykiety, naglowki stron
#>

# Anchor i Dock na koncu: kotwica zapamietuje odleglosci od krawedzi rodzica w chwili ustawienia,
# wiec rozmiar i polozenie musza byc juz znane (kolejnosc kluczy w hashtable jest przypadkowa)
function New-Control([string]$type, [hashtable]$props) {
    $c = New-Object "Windows.Forms.$type"
    foreach ($k in $props.Keys) { if ($k -notin 'Anchor', 'Dock') { $c.$k = $props[$k] } }
    foreach ($k in 'Dock', 'Anchor') { if ($props.ContainsKey($k)) { $c.$k = $props[$k] } }
    $c
}

# Klatka ikony jako obrazek. LLMCleaner.ico ma klatki PNG, ktorych Icon.ToBitmap() w .NET Framework nie umie.
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

# DoubleBuffered jest chronione - bez niego wlasne rysowanie migocze przy zmianie rozmiaru
function Enable-DoubleBuffer($c) {
    [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($c, $true, $null)
}

# Karta: panel z zaokraglonymi rogami. Rogi maluje kolorem rodzica, wnetrze swoim BackColor.
# Bez ramki - karta odcina sie od tla samym kolorem. -Ramka dodaje cienka ramke.
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

# Panel rysowany w calosci przez podany blok (Paint dostaje Graphics i panel)
function New-Canvas([hashtable]$w, [scriptblock]$draw) {
    $p = New-Control Panel $w
    Enable-DoubleBuffer $p
    $p.Tag = @{ Draw = $draw }
    $p.Add_Paint({ $_.Graphics.Clear($this.BackColor); & $this.Tag.Draw $_.Graphics $this })
    $p.Add_Resize({ $this.Invalidate() })
    $p
}

# Przycisk rysowany od zera. Style: glowny (niebieski), zielony, drugi (jasnoniebieski), ramka (bialy z ramka),
# link (sam tekst), nav (pasek po lewej).
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

# Dodaje kontrolki zadokowane - lista od zewnetrznej (pierwsza = najwyzej/najnizej przy krawedzi), Fill na koncu.
# WinForms dokuje od konca kolekcji, wiec dodajemy w odwrotnej kolejnosci.
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
    # Etykieta zadokowana u gory lub u dolu zawsze miesci swoj tekst (inna czcionka systemowa, inne DPI)
    if ($w.ContainsKey('Height') -and "$($l.Dock)" -in 'Top', 'Bottom') {
        $sample = if ($text) { $text } else { 'Ąg' }
        $min = [Windows.Forms.TextRenderer]::MeasureText($sample, $l.Font).Height + $l.Padding.Vertical
        if ($l.Height -lt $min) { $l.Height = $min }
    }
    $l
}

# Naglowek strony: tytul, opis pod nim i przyciski po prawej (w kolejnosci od lewej)
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
