<#
    LLMCleaner - okno graficzne (Windows Forms, wbudowane w Windows). Logika jest w Rdzen.ps1.
    Uklad wedlug makiet 1.5: ciemny pasek nawigacji po lewej, strony z kartami, listy rysowane od zera
    (dwie linie tekstu, odznaki typu, paski rozmiaru, przelaczniki), ekran postepu czyszczenia.
    Okno zna skalowanie ekranu (DPI) - wszystkie wymiary w pikselach ida przez Px - i motyw Windows
    (jasny albo ciemny). Rozmiar, polozenie i ostatnia strona sa zapamietywane w okno.json.
    Dlugie operacje AI ida w osobnym watku (CzekajNa), skan i czyszczenie odswiezaja okno (DoEvents).
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:UI = @{}
$script:Zeskanowano = $false
$script:Pracuje = $false
$script:Czyszczenie = $false
$script:Kroki = @()
$script:WynikCzyszczenia = $null
$script:FiltrPlanu = 'wszystko'
$script:Strona = 'przeglad'
$script:Skala = 1.0

function Kolor([string]$hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function Px([double]$n) { [int][Math]::Round($n * $script:Skala) }
function Rozm([double]$w, [double]$h) { New-Object Drawing.Size((Px $w), (Px $h)) }
function Pkt([double]$x, [double]$y) { New-Object Drawing.Point((Px $x), (Px $y)) }
function Marg([double]$l, [double]$t, [double]$r, [double]$b) { New-Object Windows.Forms.Padding((Px $l), (Px $t), (Px $r), (Px $b)) }

# ---------- USTAWIENIA OKNA I MOTYW ----------
# okno.json: rozmiar, polozenie, ostatnia strona i motyw ("auto", "jasny" albo "ciemny")
$script:OknoPlik = Join-Path $env:LOCALAPPDATA 'LLMCleaner\okno.json'
$script:Ustawienia = $null
if (Test-Path -LiteralPath $script:OknoPlik) {
    try { $script:Ustawienia = Get-Content -LiteralPath $script:OknoPlik -Raw | ConvertFrom-Json } catch { $script:Ustawienia = $null }
}

function MotywCiemny {
    $m = "$($script:Ustawienia.Motyw)"
    if ($m -in 'ciemny', 'dark') { return $true }
    if ($m -in 'jasny', 'light') { return $false }
    (Get-ItemProperty "$HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize").AppsUseLightTheme -eq 0
}
$script:Ciemny = [bool](MotywCiemny)

$PaletaJasna = @{
    Tlo = '#F3F4F8'; Karta = '#FFFFFF'; Kafelek = '#F6F7FB'; Ramka = '#E2E5EE'; RamkaPrzycisku = '#D5D9E4'; Linia = '#F0F1F5'
    Tekst = '#1F2333'; TekstSlaby = '#5B6170'; Wiersz = '#F8F9FC'
    Akcent = '#2563EB'; AkcentHover = '#1D4ED8'; AkcentWcisniety = '#1E40AF'; AkcentJasny = '#EEF2FF'; AkcentJasnyHover = '#E0E7FF'; AkcentTekst = '#1D4ED8'
    Zielony = '#16A34A'; ZielonyHover = '#15803D'; Ostrzezenie = '#B45309'; Czerwony = '#B91C1C'; Ai = '#0F5E59'
    Tor = '#EEF0F5'; SzaryPasek = '#A3A9B8'; Pole = '#B8BDC9'; PrzelacznikWyl = '#B8BDC9'; KafelekChroniony = '#6B7280'
    Wylaczony = '#E5E7EB'; TekstWylaczony = '#9CA3AF'; Segment = '#E6E8EF'; SegmentWybrany = '#FFFFFF'
    Nawigacja = '#161A2B'; NawHover = '#222740'; NawWybrany = '#2B3254'; NawTekst = '#C3C8DA'; NawSlaby = '#A7AEC6'
    NotkaTlo = '#FFFBEB'; NotkaRamka = '#FDE68A'; NotkaTekst = '#78350F'
    SukcesTlo = '#F0FDF4'; SukcesRamka = '#BBF7D0'; SukcesTekst = '#166534'
    OkTlo = '#DCFCE7'; OkTekst = '#166534'; UwagaTlo = '#FEF3C7'; UwagaTekst = '#92400E'; BladTlo = '#FEE2E2'; BladTekst = '#991B1B'; NeutralTlo = '#EEF0F5'; NeutralTekst = '#4B5160'
    FioletTlo = '#F3E8FF'; FioletTekst = '#6B21A8'; BlekitTlo = '#E0F2FE'; BlekitTekst = '#075985'
}
$PaletaCiemna = @{
    Tlo = '#0F1220'; Karta = '#181C2C'; Kafelek = '#20253A'; Ramka = '#262B40'; RamkaPrzycisku = '#343A55'; Linia = '#20253A'
    Tekst = '#E6E8F0'; TekstSlaby = '#A3A9BD'; Wiersz = '#1D2133'
    Akcent = '#3B82F6'; AkcentHover = '#2563EB'; AkcentWcisniety = '#1D4ED8'; AkcentJasny = '#1E2A4D'; AkcentJasnyHover = '#25345F'; AkcentTekst = '#BFD0FF'
    Zielony = '#22C55E'; ZielonyHover = '#16A34A'; Ostrzezenie = '#F59E0B'; Czerwony = '#EF4444'; Ai = '#5EEAD4'
    Tor = '#2A3048'; SzaryPasek = '#4B5368'; Pole = '#4B5368'; PrzelacznikWyl = '#3A4160'; KafelekChroniony = '#4B5563'
    Wylaczony = '#2A3048'; TekstWylaczony = '#5B6378'; Segment = '#20253A'; SegmentWybrany = '#2F3652'
    Nawigacja = '#0A0C17'; NawHover = '#151933'; NawWybrany = '#1E2440'; NawTekst = '#C3C8DA'; NawSlaby = '#A3A9BD'
    NotkaTlo = '#2A2410'; NotkaRamka = '#4A3B12'; NotkaTekst = '#FCD34D'
    SukcesTlo = '#0F2A1C'; SukcesRamka = '#14532D'; SukcesTekst = '#86EFAC'
    OkTlo = '#12301F'; OkTekst = '#86EFAC'; UwagaTlo = '#3A2E12'; UwagaTekst = '#FCD34D'; BladTlo = '#3A1618'; BladTekst = '#FCA5A5'; NeutralTlo = '#2A3048'; NeutralTekst = '#A3A9BD'
    FioletTlo = '#2E1F45'; FioletTekst = '#D8B4FE'; BlekitTlo = '#0C2A3A'; BlekitTekst = '#7DD3FC'
}

$script:Styl = @{}
$paleta = if ($script:Ciemny) { $PaletaCiemna } else { $PaletaJasna }
foreach ($k in $paleta.Keys) { $script:Styl[$k] = Kolor $paleta[$k] }
$czcionki = (New-Object Drawing.Text.InstalledFontCollection).Families.Name
$script:Styl.Czcionka = New-Object Drawing.Font('Segoe UI', 10)
$script:Styl.Mala = New-Object Drawing.Font('Segoe UI', 9.25)
$script:Styl.MalaPogr = New-Object Drawing.Font('Segoe UI Semibold', 8.75)
$script:Styl.Odznaka = New-Object Drawing.Font('Segoe UI Semibold', 7.5)
$script:Styl.Kolumna = New-Object Drawing.Font('Segoe UI Semibold', 8.25)
$script:Styl.Pogrubiona = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Styl.TytulKarty = New-Object Drawing.Font('Segoe UI Semibold', 12)
$script:Styl.Srednia = New-Object Drawing.Font('Segoe UI Semibold', 13)
$script:Styl.Liczba = New-Object Drawing.Font('Segoe UI Semibold', 16)
$script:Styl.Tytul = New-Object Drawing.Font('Segoe UI Semibold', 19)
$script:Styl.Duza = New-Object Drawing.Font('Segoe UI Semibold', 30)
$script:Styl.Nav = New-Object Drawing.Font('Segoe UI', 10.5)
$script:Styl.NavWybrany = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
# Ikony z czcionki Windows 10/11; bez niej nawigacja jest po prostu bez ikon
if ($czcionki -contains 'Segoe MDL2 Assets') {
    $script:Styl.Ikony = New-Object Drawing.Font('Segoe MDL2 Assets', 12)
    $script:Styl.IkonyMale = New-Object Drawing.Font('Segoe MDL2 Assets', 7.5)
}

# Kolory linii logu (nazwy kolorow konsoli)
$KoloryOkna = if ($script:Ciemny) {
    @{ Gray = Kolor '#C9CDD8'; DarkGray = Kolor '#7C8399'; White = Kolor '#F3F4F8'; Green = Kolor '#4ADE80'; Yellow = Kolor '#FBBF24'
       Cyan = Kolor '#93B4FF'; DarkCyan = Kolor '#5EEAD4'; DarkYellow = Kolor '#E0A458' }
} else {
    @{ Gray = Kolor '#374151'; DarkGray = Kolor '#9CA3AF'; White = Kolor '#111827'; Green = Kolor '#16A34A'; Yellow = Kolor '#B45309'
       Cyan = Kolor '#2563EB'; DarkCyan = [Drawing.Color]::Teal; DarkYellow = [Drawing.Color]::Peru }
}

# Funkcje Windows: konsola, skalowanie, ciemny pasek tytulu i przewijania, postep na pasku zadan
if (-not ('LlmWin.Natywne' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace LlmWin {
    [ComImport, Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eee6f"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ITaskbarList3 {
        void HrInit(); void AddTab(IntPtr h); void DeleteTab(IntPtr h); void ActivateTab(IntPtr h); void SetActiveAlt(IntPtr h);
        void MarkFullscreenWindow(IntPtr h, [MarshalAs(UnmanagedType.Bool)] bool f);
        void SetProgressValue(IntPtr h, ulong done, ulong total);
        void SetProgressState(IntPtr h, int flags);
    }
    [ComImport, Guid("56FDF344-FD6D-11d0-958A-006097C9A090"), ClassInterface(ClassInterfaceType.None)]
    class TaskbarList { }
    public static class Natywne {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string id);
        static ITaskbarList3 pasek;
        // stan: 0 brak, 1 nieokreslony, 2 normalny, 4 blad
        public static void PostepNaPasku(IntPtr h, int stan, ulong ile, ulong z) {
            try {
                if (pasek == null) { pasek = (ITaskbarList3)new TaskbarList(); pasek.HrInit(); }
                pasek.SetProgressState(h, stan);
                if (stan == 2 || stan == 4) { pasek.SetProgressValue(h, ile, z); }
            } catch { }
        }
        public static void CiemnyPasekTytulu(IntPtr h) {
            int tak = 1;
            if (DwmSetWindowAttribute(h, 20, ref tak, 4) != 0) { DwmSetWindowAttribute(h, 19, ref tak, 4); }
        }
    }
}
'@
}

function PostepNaPasku([int]$stan, [double]$ile = 0, [double]$z = 1) {
    if ($script:UI.Okno) { [LlmWin.Natywne]::PostepNaPasku($script:UI.Okno.Handle, $stan, [uint64]$ile, [uint64][Math]::Max(1, $z)) }
}

# ---------- WYJSCIE Z RDZENIA ----------
function OknoWypisz([string]$t, [string]$kolor) {
    $box = $script:UI.Log
    if (-not $box) { return }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $(if ($KoloryOkna[$kolor]) { $KoloryOkna[$kolor] } else { $KoloryOkna.Gray })
    $box.AppendText("$t`r`n")
    $box.ScrollToCaret()
    if ($script:UI.Skanuje -and $t.Trim()) { $script:UI.Etap.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}
function OknoStatus([string]$t) {
    if ($script:UI.Status) { $script:UI.Status.Text = $t.Trim() }
    if ($script:UI.Skanuje -and $t.Trim()) { $script:UI.Etap.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}

# ---------- RYSOWANIE ----------
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

function SciezkaZaokraglona([Drawing.Rectangle]$r, [int]$promien) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Max(1, [Math]::Min($promien * 2, [Math]::Min($r.Width, $r.Height)))
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

function WypelnijZaokraglony($g, [Drawing.Rectangle]$r, [int]$promien, $tlo, $ramka) {
    $g.SmoothingMode = 'AntiAlias'
    $p = SciezkaZaokraglona $r $promien
    $b = New-Object Drawing.SolidBrush($tlo); $g.FillPath($b, $p); $b.Dispose()
    if ($ramka) { $pen = New-Object Drawing.Pen($ramka); $g.DrawPath($pen, $p); $pen.Dispose() }
    $p.Dispose()
}

function Prostokat($g, [int]$x, [int]$y, [int]$w, [int]$h, $kolor, [int]$promien = 0, $ramka = $null) {
    if ($w -le 0 -or $h -le 0) { return }
    if ($promien -le 0 -and -not $ramka) { $b = New-Object Drawing.SolidBrush($kolor); $g.FillRectangle($b, $x, $y, $w, $h); $b.Dispose(); return }
    WypelnijZaokraglony $g (New-Object Drawing.Rectangle($x, $y, $w, $h)) $promien $kolor $ramka
}

function Linia($g, $kolor, [int]$x1, [int]$y1, [int]$x2, [int]$y2) {
    $pen = New-Object Drawing.Pen($kolor); $g.DrawLine($pen, $x1, $y1, $x2, $y2); $pen.Dispose()
}

# Tekst w jednej linii z wielokropkiem; poziom: Left, Right albo HorizontalCenter
function Tekst($g, [string]$t, $font, $kolor, [int]$x, [int]$y, [int]$w, [int]$h, [string]$poziom = 'Left') {
    if (-not $t -or $w -le 0) { return }
    [Windows.Forms.TextRenderer]::DrawText($g, $t, $font, (New-Object Drawing.Rectangle($x, $y, $w, $h)), $kolor,
        [Windows.Forms.TextFormatFlags]"$poziom, VerticalCenter, EndEllipsis, SingleLine, NoPrefix")
}
function TekstWiele($g, [string]$t, $font, $kolor, [int]$x, [int]$y, [int]$w, [int]$h) {
    if (-not $t -or $w -le 0) { return }
    [Windows.Forms.TextRenderer]::DrawText($g, $t, $font, (New-Object Drawing.Rectangle($x, $y, $w, $h)), $kolor,
        [Windows.Forms.TextFormatFlags]'Left, Top, WordBreak, EndEllipsis, NoPrefix')
}
function SzerTekstu([string]$t, $font) {
    [Windows.Forms.TextRenderer]::MeasureText($t, $font, (New-Object Drawing.Size(9999, 999)), [Windows.Forms.TextFormatFlags]'SingleLine, NoPrefix').Width
}

# Zaokraglona etykieta (pewnosc, ochrona). Zwraca szerokosc.
function Pigulka($g, [string]$t, [int]$x, [int]$srodek, $tlo, $kolor, [string]$ikona = '') {
    $s = $script:Styl
    $ik = if ($ikona -and $s.IkonyMale) { Px 16 } else { 0 }
    $w = (SzerTekstu $t $s.MalaPogr) + (Px 16) + $ik
    $h = Px 22
    $y = $srodek - [int]($h / 2)
    Prostokat $g $x $y $w $h $tlo ([int]($h / 2))
    if ($ik) { Tekst $g $ikona $s.IkonyMale $kolor ($x + (Px 8)) $y $ik $h }
    Tekst $g $t $s.MalaPogr $kolor ($x + (Px 8) + $ik) $y ($w - (Px 16) - $ik + (Px 2)) $h
    $w
}

# Pole wyboru rysowane (18 px przy 100%)
function PoleWyboru($g, [int]$x, [int]$y, [bool]$zazn, [bool]$wyl) {
    $s = $script:Styl; $b = Px 18
    if ($zazn) {
        Prostokat $g $x $y $b $b $(if ($wyl) { $s.TekstWylaczony } else { $s.Akcent }) (Px 4)
        $pen = New-Object Drawing.Pen([Drawing.Color]::White, [float](Px 2))
        $g.DrawLines($pen, [Drawing.Point[]]@(
            (New-Object Drawing.Point(($x + (Px 4)), ($y + (Px 9)))),
            (New-Object Drawing.Point(($x + (Px 8)), ($y + (Px 13)))),
            (New-Object Drawing.Point(($x + (Px 14)), ($y + (Px 5))))))
        $pen.Dispose()
    }
    else { Prostokat $g $x $y ($b - 1) ($b - 1) $(if ($wyl) { $s.Wylaczony } else { $s.Karta }) (Px 4) $s.Pole }
}

# Przelacznik jak w Ustawieniach Windows (48 x 28 px przy 100%)
function Przelacznik($g, [int]$x, [int]$y, [bool]$wl, [bool]$wyl) {
    $s = $script:Styl
    $tor = if ($wl) { $s.Akcent } else { $s.PrzelacznikWyl }
    $galka = [Drawing.Color]::White
    if ($wyl) { $tor = [Drawing.Color]::FromArgb(110, $tor); $galka = [Drawing.Color]::FromArgb(170, $galka) }
    Prostokat $g $x $y (Px 48) (Px 28) $tor (Px 14)
    $gx = if ($wl) { $x + (Px 23) } else { $x + (Px 3) }
    Prostokat $g $gx ($y + (Px 3)) (Px 22) (Px 22) $galka (Px 11)
}

# Karta: panel z zaokraglonymi rogami. Rogi maluje kolorem rodzica, wnetrze swoim BackColor.
function Karta([hashtable]$w = @{}, [switch]$BezRamki) {
    $k = Kontrolka Panel $w
    if (-not $w.ContainsKey('BackColor')) { $k.BackColor = $script:Styl.Karta }
    if (-not $w.ContainsKey('Padding')) { $k.Padding = Marg 18 16 18 16 }
    PodwojnyBufor $k
    $k.AccessibleDescription = $(if ($BezRamki) { 'bez-ramki' } else { '' })
    $k.Add_Paint({
        $_.Graphics.Clear($this.Parent.BackColor)
        $r = New-Object Drawing.Rectangle(0, 0, ($this.Width - 1), ($this.Height - 1))
        WypelnijZaokraglony $_.Graphics $r (Px 12) $this.BackColor $(if ($this.AccessibleDescription -ne 'bez-ramki') { $script:Styl.Ramka })
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
    if (-not $w.ContainsKey('Font')) { $b.Font = $script:Styl.Pogrubiona }
    $b.Tag = @{ Styl = $styl; Hover = $false; Wcisniety = $false; Wybrany = $false; Ikona = $w.AccessibleName }
    $b.Add_MouseEnter({ $this.Tag.Hover = $true; $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Tag.Wcisniety = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Tag.Wcisniety = $true; $this.Invalidate() })
    $b.Add_MouseUp({ $this.Tag.Wcisniety = $false; $this.Invalidate() })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({ RysujPrzycisk $this $_.Graphics })
    $b
}

function RysujPrzycisk($b, $g) {
    $s = $script:Styl; $t = $b.Tag
    $g.Clear($b.Parent.BackColor)
    $r = New-Object Drawing.Rectangle(0, 0, ($b.Width - 1), ($b.Height - 1))
    $ramka = $null
    $font = $b.Font
    switch ($t.Styl) {
        'nav' {
            $tlo = if ($t.Wybrany) { $s.NawWybrany } elseif ($t.Hover) { $s.NawHover } else { $s.Nawigacja }
            $kolor = if ($t.Wybrany) { [Drawing.Color]::White } else { $s.NawTekst }
            if ($t.Wybrany) { $font = $s.NavWybrany }
        }
        'drugi' {
            $tlo = if (-not $b.Enabled) { $s.Wylaczony } elseif ($t.Wcisniety -or $t.Hover) { $s.AkcentJasnyHover } else { $s.AkcentJasny }
            $kolor = if ($b.Enabled) { $s.AkcentTekst } else { $s.TekstWylaczony }
        }
        'ramka' {
            $tlo = if ($b.Enabled -and ($t.Wcisniety -or $t.Hover)) { $s.Kafelek } else { $s.Karta }
            $kolor = if ($b.Enabled) { $s.Tekst } else { $s.TekstWylaczony }
            $ramka = $s.RamkaPrzycisku
        }
        'link' {
            $tlo = $b.Parent.BackColor
            $kolor = if (-not $b.Enabled) { $s.TekstWylaczony } elseif ($t.Hover) { $s.AkcentHover } else { $s.AkcentTekst }
        }
        default {
            $zielony = $t.Styl -eq 'zielony'
            $tlo = if (-not $b.Enabled) { $s.Wylaczony }
                   elseif ($t.Wcisniety) { if ($zielony) { $s.ZielonyHover } else { $s.AkcentWcisniety } }
                   elseif ($t.Hover) { if ($zielony) { $s.ZielonyHover } else { $s.AkcentHover } }
                   else { if ($zielony) { $s.Zielony } else { $s.Akcent } }
            $kolor = if ($b.Enabled) { [Drawing.Color]::White } else { $s.TekstWylaczony }
        }
    }
    if ($t.Styl -ne 'link') { WypelnijZaokraglony $g $r (Px 8) $tlo $ramka }
    if ($t.Styl -eq 'nav') {
        if ($t.Wybrany) { Prostokat $g 0 (Px 12) (Px 3) ($b.Height - (Px 24)) $s.Akcent }
        $x = Px 16
        if ($s.Ikony -and $t.Ikona) {
            [Windows.Forms.TextRenderer]::DrawText($g, $t.Ikona, $s.Ikony, (New-Object Drawing.Rectangle((Px 14), 0, (Px 24), $b.Height)), $kolor, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter')
            $x = Px 48
        }
        Tekst $g $b.Text $font $kolor $x 0 ($b.Width - $x - (Px 6)) $b.Height
    }
    elseif ($t.Styl -eq 'link') { Tekst $g $b.Text $font $kolor 0 0 $b.Width $b.Height }
    else { Tekst $g $b.Text $font $kolor (Px 6) 0 ($b.Width - (Px 12)) $b.Height 'HorizontalCenter' }
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

# ---------- LISTA RYSOWANA ----------
# Przewijana lista wierszy o dowolnej wysokosci. Wiersz to hashtable z H (wysokosc), Sekcja (naglowek grupy)
# albo Obj (dane). Rysuje blok Rysuj($g, $wiersz, $prostokat, $hover); klik i dwuklik ida do Klik/Dwuklik.
function ListaWierszy([scriptblock]$rysuj) {
    $p = Kontrolka Panel @{ Dock = 'Fill'; AutoScroll = $true; BackColor = $script:Styl.Karta }
    PodwojnyBufor $p
    $p.Tag = @{ Wiersze = @(); Rysuj = $rysuj; Hover = -1; Klik = $null; Dwuklik = $null; Kursor = $null; Podpowiedz = $null; Pusty = '' }
    $p.Add_Paint({
        $g = $_.Graphics; $t = $this.Tag; $s = $script:Styl
        $g.Clear($this.BackColor)
        $szer = $this.ClientSize.Width
        if (-not $t.Wiersze.Count) {
            TekstWiele $g $t.Pusty $s.Czcionka $s.TekstSlaby (Px 20) (Px 18) ($szer - (Px 40)) (Px 80)
            return
        }
        $dy = $this.AutoScrollPosition.Y
        $gora = -$dy; $dol = $gora + $this.ClientSize.Height
        for ($i = 0; $i -lt $t.Wiersze.Count; $i++) {
            $w = $t.Wiersze[$i]
            if ($w.Y + $w.H -lt $gora) { continue }
            if ($w.Y -gt $dol) { break }
            $r = New-Object Drawing.Rectangle(0, ($w.Y + $dy), $szer, $w.H)
            & $t.Rysuj $g $w $r ($i -eq $t.Hover -and -not $w.Sekcja)
        }
    })
    $p.Add_Resize({ $this.Invalidate() })
    $p.Add_MouseMove({
        $t = $this.Tag
        $i = WierszPod $this $_.Y
        $w = if ($i -ge 0) { $t.Wiersze[$i] }
        $reka = $false
        if ($w -and -not $w.Sekcja -and $t.Klik) {
            $reka = if ($t.Kursor) { [bool](& $t.Kursor $w $_.X (ProstokatWiersza $this $w)) } else { $true }
        }
        $this.Cursor = $(if ($reka) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default })
        if ($i -ne $t.Hover) {
            $t.Hover = $i
            $this.Invalidate()
            $tekst = if ($w -and -not $w.Sekcja -and $t.Podpowiedz) { & $t.Podpowiedz $w } else { '' }
            $script:UI.Podpowiedz.SetToolTip($this, "$tekst")
        }
    })
    $p.Add_MouseLeave({ $this.Tag.Hover = -1; $this.Invalidate() })
    $p.Add_MouseClick({
        if ($_.Button -ne 'Left') { return }
        $t = $this.Tag
        $i = WierszPod $this $_.Y
        if ($i -lt 0 -or -not $t.Klik) { return }
        $w = $t.Wiersze[$i]
        if (-not $w.Sekcja) { & $t.Klik $w $_.X (ProstokatWiersza $this $w) }
    })
    $p.Add_MouseDoubleClick({
        $t = $this.Tag
        $i = WierszPod $this $_.Y
        if ($i -ge 0 -and $t.Dwuklik -and -not $t.Wiersze[$i].Sekcja) { & $t.Dwuklik $t.Wiersze[$i] }
    })
    $script:UI.Przewijane += $p
    $p
}

function UstawWiersze($lista, $wiersze) {
    $y = 0
    $tab = @($wiersze | Where-Object { $_ })
    foreach ($w in $tab) { $w.Y = $y; $y += $w.H }
    $lista.Tag.Wiersze = $tab
    $lista.Tag.Hover = -1
    $lista.AutoScrollMinSize = New-Object Drawing.Size(0, $y)
    $lista.Invalidate()
}

function WierszPod($lista, [int]$y) {
    $yy = $y - $lista.AutoScrollPosition.Y
    $i = 0
    foreach ($w in $lista.Tag.Wiersze) {
        if ($yy -ge $w.Y -and $yy -lt $w.Y + $w.H) { return $i }
        $i++
    }
    -1
}
function ProstokatWiersza($lista, $w) { New-Object Drawing.Rectangle(0, ($w.Y + $lista.AutoScrollPosition.Y), $lista.ClientSize.Width, $w.H) }

# Wspolne elementy wierszy: tlo pod kursorem, linia nad wierszem, naglowek grupy
function TloWiersza($g, $r, [bool]$hover) {
    $s = $script:Styl
    if ($hover) { Prostokat $g 0 $r.Y $r.Width $r.Height $s.Wiersz }
    Linia $g $s.Linia (Px 18) $r.Y ($r.Right - (Px 18)) $r.Y
}
function RysujSekcje($g, $w, $r) {
    $s = $script:Styl
    $prawy = if ($w.Prawy) { & $w.Prawy } else { '' }
    $szerP = if ($prawy) { (SzerTekstu $prawy $s.Mala) + (Px 4) } else { 0 }
    Tekst $g $w.Tekst $s.Pogrubiona $s.AkcentTekst (Px 18) ($r.Y + (Px 8)) ($r.Width - (Px 50) - $szerP) ($r.Height - (Px 8))
    Tekst $g $prawy $s.Mala $s.TekstSlaby ($r.Width - (Px 18) - $szerP) ($r.Y + (Px 8)) $szerP ($r.Height - (Px 8)) 'Right'
}

# ---------- STAN ----------
# Blokuje przyciski na czas pracy i pokazuje pasek postepu
function Zajety([bool]$z) {
    $script:Pracuje = $z
    foreach ($b in $script:UI.Akcje) { if ($b) { $b.Enabled = -not $z } }
    $script:UI.Pasek.Visible = $z
    $script:UI.Okno.Cursor = $(if ($z) { [Windows.Forms.Cursors]::AppStarting } else { [Windows.Forms.Cursors]::Default })
    $script:UI.ListaDyskow.Invalidate()
    if (-not $z) { UstawPrzyciski }
    [Windows.Forms.Application]::DoEvents()
}

# Przycisk wlaczony tylko wtedy, gdy ma sens (po skanie, z AI, bez trybu podgladu)
function UstawPrzyciski {
    $u = $script:UI
    $ai = -not $BezLLM
    $z = $script:Zeskanowano
    $u.BtnWyjasnij.Enabled = $z -and $ai -and [bool]@($script:Pozostalosci).Count
    $u.BtnWyczysc.Enabled = $z -and -not $Podglad -and -not $script:PoCzyszczeniu
    $u.BtnOdRazu.Enabled = $u.BtnWyczysc.Enabled
    $u.BtnZalecane.Enabled = $z -and -not $script:PoCzyszczeniu
    $u.BtnOdznacz.Enabled = $u.BtnZalecane.Enabled
    $u.BtnAnalizuj.Enabled = $z
    $u.BtnAnalizaAi.Enabled = $z -and $ai -and [bool]$u.AnalizaDane
    $u.BtnWyslij.Enabled = $ai
    $u.BtnAutoAi.Enabled = $ai -and [bool]$script:Autostart
    $u.BtnSkan.Text = $(if ($z) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj' 'Scan' })
    $u.BtnStart.Visible = (-not $z) -or [bool]$script:PoCzyszczeniu
    $u.BtnStart.Text = $(if ($z) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj teraz' 'Scan now' })
    $u.BtnDoPlanu.Visible = $z -and -not $script:PoCzyszczeniu
    $u.BtnOdRazu.Visible = $u.BtnDoPlanu.Visible
}

# Akcja przycisku: blokada okna, obsluga bledow
function Akcja([scriptblock]$sb) {
    Zajety $true
    try { & $sb }
    catch {
        Log "Blad okna: $($_.Exception.Message) $($_.ScriptStackTrace)"
        Komunikat ((L 'Wystąpił błąd: {0}' 'An error occurred: {0}') -f $_.Exception.Message) 'Error'
    }
    finally { Zajety $false }
}

function PokazStrone([string]$id) {
    if ($script:Czyszczenie -and $id -ne 'czyszczenie') { return }
    $script:Strona = $id
    foreach ($k in $script:UI.Strony.Keys) { $script:UI.Strony[$k].Visible = ($k -eq $id) }
    foreach ($k in $script:UI.Nav.Keys) { $script:UI.Nav[$k].Tag.Wybrany = ($k -eq $id); $script:UI.Nav[$k].Invalidate() }
    $script:UI.Strony[$id].BringToFront()
    if ($id -eq 'czat') { $script:UI.Pytanie.Focus() }
    # Lista autostartu wczytuje sie przy pierwszym wejsciu na strone (kilka sekund, bez skanu dyskow)
    if ($id -eq 'autostart' -and $null -eq $script:Autostart -and -not $script:UI.Skanuje) { $script:UI.BtnAutoOdswiez.PerformClick() }
}

# Na czas czyszczenia pasek nawigacji pokazuje tylko informacje
function ZablokujNawigacje([bool]$z) {
    $script:Czyszczenie = $z
    $script:UI.NavLista.Visible = -not $z
    $script:UI.NavInfo.Visible = $z
}

# ---------- PRZEGLAD ----------
function AktualizujPrzeglad {
    $u = $script:UI; $s = $script:Styl
    if (-not $script:Zeskanowano) { return }
    $suma = SumaZaznaczonych
    if ($script:PoCzyszczeniu) {
        $u.WynikMaly.Text = L 'Czyszczenie zakończone' 'Cleaning finished'
        $u.Wynik.Text = (L 'Zwolniono {0}' '{0} freed') -f (Rozmiar ([double]$script:WynikCzyszczenia.Suma))
        $u.Wynik.ForeColor = $s.Zielony
        $u.Etap.Text = L 'Kliknij „Skanuj ponownie”, żeby zobaczyć aktualny stan dysków.' 'Click "Scan again" to see the current state of your drives.'
    }
    elseif ($suma -gt 0) {
        $u.WynikMaly.Text = L 'Można bezpiecznie zwolnić' 'Can be freed safely'
        $u.Wynik.Text = Rozmiar $suma
        $u.Wynik.ForeColor = $s.Akcent
        $u.Etap.Text = L 'Zaznaczone są tylko rzeczy, które odtwarzają się same albo idą do Kosza. Nic nie jest usuwane bez potwierdzenia.' 'Only things that rebuild themselves or go to the Recycle Bin are selected. Nothing is deleted without your confirmation.'
    }
    else {
        $u.WynikMaly.Text = L 'Wynik skanu' 'Scan result'
        $u.Wynik.Text = L 'Komputer jest czysty' 'Your PC is clean'
        $u.Wynik.ForeColor = $s.Zielony
        $u.Etap.Text = L 'Nic nie jest zaznaczone. Plan czyszczenia pokazuje też pozycje na życzenie.' 'Nothing is selected. The cleanup plan also lists opt-in items.'
    }
    $zablokowane = [double](@($script:Kategorie | ForEach-Object { [double]$_.Zablokowane }) | Measure-Object -Sum).Sum
    $wl = @($script:Autostart | Where-Object { $_ -and $_.Wlaczony }).Count
    $u.StatyDane = @(
        @{ W = "$(@($script:Kategorie | Where-Object { $_.Bajty -gt 0 }).Count)"; O = (L 'kategorii z danymi' 'categories with data') }
        @{ W = "$(@($script:Pozostalosci).Count)"; O = (L 'pozostałości po programach' 'program leftovers') }
        @{ W = (Rozmiar $zablokowane); O = (L 'zablokowane (pliki w użyciu)' 'locked (files in use)') }
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$wl" }); O = (L 'programów w autostarcie' 'startup apps') })
    $u.Staty.Visible = $true
    $u.Staty.Invalidate()

    # Slupki: najwieksze kategorie, pozostalosci razem, reszta razem
    $el = @($script:Kategorie | Where-Object { $_.Bajty -gt 0 } | ForEach-Object { @{ Nazwa = $_.Nazwa; Bajty = [double]$_.Bajty; Wybrana = [bool]$_.Wybrana } })
    $poz = @($script:Pozostalosci | Where-Object { NaKosz $_ })
    if ($poz.Count) {
        $el += @{ Nazwa = (L 'Pozostałości po programach' 'Program leftovers'); Bajty = [double]($poz | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
                  Wybrana = [bool]@($poz | Where-Object { $_.Wybrana }).Count }
    }
    $el = @($el | Sort-Object { $_.Bajty } -Descending)
    if ($el.Count -gt 7) {
        $reszta = $el[6..($el.Count - 1)]
        $el = @($el[0..5]) + @(@{ Nazwa = (L 'Pozostałe pozycje' 'Other items'); Bajty = [double]($reszta | ForEach-Object { $_.Bajty } | Measure-Object -Sum).Sum
                                  Wybrana = [bool]@($reszta | Where-Object { $_.Wybrana }).Count })
    }
    $u.SlupkiDane = $el
    $u.Slupki.Invalidate()
    AktualizujStart
}

function AktualizujStart {
    $u = $script:UI
    if ($null -eq $script:Autostart) {
        $u.StartTekst.Text = L 'Sprawdź, które programy uruchamiają się przy logowaniu i spowalniają start Windows.' 'See which programs start when you sign in and slow down Windows startup.'
        return
    }
    $wl = @($script:Autostart | Where-Object { $_.Wlaczony })
    $t = (L 'Przy logowaniu uruchamia się programów: {0}.' 'Programs starting at sign-in: {0}.') -f $wl.Count
    $zbedne = @($wl | Where-Object { $_.Ai -and $_.Ai -like "*$($RadyAutostartu[1])*" }).Count
    if ($zbedne) { $t += ' ' + ((L 'Według AI {0} z nich można wyłączyć.' 'According to AI, {0} of them can be turned off.') -f $zbedne) }
    elseif ($wl.Count) { $t += ' ' + (L 'Wyłączenie niepotrzebnych przyspieszy start Windows.' 'Turning off the ones you do not need speeds up Windows startup.') }
    $u.StartTekst.Text = $t
    $u.Staty.Invalidate()
}

function RysujStaty($g, $p) {
    $s = $script:Styl
    $dane = @($script:UI.StatyDane)
    $odst = Px 12
    $w = [int](($p.Width - $odst) / 2); $h = [int](($p.Height - $odst) / 2)
    for ($i = 0; $i -lt [Math]::Min(4, $dane.Count); $i++) {
        $x = ($i % 2) * ($w + $odst); $y = [Math]::Floor($i / 2) * ($h + $odst)
        Prostokat $g $x $y $w $h $s.Kafelek (Px 10)
        Tekst $g $dane[$i].W $s.Liczba $s.Tekst ($x + (Px 16)) ($y + (Px 8)) ($w - (Px 24)) (Px 32)
        Tekst $g $dane[$i].O $s.Mala $s.TekstSlaby ($x + (Px 16)) ($y + (Px 38)) ($w - (Px 24)) (Px 22)
    }
}

function RysujSlupki($g, $p) {
    $s = $script:Styl
    $w = $p.Width
    Tekst $g (L 'Co zajmuje miejsce do zwolnienia' 'What takes up space you can free') $s.TytulKarty $s.Tekst 0 0 ($w - (Px 230)) (Px 28)
    $dane = @($script:UI.SlupkiDane)
    if (-not $script:Zeskanowano -or -not $dane.Count) {
        $t = if ($script:Zeskanowano) { L 'Skan nie znalazł nic do zwolnienia.' 'The scan found nothing to free.' }
             else { L 'Po skanie zobaczysz tu największe pozycje planu czyszczenia, od największej.' 'After the scan you will see the largest cleanup plan items here, largest first.' }
        TekstWiele $g $t $s.Czcionka $s.TekstSlaby 0 (Px 44) $w (Px 60)
        return
    }
    Tekst $g (L 'szary pasek = niezaznaczone w planie' 'grey bar = not selected in the plan') $s.Mala $s.TekstSlaby ($w - (Px 230)) 0 (Px 230) (Px 28) 'Right'
    $max = [Math]::Max(1, ($dane | ForEach-Object { $_.Bajty } | Measure-Object -Maximum).Maximum)
    $szerN = [Math]::Min((Px 210), [int]($w * 0.38))
    $xT = $szerN + (Px 14); $szerR = Px 76
    $szerT = $w - $xT - $szerR - (Px 14)
    $y = Px 44
    foreach ($d in $dane) {
        if ($y + (Px 26) -gt $p.Height) { break }
        Tekst $g $d.Nazwa $s.Czcionka $s.Tekst 0 $y $szerN (Px 26)
        Prostokat $g $xT ($y + (Px 7)) $szerT (Px 12) $s.Tor (Px 6)
        $dl = [int][Math]::Max((Px 6), $szerT * $d.Bajty / $max)
        Prostokat $g $xT ($y + (Px 7)) $dl (Px 12) $(if ($d.Wybrana) { $s.Akcent } else { $s.SzaryPasek }) (Px 6)
        Tekst $g (Rozmiar $d.Bajty) $s.Pogrubiona $s.Tekst ($w - $szerR) $y $szerR (Px 26) 'Right'
        $y += Px 34
    }
}

function RysujDysk($g, $w, $r, [bool]$hover) {
    $s = $script:Styl; $d = $w.Obj
    $wyl = $d.Sys -or $script:Pracuje
    $y = $r.Y + (Px 8)
    PoleWyboru $g (Px 2) ($y + (Px 2)) ([bool]$d.Zazn) $wyl
    $nazwa = "$($d.D.DeviceID)  $(if ($d.D.VolumeName) { $d.D.VolumeName } else { L 'bez nazwy' 'no label' })"
    if ($d.Sys) { $nazwa += L '  (systemowy)' '  (system)' }
    $wolne = (L 'wolne {0} z {1}' '{0} free of {1}') -f (Rozmiar $d.D.FreeSpace), (Rozmiar $d.D.Size)
    $szerW = SzerTekstu $wolne $s.Mala
    Tekst $g $nazwa $s.Pogrubiona $s.Tekst (Px 30) $y ($r.Width - (Px 36) - $szerW) (Px 22)
    Tekst $g $wolne $s.Mala $s.TekstSlaby ($r.Width - $szerW - (Px 2)) $y $szerW (Px 22) 'Right'
    $zajete = if ($d.D.Size -gt 0) { 1 - [double]$d.D.FreeSpace / [double]$d.D.Size } else { 0 }
    $szerT = $r.Width - (Px 32)
    Prostokat $g (Px 30) ($y + (Px 30)) $szerT (Px 8) $s.Tor (Px 4)
    $k = if ($zajete -gt 0.9) { $s.Czerwony } elseif ($zajete -gt 0.75) { $s.Ostrzezenie } else { $s.Akcent }
    Prostokat $g (Px 30) ($y + (Px 30)) ([int][Math]::Max((Px 8), $szerT * $zajete)) (Px 8) $k (Px 4)
}

# ---------- PLAN ----------
function KolorPewnosci([string]$p) {
    $s = $script:Styl
    switch ($p) {
        'wysoka' { @{ T = (NazwaPewnosci $p); Tlo = $s.OkTlo; Kolor = $s.OkTekst } }
        'srednia' { @{ T = (NazwaPewnosci $p); Tlo = $s.UwagaTlo; Kolor = $s.UwagaTekst } }
        'niska' { @{ T = (NazwaPewnosci $p); Tlo = $s.BladTlo; Kolor = $s.BladTekst } }
        default { @{ T = (L 'na życzenie' 'opt-in'); Tlo = $s.NeutralTlo; Kolor = $s.NeutralTekst } }
    }
}

function OdznakaPlanu($o, [bool]$kat) {
    $s = $script:Styl
    if ($kat) { return @{ T = (L 'KAT' 'CAT'); Tlo = $s.AkcentJasny; Kolor = $s.AkcentTekst } }
    switch ($o.Typ) {
        'folder' { @{ T = 'DIR'; Tlo = $s.UwagaTlo; Kolor = $s.UwagaTekst } }
        'plik' {
            if ($o.Sciezka -like '*.lnk') { @{ T = 'LNK'; Tlo = $s.BlekitTlo; Kolor = $s.BlekitTekst } }
            else { @{ T = (L 'PLIK' 'FILE'); Tlo = $s.BlekitTlo; Kolor = $s.BlekitTekst } }
        }
        'zadanie' { @{ T = (L 'ZAD' 'TASK'); Tlo = $s.OkTlo; Kolor = $s.OkTekst } }
        default { @{ T = 'REG'; Tlo = $s.FioletTlo; Kolor = $s.FioletTekst } }
    }
}

# Opis pozycji planu w drugiej linii: tekst i kolor
function OpisPlanu($o, [bool]$kat) {
    $s = $script:Styl
    if ($kat) {
        if ($o.Blokada) { return @{ T = "! $($o.Blokada)"; K = $s.Ostrzezenie } }
        if ($o.Uwaga) { return @{ T = $o.Uwaga; K = $s.TekstSlaby } }
        return @{ T = $o.Opis; K = $s.TekstSlaby }
    }
    if ($o.Ai) { return @{ T = "$EtykietaAi`: $($o.Ai)"; K = $s.Ai } }
    @{ T = $o.Dlaczego; K = $s.TekstSlaby }
}

# Uklad kolumn listy planu (ten sam dla naglowka i wierszy)
function KolumnyPlanu([int]$szer) {
    $pew = $szer - (Px 18) - (Px 110)
    $roz = $pew - (Px 12) - (Px 190)
    @{ Pole = (Px 20); Odznaka = (Px 54); Nazwa = (Px 98); SzerNazwy = ($roz - (Px 16) - (Px 98)); Rozmiar = $roz; Pewnosc = $pew }
}

function RysujWierszPlanu($g, $w, $r, [bool]$hover) {
    if ($w.Sekcja) { RysujSekcje $g $w $r; return }
    $s = $script:Styl; $o = $w.Obj; $kat = [bool]$w.Kat
    TloWiersza $g $r $hover
    $k = KolumnyPlanu $r.Width
    $sr = $r.Y + [int]($r.Height / 2)
    $wyl = [bool]($o.Blokada -and -not $o.Wybrana)
    PoleWyboru $g $k.Pole ($sr - (Px 9)) ([bool]$o.Wybrana) ($wyl -or [bool]$script:PoCzyszczeniu)
    $odz = OdznakaPlanu $o $kat
    Prostokat $g $k.Odznaka ($sr - (Px 16)) (Px 32) (Px 32) $odz.Tlo (Px 8)
    Tekst $g $odz.T $s.Odznaka $odz.Kolor $k.Odznaka ($sr - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter'
    $nazwa = if ($kat) { $o.Nazwa } else { PokazPozostalosc $o }
    $opis = OpisPlanu $o $kat
    Tekst $g $nazwa $s.Pogrubiona $(if ($wyl) { $s.TekstSlaby } else { $s.Tekst }) $k.Nazwa ($sr - (Px 22)) $k.SzerNazwy (Px 22)
    Tekst $g $opis.T $s.Mala $opis.K $k.Nazwa ($sr + (Px 1)) $k.SzerNazwy (Px 20)
    $mierzalny = if ($kat) { MierzalnaKategoria $o } else { NaKosz $o }
    $roz = if ($kat) { RozmiarKategorii $o } else { RozmiarPozostalosci $o }
    $szerBar = Px 100
    if ($mierzalny) {
        Prostokat $g $k.Rozmiar ($sr - (Px 3)) $szerBar (Px 6) $s.Tor (Px 3)
        $dl = [int][Math]::Max((Px 4), $szerBar * [double]$o.Bajty / [Math]::Max(1, $w.Max))
        Prostokat $g $k.Rozmiar ($sr - (Px 3)) $dl (Px 6) $(if ($o.Wybrana) { $s.Akcent } else { $s.SzaryPasek }) (Px 3)
    }
    Tekst $g $roz $s.Pogrubiona $(if ($mierzalny) { $s.Tekst } else { $s.TekstSlaby }) ($k.Rozmiar + $szerBar) ($sr - (Px 12)) (Px 90) (Px 24) 'Right'
    $pew = if ($kat) { if ($o.TylkoRecznie) { 'reczne' } } else { $o.Pewnosc }
    if ($pew) { $p = KolorPewnosci $pew; [void](Pigulka $g $p.T $k.Pewnosc $sr $p.Tlo $p.Kolor) }
}

function RysujKolumnyPlanu($g, $p) {
    $s = $script:Styl
    $k = KolumnyPlanu $script:UI.LvPlan.ClientSize.Width
    $h = $p.Height
    Tekst $g (L 'POZYCJA' 'ITEM') $s.Kolumna $s.TekstSlaby $k.Nazwa 0 (Px 200) $h
    Tekst $g (L 'ROZMIAR' 'SIZE') $s.Kolumna $s.TekstSlaby $k.Rozmiar 0 (Px 190) $h
    Tekst $g (L 'PEWNOŚĆ' 'CONFIDENCE') $s.Kolumna $s.TekstSlaby $k.Pewnosc 0 (Px 110) $h
    Linia $g $s.Ramka 0 ($h - 1) $p.Width ($h - 1)
}

function PasujeDoFiltra($o, [bool]$kat) {
    switch ($script:FiltrPlanu) {
        'zaznaczone' { if (-not $o.Wybrana) { return $false } }
        'reczne' { if (-not ($o.TylkoRecznie -or $o.Pewnosc -eq 'niska')) { return $false } }
    }
    $q = $script:UI.Szukaj.Text.Trim()
    if (-not $q) { return $true }
    $t = if ($kat) { "$($o.Nazwa) $($o.Opis) $($o.Uwaga)" } else { "$(PokazPozostalosc $o) $($o.Dlaczego) $($o.Ai)" }
    $t.IndexOf($q, [StringComparison]::CurrentCultureIgnoreCase) -ge 0
}

function SumaGrupy($lista) {
    $z = @($lista | Where-Object { $_.Wybrana })
    $b = [double]($z | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
    if (-not $z.Count) { return L 'nic nie zaznaczono' 'nothing selected' }
    if ($b -gt 0) { (L 'zaznaczone {0}' '{0} selected') -f (Rozmiar $b) } else { (L 'zaznaczone: {0}' 'selected: {0}') -f $z.Count }
}

function WypelnijPlan {
    $lv = $script:UI.LvPlan
    $kat = @($script:Kategorie | Where-Object { $_.Bajty -gt 0 -or $_.Wybrana -or ($_.Typ -in 'dns', 'dism', 'docker', 'dockerall') } | Sort-Object { [double]$_.Bajty } -Descending)
    $poz = @(@($script:Pozostalosci | Where-Object { NaKosz $_ } | Sort-Object { [double]$_.Bajty } -Descending) +
             @($script:Pozostalosci | Where-Object { -not (NaKosz $_) }))
    $max = [double](@($kat) + @($poz) | ForEach-Object { [double]$_.Bajty } | Measure-Object -Maximum).Maximum
    $wiersze = [System.Collections.Generic.List[object]]::new()
    $wk = @($kat | Where-Object { PasujeDoFiltra $_ $true })
    if ($wk.Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 40); Tekst = (L 'Kategorie czyszczenia - odtwarzają się same' 'Cleanup categories - they rebuild themselves')
                        Prawy = { SumaGrupy $script:Kategorie } })
        foreach ($k in $wk) { $wiersze.Add(@{ H = (Px 60); Obj = $k; Kat = $true; Max = $max }) }
    }
    $wp = @($poz | Where-Object { PasujeDoFiltra $_ $false })
    if ($wp.Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 44); Tekst = (L 'Pozostałości po odinstalowanych programach i grach' 'Leftovers of uninstalled programs and games')
                        Prawy = { SumaGrupy $script:Pozostalosci } })
        foreach ($p in $wp) { $wiersze.Add(@{ H = (Px 60); Obj = $p; Kat = $false; Max = $max }) }
    }
    $lv.Tag.Pusty = if (-not $script:Zeskanowano) { L 'Plan pojawi się po skanie. Wróć do Przeglądu i kliknij „Skanuj”.' 'The plan appears after a scan. Go back to Overview and click "Scan".' }
                    else { L 'Nic nie pasuje do wyszukiwania albo filtra.' 'Nothing matches the search or filter.' }
    UstawWiersze $lv $wiersze
    AktualizujSume
}

function AktualizujSume {
    $u = $script:UI
    $wybrane = @(@($script:Kategorie) + @($script:Pozostalosci) | Where-Object { $_ -and $_.Wybrana })
    $u.Suma.Text = (L 'Zaznaczone: {0}' 'Selected: {0}') -f (Rozmiar (SumaZaznaczonych))
    $t = (L 'Pozycji: {0}' 'Items: {0}') -f $wybrane.Count
    $zabl = SumaZablokowanych
    if ($zabl) { $t += ' · ' + ((L '{0} zablokowane przez działające programy' '{0} locked by running programs') -f (Rozmiar $zabl)) }
    $u.SumaOpis.Text = $t
    $u.LvPlan.Invalidate()
    AktualizujPrzeglad
}

# ---------- ANALIZA ----------
function RysujWierszAnalizy($g, $w, $r, [bool]$hover) {
    if ($w.Sekcja) { RysujSekcje $g $w $r; return }
    $s = $script:Styl; $p = $w.Obj
    TloWiersza $g $r $hover
    $sr = $r.Y + [int]($r.Height / 2)
    Tekst $g (Rozmiar $p.Bajty) $s.Pogrubiona $s.Tekst (Px 18) ($sr - (Px 12)) (Px 84) (Px 24) 'Right'
    $data = if ($p.Ostatnio -gt [datetime]'1980-01-01') { $p.Ostatnio.ToString('yyyy-MM-dd') } else { '' }
    Tekst $g $data $s.Mala $s.TekstSlaby (Px 118) ($sr - (Px 12)) (Px 90) (Px 24)
    $sciezka = $p.Sciezka
    if ($p.Reszta) { $sciezka += L '  (pliki poza wymienionymi podfolderami)' '  (files outside the listed subfolders)' }
    $x = Px 214; $szer = $r.Width - $x - (Px 18)
    Tekst $g $sciezka $s.Czcionka $s.Tekst $x ($sr - (Px 21)) $szer (Px 21)
    if ($p.Ai) { Tekst $g "$EtykietaAi`: $($p.Ai)" $s.Mala $s.Ai $x ($sr + (Px 1)) $szer (Px 20) }
    elseif ($p.Podpowiedz) { Tekst $g $p.Podpowiedz $s.Mala $s.TekstSlaby $x ($sr + (Px 1)) $szer (Px 20) }
}

function WypelnijAnalize($a) {
    $wiersze = [System.Collections.Generic.List[object]]::new()
    if (@($a.Foldery).Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 40); Tekst = (L 'Największe foldery' 'Largest folders') })
        foreach ($p in $a.Foldery) { $wiersze.Add(@{ H = (Px 54); Obj = $p }) }
    }
    if (@($a.Pliki).Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 44); Tekst = (L 'Największe pliki' 'Largest files') })
        foreach ($p in $a.Pliki) { $wiersze.Add(@{ H = (Px 54); Obj = $p }) }
    }
    $script:UI.LvAnaliza.Tag.Pusty = L 'Na tym dysku nie ma dużych folderów ani plików.' 'There are no large folders or files on this drive.'
    UstawWiersze $script:UI.LvAnaliza $wiersze
    $script:UI.AnalizaDane = $a
    $info = (L 'Dysk {0}: zajęte {1} z {2}, wolne {3}. Tylko do wglądu - nic stąd nie jest usuwane. Dwuklik otwiera folder.' 'Drive {0}: {1} used of {2}, {3} free. Read-only - nothing here is deleted. Double-click opens the folder.') -f
        $a.Litera, (Rozmiar ($a.Rozmiar - $a.Wolne)), (Rozmiar $a.Rozmiar), (Rozmiar $a.Wolne)
    if ($a.Cienie -gt 0) { $info += ' ' + ((L 'Punkty przywracania: {0}.' 'Restore points: {0}.') -f (Rozmiar $a.Cienie)) }
    $niewidoczne = ($a.Rozmiar - $a.Wolne) - $a.Zeskanowane - $a.Cienie
    if ($niewidoczne -gt 2GB) { $info += ' ' + ((L 'Niedostępne dla skanera: ok. {0}.' 'Not readable by the scanner: about {0}.') -f (Rozmiar $niewidoczne)) }
    $script:UI.InfoAnaliza.Text = $info
}

# ---------- AUTOSTART ----------
$KoloryInicjalow = @('#5865F2', '#0A64AD', '#1A7F3C', '#B30B00', '#7C3AED', '#C2410C', '#0F766E', '#BE185D')
function KolorInicjalu([string]$n) {
    $h = 0; foreach ($c in $n.ToCharArray()) { $h = ($h * 31 + [int]$c) % 1000003 }
    Kolor $KoloryInicjalow[$h % $KoloryInicjalow.Count]
}

function RysujWierszAutostartu($g, $w, $r, [bool]$hover) {
    $s = $script:Styl; $a = $w.Obj
    TloWiersza $g $r $hover
    $sr = $r.Y + [int]($r.Height / 2)
    $kaf = if ($a.Chroniony) { $s.KafelekChroniony } else { KolorInicjalu $a.Nazwa }
    Prostokat $g (Px 20) ($sr - (Px 18)) (Px 36) (Px 36) $kaf (Px 9)
    $ini = if ($a.Nazwa) { $a.Nazwa.Substring(0, 1).ToUpper() } else { '?' }
    Tekst $g $ini $s.Pogrubiona ([Drawing.Color]::White) (Px 20) ($sr - (Px 18)) (Px 36) (Px 36) 'HorizontalCenter'
    $xP = $r.Width - (Px 20) - (Px 48)
    $xU = $xP - (Px 44)
    $xZ = $xU - (Px 12) - (Px 170)
    $xN = Px 70
    $szerN = $xZ - (Px 14) - $xN
    $y1 = $sr - (Px 31)
    $nw = [Math]::Min((SzerTekstu $a.Nazwa $s.Pogrubiona), $szerN)
    Tekst $g $a.Nazwa $s.Pogrubiona $(if ($a.Wlaczony) { $s.Tekst } else { $s.TekstSlaby }) $xN $y1 $nw (Px 22)
    if ($a.Chroniony) {
        $krotko = ($a.Chroniony -split ' - ')[0]
        if ($xN + $nw + (Px 160) -lt $xZ) { [void](Pigulka $g $krotko ($xN + $nw + (Px 8)) ($y1 + (Px 11)) $s.NeutralTlo $s.NeutralTekst ([string][char]0xE72E)) }
    }
    $druga = (@($a.Wydawca, $a.Polecenie) | Where-Object { $_ }) -join ' · '
    Tekst $g $druga $s.Mala $s.TekstSlaby $xN ($sr - (Px 9)) $szerN (Px 20)
    $trzecia = if ($a.Martwy) { @{ T = (L 'Martwy wpis: programu już nie ma na dysku. Kosz obok przełącznika usuwa wpis.' 'Dead entry: the program is no longer on the drive. The bin next to the switch removes the entry.'); K = $s.Ostrzezenie } }
               elseif ($a.Ai) { @{ T = "$EtykietaAi`: $($a.Ai)"; K = $s.Ai } }
               elseif ($a.Chroniony) { @{ T = $a.Chroniony; K = $s.TekstSlaby } }
    if ($trzecia) { Tekst $g $trzecia.T $s.Mala $trzecia.K $xN ($sr + (Px 11)) $szerN (Px 20) }
    Tekst $g $a.Zrodlo $s.Mala $s.TekstSlaby $xZ ($sr - (Px 11)) (Px 170) (Px 22)
    Przelacznik $g $xP ($sr - (Px 14)) ([bool]$a.Wlaczony) ([bool]$a.Chroniony -or [bool]$Podglad)
    # Usuniecie wpisu na stale (z kopia) - tylko dla niechronionych
    if (-not $a.Chroniony -and -not $Podglad) {
        $kol = if ($a.Martwy) { $s.Ostrzezenie } else { $s.TekstSlaby }
        if ($hover) { Prostokat $g $xU ($sr - (Px 16)) (Px 32) (Px 32) $s.Kafelek (Px 8) }
        if ($s.Ikony) { Tekst $g ([string][char]0xE74D) $s.Ikony $kol $xU ($sr - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
        else { Tekst $g ([string][char]0x00D7) $s.TytulKarty $kol $xU ($sr - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
    }
}

function RysujPodsumowanieAutostartu($g, $p) {
    $s = $script:Styl
    $wpisy = @($script:Autostart | Where-Object { $_ })
    $wl = @($wpisy | Where-Object { $_.Wlaczony }).Count
    $dane = @(
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$wl" }); O = (L 'uruchamia się przy logowaniu' 'start at sign-in') }
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$($wpisy.Count - $wl)" }); O = (L 'wyłączone' 'turned off') }
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$(@($wpisy | Where-Object { $_.Chroniony }).Count)" }); O = (L 'chronione (tylko podgląd)' 'protected (read-only)') })
    $szer = Px 200; $odst = Px 12; $h = $p.Height - 1
    $x = 0
    foreach ($d in $dane) {
        Prostokat $g $x 0 $szer $h $s.Karta (Px 12) $s.Ramka
        Tekst $g $d.W $s.Liczba $s.Tekst ($x + (Px 18)) (Px 6) ($szer - (Px 24)) (Px 32)
        Tekst $g $d.O $s.Mala $s.TekstSlaby ($x + (Px 18)) (Px 36) ($szer - (Px 24)) (Px 22)
        $x += $szer + $odst
    }
    $szerN = $p.Width - $x - 1
    if ($szerN -gt (Px 120)) {
        Prostokat $g $x 0 $szerN $h $s.NotkaTlo (Px 12) $s.NotkaRamka
        $t = if ($Podglad) { L 'Tryb podglądu - przełączniki są tylko do wglądu.' 'Preview mode - the switches are read-only.' }
             else { L 'Zmiana działa od następnego logowania. Programy możesz dalej uruchamiać ręcznie.' 'Changes take effect at the next sign-in. You can still start the programs by hand.' }
        [Windows.Forms.TextRenderer]::DrawText($g, $t, $s.Czcionka, (New-Object Drawing.Rectangle(($x + (Px 18)), 0, ($szerN - (Px 30)), $h)), $s.NotkaTekst,
            [Windows.Forms.TextFormatFlags]'Left, VerticalCenter, WordBreak, EndEllipsis, NoPrefix')
    }
}

function WypelnijAutostart {
    $wiersze = @(@($script:Autostart | Where-Object { $_ } | Sort-Object { -not $_.Wlaczony }, { [bool]$_.Chroniony }, { $_.Nazwa }) |
                 ForEach-Object { @{ H = (Px 74); Obj = $_ } })
    $script:UI.LvAutostart.Tag.Pusty = L 'Nie znaleziono programów uruchamianych przy logowaniu.' 'No programs that start at sign-in were found.'
    UstawWiersze $script:UI.LvAutostart $wiersze
    $script:UI.AutoPodsum.Invalidate()
    AktualizujStart
    if ($script:Zeskanowano) { AktualizujPrzeglad }
}

# Przelacznik w wierszu: dziala od razu, jak w Menedzerze zadan (wylaczenie niczego nie usuwa)
function PrzelaczWiersz($a) {
    if ($script:Pracuje) { return }
    if ($Podglad) { OknoStatus (L 'Tryb podglądu - autostart się nie zmienia.' 'Preview mode - startup apps are not changed.'); return }
    if ($a.Chroniony) { OknoStatus ((L '{0}: chronione - {1}' '{0}: protected - {1}') -f $a.Nazwa, $a.Chroniony); return }
    $wlacz = -not $a.Wlaczony
    try {
        PrzelaczAutostart $a $wlacz
        $stan = if ($wlacz) { L 'włączony' 'on' } else { L 'wyłączony' 'off' }
        OknoWypisz ("  Autostart: {0} -> {1}" -f $a.Nazwa, $stan) 'Green'
        OknoStatus ((L '{0}: autostart {1}. Zmiana działa od następnego logowania.' '{0}: startup {1}. It takes effect at the next sign-in.') -f $a.Nazwa, $stan)
    }
    catch {
        Log "Autostart - blad $($a.Nazwa): $($_.Exception.Message)"
        Komunikat ((L 'Nie udało się zmienić {0}: {1}' 'Could not change {0}: {1}') -f $a.Nazwa, $_.Exception.Message) 'Warning'
    }
    $script:UI.LvAutostart.Invalidate()
    $script:UI.AutoPodsum.Invalidate()
    AktualizujStart
    if ($script:Zeskanowano) { AktualizujPrzeglad }
}

# Usuniecie wpisu na stale, po potwierdzeniu. Kopia .reg / .xml albo skrot w Koszu.
function UsunWiersz($a) {
    if ($script:Pracuje -or $Podglad -or $a.Chroniony) { return }
    $kopia = switch ($a.Rodzaj) { 'folder' { L 'Skrót trafi do Kosza.' 'The shortcut goes to the Recycle Bin.' } 'zadanie' { L 'Zadanie dostanie kopię .xml (Harmonogram zadań > Importuj zadanie przywraca je).' 'The task gets an .xml backup (Task Scheduler > Import Task restores it).' } default { L 'Wpis dostanie kopię .reg (dwuklik na niej przywraca wpis).' 'The entry gets a .reg backup (double-clicking it restores the entry).' } }
    $tekst = (L "Usunąć z autostartu na stałe:`r`n`r`n  {0}`r`n  {1}`r`n`r`nProgram nie jest odinstalowywany, znika tylko wpis uruchamiania. {2}" "Remove from startup permanently:`r`n`r`n  {0}`r`n  {1}`r`n`r`nThe program is not uninstalled, only its startup entry is removed. {2}") -f $a.Nazwa, $a.Polecenie, $kopia
    $odp = [Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, (L 'LLMCleaner - usuń z autostartu' 'LLMCleaner - remove from startup'), 'YesNo', 'Question', 'Button2')
    if ($odp -ne 'Yes') { return }
    try {
        $gdzie = UsunAutostart $a
        OknoWypisz ((L '  Autostart: {0} usunięty (kopia: {1})' '  Startup: {0} removed (backup: {1})') -f $a.Nazwa, $gdzie) 'Green'
        OknoStatus ((L '{0}: usunięty z autostartu. Kopia: {1}' '{0}: removed from startup. Backup: {1}') -f $a.Nazwa, $gdzie)
    }
    catch {
        Log "Autostart - blad usuwania $($a.Nazwa): $($_.Exception.Message)"
        Komunikat ((L 'Nie udało się usunąć {0}: {1}' 'Could not remove {0}: {1}') -f $a.Nazwa, $_.Exception.Message) 'Warning'
    }
    WypelnijAutostart
}

# ---------- CZYSZCZENIE ----------
function PrzygotujKroki {
    $kroki = @()
    if (PotrzebnyPunkt) { $kroki += @{ Id = 'punkt'; Nazwa = (L 'Punkt przywracania systemu' 'System Restore point') } }
    foreach ($k in ($script:Kategorie | Where-Object { $_.Wybrana })) {
        $u = if ($k.Typ -eq 'miniatury') { L 'pasek zadań zniknie na chwilę' 'the taskbar disappears for a moment' } elseif ($k.Typ -in 'dism', 'winold') { L 'potrwa kilka minut' 'takes a few minutes' } else { '' }
        $kroki += @{ Id = $k.Id; Nazwa = $k.Nazwa; Opis = $u }
    }
    $wp = @($script:Pozostalosci | Where-Object { $_.Wybrana })
    $nk = @($wp | Where-Object { NaKosz $_ }).Count
    if ($nk) { $kroki += @{ Id = 'poz-kosz'; Nazwa = ((L 'Pozostałości do Kosza: {0}' 'Leftovers to the Recycle Bin: {0}') -f $nk) } }
    $nr = $wp.Count - $nk
    if ($nr) { $kroki += @{ Id = 'poz-kopia'; Nazwa = ((L 'Rejestr i zadania z kopią: {0}' 'Registry and tasks with a backup: {0}') -f $nr) } }
    foreach ($k in $kroki) { $k.Stan = 'czeka'; $k.Bajty = 0.0; $k.Uwaga = '' }
    $script:Kroki = $kroki
    $script:WynikCzyszczenia = $null
    $script:UI.WynikInfo.Text = L 'Kopie rejestru i zadań, punkt przywracania i pominięte pliki pojawią się tutaj po ostatnim kroku.' 'Registry and task backups, the restore point and skipped files appear here after the last step.'
    $script:UI.WynikTytul.Text = L 'Po zakończeniu zobaczysz' 'When it finishes you will see'
    $script:UI.WynikPrzyciski.Visible = $false
    UstawWiersze $script:UI.LvKroki @($kroki | ForEach-Object { @{ H = (Px 52); Obj = $_ } })
    OdswiezKroki
}

# Wywolywane z rdzenia (ZglosKrok) w trakcie czyszczenia
function KrokOkna([string]$id, [string]$stan, [double]$bajty, [string]$uwaga) {
    $k = $script:Kroki | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if (-not $k) { return }
    $k.Stan = $stan
    if ($stan -ne 'trwa') { $k.Bajty = $bajty; $k.Uwaga = $uwaga }
    OdswiezKroki
    # Biezacy krok zawsze widoczny na liscie
    if ($stan -eq 'trwa') {
        $lv = $script:UI.LvKroki
        $w = $lv.Tag.Wiersze | Where-Object { $_.Obj -eq $k } | Select-Object -First 1
        if ($w) { $lv.AutoScrollPosition = New-Object Drawing.Point(0, [Math]::Max(0, $w.Y - $lv.ClientSize.Height + 2 * $w.H)) }
    }
    [Windows.Forms.Application]::DoEvents()
}

function ZwolnionoDoTejPory { [double](@($script:Kroki | Where-Object { $_.Id -ne 'poz-kosz' } | ForEach-Object { [double]$_.Bajty }) | Measure-Object -Sum).Sum }

function OdswiezKroki {
    $u = $script:UI
    $u.LvKroki.Invalidate(); $u.PostepKart.Invalidate(); $u.WynikPole.Invalidate()
    $n = @($script:Kroki).Count
    $gotowe = @($script:Kroki | Where-Object { $_.Stan -notin 'czeka', 'trwa' }).Count
    if ($script:Czyszczenie -and $n) { PostepNaPasku 2 $gotowe $n }
}

function RysujPostepCzyszczenia($g, $p) {
    $s = $script:Styl
    $kroki = @($script:Kroki)
    $n = $kroki.Count
    $gotowe = @($kroki | Where-Object { $_.Stan -notin 'czeka', 'trwa' }).Count
    $biezacy = $kroki | Where-Object { $_.Stan -eq 'trwa' } | Select-Object -First 1
    $t = if ($script:WynikCzyszczenia) { L 'Gotowe - wszystkie kroki zakończone' 'Done - all steps finished' }
         elseif ($biezacy) { (L 'Krok {0} z {1} · {2}' 'Step {0} of {1} · {2}') -f ($gotowe + 1), $n, $biezacy.Nazwa }
         else { (L 'Krok {0} z {1}' 'Step {0} of {1}') -f [Math]::Min($n, $gotowe + 1), $n }
    $prawy = (L 'zwolniono {0}' '{0} freed') -f (Rozmiar (ZwolnionoDoTejPory))
    $szerP = (SzerTekstu $prawy $s.Czcionka) + (Px 4)
    Tekst $g $t $s.TytulKarty $s.Tekst 0 0 ($p.Width - $szerP - (Px 12)) (Px 30)
    Tekst $g $prawy $s.Czcionka $s.TekstSlaby ($p.Width - $szerP) 0 $szerP (Px 30) 'Right'
    $y = Px 42
    Prostokat $g 0 $y $p.Width (Px 10) $s.Tor (Px 5)
    if ($n) { Prostokat $g 0 $y ([int][Math]::Max((Px 10), $p.Width * $gotowe / $n)) (Px 10) $(if ($script:WynikCzyszczenia) { $s.Zielony } else { $s.Akcent }) (Px 5) }
}

function RysujKrok($g, $w, $r, [bool]$hover) {
    $s = $script:Styl; $k = $w.Obj
    TloWiersza $g $r $false
    $sr = $r.Y + [int]($r.Height / 2)
    $d = Px 24; $x = Px 20; $y = $sr - [int]($d / 2)
    switch ($k.Stan) {
        'ok' { Prostokat $g $x $y $d $d $s.OkTlo ([int]($d / 2)); $znak = [string][char]0x2713; $kz = $s.OkTekst; $ku = $s.TekstSlaby }
        'czesc' { Prostokat $g $x $y $d $d $s.OkTlo ([int]($d / 2)); $znak = [string][char]0x2713; $kz = $s.OkTekst; $ku = $s.Ostrzezenie }
        'trwa' { Prostokat $g $x $y $d $d $s.Akcent ([int]($d / 2)); $znak = [string][char]0x2026; $kz = [Drawing.Color]::White; $ku = $s.AkcentTekst }
        'pominieto' { Prostokat $g $x $y $d $d $s.UwagaTlo ([int]($d / 2)); $znak = '!'; $kz = $s.UwagaTekst; $ku = $s.Ostrzezenie }
        'blad' { Prostokat $g $x $y $d $d $s.BladTlo ([int]($d / 2)); $znak = '!'; $kz = $s.BladTekst; $ku = $s.Czerwony }
        default { Prostokat $g $x $y ($d - 1) ($d - 1) $s.Karta ([int]($d / 2)) $s.Pole; $znak = ''; $kz = $s.Tekst; $ku = $s.TekstSlaby }
    }
    Tekst $g $znak $s.MalaPogr $kz $x $y $d $d 'HorizontalCenter'
    $uwaga = switch ($k.Stan) {
        'czeka' { if ($k.Opis) { (L 'czeka - {0}' 'waiting - {0}') -f $k.Opis } else { L 'czeka' 'waiting' } }
        'trwa' { if ($k.Opis) { (L 'w toku - {0}' 'in progress - {0}') -f $k.Opis } else { L 'w toku...' 'in progress...' } }
        default { $k.Uwaga }
    }
    $xN = Px 60; $szer = $r.Width - $xN - (Px 120)
    Tekst $g $k.Nazwa $s.Pogrubiona $s.Tekst $xN ($sr - (Px 20)) $szer (Px 21)
    Tekst $g $uwaga $s.Mala $ku $xN ($sr + (Px 1)) $szer (Px 19)
    if ($k.Bajty -gt 0) { Tekst $g (Rozmiar $k.Bajty) $s.Pogrubiona $s.Tekst ($r.Width - (Px 110)) ($sr - (Px 12)) (Px 90) (Px 24) 'Right' }
}

function RysujWynik($g, $p) {
    $s = $script:Styl
    $w = $script:WynikCzyszczenia
    $h = $p.Height - 1
    if ($w) {
        Prostokat $g 0 0 ($p.Width - 1) $h $s.SukcesTlo (Px 12) $s.SukcesRamka
        $kolor = $s.SukcesTekst
        $maly = L 'Zwolniono' 'Freed'
        $duzy = Rozmiar $w.Suma
        $dol = (L 'Wolne na {0} {1} → {2} · {3} min {4} s' 'Free on {0} {1} → {2} · {3} min {4} s') -f $Sys, (Rozmiar $w.WolnePrzed), (Rozmiar $w.WolnePo), [int][Math]::Floor($w.Czas.TotalMinutes), $w.Czas.Seconds
    }
    else {
        Prostokat $g 0 0 ($p.Width - 1) $h $s.Kafelek (Px 12)
        $kolor = $s.Tekst
        $maly = L 'Zwolniono do tej pory' 'Freed so far'
        $duzy = Rozmiar (ZwolnionoDoTejPory)
        $dol = L 'Wolne miejsce przed i po pojawi się po ostatnim kroku.' 'Free space before and after appears after the last step.'
    }
    Tekst $g $maly $s.Mala $kolor (Px 18) (Px 10) ($p.Width - (Px 36)) (Px 20)
    Tekst $g $duzy $s.Duza $kolor (Px 14) (Px 30) ($p.Width - (Px 30)) (Px 56)
    Tekst $g $dol $s.Mala $kolor (Px 18) (Px 88) ($p.Width - (Px 36)) (Px 20)
}

# Czyszczenie z ekranem postepu: kroki, pasek, wynik. Potwierdzenie jest wczesniej (przycisk).
function CzyscZOknem {
    PrzygotujKroki
    $zablokowane = SumaZablokowanych
    ZablokujNawigacje $true
    PokazStrone 'czyszczenie'
    OknoWypisz ''
    OknoWypisz (L '2/2  Czyszczenie' '2/2  Cleaning') 'Cyan'
    $script:NaKrok = { param($id, $stan, $bajty, $uwaga) KrokOkna $id $stan $bajty $uwaga }
    $ok = $false
    try { $w = WykonajCzyszczenie; $ok = $true }
    finally {
        $script:NaKrok = $null
        ZablokujNawigacje $false
        PostepNaPasku $(if ($ok) { 0 } else { 4 }) 1 1
        if (-not $ok) { foreach ($k in $script:Kroki) { if ($k.Stan -eq 'trwa') { $k.Stan = 'blad'; $k.Uwaga = L 'przerwane - szczegóły w Dzienniku' 'interrupted - see the Log' } }; OdswiezKroki }
    }
    $script:PoCzyszczeniu = $true
    $punkt = $script:Kroki | Where-Object { $_.Id -eq 'punkt' } | Select-Object -First 1
    $kopie = if ($w.Kopie -and (Test-Path -LiteralPath $w.Kopie)) { @(Get-ChildItem -LiteralPath $w.Kopie -File).Count } else { 0 }
    $w.Kopii = $kopie
    $script:WynikCzyszczenia = $w
    $info = @(
        $(if ($kopie) { (L 'Kopie rejestru i zadań: {0} plików ({1})' 'Registry and task backups: {0} files ({1})') -f $kopie, $w.Kopie } else { L 'Kopie rejestru i zadań: nie były potrzebne' 'Registry and task backups: not needed' })
        $(if ($punkt) { (L 'Punkt przywracania: {0}' 'Restore point: {0}') -f $punkt.Uwaga } else { L 'Punkt przywracania: nie był potrzebny' 'Restore point: not needed' }))
    if ($zablokowane) { $info += (L 'Pominięte: {0} w użyciu' 'Skipped: {0} in use') -f (Rozmiar $zablokowane) }
    $doKosza = $script:Kroki | Where-Object { $_.Id -eq 'poz-kosz' } | Select-Object -First 1
    if ($doKosza -and $doKosza.Bajty) { $info += (L 'W Koszu: {0} - zwolni się po opróżnieniu Kosza' 'In the Recycle Bin: {0} - freed when you empty it') -f (Rozmiar $doKosza.Bajty) }
    $script:UI.WynikInfo.Text = $info -join "`r`n"
    $script:UI.WynikTytul.Text = L 'Gotowe' 'Done'
    $script:UI.WynikPrzyciski.Visible = $true
    OdswiezKroki
    OknoWypisz ''
    foreach ($x in (TekstPoCzyszczeniu $w)) { OknoWypisz "  $x" 'White' }
    OknoWypisz "  Log: $LogPlik" 'DarkGray'
    # Martwe wpisy mogly zniknac - lista autostartu od nowa
    try { [void](WpisyAutostartu); WypelnijAutostart } catch { BladSkanu 'autostart' $_ }
    AktualizujPrzeglad
    WypelnijPlan
    OknoStatus (L 'Czyszczenie zakończone. Kliknij „Skanuj ponownie”, żeby zobaczyć aktualny stan.' 'Cleaning finished. Click "Scan again" to see the current state.')
    if ($script:UI.Okno.WindowState -eq 'Minimized') { $script:UI.Okno.WindowState = 'Normal' }
}

# ---------- CZAT ----------
function DopiszCzat([string]$kto, [string]$tekst, $kolor) {
    $box = $script:UI.Czat
    $box.SelectionStart = $box.TextLength
    $box.SelectionFont = $script:Styl.Pogrubiona
    $box.SelectionColor = $kolor
    $box.AppendText("$kto`r`n")
    $box.SelectionFont = $box.Font
    $box.SelectionColor = $script:Styl.Tekst
    $box.AppendText("$tekst`r`n`r`n")
    $box.ScrollToCaret()
}

# ---------- BUDOWA STRON ----------
function StronaPrzeglad {
    $s = $script:Styl
    $str = Strona
    $btnSkan = Przycisk (L 'Skanuj' 'Scan') 'ramka' @{ Width = (Px 170) }
    $n = Naglowek (L 'Przegląd' 'Overview') (L 'Wybierz dyski i kliknij „Skanuj”. LLMCleaner sprawdzi śmieci systemowe, cache programów i pozostałości po odinstalowanych programach i grach.' 'Pick the drives and click "Scan". LLMCleaner checks system junk, app caches and leftovers of uninstalled programs and games.') @($btnSkan)
    $script:UI.PrzegladOpis = $n.Opis

    # Karta wyniku: maly napis, duza liczba, opis, przyciski i kafelki statystyk po prawej
    $k = Karta @{ Dock = 'Top'; Height = (Px 230); Padding = (Marg 28 22 28 22) }
    $staty = Plotno @{ Dock = 'Right'; Width = (Px 420); BackColor = $s.Karta; Visible = $false } { param($g, $p) RysujStaty $g $p }
    $lewa = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Karta }
    $maly = Etykieta (L 'Pierwszy krok' 'First step') @{ Dock = 'Top'; Height = (Px 24); ForeColor = $s.TekstSlaby }
    $wynik = Etykieta (L 'Gotowy do skanu' 'Ready to scan') @{ Dock = 'Top'; Height = (Px 60); Font = $s.Duza; AutoEllipsis = $true }
    $etap = Etykieta (L 'Skan trwa zwykle 1-3 minuty i niczego nie usuwa. Potem zobaczysz plan czyszczenia do sprawdzenia.' 'A scan usually takes 1-3 minutes and deletes nothing. Then you get a cleanup plan to review.') @{
        Dock = 'Top'; Height = (Px 44); ForeColor = $s.TekstSlaby; AutoEllipsis = $true }
    $rzad = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 46) }
    $btnStart = Przycisk (L 'Skanuj teraz' 'Scan now') 'glowny' @{ Dock = 'Left'; Width = (Px 200); Font = (New-Object Drawing.Font('Segoe UI Semibold', 11)) }
    $btnPlan = Przycisk (L 'Zobacz plan czyszczenia' 'View the cleanup plan') 'glowny' @{ Dock = 'Left'; Width = (Px 214); Visible = $false }
    $btnOdRazu = Przycisk $(if ($Podglad) { L 'Podgląd - bez czyszczenia' 'Preview - no cleaning' } else { L 'Wyczyść od razu...' 'Clean now...' }) 'drugi' @{ Dock = 'Left'; Width = (Px 176); Visible = $false }
    Dokuj $rzad @($btnStart, $btnPlan, (Odstep 'Left' 10), $btnOdRazu)
    Dokuj $lewa @($maly, $wynik, $etap, (Odstep 'Top' 8), $rzad)
    Dokuj $k @($staty, (Odstep 'Right' 24), $lewa)
    # Waskie okno: kafelki statystyk ustepuja miejsca przyciskom
    $k.Add_Resize({ if ($script:UI.Staty) { $script:UI.Staty.Width = [Math]::Max((Px 220), [Math]::Min((Px 420), $this.Width - $this.Padding.Horizontal - (Px 424))) } })
    $script:UI.WynikMaly = $maly; $script:UI.Wynik = $wynik; $script:UI.Etap = $etap; $script:UI.Staty = $staty
    $script:UI.BtnSkan = $btnSkan; $script:UI.BtnStart = $btnStart; $script:UI.BtnDoPlanu = $btnPlan; $script:UI.BtnOdRazu = $btnOdRazu

    # Dol: slupki po lewej, dyski i autostart po prawej (40% szerokosci)
    $dol = Kontrolka Panel @{ Dock = 'Fill' }
    $kSl = Karta @{ Dock = 'Fill'; Padding = (Marg 24 20 24 16) }
    $slupki = Plotno @{ Dock = 'Fill'; BackColor = $s.Karta } { param($g, $p) RysujSlupki $g $p }
    $kSl.Controls.Add($slupki)
    $script:UI.Slupki = $slupki

    $prawa = Kontrolka Panel @{ Dock = 'Right'; Width = (Px 380) }
    $kD = Karta @{ Dock = 'Fill'; Padding = (Marg 22 16 22 8) }
    $tD = Etykieta (L 'Dyski do skanowania' 'Drives to scan') @{ Dock = 'Top'; Height = (Px 30); Font = $s.TytulKarty }
    $lvD = ListaWierszy { param($g, $w, $r, $h) RysujDysk $g $w $r $h }
    $lvD.Tag.Klik = {
        param($w, $x, $r)
        $d = $w.Obj
        if ($d.Sys -or $script:Pracuje) { return }
        $d.Zazn = -not $d.Zazn
        $script:UI.ListaDyskow.Invalidate()
    }
    $lvD.Tag.Kursor = { param($w, $x, $r) -not $w.Obj.Sys }
    $dyski = @()
    $wybrane = @($Dyski | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() } | Where-Object { $_ })
    foreach ($d in DyskiStale) {
        $sys = $d.DeviceID -eq $Sys
        $zazn = $sys -or -not $wybrane.Count -or ($d.DeviceID.TrimEnd(':') -in $wybrane)
        $dyski += @{ H = (Px 58); Obj = @{ D = $d; Sys = $sys; Zazn = $zazn; Id = $d.DeviceID } }
    }
    UstawWiersze $lvD $dyski
    $script:UI.ListaDyskow = $lvD
    Dokuj $kD @($tD, $lvD)

    $kS = Karta @{ Dock = 'Bottom'; Height = (Px 150); Padding = (Marg 22 16 22 12) }
    $tS = Etykieta (L 'Start Windows' 'Windows startup') @{ Dock = 'Top'; Height = (Px 30); Font = $s.TytulKarty }
    $tekstS = Etykieta '' @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; AutoEllipsis = $true }
    $btnS = Przycisk (L 'Przejrzyj autostart' 'Review startup apps') 'link' @{ Dock = 'Bottom'; Height = (Px 30) }
    $btnS.Add_Click({ PokazStrone 'autostart' })
    Dokuj $kS @($tS, $btnS, $tekstS)
    $script:UI.StartTekst = $tekstS
    Dokuj $prawa @($kS, (Odstep 'Bottom' 18), $kD)

    $script:UI.PrawaKolumna = $prawa
    Dokuj $dol @($prawa, (Odstep 'Right' 18), $kSl)
    $dol.Add_Resize({ if ($script:UI.PrawaKolumna) { $script:UI.PrawaKolumna.Width = [Math]::Max((Px 320), [int](($this.Width - (Px 18)) * 0.4)) } })

    Dokuj $str @($n.Panel, $k, (Odstep 'Top' 18), $dol)
    $str
}

function StronaPlan {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Plan czyszczenia' 'Cleanup plan') (L 'Kliknij pozycję, żeby ją zaznaczyć lub odznaczyć. Pliki i foldery trafiają do Kosza, rejestr i zadania mają kopię i punkt przywracania. Najedź na pozycję, żeby zobaczyć pełny opis.' 'Click an item to tick or untick it. Files and folders go to the Recycle Bin; registry entries and tasks get a backup and a restore point. Hover over an item to see its full description.')

    # Pasek narzedzi: szukanie, filtr, przyciski zaznaczania
    $pas = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 40) }
    $szukaj = Karta @{ Dock = 'Left'; Width = (Px 300); Padding = (Marg 12 10 10 6) }
    $script:UI.SzukajKarta = $szukaj
    if ($s.Ikony) { $szukaj.Controls.Add((Etykieta ([string][char]0xE721) @{ Dock = 'Left'; Width = (Px 26); Font = $s.Ikony; ForeColor = $s.TekstSlaby; BackColor = $s.Karta })) }
    $pole = Kontrolka TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = $s.Czcionka }
    $szukaj.Controls.Add($pole); $pole.BringToFront()
    $pole.Add_TextChanged({ if ($script:Zeskanowano) { WypelnijPlan } })
    $script:UI.Szukaj = $pole

    $filtr = Plotno @{ Dock = 'Left'; Width = (Px 300); BackColor = $s.Tlo; Cursor = [Windows.Forms.Cursors]::Hand } {
        param($g, $p)
        $s = $script:Styl
        $opcje = $p.Tag.Opcje
        Prostokat $g 0 0 ($p.Width - 1) ($p.Height - 1) $s.Segment (Px 8)
        $w = [int](($p.Width - (Px 6)) / $opcje.Count)
        for ($i = 0; $i -lt $opcje.Count; $i++) {
            $x = (Px 3) + $i * $w
            $wyb = $opcje[$i].Id -eq $script:FiltrPlanu
            if ($wyb) { Prostokat $g $x (Px 3) $w ($p.Height - (Px 7)) $s.SegmentWybrany (Px 6) }
            Tekst $g $opcje[$i].T $(if ($wyb) { $s.Pogrubiona } else { $s.Czcionka }) $(if ($wyb) { $s.Tekst } else { $s.TekstSlaby }) $x 0 $w $p.Height 'HorizontalCenter'
        }
    }
    $filtr.Tag.Opcje = @(@{ Id = 'wszystko'; T = (L 'Wszystko' 'All') }, @{ Id = 'zaznaczone'; T = (L 'Zaznaczone' 'Selected') }, @{ Id = 'reczne'; T = (L 'Na życzenie' 'Opt-in') })
    $filtr.Add_MouseClick({
        $o = $this.Tag.Opcje
        $i = [Math]::Min($o.Count - 1, [Math]::Max(0, [int][Math]::Floor(($_.X - (Px 3)) / (($this.Width - (Px 6)) / $o.Count))))
        $script:FiltrPlanu = $o[$i].Id
        $this.Invalidate()
        if ($script:Zeskanowano) { WypelnijPlan }
    })
    $btnZal = Przycisk (L 'Zaznacz zalecane' 'Select recommended') 'ramka' @{ Dock = 'Right'; Width = (Px 160) }
    $btnOdz = Przycisk (L 'Odznacz wszystko' 'Clear selection') 'ramka' @{ Dock = 'Right'; Width = (Px 150) }
    Dokuj $pas @($szukaj, (Odstep 'Left' 12), $filtr, $btnOdz, (Odstep 'Right' 10), $btnZal)
    $pas.Add_Resize({ if ($script:UI.SzukajKarta) { $script:UI.SzukajKarta.Width = [Math]::Max((Px 160), [Math]::Min((Px 320), $this.Width - (Px 644))) } })
    $script:UI.BtnZalecane = $btnZal; $script:UI.BtnOdznacz = $btnOdz

    # Lista z naglowkiem kolumn
    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 2 4 2 8) }
    $lv = ListaWierszy { param($g, $w, $r, $h) RysujWierszPlanu $g $w $r $h }
    $kol = Plotno @{ Dock = 'Top'; Height = (Px 34); BackColor = $s.Karta } { param($g, $p) RysujKolumnyPlanu $g $p }
    $lv.Tag.Klik = {
        param($w, $x, $r)
        if ($script:Pracuje -or $script:PoCzyszczeniu) { return }
        $o = $w.Obj
        if ($o.Blokada -and -not $o.Wybrana) { OknoStatus $o.Blokada; return }
        $o.Wybrana = -not $o.Wybrana
        AktualizujSume
    }
    $lv.Tag.Podpowiedz = {
        param($w)
        $o = $w.Obj
        if ($w.Kat) { (@($o.Nazwa, $o.Opis, $o.Uwaga, $o.Blokada) | Where-Object { $_ }) -join "`n" }
        else { (@((PokazPozostalosc $o), $o.Dlaczego, $(if ($o.Ai) { "$EtykietaAi`: $($o.Ai)" })) | Where-Object { $_ }) -join "`n" }
    }
    $lv.Add_Resize({ if ($script:UI.KolumnyPlanu) { $script:UI.KolumnyPlanu.Invalidate() } })
    Dokuj $k @($kol, $lv)
    $script:UI.LvPlan = $lv; $script:UI.KolumnyPlanu = $kol

    # Pasek akcji pod lista
    $dol = Karta @{ Dock = 'Bottom'; Height = (Px 74); Padding = (Marg 20 14 14 14) }
    $btnWyczysc = Przycisk $(if ($Podglad) { L 'Podgląd - czyszczenie wyłączone' 'Preview - cleaning disabled' } else { L 'Wyczyść zaznaczone...' 'Clean selected...' }) 'glowny' @{ Dock = 'Right'; Width = (Px 220) }
    $btnWyjasnij = Przycisk (L 'AI: czym były pozostałości?' 'AI: what were the leftovers?') 'drugi' @{ Dock = 'Right'; Width = (Px 240) }
    $teksty = Kontrolka Panel @{ Dock = 'Fill' }
    $suma = Etykieta '' @{ Dock = 'Top'; Height = (Px 26); Font = $s.Srednia }
    $sumaOpis = Etykieta '' @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; Font = $s.Mala; AutoEllipsis = $true }
    Dokuj $teksty @($suma, $sumaOpis)
    Dokuj $dol @($btnWyczysc, (Odstep 'Right' 10), $btnWyjasnij, $teksty)
    $script:UI.Suma = $suma; $script:UI.SumaOpis = $sumaOpis; $script:UI.BtnWyczysc = $btnWyczysc; $script:UI.BtnWyjasnij = $btnWyjasnij

    Dokuj $str @($n.Panel, $pas, (Odstep 'Top' 14), $dol, (Odstep 'Bottom' 14), $k)
    $str
}

function StronaAnaliza {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Co zajmuje miejsce' 'What takes up space') (L 'Szybki skan całego dysku (zwykle 30 s - 3 min). Pokazuje najbardziej konkretne duże foldery i największe pliki. Tylko do wglądu - nic stąd nie jest usuwane.' 'A fast scan of the whole drive (usually 30 s - 3 min). Shows the most specific large folders and the largest files. Read-only - nothing here is deleted.')
    $script:UI.InfoAnaliza = $n.Opis

    $pas = Karta @{ Dock = 'Top'; Height = (Px 70); Padding = (Marg 20 14 14 14) }
    $lbl = Etykieta (L 'Dysk' 'Drive') @{ Dock = 'Left'; Width = (Px 56); Font = $s.Pogrubiona; TextAlign = 'MiddleLeft' }
    $cboPanel = Kontrolka Panel @{ Dock = 'Left'; Width = (Px 260); Padding = (Marg 0 8 0 0) }
    $cbo = Kontrolka ComboBox @{ DropDownStyle = 'DropDownList'; Dock = 'Top'; Font = $s.Czcionka; FlatStyle = 'Flat'; BackColor = $s.Kafelek; ForeColor = $s.Tekst }
    $cboPanel.Controls.Add($cbo)
    $btnAn = Przycisk (L 'Analizuj' 'Analyse') 'glowny' @{ Dock = 'Left'; Width = (Px 140) }
    $btnAnAi = Przycisk (L 'AI: opisz i doradź' 'AI: describe and advise') 'drugi' @{ Dock = 'Left'; Width = (Px 200) }
    Dokuj $pas @($lbl, $cboPanel, (Odstep 'Left' 14), $btnAn, (Odstep 'Left' 10), $btnAnAi)
    $script:UI.CboDysk = $cbo; $script:UI.BtnAnalizuj = $btnAn; $script:UI.BtnAnalizaAi = $btnAnAi

    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 2 4 2 8) }
    $lv = ListaWierszy { param($g, $w, $r, $h) RysujWierszAnalizy $g $w $r $h }
    $lv.Tag.Pusty = L 'Wybierz dysk i kliknij „Analizuj”. Lista działa po skanie z Przeglądu.' 'Pick a drive and click "Analyse". The list works after a scan from Overview.'
    $lv.Tag.Klik = { param($w, $x, $r) }
    $lv.Tag.Kursor = { param($w, $x, $r) $false }
    $lv.Tag.Dwuklik = { param($w) if ($w.Obj.Sciezka) { Start-Process explorer.exe -ArgumentList "/select,`"$($w.Obj.Sciezka)`"" } }
    $lv.Tag.Podpowiedz = {
        param($w)
        $p = $w.Obj
        (@($p.Sciezka, $p.Podpowiedz, $(if ($p.Ai) { "$EtykietaAi`: $($p.Ai)" })) | Where-Object { $_ }) -join "`n"
    }
    $k.Controls.Add($lv)
    $script:UI.LvAnaliza = $lv

    Dokuj $str @($n.Panel, $pas, (Odstep 'Top' 14), $k)
    $str
}

function StronaAutostart {
    $s = $script:Styl
    $str = Strona
    $btnOd = Przycisk (L 'Odśwież' 'Refresh') 'ramka' @{ Width = (Px 120) }
    $btnAi = Przycisk (L 'AI: co to jest?' 'AI: what is it?') 'drugi' @{ Width = (Px 170) }
    $n = Naglowek (L 'Autostart' 'Startup apps') (L 'Programy uruchamiane przy logowaniu. Przełącznik działa jak w Menedżerze zadań: wyłączenie niczego nie usuwa. Kosz usuwa wpis na stałe, z kopią. Ochrona, sterowniki, aktualizacje i części Windows są tylko do wglądu.' 'Programs that start when you sign in. The switch works like in Task Manager: turning one off removes nothing. The bin removes the entry permanently, with a backup. Security software, drivers, updaters and parts of Windows are read-only.') @($btnOd, $btnAi)
    $script:UI.BtnAutoOdswiez = $btnOd; $script:UI.BtnAutoAi = $btnAi

    $pod = Plotno @{ Dock = 'Top'; Height = (Px 66); BackColor = $s.Tlo } { param($g, $p) RysujPodsumowanieAutostartu $g $p }
    $script:UI.AutoPodsum = $pod

    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 2 4 2 8) }
    $lv = ListaWierszy { param($g, $w, $r, $h) RysujWierszAutostartu $g $w $r $h }
    $lv.Tag.Pusty = L 'Lista wczytuje się przy wejściu na stronę.' 'The list loads when you open this page.'
    $lv.Tag.Klik = {
        param($w, $x, $r)
        if ($x -ge $r.Width - (Px 76)) { PrzelaczWiersz $w.Obj }
        elseif ($x -ge $r.Width - (Px 112)) { UsunWiersz $w.Obj }
    }
    $lv.Tag.Kursor = { param($w, $x, $r) $x -ge $r.Width - (Px 112) -and -not $w.Obj.Chroniony -and -not $Podglad }
    $lv.Tag.Dwuklik = { param($w) if ($w.Obj.Istnieje) { Start-Process explorer.exe -ArgumentList "/select,`"$($w.Obj.Plik)`"" } }
    $lv.Tag.Podpowiedz = {
        param($w)
        $a = $w.Obj
        (@($a.Nazwa, $a.Polecenie, $a.Zrodlo, $a.Chroniony, $(if ($a.Ai) { "$EtykietaAi`: $($a.Ai)" }), (L 'Dwuklik pokazuje plik w Eksploratorze.' 'Double-click shows the file in File Explorer.')) | Where-Object { $_ }) -join "`n"
    }
    $k.Controls.Add($lv)
    $script:UI.LvAutostart = $lv

    Dokuj $str @($n.Panel, $pod, (Odstep 'Top' 14), $k)
    $str
}

function StronaCzyszczenie {
    $s = $script:Styl
    $str = Strona
    $aside = Kontrolka Panel @{ Dock = 'Right'; Width = (Px 380) }
    $lewa = Kontrolka Panel @{ Dock = 'Fill' }
    $n = Naglowek (L 'Czyszczenie' 'Cleaning') (L 'Nie wyłączaj komputera. Pliki w użyciu są pomijane, foldery i skróty trafiają do Kosza.' 'Do not turn off the computer. Files in use are skipped; folders and shortcuts go to the Recycle Bin.')
    $kP = Karta @{ Dock = 'Top'; Height = (Px 96); Padding = (Marg 24 20 24 16) }
    $postep = Plotno @{ Dock = 'Fill'; BackColor = $s.Karta } { param($g, $p) RysujPostepCzyszczenia $g $p }
    $kP.Controls.Add($postep)
    $kK = Karta @{ Dock = 'Fill'; Padding = (Marg 2 4 2 8) }
    $lv = ListaWierszy { param($g, $w, $r, $h) RysujKrok $g $w $r $h }
    $kK.Controls.Add($lv)
    Dokuj $lewa @($n.Panel, $kP, (Odstep 'Top' 16), $kK)
    $script:UI.PostepKart = $postep; $script:UI.LvKroki = $lv

    $kW = Karta @{ Dock = 'Top'; Height = (Px 380); Padding = (Marg 24 20 24 20) }
    $tW = Etykieta '' @{ Dock = 'Top'; Height = (Px 34); Font = $s.TytulKarty }
    $pole = Plotno @{ Dock = 'Top'; Height = (Px 116); BackColor = $s.Karta } { param($g, $p) RysujWynik $g $p }
    $info = Etykieta '' @{ Dock = 'Fill'; AutoEllipsis = $true }
    $przyc = Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 44); Visible = $false }
    $btnPon = Przycisk (L 'Skanuj ponownie' 'Scan again') 'glowny' @{ Dock = 'Left'; Width = (Px 170) }
    $btnLog = Przycisk (L 'Otwórz log' 'Open the log') 'drugi' @{ Dock = 'Left'; Width = (Px 140) }
    Dokuj $przyc @($btnPon, (Odstep 'Left' 10), $btnLog)
    Dokuj $kW @($tW, $pole, (Odstep 'Top' 14), $przyc, $info)
    $btnPon.Add_Click({ $script:UI.BtnSkan.PerformClick() })
    $btnLog.Add_Click({ if (Test-Path -LiteralPath $LogPlik) { Start-Process notepad.exe -ArgumentList "`"$LogPlik`"" } })
    $script:UI.WynikTytul = $tW; $script:UI.WynikPole = $pole; $script:UI.WynikInfo = $info; $script:UI.WynikPrzyciski = $przyc; $script:UI.BtnWynikSkan = $btnPon

    $kN = Karta @{ Dock = 'Top'; Height = (Px 86); Padding = (Marg 24 16 24 14) }
    $kN.Controls.Add((Etykieta (L 'Postęp jest też widoczny na ikonie LLMCleanera na pasku zadań, więc okno może pracować w tle.' 'Progress is also shown on the LLMCleaner taskbar icon, so the window can work in the background.') @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; Font = $s.Mala }))
    Dokuj $aside @($kW, (Odstep 'Top' 16), $kN)

    $script:UI.Aside = $aside
    Dokuj $str @($aside, (Odstep 'Right' 18), $lewa)
    $str.Add_Resize({ if ($script:UI.Aside) { $script:UI.Aside.Width = [Math]::Max((Px 320), [int](($this.ClientSize.Width - $this.Padding.Horizontal - (Px 18)) * 0.4)) } })
    $str
}

function StronaCzat {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Asystent AI' 'AI assistant') $(if ($BezLLM) { L 'Asystent jest wyłączony (uruchomiono z -BezLLM).' 'The assistant is disabled (started with -BezLLM).' }
        else { (L 'Lokalny model {0} - działa na tym komputerze, nic nie wysyła do internetu i niczego nie usuwa.' 'Local model {0} - runs on this computer, sends nothing to the internet and never deletes anything.') -f $Model })

    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 20 16 6 10) }
    $czat = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = (New-Object Drawing.Font('Segoe UI', 10.5)) }
    # Tekst powitalny wpisuje Shown - RichTextBox gubi kolory ustawione przed utworzeniem okna
    $czat.Tag = $(if ($BezLLM) { '' }
                   else { L "Zapytaj o plan, foldery, programy albo gry. Asystent zna wyniki skanu, analizy dysku i listę autostartu.`r`nPrzed skanem odpowiada tylko ogólnie - żeby pytać o pliki tego komputera, najpierw kliknij `„Skanuj`”.`r`nPierwsze pytanie uruchamia model (ok. 10-20 s).`r`n`r`n" "Ask about the plan, folders, programs or games. The assistant knows the scan results, the disk analysis and the startup list.`r`nBefore a scan it only answers in general terms - to ask about the files on this computer, click ""Scan"" first.`r`nThe first question starts the model (about 10-20 s).`r`n`r`n" })
    $k.Controls.Add($czat)
    $script:UI.Czat = $czat
    $script:UI.Przewijane += $czat

    # Pole pytania: karta z polem bez ramki i przyciskiem
    $dol = Karta @{ Dock = 'Bottom'; Height = (Px 62); Padding = (Marg 20 10 10 10) }
    $btnW = Przycisk (L 'Wyślij' 'Send') 'glowny' @{ Dock = 'Right'; Width = (Px 120) }
    $pole = Kontrolka Panel @{ Dock = 'Fill'; Padding = (Marg 0 10 12 0) }
    $pyt = Kontrolka TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = (New-Object Drawing.Font('Segoe UI', 10.5)) }
    $pole.Controls.Add($pyt)
    Dokuj $dol @($btnW, $pole)
    $pyt.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; if ($script:UI.BtnWyslij.Enabled) { $script:UI.BtnWyslij.PerformClick() } } })
    $script:UI.Pytanie = $pyt; $script:UI.BtnWyslij = $btnW

    Dokuj $str @($n.Panel, $dol, (Odstep 'Bottom' 14), $k)
    $str
}

function StronaDziennik {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Dziennik' 'Log') ((L 'Przebieg skanu i czyszczenia. Pełny log: {0}' 'Scan and cleaning progress. Full log: {0}') -f $LogPlik)
    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 18 14 6 10) }
    $log = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = (New-Object Drawing.Font('Consolas', 9.5)); WordWrap = $false }
    $k.Controls.Add($log)
    $script:UI.Log = $log
    $script:UI.Przewijane += $log
    Dokuj $str @($n.Panel, $k)
    $str
}

function PasekNawigacji {
    $s = $script:Styl
    $nav = Kontrolka Panel @{ Dock = 'Left'; Width = (Px 232); BackColor = $s.Nawigacja; Padding = (Marg 12 20 12 14) }

    $logo = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 70); BackColor = $s.Nawigacja }
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) {
        $pb = Kontrolka PictureBox @{ Location = (Pkt 6 4); Size = (Rozm 36 36); SizeMode = 'Zoom'; BackColor = $s.Nawigacja }
        $pb.Image = ObrazZIkony $ico 48
        $logo.Controls.Add($pb)
    }
    $logo.Controls.Add((Etykieta 'LLMCleaner' @{ Location = (Pkt 48 1); ForeColor = [Drawing.Color]::White; BackColor = $s.Nawigacja; Font = (New-Object Drawing.Font('Segoe UI Semibold', 13)) }))
    $logo.Controls.Add((Etykieta ((L 'wersja {0}' 'version {0}') -f $Wersja) @{ Location = (Pkt 50 27); ForeColor = $s.NawSlaby; BackColor = $s.Nawigacja; Font = $s.Mala }))

    $script:UI.Nav = [ordered]@{}
    $pozycje = @(
        @{ Id = 'przeglad'; T = (L 'Przegląd' 'Overview'); I = [char]0xE80F }
        @{ Id = 'plan'; T = (L 'Plan czyszczenia' 'Cleanup plan'); I = [char]0xE74D }
        @{ Id = 'analiza'; T = (L 'Co zajmuje miejsce' 'What takes up space'); I = [char]0xEDA2 }
        @{ Id = 'autostart'; T = (L 'Autostart' 'Startup apps'); I = [char]0xE7E8 }
        @{ Id = 'czat'; T = (L 'Asystent AI' 'AI assistant'); I = [char]0xE8BD }
        @{ Id = 'log'; T = (L 'Dziennik' 'Log'); I = [char]0xE81C })
    $lista = Kontrolka Panel @{ Dock = 'Top'; Height = (Px (48 * $pozycje.Count)); BackColor = $s.Nawigacja }
    $el = @()
    $i = 0
    foreach ($p in $pozycje) {
        $i++
        $b = Przycisk $p.T 'nav' @{ Dock = 'Top'; Height = (Px 44); Font = $s.Nav; AccessibleName = "$($p.I)"; Name = $p.Id }
        $b.Add_Click({ PokazStrone $this.Name })
        $script:UI.Podpowiedz.SetToolTip($b, "Ctrl+$i")
        $script:UI.Nav[$p.Id] = $b
        $el += $b, (Kontrolka Panel @{ Dock = 'Top'; Height = (Px 4) })
    }
    Dokuj $lista $el
    $info = Etykieta (L 'Trwa czyszczenie. Nawigacja wróci po zakończeniu.' 'Cleaning in progress. Navigation comes back when it finishes.') @{
        Dock = 'Top'; Height = (Px 64); ForeColor = $s.NawTekst; BackColor = $s.Nawigacja; Padding = (Marg 10 8 6 0); Visible = $false }
    $script:UI.NavLista = $lista; $script:UI.NavInfo = $info

    # Dol paska: stan asystenta, tryb podgladu, aktualizacja
    $dol = Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 120); BackColor = $s.Nawigacja }
    $ai = Etykieta $(if ($BezLLM) { L 'Asystent AI: wyłączony' 'AI assistant: off' } else { (L "Asystent AI: na żądanie`r`n{0}" "AI assistant: on demand`r`n{0}") -f $Model }) @{
        Dock = 'Bottom'; Height = (Px 44); ForeColor = $s.NawSlaby; BackColor = $s.Nawigacja; Font = $s.Mala; Padding = (Marg 6 8 0 0) }
    $btnAkt = Przycisk '' 'zielony' @{ Dock = 'Bottom'; Height = (Px 40); Visible = $false }
    $dol.Controls.Add($btnAkt); $dol.Controls.Add((Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 8) }))
    if ($Podglad) {
        $dol.Controls.Add((Etykieta (L 'TRYB PODGLĄDU - nic nie zostanie usunięte' 'PREVIEW MODE - nothing will be deleted') @{ Dock = 'Bottom'; Height = (Px 34); ForeColor = (Kolor '#FBBF24'); BackColor = $s.Nawigacja; Font = $s.Mala }))
    }
    $dol.Controls.Add($ai)
    $script:UI.BtnAkt = $btnAkt

    Dokuj $nav @($logo, $lista, $info, $dol)
    $nav
}

# ---------- ROZMIAR I POLOZENIE OKNA ----------
function PrzywrocOkno($f) {
    $u = $script:Ustawienia
    $obszar = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $f.Size = New-Object Drawing.Size([Math]::Min((Px 1240), $obszar.Width), [Math]::Min((Px 800), $obszar.Height))
    $f.StartPosition = 'CenterScreen'
    if (-not $u -or -not $u.W -or -not $u.H) { return }
    # Inne skalowanie niz przy zapisie - rozmiar przeliczony
    $k = if ($u.Skala) { $script:Skala / [double]$u.Skala } else { 1.0 }
    $r = New-Object Drawing.Rectangle([int]$u.X, [int]$u.Y, [int]([int]$u.W * $k), [int]([int]$u.H * $k))
    # Tylko gdy okno trafi na ktorys z ekranow (monitor mogl zostac odlaczony)
    $widoczne = @([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith((New-Object Drawing.Rectangle($r.X, $r.Y, [Math]::Min($r.Width, (Px 200)), (Px 60)))) }).Count
    if ($widoczne -and $r.Width -ge $f.MinimumSize.Width -and $r.Height -ge $f.MinimumSize.Height) {
        $f.StartPosition = 'Manual'
        $f.Bounds = $r
        if ($u.Max) { $f.WindowState = 'Maximized' }
    }
}

function ZapiszOkno {
    $f = $script:UI.Okno
    $b = if ($f.WindowState -eq 'Normal') { $f.Bounds } else { $f.RestoreBounds }
    $motyw = if ($script:Ustawienia.Motyw) { "$($script:Ustawienia.Motyw)" } else { 'auto' }
    $strona = if ($script:Strona -in 'plan', 'czyszczenie') { 'przeglad' } else { $script:Strona }
    $dane = [ordered]@{ X = $b.X; Y = $b.Y; W = $b.Width; H = $b.Height; Max = ($f.WindowState -eq 'Maximized'); Skala = $script:Skala; Strona = $strona; Motyw = $motyw }
    try {
        New-Item -ItemType Directory -Force (Split-Path $script:OknoPlik) | Out-Null
        Set-Content -LiteralPath $script:OknoPlik -Value (ConvertTo-Json -InputObject $dane) -Encoding UTF8
    }
    catch { Log "Zapis okno.json: $($_.Exception.Message)" }
}

# Ciemny pasek tytulu i ciemne paski przewijania (Windows 10 1809+; starsze ignoruja)
function CiemnyTytul {
    if ($script:Ciemny) { try { [LlmWin.Natywne]::CiemnyPasekTytulu($script:UI.Okno.Handle) } catch { Log "Motyw ciemny: $($_.Exception.Message)" } }
}
function CiemnePrzewijanie {
    if (-not $script:Ciemny) { return }
    try { foreach ($c in $script:UI.Przewijane) { [void][LlmWin.Natywne]::SetWindowTheme($c.Handle, 'DarkMode_Explorer', [NullString]::Value) } }
    catch { Log "Motyw ciemny: $($_.Exception.Message)" }
}

# ---------- OKNO ----------
function PokazOkno {
    $script:Tryb = 'okno'
    # Konsola PowerShella nie jest potrzebna, gdy jest okno
    if (-not $script:TestPoStarcie) { [void][LlmWin.Natywne]::ShowWindow([LlmWin.Natywne]::GetConsoleWindow(), 0) }
    # Ostry tekst przy skalowaniu ekranu 125-200%: okno samo przelicza wymiary (Px), Windows go nie rozmywa
    [void][LlmWin.Natywne]::SetProcessDPIAware()
    $gr = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:Skala = [Math]::Max(1.0, $gr.DpiX / 96.0)
    $gr.Dispose()

    [Windows.Forms.Application]::EnableVisualStyles()
    $s = $script:Styl
    $script:UI.Podpowiedz = New-Object Windows.Forms.ToolTip
    $script:UI.Podpowiedz.AutoPopDelay = 15000
    $script:UI.Przewijane = @()
    $f = Kontrolka Form @{ Text = "LLMCleaner $Wersja"; MinimumSize = (Rozm 1080 680); AutoScaleMode = 'None'; Font = $s.Czcionka; BackColor = $s.Tlo; KeyPreview = $true }
    PrzywrocOkno $f
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) { $f.Icon = New-Object Drawing.Icon $ico }
    $script:UI.Okno = $f
    $f.SuspendLayout()

    # Strony (wszystkie Fill, widoczna jedna) i pasek stanu pod nimi
    $tresc = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo }
    $script:UI.Strony = [ordered]@{ przeglad = (StronaPrzeglad); plan = (StronaPlan); analiza = (StronaAnaliza); autostart = (StronaAutostart)
                                    czat = (StronaCzat); log = (StronaDziennik); czyszczenie = (StronaCzyszczenie) }
    $stan = Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 30); BackColor = $s.Tlo; Padding = (Marg 32 0 32 10) }
    $st = Etykieta (L 'Gotowy. Wybierz dyski i kliknij „Skanuj” (F5).' 'Ready. Pick the drives and click "Scan" (F5).') @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; Font = $s.Mala; AutoEllipsis = $true; TextAlign = 'MiddleLeft' }
    $pb = Kontrolka ProgressBar @{ Dock = 'Right'; Width = (Px 160); Style = 'Marquee'; MarqueeAnimationSpeed = 30; Visible = $false }
    Dokuj $stan @($pb, $st)
    Dokuj $tresc (@($stan) + @($script:UI.Strony.Values))
    Dokuj $f @((PasekNawigacji), $tresc)
    $script:UI.Status = $st; $script:UI.Pasek = $pb
    $f.ResumeLayout()
    $u = $script:UI
    $script:UI.Akcje = @($u.BtnSkan, $u.BtnStart, $u.BtnDoPlanu, $u.BtnOdRazu, $u.BtnWyczysc, $u.BtnWyjasnij, $u.BtnZalecane, $u.BtnOdznacz,
                         $u.BtnAnalizuj, $u.BtnAnalizaAi, $u.BtnWyslij, $u.BtnAkt, $u.BtnAutoOdswiez, $u.BtnAutoAi, $u.BtnWynikSkan)

    # ---------- ZDARZENIA ----------
    $u.BtnSkan.Add_Click({ Akcja {
        UstawDyski @($script:UI.ListaDyskow.Tag.Wiersze | Where-Object { $_.Obj.Zazn } | ForEach-Object { $_.Obj.Id })
        PokazStrone 'przeglad'
        $script:UI.Log.Clear()
        $script:UI.Staty.Visible = $false
        $script:UI.BtnStart.Visible = $script:UI.BtnDoPlanu.Visible = $script:UI.BtnOdRazu.Visible = $false
        $script:UI.WynikMaly.Text = L 'Trwa skan - niczego nie usuwa' 'Scanning - nothing is deleted'
        $script:UI.Wynik.Text = L 'Skanowanie...' 'Scanning...'
        $script:UI.Wynik.ForeColor = $script:Styl.Tekst
        $script:UI.Skanuje = $true
        PostepNaPasku 1
        $ok = $false
        try {
            OknoWypisz ((L '1/2  Skanowanie dysków: {0}' '1/2  Scanning drives: {0}') -f ($script:WybraneDyski -join ', ')) 'Cyan'
            SkanujWszystko
            $ok = $true
        }
        finally {
            $script:UI.Skanuje = $false
            PostepNaPasku 0
            if (-not $ok) {
                $script:UI.Wynik.Text = L 'Skan nie powiódł się' 'The scan failed'
                $script:UI.Wynik.ForeColor = $script:Styl.Czerwony
                $script:UI.Etap.Text = L 'Szczegóły są w Dzienniku.' 'See the Log for details.'
            }
        }
        $script:Zeskanowano = $true
        $script:PoCzyszczeniu = $false
        $script:WynikCzyszczenia = $null
        $script:Rozmowa = $null
        $script:UI.PrzegladOpis.Text = (L 'Ostatni skan: dziś, {0} · dyski {1} · nic nie zostało jeszcze usunięte' 'Last scan: today, {0} · drives {1} · nothing has been deleted yet') -f (Get-Date -Format 'HH:mm'), ($script:WybraneDyski -join ', ')
        # Autostart do kafelka na Przegladzie (kilka sekund, tylko odczyt)
        if ($null -eq $script:Autostart) {
            OknoStatus (L 'Wczytuję programy uruchamiane przy logowaniu...' 'Reading the programs that start at sign-in...')
            try { [void](WpisyAutostartu); WypelnijAutostart } catch { BladSkanu 'autostart' $_ }
        }
        WypelnijPlan
        $script:UI.CboDysk.Items.Clear()
        foreach ($d in DyskiWybrane) { [void]$script:UI.CboDysk.Items.Add((OpisDysku $d)) }
        $script:UI.CboDysk.SelectedIndex = 0
        OknoStatus ((L 'Skan zakończony. Sprawdź plan i kliknij „Wyczyść zaznaczone...”.' 'Scan finished. Review the plan and click "Clean selected...".'))
    } })

    $u.BtnStart.Add_Click({ $script:UI.BtnSkan.PerformClick() })
    $u.BtnDoPlanu.Add_Click({ PokazStrone 'plan' })
    $u.BtnOdRazu.Add_Click({ $script:UI.BtnWyczysc.PerformClick() })
    $u.BtnZalecane.Add_Click({ UlozPlan; WypelnijPlan })
    $u.BtnOdznacz.Add_Click({ foreach ($x in @($script:Kategorie) + @($script:Pozostalosci)) { if ($x) { $x.Wybrana = $false } }; WypelnijPlan })

    $u.BtnWyjasnij.Add_Click({ Akcja {
        OknoStatus (L 'Model opisuje pozostałości (ok. 20-40 s)...' 'The model is describing the leftovers (about 20-40 s)...')
        $n = WyjasnijPozostalosci
        WypelnijPlan
        OknoStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji (druga linia, dopisek AI).' '{0} items described (second line, AI note).') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
    } })

    $u.BtnWyczysc.Add_Click({
        $linie = Podsumowanie
        if (-not $linie) { Komunikat (L 'Nic nie jest zaznaczone - nie ma czego czyścić.' 'Nothing is selected - there is nothing to clean.'); return }
        $tekst = (($linie | ForEach-Object { $_.T -replace '\s{2,}', '  ' }) -join "`r`n") + "`r`n`r`n" + (L 'Uruchomić czyszczenie?' 'Start cleaning?')
        $odp = [Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, (L 'LLMCleaner - podsumowanie przed czyszczeniem' 'LLMCleaner - summary before cleaning'), 'YesNo', 'Warning', 'Button2')
        if ($odp -ne 'Yes') { return }
        Akcja { CzyscZOknem }
    })

    $u.BtnAnalizuj.Add_Click({ Akcja {
        $i = $script:UI.CboDysk.SelectedIndex
        if ($i -lt 0) { return }
        $l = @(DyskiWybrane)[$i].DeviceID.TrimEnd(':')
        $a = Analizuj $l
        WypelnijAnalize $a
        OknoStatus ((L 'Analiza dysku {0}: gotowa.' 'Drive {0}: analysis ready.') -f $l)
    } })

    $u.BtnAnalizaAi.Add_Click({ Akcja {
        $a = $script:UI.AnalizaDane
        if (-not $a) { return }
        OknoStatus (L 'Model opisuje pozycje (ok. 20-40 s)...' 'The model is describing the items (about 20-40 s)...')
        $n = AnalizaAi $a
        WypelnijAnalize $a
        OknoStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji.' '{0} items described.') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
    } })

    $u.BtnWyslij.Add_Click({
        $q = $script:UI.Pytanie.Text.Trim()
        if (-not $q) { return }
        $script:UI.Pytanie.Clear()
        DopiszCzat (L 'Ty' 'You') $q $script:Styl.Akcent
        Akcja {
            OknoStatus (L 'Asystent myśli...' 'The assistant is thinking...')
            $a = Zapytaj $q
            if ($a) { DopiszCzat 'LLMCleaner' $a $script:Styl.Ai; OknoStatus '' }
            else { DopiszCzat 'LLMCleaner' (L '(brak odpowiedzi - szczegóły w Dzienniku)' '(no answer - see the Log)') $script:Styl.TekstSlaby }
        }
        $script:UI.Pytanie.Focus()
    })

    $u.BtnAutoOdswiez.Add_Click({ Akcja {
        OknoStatus (L 'Wczytuję programy uruchamiane przy logowaniu...' 'Reading the programs that start at sign-in...')
        [void](WpisyAutostartu)
        WypelnijAutostart
        OknoStatus (L 'Autostart wczytany. Przełącznik po prawej włącza i wyłącza program.' 'Startup apps loaded. The switch on the right turns a program on or off.')
    } })
    $u.BtnAutoAi.Add_Click({ Akcja {
        OknoStatus (L 'Model opisuje programy (ok. 20-40 s)...' 'The model is describing the programs (about 20-40 s)...')
        $n = AutostartAi $script:Autostart
        WypelnijAutostart
        OknoStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji.' '{0} items described.') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
    } })

    $u.BtnAkt.Add_Click({ Akcja {
        if (ZainstalujAktualizacje) { $script:UI.Okno.Close() }
    } })

    # Skroty: F5 skanuje, Ctrl+1..6 przelacza strony
    $f.Add_KeyDown({
        if ($script:Czyszczenie) { return }
        if ($_.KeyCode -eq 'F5') {
            $_.Handled = $true
            if ($script:UI.BtnSkan.Enabled) { $script:UI.BtnSkan.PerformClick() }
        }
        elseif ($_.Control -and $_.KeyValue -ge 49 -and $_.KeyValue -le 54) {
            $_.Handled = $true; $_.SuppressKeyPress = $true
            PokazStrone @($script:UI.Nav.Keys)[$_.KeyValue - 49]
        }
    })

    $f.Add_HandleCreated({ CiemnyTytul })
    $f.Add_Shown({
        CiemnePrzewijanie
        $str = "$($script:Ustawienia.Strona)"
        PokazStrone $(if ($str -in 'analiza', 'autostart', 'czat', 'log') { $str } else { 'przeglad' })
        WypelnijPlan
        UstawPrzyciski
        AktualizujStart
        $c = $script:UI.Czat
        $c.AppendText($c.Tag)
        $c.SelectAll(); $c.SelectionColor = $script:Styl.TekstSlaby; $c.Select($c.TextLength, 0)
        # Podpowiedzi w pustych polach (EM_SETCUEBANNER)
        [void][LlmWin.Natywne]::SendMessage($script:UI.Pytanie.Handle, 0x1501, [IntPtr]1, (L 'Napisz pytanie i naciśnij Enter...' 'Type a question and press Enter...'))
        [void][LlmWin.Natywne]::SendMessage($script:UI.Szukaj.Handle, 0x1501, [IntPtr]1, (L 'Szukaj, np. Steam, cache, rejestr' 'Search, e.g. Steam, cache, registry'))
        if (-not $BezAktualizacji) {
            OknoStatus (L 'Sprawdzam aktualizacje...' 'Checking for updates...')
            SprawdzAktualizacje
            if ($script:Aktualizacja) {
                $script:UI.BtnAkt.Text = (L 'Zainstaluj wersję {0}' 'Install version {0}') -f $script:Aktualizacja.Wersja
                $script:UI.BtnAkt.Visible = $true
            }
            OknoStatus (L 'Gotowy. Wybierz dyski i kliknij „Skanuj” (F5).' 'Ready. Pick the drives and click "Scan" (F5).')
        }
        # Tylko dla testow: ustawiane przez skrypt testowy w tym samym procesie (nigdy ze zmiennych srodowiska)
        if ($script:TestPoStarcie) { & $script:TestPoStarcie }
    })
    # W trakcie czyszczenia okno sie nie zamyka (uslugi Windows Update, Eksplorator, pliki w polowie)
    $f.Add_FormClosing({
        if ($script:Czyszczenie) {
            $_.Cancel = $true
            Komunikat (L 'Poczekaj na koniec czyszczenia - przerwanie w połowie zostawiłoby wstrzymane usługi albo wyłączony Eksplorator.' 'Wait for the cleaning to finish - stopping halfway could leave services paused or File Explorer closed.') 'Warning'
            return
        }
        ZapiszOkno
    })
    $f.Add_FormClosed({ ZatrzymajOllama; Log 'Koniec (okno).' })

    Log "Start (okno). Model: $Model, Podglad: $Podglad, BezLLM: $BezLLM, Jezyk: $Jezyk, Skala: $($script:Skala), Ciemny: $($script:Ciemny)"
    [void]$f.ShowDialog()
}
