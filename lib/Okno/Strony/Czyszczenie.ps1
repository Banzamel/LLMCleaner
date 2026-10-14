<#
    LLMCleaner - strona Czyszczenie (postep i wynik)
#>

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
