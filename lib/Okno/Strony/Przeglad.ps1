<#
    LLMCleaner - strona Przeglad
#>

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
            Wybrana = [bool]@($poz | Where-Object { $_.Wybrana }).Count
        }
    }
    $el = @($el | Sort-Object { $_.Bajty } -Descending)
    if ($el.Count -gt 7) {
        $reszta = $el[6..($el.Count - 1)]
        $el = @($el[0..5]) + @(@{ Nazwa = (L 'Pozostałe pozycje' 'Other items'); Bajty = [double]($reszta | ForEach-Object { $_.Bajty } | Measure-Object -Sum).Sum
                Wybrana = [bool]@($reszta | Where-Object { $_.Wybrana }).Count
            })
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
    $max = [Math]::Max(1.0, ($dane | ForEach-Object { $_.Bajty } | Measure-Object -Maximum).Maximum)
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
        Dock = 'Top'; Height = (Px 44); ForeColor = $s.TekstSlaby; AutoEllipsis = $true
    }
    $rzad = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 46) }
    $btnStart = Przycisk (L 'Skanuj teraz' 'Scan now') 'glowny' @{ Dock = 'Left'; Width = (Px 200) }
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
