<#
    LLMCleaner - budowa kontrolek: karty, plotna, etykiety, naglowki stron
#>

# Anchor i Dock na koncu: kotwica zapamietuje odleglosci od krawedzi rodzica w chwili ustawienia,
# wiec rozmiar i polozenie musza byc juz znane (kolejnosc kluczy w hashtable jest przypadkowa)
function Kontrolka([string]$typ, [hashtable]$wlasciwosci) {
    $c = New-Object "Windows.Forms.$typ"
    foreach ($k in $wlasciwosci.Keys) { if ($k -notin 'Anchor', 'Dock') { $c.$k = $wlasciwosci[$k] } }
    foreach ($k in 'Dock', 'Anchor') { if ($wlasciwosci.ContainsKey($k)) { $c.$k = $wlasciwosci[$k] } }
    $c
}

# Klatka ikony jako obrazek. LLMCleaner.ico ma klatki PNG, ktorych Icon.ToBitmap() w .NET Framework nie umie.
function ObrazZIkony([string]$plik, [int]$rozmiar) {
    $b = [IO.File]::ReadAllBytes($plik)
    $najlepsza = $null
    for ($i = 0; $i -lt [BitConverter]::ToUInt16($b, 4); $i++) {
        $o = 6 + 16 * $i
        $w = if ($b[$o] -eq 0) { 256 } else { [int]$b[$o] }
        if ($w -ge $rozmiar -and (-not $najlepsza -or $w -lt $najlepsza.W)) {
            $najlepsza = @{ W = $w; Dl = [BitConverter]::ToInt32($b, $o + 8); Od = [BitConverter]::ToInt32($b, $o + 12) }
        }
    }
    if (-not $najlepsza) { return (New-Object Drawing.Icon($plik, $rozmiar, $rozmiar)).ToBitmap() }
    $ms = New-Object IO.MemoryStream($b, $najlepsza.Od, $najlepsza.Dl)
    try { New-Object Drawing.Bitmap($ms) } catch { (New-Object Drawing.Icon($plik, $rozmiar, $rozmiar)).ToBitmap() }
}

# DoubleBuffered jest chronione - bez niego wlasne rysowanie migocze przy zmianie rozmiaru
function PodwojnyBufor($c) {
    [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($c, $true, $null)
}

# Karta: panel z zaokraglonymi rogami. Rogi maluje kolorem rodzica, wnetrze swoim BackColor.
# Bez ramki - karta odcina sie od tla samym kolorem. -Ramka dodaje cienka ramke.
function Karta([hashtable]$w = @{}, [switch]$Ramka) {
    $k = Kontrolka Panel $w
    if (-not $w.ContainsKey('BackColor')) { $k.BackColor = $script:Styl.Karta }
    if (-not $w.ContainsKey('Padding')) { $k.Padding = Marg 18 16 18 16 }
    PodwojnyBufor $k
    $k.AccessibleDescription = $(if ($Ramka) { 'ramka' } else { '' })
    $k.Add_Paint({
            $_.Graphics.Clear($this.Parent.BackColor)
            $r = New-Object Drawing.Rectangle(0, 0, ($this.Width - 1), ($this.Height - 1))
            WypelnijZaokraglony $_.Graphics $r (Px 12) $this.BackColor $(if ($this.AccessibleDescription -eq 'ramka') { $script:Styl.Ramka })
        })
    $k.Add_Resize({ $this.Invalidate() })
    $k
}

# Panel rysowany w calosci przez podany blok (Paint dostaje Graphics i panel)
function Plotno([hashtable]$w, [scriptblock]$rysuj) {
    $p = Kontrolka Panel $w
    PodwojnyBufor $p
    $p.Tag = @{ Rysuj = $rysuj }
    $p.Add_Paint({ $_.Graphics.Clear($this.BackColor); & $this.Tag.Rysuj $_.Graphics $this })
    $p.Add_Resize({ $this.Invalidate() })
    $p
}

# Przycisk rysowany od zera. Style: glowny (niebieski), zielony, drugi (jasnoniebieski), ramka (bialy z ramka),
# link (sam tekst), nav (pasek po lewej).
function Przycisk([string]$tekst, [string]$styl = 'glowny', [hashtable]$w = @{}) {
    $b = Kontrolka Button $w
    $b.Text = $tekst
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.UseVisualStyleBackColor = $false
    $b.UseMnemonic = $false
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    if (-not $w.ContainsKey('Font')) { $b.Font = $script:Styl.Przycisk }
    $b.Tag = @{ Styl = $styl; Hover = $false; Wcisniety = $false; Wybrany = $false; Ikona = $w.AccessibleName }
    if ($styl -notin 'nav', 'link') { DopasujSzerokosc $b; $b.Add_TextChanged({ DopasujSzerokosc $this }) }
    $b.Add_MouseEnter({ $this.Tag.Hover = $true; $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Tag.Wcisniety = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Tag.Wcisniety = $true; $this.Invalidate() })
    $b.Add_MouseUp({ $this.Tag.Wcisniety = $false; $this.Invalidate() })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({ RysujPrzycisk $this $_.Graphics })
    $b
}

# Dodaje kontrolki zadokowane - lista od zewnetrznej (pierwsza = najwyzej/najnizej przy krawedzi), Fill na koncu.
# WinForms dokuje od konca kolekcji, wiec dodajemy w odwrotnej kolejnosci.
function Dokuj($rodzic, [object[]]$lista) {
    [array]::Reverse($lista)
    foreach ($c in $lista) { $rodzic.Controls.Add($c) }
}
function Odstep([string]$dok = 'Top', [double]$ile = 16) { Kontrolka Panel @{ Dock = $dok; Height = (Px $ile); Width = (Px $ile) } }

function Etykieta([string]$tekst, [hashtable]$w = @{}) {
    $l = Kontrolka Label $w
    $l.Text = $tekst
    $l.UseMnemonic = $false
    if (-not $w.ContainsKey('Font')) { $l.Font = $script:Styl.Czcionka }
    if (-not $w.ContainsKey('ForeColor')) { $l.ForeColor = $script:Styl.Tekst }
    if (-not $w.ContainsKey('AutoSize') -and -not $w.ContainsKey('Dock')) { $l.AutoSize = $true }
    # Etykieta zadokowana u gory lub u dolu zawsze miesci swoj tekst (inna czcionka systemowa, inne DPI)
    if ($w.ContainsKey('Height') -and "$($l.Dock)" -in 'Top', 'Bottom') {
        $wzor = if ($tekst) { $tekst } else { 'Ąg' }
        $min = [Windows.Forms.TextRenderer]::MeasureText($wzor, $l.Font).Height + $l.Padding.Vertical
        if ($l.Height -lt $min) { $l.Height = $min }
    }
    $l
}

# Naglowek strony: tytul, opis pod nim i przyciski po prawej (w kolejnosci od lewej)
function Naglowek([string]$tytul, [string]$opis, [object[]]$przyciski = @()) {
    $n = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 84) }
    $lewy = Kontrolka Panel @{ Dock = 'Fill' }
    $o = Etykieta $opis @{ Dock = 'Fill'; ForeColor = $script:Styl.TekstSlaby; AutoEllipsis = $true }
    $t = Etykieta $tytul @{ Dock = 'Top'; Height = (Px 44); Font = $script:Styl.Tytul }
    Dokuj $lewy @($t, $o)
    $el = @()
    if ($przyciski.Count) {
        $prawy = Kontrolka Panel @{ Dock = 'Right'; Padding = (Marg 16 20 0 20) }
        $wew = @(); $szer = Px 16
        for ($i = $przyciski.Count - 1; $i -ge 0; $i--) {
            $b = $przyciski[$i]; $b.Dock = 'Right'; $wew += $b; $szer += $b.Width
            if ($i) { $wew += (Odstep 'Right' 10); $szer += Px 10 }
        }
        $prawy.Width = $szer
        Dokuj $prawy $wew
        $el += $prawy
    }
    Dokuj $n ($el + @($lewy))
    @{ Panel = $n; Opis = $o; Tytul = $t }
}

function Strona {
    Kontrolka Panel @{ Dock = 'Fill'; BackColor = $script:Styl.Tlo; Padding = (Marg 30 22 30 14) }
}

function Komunikat([string]$tekst, [string]$ikona = 'Information') {
    [void][Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, 'LLMCleaner', 'OK', $ikona)
}
