<#
    LLMCleaner - glowne okno i zdarzenia (Windows Forms, wbudowane w Windows). Logika jest w lib\Rdzen.
    Uklad wedlug makiet 1.5: ciemny pasek nawigacji po lewej, strony z kartami (lib\Okno\Strony), listy rysowane
    od zera (dwie linie tekstu, odznaki typu, paski rozmiaru, przelaczniki), ekran postepu czyszczenia.
    Okno zna skalowanie ekranu (DPI) - wszystkie wymiary w pikselach ida przez Px - i motyw Windows
    (jasny albo ciemny). Rozmiar, polozenie i ostatnia strona sa zapamietywane w okno.json.
    Dlugie operacje AI ida w osobnym watku (CzekajNa), skan i czyszczenie odswiezaja okno (DoEvents).
#>

function PokazOkno {
    $script:Tryb = 'okno'
    # Konsola PowerShella nie jest potrzebna, gdy jest okno
    if (-not $script:TestPoStarcie) { [void][LlmWin.Natywne]::ShowWindow([LlmWin.Natywne]::GetConsoleWindow(), 0) }
    # Skala jest liczona przy wczytaniu tego pliku (przed czcionkami); GDI+ powinno widziec to samo DPI
    $gr = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:DpiGdiPlus = $gr.DpiX
    $gr.Dispose()

    [Windows.Forms.Application]::EnableVisualStyles()
    $s = $script:Styl
    $script:UI.Podpowiedz = New-Object Windows.Forms.ToolTip
    $script:UI.Podpowiedz.AutoPopDelay = 15000
    $script:UI.Przewijane = @()
    # Minimalny rozmiar nie wiekszy niz ekran (np. 175% na ekranie 1920x1080)
    $obszar = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $min = New-Object Drawing.Size([Math]::Min((Px 1080), $obszar.Width), [Math]::Min((Px 680), $obszar.Height))
    $f = Kontrolka Form @{ Text = "LLMCleaner $Wersja"; MinimumSize = $min; AutoScaleMode = 'None'; Font = $s.Czcionka; BackColor = $s.Tlo; KeyPreview = $true }
    PrzywrocOkno $f
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) { $f.Icon = New-Object Drawing.Icon $ico }
    $script:UI.Okno = $f
    $f.SuspendLayout()

    # Strony (wszystkie Fill, widoczna jedna) i pasek stanu pod nimi
    $tresc = Kontrolka Panel @{ Dock = 'Fill'; BackColor = $s.Tlo }
    $script:UI.Strony = [ordered]@{ przeglad = (StronaPrzeglad); plan = (StronaPlan); analiza = (StronaAnaliza); autostart = (StronaAutostart)
        sterowniki = (StronaSterowniki); czat = (StronaCzat); log = (StronaDziennik); czyszczenie = (StronaCzyszczenie)
    }
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
        $u.BtnAnalizuj, $u.BtnAnalizaAi, $u.BtnWyslij, $u.BtnAkt, $u.BtnAutoOdswiez, $u.BtnAutoAi, $u.BtnWynikSkan,
        $u.BtnSterSprawdz, $u.BtnSterInstaluj)

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

    $u.BtnSterSprawdz.Add_Click({ Akcja {
                OknoStatus (L 'Szukam nowszych sterowników w Windows Update (zwykle 1-3 minuty)...' 'Looking for newer drivers on Windows Update (usually 1-3 minutes)...')
                $lv = $script:UI.LvSterowniki
                $lv.Tag.Pusty = L 'Szukam w Windows Update... Trwa to zwykle 1-3 minuty.' 'Searching Windows Update... It usually takes 1-3 minutes.'
                UstawWiersze $lv @()
                PostepNaPasku 1
                try { $n = SzukajSterownikow }
                catch {
                    Log "Sterowniki - blad szukania: $($_.Exception.Message)"
                    $lv.Tag.Pusty = (L 'Nie udało się sprawdzić Windows Update: {0}. Sprawdź połączenie z internetem i czy usługa Windows Update działa.' 'Could not check Windows Update: {0}. Check the internet connection and that the Windows Update service is running.') -f $_.Exception.Message.Trim()
                    $lv.Invalidate()
                    OknoStatus (L 'Sprawdzanie sterowników nie powiodło się.' 'Checking for drivers failed.')
                    return
                }
                finally { PostepNaPasku 0 }
                WypelnijSterowniki
                OknoWypisz ((L '  Sterowniki: nowszych {0}, urządzeń z problemem {1}' '  Drivers: {0} newer, {1} devices with a problem') -f $n, @($script:UrzadzeniaZProblemem).Count) 'Cyan'
                OknoStatus $(if ($n) { (L 'Znaleziono nowszych sterowników: {0}. Sprawdź listę i kliknij „Zainstaluj zaznaczone...”.' 'Newer drivers found: {0}. Review the list and click "Install selected...".') -f $n }
                    else { L 'Windows Update nie ma nowszych sterowników dla tego komputera.' 'Windows Update has no newer drivers for this PC.' })
            } })
    $u.BtnSterInstaluj.Add_Click({
            $wyb = @($script:Sterowniki | Where-Object { $_ -and $_.Wybrana -and $_.Stan -in 'nowy', 'blad' })
            if (-not $wyb.Count) { return }
            $lista = ($wyb | ForEach-Object { "  - $($_.Nazwa)  $($_.Wersja)" }) -join "`r`n"
            $tekst = (L "Zainstalować sterowniki z Windows Update:`r`n`r`n{0}`r`n`r`nNajpierw powstanie punkt przywracania systemu. Przy sterowniku karty graficznej ekran może na chwilę zgasnąć. Nie wyłączaj komputera w trakcie instalacji." "Install drivers from Windows Update:`r`n`r`n{0}`r`n`r`nA System Restore point is created first. With a graphics driver the screen may go blank for a moment. Do not turn off the computer while installing.") -f $lista
            $odp = [Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, (L 'LLMCleaner - instalacja sterowników' 'LLMCleaner - install drivers'), 'YesNo', 'Question', 'Button2')
            if ($odp -ne 'Yes') { return }
            Akcja { InstalujSterownikiZOknem $wyb }
        })

    $u.BtnAkt.Add_Click({ Akcja {
                if (ZainstalujAktualizacje) { $script:UI.Okno.Close() }
            } })

    # Skroty: F5 skanuje, Ctrl+1..7 przelacza strony
    $f.Add_KeyDown({
            if ($script:Czyszczenie) { return }
            if ($_.KeyCode -eq 'F5') {
                $_.Handled = $true
                if ($script:UI.BtnSkan.Enabled) { $script:UI.BtnSkan.PerformClick() }
            }
            elseif ($_.Control -and $_.KeyValue -ge 49 -and $_.KeyValue -lt 49 + $script:UI.Nav.Count) {
                $_.Handled = $true; $_.SuppressKeyPress = $true
                PokazStrone @($script:UI.Nav.Keys)[$_.KeyValue - 49]
            }
        })

    $f.Add_HandleCreated({ CiemnyTytul })
    $f.Add_Shown({
            CiemnePrzewijanie
            $str = "$($script:Ustawienia.Strona)"
            PokazStrone $(if ($str -in 'analiza', 'autostart', 'sterowniki', 'czat', 'log') { $str } else { 'przeglad' })
            WypelnijPlan
            WypelnijSterowniki
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
            if ($script:InstalujeSterowniki) {
                $_.Cancel = $true
                Komunikat (L 'Poczekaj na koniec instalacji sterowników.' 'Wait for the driver installation to finish.') 'Warning'
                return
            }
            if ($script:Czyszczenie) {
                $_.Cancel = $true
                Komunikat (L 'Poczekaj na koniec czyszczenia - przerwanie w połowie zostawiłoby wstrzymane usługi albo wyłączony Eksplorator.' 'Wait for the cleaning to finish - stopping halfway could leave services paused or File Explorer closed.') 'Warning'
                return
            }
            ZapiszOkno
        })
    $f.Add_FormClosed({ ZatrzymajOllama; Log 'Koniec (okno).' })

    Log "Start (okno). Model: $Model, Podglad: $Podglad, BezLLM: $BezLLM, Jezyk: $Jezyk, Skala: $($script:Skala) (GDI+ $($script:DpiGdiPlus) dpi), Ciemny: $($script:Ciemny)"
    [void]$f.ShowDialog()
}
