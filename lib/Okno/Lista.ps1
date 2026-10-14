<#
    LLMCleaner - lista rysowana od zera (wiersze, sekcje, przewijanie)
#>

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
            $gora = - $dy; $dol = $gora + $this.ClientSize.Height
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
