<#
    LLMCleaner - rysowanie: ksztalty, tekst, pigulki, pola wyboru, przelaczniki, przyciski
#>

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

# Przycisk o stalej szerokosci rosnie, gdy napis by sie nie zmiescil (zamiast ucinac go wielokropkiem)
function DopasujSzerokosc($b) {
    if ("$($b.Dock)" -in 'Fill', 'Top', 'Bottom' -or -not $b.Text) { return }
    $min = (SzerTekstu $b.Text $b.Font) + (Px 32)
    if ($b.Width -lt $min) { $b.Width = $min }
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
