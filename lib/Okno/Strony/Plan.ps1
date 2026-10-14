<#
    LLMCleaner - strona Plan czyszczenia
#>

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
        $dl = [int][Math]::Max((Px 4), $szerBar * [double]$o.Bajty / [Math]::Max(1.0, [double]$w.Max))
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
                Prawy = { SumaGrupy $script:Kategorie }
            })
        foreach ($k in $wk) { $wiersze.Add(@{ H = (Px 60); Obj = $k; Kat = $true; Max = $max }) }
    }
    $wp = @($poz | Where-Object { PasujeDoFiltra $_ $false })
    if ($wp.Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 44); Tekst = (L 'Pozostałości po odinstalowanych programach i grach' 'Leftovers of uninstalled programs and games')
                Prawy = { SumaGrupy $script:Pozostalosci }
            })
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
    $najszerszy = ($filtr.Tag.Opcje | ForEach-Object { SzerTekstu $_.T $s.Pogrubiona } | Measure-Object -Maximum).Maximum
    $filtr.Width = [Math]::Max((Px 300), 3 * ([int]$najszerszy + (Px 24)) + (Px 6))
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
    $pas.Add_Resize({ if ($script:UI.SzukajKarta) { $script:UI.SzukajKarta.Width = [Math]::Max((Px 160), [Math]::Min((Px 320), $this.Width - $script:UI.FiltrPlanu.Width - $script:UI.BtnZalecane.Width - $script:UI.BtnOdznacz.Width - (Px 34))) } })
    $script:UI.BtnZalecane = $btnZal; $script:UI.BtnOdznacz = $btnOdz; $script:UI.FiltrPlanu = $filtr

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
