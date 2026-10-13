<#
    LLMCleaner - okno graficzne (Windows Forms, wbudowane w Windows). Logika jest w Rdzen.ps1.
    Uklad jak w nowoczesnych programach do czyszczenia: ciemny pasek nawigacji po lewej, strony z kartami.
    Karty i przyciski rysujemy sami (zaokraglone rogi), bo standardowe kontrolki WinForms wygladaja jak z Windows XP.
    Dlugie operacje AI ida w osobnym watku (CzekajNa), skan odswieza okno co chwile (DoEvents).
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:UI = @{}
$script:Wypelniam = $false
$script:Zeskanowano = $false

function Kolor([string]$hex) { [Drawing.ColorTranslator]::FromHtml($hex) }

$script:Styl = @{
    Tlo = Kolor '#F3F4F8'; Karta = [Drawing.Color]::White; Kafelek = Kolor '#F6F7FB'; Ramka = Kolor '#E2E5EE'
    Tekst = Kolor '#1F2333'; TekstSlaby = Kolor '#6B7280'
    Akcent = Kolor '#2563EB'; AkcentHover = Kolor '#1D4ED8'; AkcentWcisniety = Kolor '#1E40AF'; AkcentJasny = Kolor '#EEF2FF'
    Zielony = Kolor '#16A34A'; ZielonyHover = Kolor '#15803D'; Ostrzezenie = Kolor '#D97706'; Czerwony = Kolor '#DC2626'
    Wylaczony = Kolor '#E5E7EB'; TekstWylaczony = Kolor '#9CA3AF'
    Nawigacja = Kolor '#161A2B'; NawHover = Kolor '#222740'; NawWybrany = Kolor '#2B3254'; NawTekst = Kolor '#A7AEC6'
    Czcionka = New-Object Drawing.Font('Segoe UI', 9.75)
    Pogrubiona = New-Object Drawing.Font('Segoe UI Semibold', 9.75)
    Tytul = New-Object Drawing.Font('Segoe UI Semibold', 18)
    Duza = New-Object Drawing.Font('Segoe UI Semibold', 15)
    Liczba = New-Object Drawing.Font('Segoe UI Semibold', 14)
    Mala = New-Object Drawing.Font('Segoe UI', 8.75)
    # Ikony z czcionki Windows 10/11; bez niej przyciski nawigacji sa po prostu bez ikon
    Ikony = $(if ((New-Object Drawing.Text.InstalledFontCollection).Families.Name -contains 'Segoe MDL2 Assets') { New-Object Drawing.Font('Segoe MDL2 Assets', 12) })
}

$KoloryOkna = @{
    Gray = Kolor '#374151'; DarkGray = Kolor '#9CA3AF'; White = Kolor '#111827'
    Green = $script:Styl.Zielony; Yellow = $script:Styl.Ostrzezenie
    Cyan = $script:Styl.Akcent; DarkCyan = [Drawing.Color]::Teal; DarkYellow = [Drawing.Color]::Peru
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

# Karta: panel z zaokraglonymi rogami. Rogi maluje kolorem rodzica, wnetrze swoim BackColor.
function Karta([hashtable]$w = @{}, [switch]$BezRamki) {
    $k = Kontrolka Panel $w
    if (-not $w.ContainsKey('BackColor')) { $k.BackColor = $script:Styl.Karta }
    if (-not $w.ContainsKey('Padding')) { $k.Padding = New-Object Windows.Forms.Padding(16) }
    PodwojnyBufor $k
    $k.AccessibleDescription = $(if ($BezRamki) { 'bez-ramki' } else { '' })
    $k.Add_Paint({
        $_.Graphics.Clear($this.Parent.BackColor)
        $r = New-Object Drawing.Rectangle(0, 0, ($this.Width - 1), ($this.Height - 1))
        WypelnijZaokraglony $_.Graphics $r 10 $this.BackColor $(if ($this.AccessibleDescription -ne 'bez-ramki') { $script:Styl.Ramka })
    })
    $k.Add_Resize({ $this.Invalidate() })
    $k
}

# Przycisk rysowany od zera. Style: glowny (niebieski), zielony, drugi (bialy z ramka), nav (pasek po lewej).
function Przycisk([string]$tekst, [string]$styl = 'glowny', [hashtable]$w = @{}) {
    $b = Kontrolka Button $w
    $b.Text = $tekst
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.UseVisualStyleBackColor = $false
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    if (-not $w.ContainsKey('Font')) { $b.Font = $script:Styl.Pogrubiona }
    $b.Tag = @{ Styl = $styl; Hover = $false; Wcisniety = $false; Wybrany = $false; Ikona = $w.AccessibleName }
    $b.Add_MouseEnter({ $this.Tag.Hover = $true; $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Tag.Wcisniety = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Tag.Wcisniety = $true; $this.Invalidate() })
    $b.Add_MouseUp({ $this.Tag.Wcisniety = $false; $this.Invalidate() })
    $b.Add_Paint({ RysujPrzycisk $this $_.Graphics })
    $b
}

function RysujPrzycisk($b, $g) {
    $s = $script:Styl; $t = $b.Tag
    $g.Clear($b.Parent.BackColor)
    $r = New-Object Drawing.Rectangle(0, 0, ($b.Width - 1), ($b.Height - 1))
    $ramka = $null
    switch ($t.Styl) {
        'nav' {
            $tlo = if ($t.Wybrany) { $s.NawWybrany } elseif ($t.Hover) { $s.NawHover } else { $s.Nawigacja }
            $kolor = if ($t.Wybrany) { [Drawing.Color]::White } else { $s.NawTekst }
        }
        'drugi' {
            $tlo = if (-not $b.Enabled) { $s.Karta } elseif ($t.Wcisniety -or $t.Hover) { $s.AkcentJasny } else { $s.Karta }
            $kolor = if ($b.Enabled) { $s.Akcent } else { $s.TekstWylaczony }
            $ramka = $s.Ramka
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
    WypelnijZaokraglony $g $r 7 $tlo $ramka
    if ($t.Styl -eq 'nav') {
        if ($t.Wybrany) { $a = New-Object Drawing.SolidBrush($s.Akcent); $g.FillRectangle($a, 0, 10, 3, $b.Height - 20); $a.Dispose() }
        $x = 16
        if ($s.Ikony -and $t.Ikona) {
            [Windows.Forms.TextRenderer]::DrawText($g, $t.Ikona, $s.Ikony, (New-Object Drawing.Rectangle(14, 0, 24, $b.Height)), $kolor, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter')
            $x = 48
        }
        [Windows.Forms.TextRenderer]::DrawText($g, $b.Text, $b.Font, (New-Object Drawing.Rectangle($x, 0, ($b.Width - $x - 6), $b.Height)), $kolor,
            [Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, SingleLine')
    }
    else {
        [Windows.Forms.TextRenderer]::DrawText($g, $b.Text, $b.Font, $r, $kolor, [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, EndEllipsis, SingleLine')
    }
}

# Dodaje kontrolki zadokowane - lista od zewnetrznej (pierwsza = najwyzej/najnizej przy krawedzi), Fill na koncu.
# WinForms dokuje od konca kolekcji, wiec dodajemy w odwrotnej kolejnosci.
function Dokuj($rodzic, [object[]]$lista) {
    [array]::Reverse($lista)
    foreach ($c in $lista) { $rodzic.Controls.Add($c) }
}
function Odstep([string]$dok = 'Top', [int]$ile = 14) { Kontrolka Panel @{ Dock = $dok; Height = $ile; Width = $ile } }

function Etykieta([string]$tekst, [hashtable]$w = @{}) {
    $l = Kontrolka Label $w
    $l.Text = $tekst
    if (-not $w.ContainsKey('Font')) { $l.Font = $script:Styl.Czcionka }
    if (-not $w.ContainsKey('ForeColor')) { $l.ForeColor = $script:Styl.Tekst }
    if (-not $w.ContainsKey('AutoSize') -and -not $w.ContainsKey('Dock')) { $l.AutoSize = $true }
    $l
}

# Naglowek strony: tytul i opis pod nim
function Naglowek([string]$tytul, [string]$opis) {
    $n = Kontrolka Panel @{ Dock = 'Top'; Height = 78 }
    $o = Etykieta $opis @{ Dock = 'Fill'; ForeColor = $script:Styl.TekstSlaby; AutoEllipsis = $true }
    $t = Etykieta $tytul @{ Dock = 'Top'; Height = 40; Font = $script:Styl.Tytul }
    Dokuj $n @($t, $o)
    @{ Panel = $n; Opis = $o }
}

function Lista([hashtable]$w) {
    $lv = Kontrolka ListView $w
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.ShowItemToolTips = $true
    $lv.BorderStyle = 'None'; $lv.Dock = 'Fill'; $lv.Font = $script:Styl.Czcionka; $lv.ForeColor = $script:Styl.Tekst
    # Wyzsze wiersze - ListView bierze wysokosc wiersza z listy obrazkow
    $il = New-Object Windows.Forms.ImageList
    $il.ImageSize = New-Object Drawing.Size(1, 28)
    $lv.SmallImageList = $il
    $lv
}

function Komunikat([string]$tekst, [string]$ikona = 'Information') {
    [void][Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, 'LLMCleaner', 'OK', $ikona)
}

# ---------- STAN ----------
# Blokuje przyciski na czas pracy i pokazuje pasek postepu
function Zajety([bool]$z) {
    foreach ($b in $script:UI.Akcje) { $b.Enabled = -not $z }
    foreach ($c in $script:UI.Dyski) { if ($c.Tag -ne $Sys) { $c.Enabled = -not $z } }
    $script:UI.Pasek.Visible = $z
    $script:UI.Okno.Cursor = $(if ($z) { [Windows.Forms.Cursors]::AppStarting } else { [Windows.Forms.Cursors]::Default })
    if (-not $z) { UstawPrzyciski }
    [Windows.Forms.Application]::DoEvents()
}

# Przycisk wlaczony tylko wtedy, gdy ma sens (po skanie, z AI, bez trybu podgladu)
function UstawPrzyciski {
    $ai = -not $BezLLM
    $script:UI.BtnWyjasnij.Enabled = $script:Zeskanowano -and $ai -and $script:Pozostalosci.Count
    $script:UI.BtnWyczysc.Enabled = $script:Zeskanowano -and -not $Podglad -and -not $script:PoCzyszczeniu
    $script:UI.BtnAnalizuj.Enabled = $script:Zeskanowano
    $script:UI.BtnAnalizaAi.Enabled = $script:Zeskanowano -and $ai -and $script:UI.LvAnaliza.Tag
    $script:UI.BtnWyslij.Enabled = $ai
    $script:UI.BtnDoPlanu.Visible = $script:Zeskanowano
    $script:UI.BtnSkan.Text = $(if ($script:Zeskanowano) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj' 'Scan' })
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
    foreach ($k in $script:UI.Strony.Keys) { $script:UI.Strony[$k].Visible = ($k -eq $id) }
    foreach ($k in $script:UI.Nav.Keys) { $script:UI.Nav[$k].Tag.Wybrany = ($k -eq $id); $script:UI.Nav[$k].Invalidate() }
    $script:UI.Strony[$id].BringToFront()
    if ($id -eq 'czat') { $script:UI.Pytanie.Focus() }
}

# ---------- PRZEGLAD ----------
function AktualizujPrzeglad {
    $u = $script:UI
    if (-not $script:Zeskanowano) { return }
    $suma = SumaZaznaczonych
    $u.Wynik.Text = $(if ($script:PoCzyszczeniu) { L 'Czyszczenie zakończone' 'Cleaning finished' }
                      elseif ($suma -gt 0) { (L 'Można zwolnić ok. {0}' 'About {0} can be freed') -f (Rozmiar $suma) }
                      else { L 'Komputer jest czysty' 'Your PC is clean' })
    $u.Wynik.ForeColor = $(if ($suma -gt 0 -and -not $script:PoCzyszczeniu) { $script:Styl.Akcent } else { $script:Styl.Zielony })
    $u.Etap.Text = $(if ($script:PoCzyszczeniu) { L 'Kliknij „Skanuj ponownie”, żeby zobaczyć aktualny stan.' 'Click "Scan again" to see the current state.' }
                     else { L 'Sprawdź plan czyszczenia - możesz odznaczyć wszystko, czego nie chcesz usuwać. Nic nie jest usuwane bez potwierdzenia.' 'Review the cleanup plan - untick anything you want to keep. Nothing is deleted without your confirmation.' })
    $u.StatZaznaczone.Text = Rozmiar $suma
    $u.StatKategorie.Text = "$(@($script:Kategorie | Where-Object { $_.Bajty -gt 0 }).Count)"
    $u.StatPozostalosci.Text = "$(@($script:Pozostalosci).Count)"
    $u.StatZablokowane.Text = Rozmiar ([double](@($script:Kategorie | ForEach-Object { [double]$_.Zablokowane }) | Measure-Object -Sum).Sum)
    $u.Statystyki.Visible = $true
}

# ---------- PLAN ----------
function AktualizujSume {
    $script:UI.Suma.Text = (L 'Zaznaczone razem: ok. {0}' 'Selected in total: about {0}') -f (Rozmiar (SumaZaznaczonych))
    AktualizujPrzeglad
}

function WypelnijPlan {
    $lv = $script:UI.LvPlan
    $script:Wypelniam = $true
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($k in $script:Kategorie) {
        $opis = if ($k.Blokada) { "! $($k.Blokada)" } elseif ($k.Uwaga) { "$($k.Opis) $($k.Uwaga)" } else { $k.Opis }
        $it = New-Object Windows.Forms.ListViewItem($k.Nazwa)
        [void]$it.SubItems.Add((RozmiarKategorii $k))
        [void]$it.SubItems.Add($(if ($k.Zablokowane) { Rozmiar $k.Zablokowane } else { '' }))
        [void]$it.SubItems.Add($(if ($k.TylkoRecznie) { L 'na życzenie' 'opt-in' } else { '' }))
        [void]$it.SubItems.Add($opis)
        $it.ToolTipText = $opis
        $it.Tag = $k
        $it.Group = $script:UI.GrKategorie
        $it.Checked = [bool]$k.Wybrana
        if ($k.Blokada) { $it.ForeColor = $script:Styl.Ostrzezenie } elseif ($k.TylkoRecznie) { $it.ForeColor = $script:Styl.TekstSlaby }
        [void]$lv.Items.Add($it)
    }
    foreach ($p in $script:Pozostalosci) {
        $pokaz = if ($p.Typ -eq 'rejestr' -and $p.Nazwa -ne (Split-Path $p.Sciezka -Leaf)) { "$($p.Nazwa)  [$($p.Sciezka)]" } else { $p.Sciezka }
        $opis = $p.Dlaczego
        if ($p.Ai) { $opis += "  |  $EtykietaAi`: $($p.Ai)" }
        $it = New-Object Windows.Forms.ListViewItem($pokaz)
        [void]$it.SubItems.Add($(if ($p.Typ -ne 'rejestr') { Rozmiar $p.Bajty } else { L 'rejestr' 'registry' }))
        [void]$it.SubItems.Add('')
        [void]$it.SubItems.Add((NazwaPewnosci $p.Pewnosc))
        [void]$it.SubItems.Add($opis)
        $it.ToolTipText = "$pokaz`n$opis"
        $it.Tag = $p
        $it.Group = $script:UI.GrPozostalosci
        $it.Checked = [bool]$p.Wybrana
        if ($p.Pewnosc -eq 'niska') { $it.ForeColor = $KoloryOkna.DarkYellow }
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    $script:Wypelniam = $false
    AktualizujSume
}

# ---------- ANALIZA ----------
function WypelnijAnalize($a) {
    $lv = $script:UI.LvAnaliza
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($p in @($a.Foldery) + @($a.Pliki)) {
        $sciezka = $p.Sciezka
        if ($p.Reszta) { $sciezka += L '  (pliki poza wymienionymi podfolderami)' '  (files outside the listed subfolders)' }
        $opis = @($p.Podpowiedz, $(if ($p.Ai) { "$EtykietaAi`: $($p.Ai)" })) | Where-Object { $_ }
        $it = New-Object Windows.Forms.ListViewItem((Rozmiar $p.Bajty))
        [void]$it.SubItems.Add($(if ($p.Ostatnio -gt [datetime]'1980-01-01') { $p.Ostatnio.ToString('yyyy-MM-dd') } else { '' }))
        [void]$it.SubItems.Add($sciezka)
        [void]$it.SubItems.Add(($opis -join '  |  '))
        $it.ToolTipText = "$sciezka`n$($opis -join "`n")"
        $it.Tag = $p.Sciezka
        $it.Group = $(if ($p.Typ -eq 'plik') { $script:UI.GrPliki } else { $script:UI.GrFoldery })
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    $lv.Tag = $a
    $info = (L 'Dysk {0}: zajęte {1} z {2}, wolne {3}. Tylko do wglądu - nic stąd nie jest usuwane. Dwuklik otwiera folder.' 'Drive {0}: {1} used of {2}, {3} free. Read-only - nothing here is deleted. Double-click opens the folder.') -f
        $a.Litera, (Rozmiar ($a.Rozmiar - $a.Wolne)), (Rozmiar $a.Rozmiar), (Rozmiar $a.Wolne)
    if ($a.Cienie -gt 0) { $info += ' ' + ((L 'Punkty przywracania: {0}.' 'Restore points: {0}.') -f (Rozmiar $a.Cienie)) }
    $niewidoczne = ($a.Rozmiar - $a.Wolne) - $a.Zeskanowane - $a.Cienie
    if ($niewidoczne -gt 2GB) { $info += ' ' + ((L 'Niedostępne dla skanera: ok. {0}.' 'Not readable by the scanner: about {0}.') -f (Rozmiar $niewidoczne)) }
    $script:UI.InfoAnaliza.Text = $info
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
function KafelekDysku($d) {
    $s = $script:Styl
    $nazwa = if ($d.VolumeName) { $d.VolumeName } else { L 'bez nazwy' 'no label' }
    $t = Karta @{ Size = (New-Object Drawing.Size(270, 86)); BackColor = $s.Kafelek; Margin = (New-Object Windows.Forms.Padding(0, 0, 12, 12)); Cursor = [Windows.Forms.Cursors]::Hand } -BezRamki
    $cb = Kontrolka CheckBox @{ Text = "$($d.DeviceID)  $nazwa"; AutoSize = $true; Checked = $true; Tag = $d.DeviceID; Location = (New-Object Drawing.Point(12, 10))
                                Font = $s.Pogrubiona; ForeColor = $s.Tekst; BackColor = $s.Kafelek; Cursor = [Windows.Forms.Cursors]::Hand }
    if ($d.DeviceID -eq $Sys) { $cb.Enabled = $false; $cb.Text += L '  (systemowy)' '  (system)' }
    elseif ($Dyski) { $cb.Checked = $d.DeviceID.TrimEnd(':') -in @($Dyski | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() }) }
    $info = Etykieta ((L 'wolne {0} z {1}' '{0} free of {1}') -f (Rozmiar $d.FreeSpace), (Rozmiar $d.Size)) @{ Location = (New-Object Drawing.Point(31, 36)); ForeColor = $s.TekstSlaby; BackColor = $s.Kafelek; Font = $s.Mala; Tag = $cb }
    $zajete = if ($d.Size -gt 0) { 1 - [double]$d.FreeSpace / [double]$d.Size } else { 0 }
    $pasek = Kontrolka Panel @{ Location = (New-Object Drawing.Point(33, 62)); Size = (New-Object Drawing.Size(222, 7)); BackColor = $s.Kafelek; Tag = $zajete }
    PodwojnyBufor $pasek
    $pasek.Add_Paint({
        $g = $_.Graphics; $g.Clear($this.BackColor)
        $r = New-Object Drawing.Rectangle(0, 0, ($this.Width - 1), ($this.Height - 1))
        WypelnijZaokraglony $g $r 3 $script:Styl.Ramka $null
        $w = [int](($this.Width - 1) * [double]$this.Tag)
        if ($w -gt 4) {
            $k = if ($this.Tag -gt 0.9) { $script:Styl.Czerwony } elseif ($this.Tag -gt 0.75) { $script:Styl.Ostrzezenie } else { $script:Styl.Akcent }
            WypelnijZaokraglony $g (New-Object Drawing.Rectangle(0, 0, $w, ($this.Height - 1))) 3 $k $null
        }
    })
    $t.Tag = $cb
    # Klik w dowolne miejsce kafelka przelacza dysk
    $przelacz = { $c = $this.Tag; if ($c.Enabled) { $c.Checked = -not $c.Checked } }
    $t.Add_Click($przelacz); $info.Add_Click($przelacz)
    $t.Controls.AddRange(@($cb, $info, $pasek))
    $script:UI.Dyski += $cb
    $t
}

function StronaPrzeglad {
    $s = $script:Styl
    $str = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo; Padding = (New-Object Windows.Forms.Padding(28, 20, 28, 16)) }
    $n = Naglowek (L 'Przegląd' 'Overview') (L 'Wybierz dyski i kliknij „Skanuj”. LLMCleaner sprawdzi śmieci systemowe, cache programów i pozostałości po odinstalowanych programach i grach.' 'Pick the drives and click "Scan". LLMCleaner checks system junk, app caches and leftovers of uninstalled programs and games.')

    # Karta wyniku: duzy napis, etap/opis, statystyki i przyciski
    $k = Karta @{ Dock = 'Top'; Size = (New-Object Drawing.Size(900, 216)); Padding = (New-Object Windows.Forms.Padding(24, 20, 24, 20)) }
    $wynik = Etykieta (L 'Gotowy do skanu' 'Ready to scan') @{ AutoSize = $false; Location = (New-Object Drawing.Point(24, 18)); Size = (New-Object Drawing.Size(620, 34)); Font = $s.Duza; BackColor = $s.Karta }
    $etap = Etykieta (L 'Skan trwa zwykle 1-3 minuty i niczego nie usuwa. Potem zobaczysz plan czyszczenia do sprawdzenia.' 'A scan usually takes 1-3 minutes and deletes nothing. Then you get a cleanup plan to review.') @{
        AutoSize = $false; AutoEllipsis = $true; Location = (New-Object Drawing.Point(24, 54)); Size = (New-Object Drawing.Size(620, 40)); ForeColor = $s.TekstSlaby; BackColor = $s.Karta }
    $staty = Kontrolka FlowLayoutPanel @{ Location = (New-Object Drawing.Point(22, 126)); Size = (New-Object Drawing.Size(856, 74)); WrapContents = $false; BackColor = $s.Karta; Visible = $false; Anchor = 'Top, Left, Right' }
    foreach ($st in @(@{ K = 'StatZaznaczone'; T = (L 'zaznaczone do czyszczenia' 'selected for cleaning') },
                      @{ K = 'StatKategorie'; T = (L 'kategorie z danymi' 'categories with data') },
                      @{ K = 'StatPozostalosci'; T = (L 'pozostałości po programach' 'program leftovers') },
                      @{ K = 'StatZablokowane'; T = (L 'zablokowane (pliki w użyciu)' 'locked (files in use)') })) {
        $kaf = Karta @{ Size = (New-Object Drawing.Size(190, 70)); BackColor = $s.Kafelek; Margin = (New-Object Windows.Forms.Padding(0, 0, 12, 0)) } -BezRamki
        $w = Etykieta '-' @{ Location = (New-Object Drawing.Point(14, 8)); Font = $s.Liczba; BackColor = $s.Kafelek }
        $o = Etykieta $st.T @{ Location = (New-Object Drawing.Point(15, 40)); Font = $s.Mala; ForeColor = $s.TekstSlaby; BackColor = $s.Kafelek }
        $kaf.Controls.AddRange(@($w, $o))
        $staty.Controls.Add($kaf)
        $script:UI[$st.K] = $w
    }
    $btnSkan = Przycisk (L 'Skanuj' 'Scan') 'glowny' @{ Size = (New-Object Drawing.Size(190, 48)); Location = (New-Object Drawing.Point(686, 22)); Anchor = 'Top, Right'
                                                     Font = (New-Object Drawing.Font('Segoe UI Semibold', 11.5)) }
    $btnPlan = Przycisk (L 'Zobacz plan czyszczenia' 'View the cleanup plan') 'drugi' @{ Size = (New-Object Drawing.Size(190, 40)); Location = (New-Object Drawing.Point(686, 80)); Anchor = 'Top, Right'; Visible = $false }
    $k.Controls.AddRange(@($wynik, $etap, $staty, $btnSkan, $btnPlan))
    # Teksty koncza sie przed kolumna przyciskow (kotwica Right liczy sie tu niepewnie)
    $k.Add_Resize({ $w = [Math]::Max(200, $this.Width - 270); $script:UI.Wynik.Width = $w; $script:UI.Etap.Width = $w })
    $script:UI.Wynik = $wynik; $script:UI.Etap = $etap; $script:UI.Statystyki = $staty; $script:UI.BtnSkan = $btnSkan; $script:UI.BtnDoPlanu = $btnPlan

    # Karta dyskow
    $kd = Karta @{ Dock = 'Fill'; Padding = (New-Object Windows.Forms.Padding(20, 14, 8, 8)) }
    $tyt = Etykieta (L 'Dyski do skanowania' 'Drives to scan') @{ Dock = 'Top'; Height = 32; Font = $s.Pogrubiona; BackColor = $s.Karta }
    $flow = Kontrolka FlowLayoutPanel @{ Dock = 'Fill'; AutoScroll = $true; BackColor = $s.Karta }
    $script:UI.Dyski = @()
    foreach ($d in DyskiStale) { $flow.Controls.Add((KafelekDysku $d)) }
    Dokuj $kd @($tyt, $flow)

    Dokuj $str @($n.Panel, $k, (Odstep), $kd)
    $str
}

function StronaPlan {
    $s = $script:Styl
    $str = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo; Padding = (New-Object Windows.Forms.Padding(28, 20, 28, 16)) }
    $n = Naglowek (L 'Plan czyszczenia' 'Cleanup plan') (L 'Zaznacz lub odznacz pozycje - nic nie jest usuwane bez potwierdzenia. Najedź na pozycję, żeby zobaczyć pełny opis. Foldery i pliki trafiają do Kosza, rejestr ma kopię .reg i punkt przywracania.' 'Tick or untick items - nothing is deleted without your confirmation. Hover over an item to see its full description. Folders and files go to the Recycle Bin; registry keys get a .reg backup and a restore point.')

    $k = Karta @{ Dock = 'Fill'; Padding = (New-Object Windows.Forms.Padding(10, 10, 4, 10)) }
    $lv = Lista @{ CheckBoxes = $true; HideSelection = $false }
    [void]$lv.Columns.Add((L 'Pozycja' 'Item'), 400)
    [void]$lv.Columns.Add((L 'Do usunięcia' 'Deletable'), 95, 'Right')
    [void]$lv.Columns.Add((L 'Zablokowane' 'Locked'), 95, 'Right')
    [void]$lv.Columns.Add((L 'Pewność' 'Confidence'), 90)
    [void]$lv.Columns.Add((L 'Opis' 'Description'), 560)
    $script:UI.GrKategorie = New-Object Windows.Forms.ListViewGroup((L 'Kategorie czyszczenia (odtwarzają się same)' 'Cleanup categories (they rebuild themselves)'))
    $script:UI.GrPozostalosci = New-Object Windows.Forms.ListViewGroup((L 'Pozostałości po odinstalowanych programach i grach (foldery i pliki idą do Kosza, rejestr - kopia .reg i punkt przywracania)' 'Leftovers of uninstalled programs and games (folders and files go to the Recycle Bin, registry - .reg backup and restore point)'))
    [void]$lv.Groups.Add($script:UI.GrKategorie)
    [void]$lv.Groups.Add($script:UI.GrPozostalosci)
    $lv.Add_ItemCheck({
        if ($script:Wypelniam) { return }
        $it = $script:UI.LvPlan.Items[$_.Index]
        if ($it.Tag.Blokada -and $_.NewValue -eq 'Checked') { $_.NewValue = 'Unchecked'; OknoStatus $it.Tag.Blokada }
    })
    $lv.Add_ItemChecked({
        if ($script:Wypelniam) { return }
        $_.Item.Tag.Wybrana = $_.Item.Checked
        AktualizujSume
    })
    $k.Controls.Add($lv)
    $script:UI.LvPlan = $lv

    # Pasek akcji pod lista
    $dol = Karta @{ Dock = 'Bottom'; Size = (New-Object Drawing.Size(900, 66)); Padding = (New-Object Windows.Forms.Padding(20, 0, 12, 0)) }
    $suma = Etykieta '' @{ Location = (New-Object Drawing.Point(20, 22)); Font = (New-Object Drawing.Font('Segoe UI Semibold', 11)); BackColor = $s.Karta }
    $btnWyczysc = Przycisk $(if ($Podglad) { L 'Podgląd - czyszczenie wyłączone' 'Preview - cleaning disabled' } else { L 'Wyczyść zaznaczone...' 'Clean selected...' }) 'glowny' @{
        Size = (New-Object Drawing.Size(220, 42)); Location = (New-Object Drawing.Point(668, 12)); Anchor = 'Top, Right' }
    $btnWyjasnij = Przycisk (L 'AI: czym były pozostałości?' 'AI: what were the leftovers?') 'drugi' @{ Size = (New-Object Drawing.Size(200, 42)); Location = (New-Object Drawing.Point(458, 12)); Anchor = 'Top, Right' }
    $dol.Controls.AddRange(@($suma, $btnWyjasnij, $btnWyczysc))
    $script:UI.Suma = $suma; $script:UI.BtnWyczysc = $btnWyczysc; $script:UI.BtnWyjasnij = $btnWyjasnij

    Dokuj $str @($n.Panel, $dol, (Odstep 'Bottom'), $k)
    $str
}

function StronaAnaliza {
    $s = $script:Styl
    $str = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo; Padding = (New-Object Windows.Forms.Padding(28, 20, 28, 16)) }
    $n = Naglowek (L 'Co zajmuje miejsce' 'What takes up space') (L 'Szybki skan całego dysku (zwykle 30 s - 3 min). Pokazuje najbardziej konkretne duże foldery i największe pliki. Tylko do wglądu - nic stąd nie jest usuwane.' 'A fast scan of the whole drive (usually 30 s - 3 min). Shows the most specific large folders and the largest files. Read-only - nothing here is deleted.')
    $script:UI.InfoAnaliza = $n.Opis

    $pas = Karta @{ Dock = 'Top'; Size = (New-Object Drawing.Size(900, 66)) }
    $lbl = Etykieta (L 'Dysk' 'Drive') @{ Location = (New-Object Drawing.Point(20, 23)); BackColor = $s.Karta; Font = $s.Pogrubiona }
    $cbo = Kontrolka ComboBox @{ DropDownStyle = 'DropDownList'; Location = (New-Object Drawing.Point(70, 19)); Width = 250; Font = $s.Czcionka; FlatStyle = 'Flat' }
    $btnAn = Przycisk (L 'Analizuj' 'Analyse') 'glowny' @{ Location = (New-Object Drawing.Point(334, 12)); Size = (New-Object Drawing.Size(130, 42)) }
    $btnAnAi = Przycisk (L 'AI: opisz i doradź' 'AI: describe and advise') 'drugi' @{ Location = (New-Object Drawing.Point(474, 12)); Size = (New-Object Drawing.Size(190, 42)) }
    $pas.Controls.AddRange(@($lbl, $cbo, $btnAn, $btnAnAi))
    $script:UI.CboDysk = $cbo; $script:UI.BtnAnalizuj = $btnAn; $script:UI.BtnAnalizaAi = $btnAnAi

    $k = Karta @{ Dock = 'Fill'; Padding = (New-Object Windows.Forms.Padding(10, 10, 4, 10)) }
    $lvA = Lista @{}
    [void]$lvA.Columns.Add((L 'Rozmiar' 'Size'), 90, 'Right')
    [void]$lvA.Columns.Add((L 'Zmieniono' 'Changed'), 90)
    [void]$lvA.Columns.Add((L 'Ścieżka' 'Path'), 480)
    [void]$lvA.Columns.Add((L 'Podpowiedź i rada AI' 'Hint and AI advice'), 520)
    $script:UI.GrFoldery = New-Object Windows.Forms.ListViewGroup((L 'Największe foldery' 'Largest folders'))
    $script:UI.GrPliki = New-Object Windows.Forms.ListViewGroup((L 'Największe pliki' 'Largest files'))
    [void]$lvA.Groups.Add($script:UI.GrFoldery)
    [void]$lvA.Groups.Add($script:UI.GrPliki)
    $lvA.Add_DoubleClick({
        $s = $script:UI.LvAnaliza.SelectedItems[0].Tag
        if ($s) { Start-Process explorer.exe -ArgumentList "/select,`"$s`"" }
    })
    $k.Controls.Add($lvA)
    $script:UI.LvAnaliza = $lvA

    Dokuj $str @($n.Panel, $pas, (Odstep), $k)
    $str
}

function StronaCzat {
    $s = $script:Styl
    $str = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo; Padding = (New-Object Windows.Forms.Padding(28, 20, 28, 16)) }
    $n = Naglowek (L 'Asystent AI' 'AI assistant') $(if ($BezLLM) { L 'Asystent jest wyłączony (uruchomiono z -BezLLM).' 'The assistant is disabled (started with -BezLLM).' }
        else { (L 'Lokalny model {0} - działa na tym komputerze, nic nie wysyła do internetu i niczego nie usuwa.' 'Local model {0} - runs on this computer, sends nothing to the internet and never deletes anything.') -f $Model })

    $k = Karta @{ Dock = 'Fill'; Padding = (New-Object Windows.Forms.Padding(18, 14, 6, 10)) }
    $czat = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = (New-Object Drawing.Font('Segoe UI', 10.5)) }
    # Tekst powitalny wpisuje Shown - RichTextBox gubi kolory ustawione przed utworzeniem okna
    $czat.Tag = $(if ($BezLLM) { '' }
                   else { L "Zapytaj o plan, foldery, programy albo gry. Asystent zna wyniki skanu i analizy dysku.`r`nPrzed skanem odpowiada tylko ogólnie - żeby pytać o pliki tego komputera, najpierw kliknij `„Skanuj`”.`r`nPierwsze pytanie uruchamia model (ok. 10-20 s).`r`n`r`n" "Ask about the plan, folders, programs or games. The assistant knows the scan and disk analysis results.`r`nBefore a scan it only answers in general terms - to ask about the files on this computer, click ""Scan"" first.`r`nThe first question starts the model (about 10-20 s).`r`n`r`n" })
    $k.Controls.Add($czat)
    $script:UI.Czat = $czat

    # Pole pytania: biala karta z polem bez ramki i przyciskiem
    $dol = Karta @{ Dock = 'Bottom'; Size = (New-Object Drawing.Size(900, 60)); Padding = (New-Object Windows.Forms.Padding(18, 9, 9, 9)) }
    $btnW = Przycisk (L 'Wyślij' 'Send') 'glowny' @{ Dock = 'Right'; Width = 120 }
    $pole = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Karta; Padding = (New-Object Windows.Forms.Padding(0, 10, 12, 0)) }
    $pyt = Kontrolka TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = (New-Object Drawing.Font('Segoe UI', 10.5)) }
    $pole.Controls.Add($pyt)
    Dokuj $dol @($btnW, $pole)
    $pyt.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; if ($script:UI.BtnWyslij.Enabled) { $script:UI.BtnWyslij.PerformClick() } } })
    $script:UI.Pytanie = $pyt; $script:UI.BtnWyslij = $btnW

    Dokuj $str @($n.Panel, $dol, (Odstep 'Bottom'), $k)
    $str
}

function StronaDziennik {
    $s = $script:Styl
    $str = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo; Padding = (New-Object Windows.Forms.Padding(28, 20, 28, 16)) }
    $n = Naglowek (L 'Dziennik' 'Log') ((L 'Przebieg skanu i czyszczenia. Pełny log: {0}' 'Scan and cleaning progress. Full log: {0}') -f $LogPlik)
    $k = Karta @{ Dock = 'Fill'; Padding = (New-Object Windows.Forms.Padding(16, 12, 6, 10)) }
    $log = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Karta; Font = (New-Object Drawing.Font('Consolas', 9.5)); WordWrap = $false }
    $k.Controls.Add($log)
    $script:UI.Log = $log
    Dokuj $str @($n.Panel, $k)
    $str
}

function PasekNawigacji {
    $s = $script:Styl
    $nav = Kontrolka Panel @{ Dock = 'Left'; Width = 232; BackColor = $s.Nawigacja; Padding = (New-Object Windows.Forms.Padding(12, 18, 12, 14)) }

    $logo = Kontrolka Panel @{ Dock = 'Top'; Height = 66; BackColor = $s.Nawigacja }
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) {
        $pb = Kontrolka PictureBox @{ Location = (New-Object Drawing.Point(6, 4)); Size = (New-Object Drawing.Size(36, 36)); SizeMode = 'Zoom'; BackColor = $s.Nawigacja }
        $pb.Image = ObrazZIkony $ico 48
        $logo.Controls.Add($pb)
    }
    $logo.Controls.Add((Etykieta 'LLMCleaner' @{ Location = (New-Object Drawing.Point(48, 2)); ForeColor = [Drawing.Color]::White; BackColor = $s.Nawigacja; Font = (New-Object Drawing.Font('Segoe UI Semibold', 13)) }))
    $logo.Controls.Add((Etykieta ((L 'wersja {0}' 'version {0}') -f $Wersja) @{ Location = (New-Object Drawing.Point(50, 27)); ForeColor = $s.NawTekst; BackColor = $s.Nawigacja; Font = $s.Mala }))

    $script:UI.Nav = @{}
    $pozycje = @(
        @{ Id = 'przeglad'; T = (L 'Przegląd' 'Overview'); I = [char]0xE80F }
        @{ Id = 'plan'; T = (L 'Plan czyszczenia' 'Cleanup plan'); I = [char]0xE74D }
        @{ Id = 'analiza'; T = (L 'Co zajmuje miejsce' 'What takes up space'); I = [char]0xEDA2 }
        @{ Id = 'czat'; T = (L 'Asystent AI' 'AI assistant'); I = [char]0xE8BD }
        @{ Id = 'log'; T = (L 'Dziennik' 'Log'); I = [char]0xE81C })
    $lista = @()
    foreach ($p in $pozycje) {
        $b = Przycisk $p.T 'nav' @{ Dock = 'Top'; Height = 44; Font = (New-Object Drawing.Font('Segoe UI', 10)); AccessibleName = "$($p.I)"; Name = $p.Id }
        $b.Add_Click({ PokazStrone $this.Name })
        $script:UI.Nav[$p.Id] = $b
        $lista += $b, (Kontrolka Panel @{ Dock = 'Top'; Height = 4 })
    }

    # Dol paska: stan asystenta, tryb podgladu, aktualizacja
    $dol = Kontrolka Panel @{ Dock = 'Bottom'; Height = 110; BackColor = $s.Nawigacja }
    $ai = Etykieta $(if ($BezLLM) { L 'Asystent AI: wyłączony' 'AI assistant: off' } else { (L "Asystent AI: na żądanie`r`n{0}" "AI assistant: on demand`r`n{0}") -f $Model }) @{
        Dock = 'Bottom'; Height = 40; ForeColor = $s.NawTekst; BackColor = $s.Nawigacja; Font = $s.Mala }
    $btnAkt = Przycisk '' 'zielony' @{ Dock = 'Bottom'; Height = 40; Visible = $false }
    $dol.Controls.Add($btnAkt); $dol.Controls.Add((Kontrolka Panel @{ Dock = 'Bottom'; Height = 8 }))
    if ($Podglad) {
        $dol.Controls.Add((Etykieta (L 'TRYB PODGLĄDU - nic nie zostanie usunięte' 'PREVIEW MODE - nothing will be deleted') @{ Dock = 'Bottom'; Height = 34; ForeColor = (Kolor '#FBBF24'); BackColor = $s.Nawigacja; Font = $s.Mala }))
    }
    $dol.Controls.Add($ai)
    $script:UI.BtnAkt = $btnAkt

    Dokuj $nav (@($logo) + $lista + @($dol))
    $nav
}

# ---------- OKNO ----------
function PokazOkno {
    $script:Tryb = 'okno'
    # Konsola PowerShella nie jest potrzebna, gdy jest okno
    if (-not ('LlmWin.Konsola' -as [type])) {
        Add-Type -Name Konsola -Namespace LlmWin -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
'@
    }
    if (-not $script:TestPoStarcie) { [void][LlmWin.Konsola]::ShowWindow([LlmWin.Konsola]::GetConsoleWindow(), 0) }

    [Windows.Forms.Application]::EnableVisualStyles()
    $s = $script:Styl
    $f = Kontrolka Form @{ Text = "LLMCleaner $Wersja"; Size = (New-Object Drawing.Size(1240, 800)); MinimumSize = (New-Object Drawing.Size(1000, 640))
                           StartPosition = 'CenterScreen'; Font = $s.Czcionka; BackColor = $s.Tlo }
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) { $f.Icon = New-Object Drawing.Icon $ico }
    $script:UI.Okno = $f

    # Strony (wszystkie Fill, widoczna jedna) i pasek stanu pod nimi
    $tresc = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo }
    $script:UI.Strony = [ordered]@{ przeglad = (StronaPrzeglad); plan = (StronaPlan); analiza = (StronaAnaliza); czat = (StronaCzat); log = (StronaDziennik) }
    $stan = Kontrolka Panel @{ Dock = 'Bottom'; Height = 30; BackColor = $s.Tlo; Padding = (New-Object Windows.Forms.Padding(30, 0, 30, 10)) }
    $st = Etykieta (L 'Gotowy. Wybierz dyski i kliknij „Skanuj”.' 'Ready. Pick the drives and click "Scan".') @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; Font = $s.Mala; AutoEllipsis = $true; TextAlign = 'MiddleLeft' }
    $pb = Kontrolka ProgressBar @{ Dock = 'Right'; Width = 160; Style = 'Marquee'; MarqueeAnimationSpeed = 30; Visible = $false }
    Dokuj $stan @($pb, $st)
    Dokuj $tresc (@($stan) + @($script:UI.Strony.Values))
    Dokuj $f @((PasekNawigacji), $tresc)
    $script:UI.Status = $st; $script:UI.Pasek = $pb
    $u = $script:UI
    $script:UI.Akcje = @($u.BtnSkan, $u.BtnWyczysc, $u.BtnWyjasnij, $u.BtnAnalizuj, $u.BtnAnalizaAi, $u.BtnWyslij, $u.BtnAkt)

    # ---------- ZDARZENIA ----------
    $u.BtnSkan.Add_Click({ Akcja {
        UstawDyski @($script:UI.Dyski | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        PokazStrone 'przeglad'
        $script:UI.Log.Clear()
        $script:UI.Statystyki.Visible = $false
        $script:UI.Wynik.Text = L 'Skanowanie...' 'Scanning...'
        $script:UI.Wynik.ForeColor = $script:Styl.Tekst
        $script:UI.Skanuje = $true
        $ok = $false
        try {
            OknoWypisz ((L '1/2  Skanowanie dysków: {0}' '1/2  Scanning drives: {0}') -f ($script:WybraneDyski -join ', ')) 'Cyan'
            SkanujWszystko
            $ok = $true
        }
        finally {
            $script:UI.Skanuje = $false
            if (-not $ok) {
                $script:UI.Wynik.Text = L 'Skan nie powiódł się' 'The scan failed'
                $script:UI.Wynik.ForeColor = $script:Styl.Czerwony
                $script:UI.Etap.Text = L 'Szczegóły są w Dzienniku.' 'See the Log for details.'
            }
        }
        $script:Zeskanowano = $true
        $script:PoCzyszczeniu = $false
        $script:Rozmowa = $null
        WypelnijPlan
        $script:UI.CboDysk.Items.Clear()
        foreach ($d in DyskiWybrane) { [void]$script:UI.CboDysk.Items.Add((OpisDysku $d)) }
        $script:UI.CboDysk.SelectedIndex = 0
        OknoStatus ((L 'Skan zakończony. Sprawdź plan i kliknij „Wyczyść zaznaczone...”.' 'Scan finished. Review the plan and click "Clean selected...".'))
    } })

    $u.BtnDoPlanu.Add_Click({ PokazStrone 'plan' })

    $u.BtnWyjasnij.Add_Click({ Akcja {
        OknoStatus (L 'Model opisuje pozostałości (ok. 20-40 s)...' 'The model is describing the leftovers (about 20-40 s)...')
        $n = WyjasnijPozostalosci
        WypelnijPlan
        OknoStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji (kolumna Opis, dopisek AI).' '{0} items described (Description column, AI note).') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
    } })

    $u.BtnWyczysc.Add_Click({
        $linie = Podsumowanie
        if (-not $linie) { Komunikat (L 'Nic nie jest zaznaczone - nie ma czego czyścić.' 'Nothing is selected - there is nothing to clean.'); return }
        $tekst = (($linie | ForEach-Object { $_.T -replace '\s{2,}', '  ' }) -join "`r`n") + "`r`n`r`n" + (L 'Uruchomić czyszczenie?' 'Start cleaning?')
        $odp = [Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, (L 'LLMCleaner - podsumowanie przed czyszczeniem' 'LLMCleaner - summary before cleaning'), 'YesNo', 'Warning', 'Button2')
        if ($odp -ne 'Yes') { return }
        Akcja {
            PokazStrone 'log'
            OknoWypisz ''
            OknoWypisz (L '2/2  Czyszczenie' '2/2  Cleaning') 'Cyan'
            $w = WykonajCzyszczenie
            $script:PoCzyszczeniu = $true
            $linie = TekstPoCzyszczeniu $w
            OknoWypisz ''
            foreach ($x in $linie) { OknoWypisz "  $x" 'White' }
            OknoWypisz "  Log: $LogPlik" 'DarkGray'
            AktualizujPrzeglad
            OknoStatus (L 'Czyszczenie zakończone. Kliknij „Skanuj ponownie”, żeby zobaczyć aktualny stan.' 'Cleaning finished. Click "Scan again" to see the current state.')
            Komunikat ((($linie | ForEach-Object { $_ -replace '\s{2,}', '  ' }) -join "`r`n") + "`r`n`r`nLog: $LogPlik")
        }
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
        $a = $script:UI.LvAnaliza.Tag
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
            if ($a) { DopiszCzat 'LLMCleaner' $a ([Drawing.Color]::Teal); OknoStatus '' }
            else { DopiszCzat 'LLMCleaner' (L '(brak odpowiedzi - szczegóły w Dzienniku)' '(no answer - see the Log)') $script:Styl.TekstSlaby }
        }
        $script:UI.Pytanie.Focus()
    })

    $u.BtnAkt.Add_Click({ Akcja {
        if (ZainstalujAktualizacje) { $script:UI.Okno.Close() }
    } })

    $f.Add_Shown({
        PokazStrone 'przeglad'
        UstawPrzyciski
        $c = $script:UI.Czat
        $c.AppendText($c.Tag)
        $c.SelectAll(); $c.SelectionColor = $script:Styl.TekstSlaby; $c.Select($c.TextLength, 0)
        # Podpowiedz w pustym polu pytania (EM_SETCUEBANNER)
        [void][LlmWin.Konsola]::SendMessage($script:UI.Pytanie.Handle, 0x1501, [IntPtr]1, (L 'Napisz pytanie i naciśnij Enter...' 'Type a question and press Enter...'))
        if (-not $BezAktualizacji) {
            OknoStatus (L 'Sprawdzam aktualizacje...' 'Checking for updates...')
            SprawdzAktualizacje
            if ($script:Aktualizacja) {
                $script:UI.BtnAkt.Text = (L 'Zainstaluj wersję {0}' 'Install version {0}') -f $script:Aktualizacja.Wersja
                $script:UI.BtnAkt.Visible = $true
            }
            OknoStatus (L 'Gotowy. Wybierz dyski i kliknij „Skanuj”.' 'Ready. Pick the drives and click "Scan".')
        }
        # Tylko dla testow: ustawiane przez skrypt testowy w tym samym procesie (nigdy ze zmiennych srodowiska)
        if ($script:TestPoStarcie) { & $script:TestPoStarcie }
    })
    $f.Add_FormClosed({ ZatrzymajOllama; Log 'Koniec (okno).' })

    Log "Start (okno). Model: $Model, Podglad: $Podglad, BezLLM: $BezLLM, Jezyk: $Jezyk"
    [void]$f.ShowDialog()
}
