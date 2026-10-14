<#
    LLMCleaner - strona Sterowniki
#>

function KolorStanuSterownika([string]$stan) {
    $s = $script:Styl
    switch ($stan) {
        'nowy' { return @{ T = $s.BlekitTlo; K = $s.BlekitTekst } }
        'czeka' { return @{ T = $s.NeutralTlo; K = $s.NeutralTekst } }
        'ok' { return @{ T = $s.OkTlo; K = $s.OkTekst } }
        'restart' { return @{ T = $s.UwagaTlo; K = $s.UwagaTekst } }
    }
    if ($stan -in 'szukanie', 'pobieranie', 'instalacja') { return @{ T = $s.AkcentJasny; K = $s.AkcentTekst } }
    @{ T = $s.BladTlo; K = $s.BladTekst }
}

# Sterownik mozna zaznaczyc, dopoki nie jest zainstalowany (blad mozna ponowic)
function SterownikDoWyboru($d) { -not $Podglad -and -not $script:Pracuje -and $d.Stan -in 'nowy', 'blad' }

function RysujWierszSterownika($g, $w, $r, [bool]$hover) {
    if ($w.Sekcja) { RysujSekcje $g $w $r; return }
    $s = $script:Styl; $d = $w.Obj
    TloWiersza $g $r $hover
    $sr = $r.Y + [int]($r.Height / 2)
    $xN = Px 64
    if ($w.Problem) {
        # Urzadzenie z bledem w Menedzerze urzadzen - tylko do wgladu
        Prostokat $g (Px 20) ($sr - (Px 16)) (Px 32) (Px 32) $s.UwagaTlo (Px 8)
        if ($s.Ikony) { Tekst $g ([string][char]0xE7BA) $s.Ikony $s.UwagaTekst (Px 20) ($sr - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
        else { Tekst $g '!' $s.Pogrubiona $s.UwagaTekst (Px 20) ($sr - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
        $szer = $r.Width - $xN - (Px 18)
        Tekst $g $d.Nazwa $s.Pogrubiona $s.Tekst $xN ($sr - (Px 21)) $szer (Px 21)
        Tekst $g $d.Opis $s.Mala $s.Ostrzezenie $xN ($sr + (Px 1)) $szer (Px 20)
        return
    }
    PoleWyboru $g (Px 26) ($sr - (Px 9)) ([bool]$d.Wybrana) (-not (SterownikDoWyboru $d))
    $xS = $r.Width - (Px 20) - (Px 124)
    $xR = $xS - (Px 12) - (Px 84)
    $szerN = $xR - (Px 14) - $xN
    Tekst $g $d.Nazwa $s.Pogrubiona $(if ($d.Stan -in 'ok', 'restart') { $s.TekstSlaby } else { $s.Tekst }) $xN ($sr - (Px 31)) $szerN (Px 22)
    $druga = (@($d.Dostawca, $d.Klasa) | Where-Object { $_ }) -join ' · '
    Tekst $g $druga $s.Mala $s.TekstSlaby $xN ($sr - (Px 9)) $szerN (Px 20)
    if ($d.Stan -eq 'blad') { $trzecia = (L 'Nie udało się: {0}' 'Failed: {0}') -f $d.Blad; $kol = $s.Czerwony }
    else {
        $teraz = if ($d.ObecnaWersja) { OpisWersji $d.ObecnaWersja $d.ObecnaData } elseif ($d.Problem) { $d.Problem } else { L 'nieznany' 'unknown' }
        $trzecia = (L 'Teraz: {0}   →   nowy: {1}' 'Now: {0}   →   new: {1}') -f $teraz, (OpisWersji $d.Wersja $d.Data)
        $kol = if ($d.Problem -and -not $d.ObecnaWersja) { $s.Ostrzezenie } else { $s.Tekst }
    }
    Tekst $g $trzecia $s.Mala $kol $xN ($sr + (Px 11)) $szerN (Px 20)
    Tekst $g $(if ($d.Bajty -gt 0) { Rozmiar $d.Bajty } else { '' }) $s.Czcionka $s.TekstSlaby $xR ($sr - (Px 12)) (Px 84) (Px 24) 'Right'
    $k = KolorStanuSterownika $d.Stan
    [void](Pigulka $g (NazwaStanuSterownika $d.Stan) $xS $sr $k.T $k.K)
}

function RysujPodsumowanieSterownikow($g, $p) {
    $st = @($script:Sterowniki | Where-Object { $_ })
    $nic = $null -eq $script:Sterowniki
    $dane = @(
        @{ W = $(if ($nic) { '-' } else { "$(@($st | Where-Object { $_.Stan -notin 'ok', 'restart' }).Count)" }); O = (L 'nowszych sterowników' 'newer drivers') }
        @{ W = $(if ($nic) { '-' } else { "$(@($st | Where-Object { $_.Wybrana }).Count)" }); O = (L 'zaznaczone do instalacji' 'selected to install') }
        @{ W = $(if ($nic) { '-' } else { "$(@($script:UrzadzeniaZProblemem | Where-Object { $_ }).Count)" }); O = (L 'urządzenia z problemem' 'devices with a problem') })
    $t = if ($Podglad) { L 'Tryb podglądu - możesz sprawdzić sterowniki, ale nie instalować.' 'Preview mode - you can check for drivers but not install them.' }
    else { L 'Sterowniki z Windows Update, jak aktualizacje opcjonalne w Ustawieniach. Przed instalacją powstaje punkt przywracania.' 'Drivers from Windows Update, like the optional updates in Settings. A restore point is created before installing.' }
    KafelkiZNotka $g $p $dane $t
}

function WypelnijSterowniki {
    $wiersze = [System.Collections.Generic.List[object]]::new()
    $st = @($script:Sterowniki | Where-Object { $_ })
    $pr = @($script:UrzadzeniaZProblemem | Where-Object { $_ })
    if ($st.Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 40); Tekst = (L 'Nowsze sterowniki z Windows Update' 'Newer drivers from Windows Update'); Prawy = { SumaGrupy $script:Sterowniki } })
        foreach ($d in ($st | Sort-Object { $_.Klasa }, { $_.Nazwa })) { $wiersze.Add(@{ H = (Px 74); Obj = $d }) }
    }
    elseif ($null -ne $script:Sterowniki -and $pr.Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 40); Tekst = (L 'Windows Update nie ma nowszych sterowników dla tego komputera' 'Windows Update has no newer drivers for this PC') })
    }
    if ($pr.Count) {
        $wiersze.Add(@{ Sekcja = $true; H = (Px 44); Tekst = (L 'Urządzenia z problemem w Menedżerze urządzeń' 'Devices with a problem in Device Manager') })
        foreach ($p in $pr) { $wiersze.Add(@{ H = (Px 58); Obj = $p; Problem = $true }) }
    }
    $script:UI.LvSterowniki.Tag.Pusty = if ($null -eq $script:Sterowniki) { L 'Kliknij „Sprawdź”, żeby poszukać nowszych sterowników w Windows Update. Trwa to zwykle 1-3 minuty i niczego nie instaluje.' 'Click "Check" to look for newer drivers on Windows Update. It usually takes 1-3 minutes and installs nothing.' }
    else { L 'Sterowniki są aktualne według Windows Update i żadne urządzenie nie zgłasza problemu.' 'Your drivers are up to date according to Windows Update and no device reports a problem.' }
    UstawWiersze $script:UI.LvSterowniki $wiersze
    AktualizujSumeSterownikow
}

function AktualizujSumeSterownikow {
    $u = $script:UI
    $wyb = @($script:Sterowniki | Where-Object { $_ -and $_.Wybrana })
    if ($null -eq $script:Sterowniki) {
        $u.SterSuma.Text = L 'Nie sprawdzono' 'Not checked yet'
        $u.SterOpis.Text = L 'Sprawdzenie łączy się z Windows Update. Wcześniej żadne dane nie są wysyłane.' 'Checking connects to Windows Update. Nothing is sent before that.'
    }
    else {
        $u.SterSuma.Text = (L 'Zaznaczone: {0}' 'Selected: {0}') -f $wyb.Count
        $u.SterOpis.Text = (L 'Do pobrania do {0}. Przy sterowniku karty graficznej ekran może na chwilę zgasnąć. Część sterowników zadziała po ponownym uruchomieniu.' 'Up to {0} to download. With a graphics driver the screen may go blank for a moment. Some drivers take effect after a restart.') -f
            (Rozmiar ([double]($wyb | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum))
    }
    $u.SterPodsum.Invalidate()
    $u.LvSterowniki.Invalidate()
    if (-not $script:Pracuje) { UstawPrzyciski }
}

# Instalacja zaznaczonych: punkt przywracania, potem po kolei pobranie i instalacja. Stan wierszy
# odswieza zegar okna, bo instalacja idzie w osobnym watku.
function InstalujSterownikiZOknem($wyb) {
    $u = $script:UI
    $script:InstalujeSterowniki = $true
    try {
        foreach ($d in $wyb) { $d.Stan = 'czeka'; $d.Blad = '' }
        $u.LvSterowniki.Invalidate()
        OknoStatus (L 'Tworzę punkt przywracania systemu...' 'Creating a System Restore point...')
        $pp = PunktPrzywracania
        Log "Punkt przywracania (sterowniki): $($pp.Opis)"
        OknoWypisz ((L '  Punkt przywracania: {0}' '  Restore point: {0}') -f $pp.Opis) $(if ($pp.Ok) { 'Green' } else { 'Yellow' })
        OknoStatus (L 'Instaluję sterowniki z Windows Update. Nie wyłączaj komputera...' 'Installing drivers from Windows Update. Do not turn off the computer...')
        PostepNaPasku 1
        $stan = [hashtable]::Synchronized(@{})
        $zegar = New-Object Windows.Forms.Timer
        $zegar.Interval = 400
        $zegar.Tag = @{ Stan = $stan; Lista = $wyb }
        $zegar.Add_Tick({
                foreach ($d in $this.Tag.Lista) { $w = "$($this.Tag.Stan[$d.Id])"; if ($w -and $w -notlike 'blad:*') { $d.Stan = $w } }
                $script:UI.LvSterowniki.Invalidate()
            })
        $zegar.Start()
        try { [void](ZainstalujSterowniki $wyb $stan) }
        finally { $zegar.Stop(); $zegar.Dispose(); PostepNaPasku 0 }
    }
    finally { $script:InstalujeSterowniki = $false }

    foreach ($d in $wyb) {
        $kol = switch ($d.Stan) { 'ok' { 'Green' } 'restart' { 'Green' } default { 'Yellow' } }
        $dop = if ($d.Blad) { ": $($d.Blad)" } else { '' }
        OknoWypisz ("  {0} {1}: {2}{3}" -f $d.Nazwa, $d.Wersja, (NazwaStanuSterownika $d.Stan), $dop) $kol
    }
    WypelnijSterowniki
    $ok = @($wyb | Where-Object { $_.Stan -eq 'ok' }).Count
    $rs = @($wyb | Where-Object { $_.Stan -eq 'restart' }).Count
    $zle = $wyb.Count - $ok - $rs
    $t = (L 'Zainstalowano sterowników: {0} z {1}.' 'Drivers installed: {0} of {1}.') -f ($ok + $rs), $wyb.Count
    if ($rs) { $t += ' ' + ((L 'Uruchom ponownie komputer, żeby dokończyć instalację ({0}).' 'Restart the computer to finish installing ({0}).') -f $rs) }
    if ($zle) { $t += ' ' + (L 'Nie wszystkie się udały - szczegóły na liście i w Dzienniku.' 'Not all of them worked - see the list and the Log.') }
    OknoStatus $t
    Komunikat $t $(if ($zle) { 'Warning' } else { 'Information' })
}

function StronaSterowniki {
    $s = $script:Styl
    $str = Strona
    $btnWu = Przycisk 'Windows Update' 'ramka' @{ Width = (Px 160) }
    $btnSp = Przycisk (L 'Sprawdź' 'Check') 'glowny' @{ Width = (Px 130) }
    $n = Naglowek (L 'Sterowniki' 'Drivers') (L 'Nowsze sterowniki dla urządzeń tego komputera z Windows Update - podpisane, te same co w aktualizacjach opcjonalnych. Kliknij wiersz, żeby go zaznaczyć lub odznaczyć. Dwuklik otwiera Menedżera urządzeń.' 'Newer drivers for the devices in this PC from Windows Update - signed, the same as the optional updates. Click a row to tick or untick it. Double-click opens Device Manager.') @($btnWu, $btnSp)
    $btnWu.Add_Click({ Start-Process 'ms-settings:windowsupdate-optionalupdates' })
    $script:UI.BtnSterSprawdz = $btnSp

    $pod = Plotno @{ Dock = 'Top'; Height = (Px 66); BackColor = $s.Tlo } { param($g, $p) RysujPodsumowanieSterownikow $g $p }
    $script:UI.SterPodsum = $pod

    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 2 4 2 8) }
    $lv = ListaWierszy { param($g, $w, $r, $h) RysujWierszSterownika $g $w $r $h }
    $lv.Tag.Klik = {
        param($w, $x, $r)
        if ($w.Problem -or -not (SterownikDoWyboru $w.Obj)) { return }
        $w.Obj.Wybrana = -not $w.Obj.Wybrana
        AktualizujSumeSterownikow
    }
    $lv.Tag.Kursor = { param($w, $x, $r) -not $w.Problem -and (SterownikDoWyboru $w.Obj) }
    $lv.Tag.Dwuklik = { param($w) Start-Process devmgmt.msc }
    $lv.Tag.Podpowiedz = {
        param($w)
        $d = $w.Obj
        if ($w.Problem) { (@($d.Nazwa, $d.Opis, $d.Id) | Where-Object { $_ }) -join "`n" }
        else { (@($d.Nazwa, $d.Tytul, $d.Model, $d.Problem, $d.Blad) | Where-Object { $_ } | Select-Object -Unique) -join "`n" }
    }
    $k.Controls.Add($lv)
    $script:UI.LvSterowniki = $lv

    $dol = Karta @{ Dock = 'Bottom'; Height = (Px 74); Padding = (Marg 20 14 14 14) }
    $btnIn = Przycisk $(if ($Podglad) { L 'Podgląd - instalacja wyłączona' 'Preview - installing disabled' } else { L 'Zainstaluj zaznaczone...' 'Install selected...' }) 'glowny' @{ Dock = 'Right'; Width = (Px 230) }
    $teksty = Kontrolka Panel @{ Dock = 'Fill' }
    $suma = Etykieta '' @{ Dock = 'Top'; Height = (Px 26); Font = $s.Srednia }
    $opis = Etykieta '' @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; Font = $s.Mala; AutoEllipsis = $true }
    Dokuj $teksty @($suma, $opis)
    Dokuj $dol @($btnIn, $teksty)
    $script:UI.SterSuma = $suma; $script:UI.SterOpis = $opis; $script:UI.BtnSterInstaluj = $btnIn

    Dokuj $str @($n.Panel, $pod, (Odstep 'Top' 14), $dol, (Odstep 'Bottom' 14), $k)
    $str
}
