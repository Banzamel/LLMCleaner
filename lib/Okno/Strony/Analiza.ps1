<#
    LLMCleaner - strona Analiza dysku
#>

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
