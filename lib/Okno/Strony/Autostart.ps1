<#
    LLMCleaner - strona Autostart
#>

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
    $wpisy = @($script:Autostart | Where-Object { $_ })
    $wl = @($wpisy | Where-Object { $_.Wlaczony }).Count
    $dane = @(
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$wl" }); O = (L 'uruchamia się przy logowaniu' 'start at sign-in') }
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$($wpisy.Count - $wl)" }); O = (L 'wyłączone' 'turned off') }
        @{ W = $(if ($null -eq $script:Autostart) { '-' } else { "$(@($wpisy | Where-Object { $_.Chroniony }).Count)" }); O = (L 'chronione (tylko podgląd)' 'protected (read-only)') })
    $t = if ($Podglad) { L 'Tryb podglądu - przełączniki są tylko do wglądu.' 'Preview mode - the switches are read-only.' }
    else { L 'Zmiana działa od następnego logowania. Programy możesz dalej uruchamiać ręcznie.' 'Changes take effect at the next sign-in. You can still start the programs by hand.' }
    KafelkiZNotka $g $p $dane $t
}

# Kafelki z liczbami i notka obok (strony Autostart i Sterowniki)
function KafelkiZNotka($g, $p, $dane, [string]$t) {
    $s = $script:Styl
    $szer = Px 200; $odst = Px 12; $h = $p.Height - 1
    $x = 0
    foreach ($d in $dane) {
        Prostokat $g $x 0 $szer $h $s.Karta (Px 12)
        Tekst $g $d.W $s.Liczba $s.Tekst ($x + (Px 18)) (Px 6) ($szer - (Px 24)) (Px 32)
        Tekst $g $d.O $s.Mala $s.TekstSlaby ($x + (Px 18)) (Px 36) ($szer - (Px 24)) (Px 22)
        $x += $szer + $odst
    }
    $szerN = $p.Width - $x - 1
    if ($szerN -gt (Px 120)) {
        Prostokat $g $x 0 $szerN $h $s.NotkaTlo (Px 12) $s.NotkaRamka
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
