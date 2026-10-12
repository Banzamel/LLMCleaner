<#
    LLMCleaner - okno graficzne (Windows Forms, wbudowane w Windows). Logika jest w Rdzen.ps1.
    Dlugie operacje AI ida w osobnym watku (CzekajNa), skan odswieza okno co chwile (DoEvents).
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:UI = @{}
$script:Wypelniam = $false
$script:Zeskanowano = $false

$KoloryOkna = @{
    Gray = [Drawing.Color]::FromArgb(50, 50, 50); DarkGray = [Drawing.Color]::Gray; White = [Drawing.Color]::Black
    Green = [Drawing.Color]::FromArgb(0, 120, 0); Yellow = [Drawing.Color]::FromArgb(190, 100, 0)
    Cyan = [Drawing.Color]::SteelBlue; DarkCyan = [Drawing.Color]::Teal; DarkYellow = [Drawing.Color]::Peru
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
    [Windows.Forms.Application]::DoEvents()
}
function OknoStatus([string]$t) {
    if ($script:UI.Status) { $script:UI.Status.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}

# ---------- POMOCNICZE ----------
function Kontrolka([string]$typ, [hashtable]$wlasciwosci) {
    $c = New-Object "Windows.Forms.$typ"
    foreach ($k in $wlasciwosci.Keys) { $c.$k = $wlasciwosci[$k] }
    $c
}

function Komunikat([string]$tekst, [string]$ikona = 'Information') {
    [void][Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, 'LLMCleaner', 'OK', $ikona)
}

# Blokuje przyciski na czas pracy i pokazuje pasek postepu
function Zajety([bool]$z) {
    foreach ($b in $script:UI.Akcje) { $b.Enabled = -not $z }
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
    $script:UI.BtnWyslij.Enabled = $script:Zeskanowano -and $ai
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

# ---------- PLAN ----------
function AktualizujSume {
    $script:UI.Suma.Text = (L 'Zaznaczone razem: ok. {0}' 'Selected in total: about {0}') -f (Rozmiar (SumaZaznaczonych))
}

function WypelnijPlan {
    $lv = $script:UI.LvPlan
    $script:Wypelniam = $true
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($k in $script:Kategorie) {
        $opis = if ($k.Blokada) { "! $($k.Blokada)" } else { $k.Opis }
        $it = New-Object Windows.Forms.ListViewItem($k.Nazwa)
        [void]$it.SubItems.Add((RozmiarKategorii $k))
        [void]$it.SubItems.Add($(if ($k.TylkoRecznie) { L 'na życzenie' 'opt-in' } else { '' }))
        [void]$it.SubItems.Add($opis)
        $it.ToolTipText = $opis
        $it.Tag = $k
        $it.Group = $script:UI.GrKategorie
        $it.Checked = [bool]$k.Wybrana
        if ($k.Blokada) { $it.ForeColor = $KoloryOkna.Yellow } elseif ($k.TylkoRecznie) { $it.ForeColor = $KoloryOkna.DarkGray }
        [void]$lv.Items.Add($it)
    }
    foreach ($p in $script:Pozostalosci) {
        $pokaz = if ($p.Typ -eq 'rejestr' -and $p.Nazwa -ne (Split-Path $p.Sciezka -Leaf)) { "$($p.Nazwa)  [$($p.Sciezka)]" } else { $p.Sciezka }
        $opis = $p.Dlaczego
        if ($p.Ai) { $opis += "  |  $EtykietaAi`: $($p.Ai)" }
        $it = New-Object Windows.Forms.ListViewItem($pokaz)
        [void]$it.SubItems.Add($(if ($p.Typ -ne 'rejestr') { Rozmiar $p.Bajty } else { L 'rejestr' 'registry' }))
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
    $box.SelectionFont = New-Object Drawing.Font($box.Font, [Drawing.FontStyle]::Bold)
    $box.SelectionColor = $kolor
    $box.AppendText("$kto`r`n")
    $box.SelectionFont = $box.Font
    $box.SelectionColor = [Drawing.Color]::Black
    $box.AppendText("$tekst`r`n`r`n")
    $box.ScrollToCaret()
}

# Przyciski przy prawej krawedzi paneli (panele zmieniaja szerokosc razem z oknem)
function UlozPrzyciski {
    $u = $script:UI
    if ($u.Gora) {
        $u.BtnSkan.Location = New-Object Drawing.Point(($u.Gora.Width - 166), 46)
        $u.BtnAkt.Location = New-Object Drawing.Point(($u.Gora.Width - 236), 8)
        $u.DyskiPanel.Width = [Math]::Max(200, $u.Gora.Width - 190)
    }
    if ($u.DolPlan) {
        $u.BtnWyczysc.Location = New-Object Drawing.Point(($u.DolPlan.Width - 256), 7)
        $u.BtnWyjasnij.Location = New-Object Drawing.Point(($u.DolPlan.Width - 484), 7)
    }
    if ($u.DolCzat) {
        $u.BtnWyslij.Location = New-Object Drawing.Point(($u.DolCzat.Width - 112), 5)
        $u.Pytanie.Width = [Math]::Max(100, $u.DolCzat.Width - 122)
    }
}

# ---------- OKNO ----------
function PokazOkno {
    $script:Tryb = 'okno'
    # Konsola PowerShella nie jest potrzebna, gdy jest okno
    if (-not ('LlmWin.Konsola' -as [type])) {
        Add-Type -Name Konsola -Namespace LlmWin -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
'@
    }
    if (-not $script:TestPoStarcie) { [void][LlmWin.Konsola]::ShowWindow([LlmWin.Konsola]::GetConsoleWindow(), 0) }

    [Windows.Forms.Application]::EnableVisualStyles()
    $f = Kontrolka Form @{ Text = "LLMCleaner $Wersja"; Size = (New-Object Drawing.Size(1200, 760)); MinimumSize = (New-Object Drawing.Size(900, 560))
                           StartPosition = 'CenterScreen'; Font = (New-Object Drawing.Font('Segoe UI', 9)) }
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) { $f.Icon = New-Object Drawing.Icon $ico }
    $script:UI.Okno = $f

    # --- zakladki (Fill - dodane pierwsze, zeby dokowaly sie na koncu) ---
    $tabs = Kontrolka TabControl @{ Dock = 'Fill' }
    $f.Controls.Add($tabs)
    $script:UI.Zakladki = $tabs

    # Plan
    $tPlan = Kontrolka TabPage @{ Text = (L 'Plan czyszczenia' 'Cleanup plan'); Padding = (New-Object Windows.Forms.Padding(6)) }
    $lv = Kontrolka ListView @{ Dock = 'Fill'; View = 'Details'; CheckBoxes = $true; FullRowSelect = $true; ShowItemToolTips = $true; HideSelection = $false }
    [void]$lv.Columns.Add((L 'Pozycja' 'Item'), 430)
    [void]$lv.Columns.Add((L 'Rozmiar' 'Size'), 90, 'Right')
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
    $script:UI.LvPlan = $lv
    $dolPlan = Kontrolka Panel @{ Dock = 'Bottom'; Height = 46 }
    $suma = Kontrolka Label @{ AutoSize = $true; Location = (New-Object Drawing.Point(4, 15)); Font = (New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)) }
    $script:UI.Suma = $suma
    $btnWyczysc = Kontrolka Button @{ Text = $(if ($Podglad) { L 'Tryb podglądu - czyszczenie wyłączone' 'Preview mode - cleaning disabled' } else { L 'Wyczyść zaznaczone...' 'Clean selected...' })
                                     Size = (New-Object Drawing.Size(250, 32)); Anchor = 'Top, Right' }
    $btnWyjasnij = Kontrolka Button @{ Text = (L 'AI: czym były pozostałości?' 'AI: what were the leftovers?'); Size = (New-Object Drawing.Size(220, 32)); Anchor = 'Top, Right' }
    $dolPlan.Controls.AddRange(@($suma, $btnWyjasnij, $btnWyczysc))
    $dolPlan.Add_Resize({ UlozPrzyciski })
    $script:UI.DolPlan = $dolPlan
    $script:UI.BtnWyczysc = $btnWyczysc
    $script:UI.BtnWyjasnij = $btnWyjasnij
    $tPlan.Controls.Add($lv)
    $tPlan.Controls.Add($dolPlan)
    $podpowiedz = Kontrolka Label @{ Dock = 'Top'; Height = 34; ForeColor = [Drawing.Color]::DimGray
        Text = (L 'Wybierz dyski na górze i kliknij „Skanuj”. Potem zaznacz lub odznacz pozycje - nic nie jest usuwane bez potwierdzenia. Najedź na pozycję, żeby zobaczyć pełny opis.' 'Pick the drives at the top and click "Scan". Then tick or untick items - nothing is deleted without your confirmation. Hover over an item to see its full description.') }
    $tPlan.Controls.Add($podpowiedz)
    $tabs.TabPages.Add($tPlan)

    # Co zajmuje miejsce
    $tAn = Kontrolka TabPage @{ Text = (L 'Co zajmuje miejsce' 'What takes up space'); Padding = (New-Object Windows.Forms.Padding(6)) }
    $lvA = Kontrolka ListView @{ Dock = 'Fill'; View = 'Details'; FullRowSelect = $true; ShowItemToolTips = $true }
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
    $script:UI.LvAnaliza = $lvA
    $goraA = Kontrolka Panel @{ Dock = 'Top'; Height = 66 }
    $lblD = Kontrolka Label @{ Text = (L 'Dysk:' 'Drive:'); AutoSize = $true; Location = (New-Object Drawing.Point(2, 10)) }
    $cbo = Kontrolka ComboBox @{ DropDownStyle = 'DropDownList'; Location = (New-Object Drawing.Point(50, 6)); Width = 330 }
    $btnAn = Kontrolka Button @{ Text = (L 'Analizuj' 'Analyse'); Location = (New-Object Drawing.Point(390, 4)); Size = (New-Object Drawing.Size(110, 28)) }
    $btnAnAi = Kontrolka Button @{ Text = (L 'AI: opisz i doradź' 'AI: describe and advise'); Location = (New-Object Drawing.Point(508, 4)); Size = (New-Object Drawing.Size(180, 28)) }
    $info = Kontrolka Label @{ AutoSize = $false; Location = (New-Object Drawing.Point(2, 38)); Size = (New-Object Drawing.Size(1150, 24)); ForeColor = [Drawing.Color]::DimGray; Anchor = 'Top, Left, Right'
                               Text = (L 'Szybki skan całego dysku (zwykle 30 s - 3 min). Pokazuje najbardziej konkretne duże foldery i największe pliki.' 'A fast scan of the whole drive (usually 30 s - 3 min). Shows the most specific large folders and the largest files.') }
    $goraA.Controls.AddRange(@($lblD, $cbo, $btnAn, $btnAnAi, $info))
    $script:UI.CboDysk = $cbo; $script:UI.BtnAnalizuj = $btnAn; $script:UI.BtnAnalizaAi = $btnAnAi; $script:UI.InfoAnaliza = $info
    $tAn.Controls.Add($lvA)
    $tAn.Controls.Add($goraA)
    $tabs.TabPages.Add($tAn)

    # Asystent
    $tCz = Kontrolka TabPage @{ Text = (L 'Asystent AI' 'AI assistant'); Padding = (New-Object Windows.Forms.Padding(6)) }
    $czat = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BackColor = [Drawing.Color]::White; Font = (New-Object Drawing.Font('Segoe UI', 10)) }
    $czat.Text = $(if ($BezLLM) { L 'Asystent jest wyłączony (uruchomiono z -BezLLM).' 'The assistant is disabled (started with -BezLLM).' }
                   else { L "Zapytaj o plan, foldery, programy albo gry. Asystent zna wyniki skanu i analizy dysku, ale niczego nie usuwa.`r`nPierwsze pytanie uruchamia model (ok. 10-20 s).`r`n`r`n" "Ask about the plan, folders, programs or games. The assistant knows the scan and disk analysis results but never deletes anything.`r`nThe first question starts the model (about 10-20 s).`r`n`r`n" })
    $script:UI.Czat = $czat
    $dolCz = Kontrolka Panel @{ Dock = 'Bottom'; Height = 38 }
    $pyt = Kontrolka TextBox @{ Location = (New-Object Drawing.Point(0, 6)); Width = 1000; Anchor = 'Top, Left, Right'; Font = (New-Object Drawing.Font('Segoe UI', 10)) }
    $btnW = Kontrolka Button @{ Text = (L 'Wyślij' 'Send'); Size = (New-Object Drawing.Size(110, 28)); Anchor = 'Top, Right' }
    $dolCz.Controls.AddRange(@($pyt, $btnW))
    $dolCz.Add_Resize({ UlozPrzyciski })
    $pyt.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; $script:UI.BtnWyslij.PerformClick() } })
    $script:UI.DolCzat = $dolCz; $script:UI.Pytanie = $pyt; $script:UI.BtnWyslij = $btnW
    $tCz.Controls.Add($czat)
    $tCz.Controls.Add($dolCz)
    $tabs.TabPages.Add($tCz)

    # Dziennik
    $tLog = Kontrolka TabPage @{ Text = (L 'Dziennik' 'Log'); Padding = (New-Object Windows.Forms.Padding(6)) }
    $log = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BackColor = [Drawing.Color]::White; Font = (New-Object Drawing.Font('Consolas', 9)); WordWrap = $false }
    $script:UI.Log = $log
    $tLog.Controls.Add($log)
    $tabs.TabPages.Add($tLog)

    # --- gorny pasek: dyski i skan ---
    $gora = Kontrolka Panel @{ Dock = 'Top'; Height = 86; Padding = (New-Object Windows.Forms.Padding(8, 6, 8, 4)) }
    $tytul = Kontrolka Label @{ AutoSize = $true; Location = (New-Object Drawing.Point(10, 6)); Font = (New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold))
                                Text = ((L 'LLMCleaner {0} - inteligentne czyszczenie komputera' 'LLMCleaner {0} - smart PC cleanup') -f $Wersja) }
    $tryb = Kontrolka Label @{ AutoSize = $true; Location = (New-Object Drawing.Point(12, 32)); ForeColor = [Drawing.Color]::DimGray
                               Text = ((L 'Asystent AI: {0}{1}' 'AI assistant: {0}{1}') -f $(if ($BezLLM) { L 'wyłączony' 'off' } else { (L '{0} (na żądanie)' '{0} (on demand)') -f $Model }),
                                       $(if ($Podglad) { L '   |   TRYB PODGLĄDU - nic nie zostanie usunięte' '   |   PREVIEW MODE - nothing will be deleted' })) }
    $dyskiPanel = Kontrolka FlowLayoutPanel @{ Location = (New-Object Drawing.Point(10, 52)); Size = (New-Object Drawing.Size(860, 30)); WrapContents = $false; AutoScroll = $true; Anchor = 'Top, Left, Right' }
    $script:UI.Dyski = @()
    foreach ($d in DyskiStale) {
        $cb = Kontrolka CheckBox @{ Text = (OpisDysku $d); AutoSize = $true; Checked = $true; Tag = $d.DeviceID; Margin = (New-Object Windows.Forms.Padding(0, 4, 18, 0)) }
        if ($d.DeviceID -eq $Sys) { $cb.Enabled = $false; $cb.Text += L ' (systemowy)' ' (system)' }
        elseif ($Dyski) { $cb.Checked = $d.DeviceID.TrimEnd(':') -in @($Dyski | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() }) }
        $dyskiPanel.Controls.Add($cb)
        $script:UI.Dyski += $cb
    }
    $btnSkan = Kontrolka Button @{ Text = (L 'Skanuj' 'Scan'); Size = (New-Object Drawing.Size(150, 34)); Anchor = 'Top, Right'; Font = (New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)) }
    $btnAkt = Kontrolka Button @{ Size = (New-Object Drawing.Size(220, 28)); Anchor = 'Top, Right'; Visible = $false; ForeColor = $KoloryOkna.Green }
    $gora.Controls.AddRange(@($tytul, $tryb, $dyskiPanel, $btnSkan, $btnAkt))
    $gora.Add_Resize({ UlozPrzyciski })
    $script:UI.Gora = $gora; $script:UI.BtnSkan = $btnSkan; $script:UI.BtnAkt = $btnAkt; $script:UI.DyskiPanel = $dyskiPanel
    $f.Controls.Add($gora)

    # --- pasek stanu ---
    $ss = New-Object Windows.Forms.StatusStrip
    $st = Kontrolka ToolStripStatusLabel @{ Spring = $true; TextAlign = 'MiddleLeft'; Text = (L 'Gotowy. Wybierz dyski i kliknij „Skanuj”.' 'Ready. Pick the drives and click "Scan".') }
    $pb = Kontrolka ToolStripProgressBar @{ Style = 'Marquee'; Visible = $false; Width = 160 }
    [void]$ss.Items.Add($st); [void]$ss.Items.Add($pb)
    $f.Controls.Add($ss)
    $script:UI.Status = $st; $script:UI.Pasek = $pb
    $script:UI.Akcje = @($btnSkan, $btnWyczysc, $btnWyjasnij, $btnAn, $btnAnAi, $btnW, $btnAkt)

    # ---------- ZDARZENIA ----------
    $btnSkan.Add_Click({ Akcja {
        UstawDyski @($script:UI.Dyski | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        $script:UI.Zakladki.SelectedIndex = 3
        $script:UI.Log.Clear()
        OknoWypisz ((L '1/2  Skanowanie dysków: {0}' '1/2  Scanning drives: {0}') -f ($script:WybraneDyski -join ', ')) 'Cyan'
        SkanujWszystko
        $script:Zeskanowano = $true
        $script:PoCzyszczeniu = $false
        $script:Rozmowa = $null
        WypelnijPlan
        $script:UI.CboDysk.Items.Clear()
        foreach ($d in DyskiWybrane) { [void]$script:UI.CboDysk.Items.Add((OpisDysku $d)) }
        $script:UI.CboDysk.SelectedIndex = 0
        $script:UI.Zakladki.SelectedIndex = 0
        OknoStatus ((L 'Skan zakończony. Sprawdź plan i kliknij „Wyczyść zaznaczone...”.' 'Scan finished. Review the plan and click "Clean selected...".'))
    } })

    $btnWyjasnij.Add_Click({ Akcja {
        $script:UI.Zakladki.SelectedIndex = 0
        OknoStatus (L 'Model opisuje pozostałości (ok. 20-40 s)...' 'The model is describing the leftovers (about 20-40 s)...')
        $n = WyjasnijPozostalosci
        WypelnijPlan
        OknoStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji (kolumna Opis, dopisek AI).' '{0} items described (Description column, AI note).') -f $n } else { L 'Asystent niedostępny - szczegóły w zakładce Dziennik.' 'The assistant is unavailable - see the Log tab.' })
    } })

    $btnWyczysc.Add_Click({
        $linie = Podsumowanie
        if (-not $linie) { Komunikat (L 'Nic nie jest zaznaczone - nie ma czego czyścić.' 'Nothing is selected - there is nothing to clean.'); return }
        $tekst = (($linie | ForEach-Object { $_.T -replace '\s{2,}', '  ' }) -join "`r`n") + "`r`n`r`n" + (L 'Uruchomić czyszczenie?' 'Start cleaning?')
        $odp = [Windows.Forms.MessageBox]::Show($script:UI.Okno, $tekst, (L 'LLMCleaner - podsumowanie przed czyszczeniem' 'LLMCleaner - summary before cleaning'), 'YesNo', 'Warning', 'Button2')
        if ($odp -ne 'Yes') { return }
        Akcja {
            $script:UI.Zakladki.SelectedIndex = 3
            OknoWypisz ''
            OknoWypisz (L '2/2  Czyszczenie' '2/2  Cleaning') 'Cyan'
            $w = WykonajCzyszczenie
            $script:PoCzyszczeniu = $true
            $linie = TekstPoCzyszczeniu $w
            OknoWypisz ''
            foreach ($x in $linie) { OknoWypisz "  $x" 'White' }
            OknoWypisz "  Log: $LogPlik" 'DarkGray'
            OknoStatus (L 'Czyszczenie zakończone. Kliknij „Skanuj”, żeby zobaczyć aktualny stan.' 'Cleaning finished. Click "Scan" to see the current state.')
            Komunikat ((($linie | ForEach-Object { $_ -replace '\s{2,}', '  ' }) -join "`r`n") + "`r`n`r`nLog: $LogPlik")
        }
    })

    $btnAn.Add_Click({ Akcja {
        $i = $script:UI.CboDysk.SelectedIndex
        if ($i -lt 0) { return }
        $l = @(DyskiWybrane)[$i].DeviceID.TrimEnd(':')
        $a = Analizuj $l
        WypelnijAnalize $a
        OknoStatus ((L 'Analiza dysku {0}: gotowa.' 'Drive {0}: analysis ready.') -f $l)
    } })

    $btnAnAi.Add_Click({ Akcja {
        $a = $script:UI.LvAnaliza.Tag
        if (-not $a) { return }
        OknoStatus (L 'Model opisuje pozycje (ok. 20-40 s)...' 'The model is describing the items (about 20-40 s)...')
        $n = AnalizaAi $a
        WypelnijAnalize $a
        OknoStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji.' '{0} items described.') -f $n } else { L 'Asystent niedostępny - szczegóły w zakładce Dziennik.' 'The assistant is unavailable - see the Log tab.' })
    } })

    $btnW.Add_Click({
        $q = $script:UI.Pytanie.Text.Trim()
        if (-not $q) { return }
        $script:UI.Pytanie.Clear()
        DopiszCzat (L 'Ty' 'You') $q ([Drawing.Color]::SteelBlue)
        Akcja {
            OknoStatus (L 'Asystent myśli...' 'The assistant is thinking...')
            $a = Zapytaj $q
            if ($a) { DopiszCzat 'LLMCleaner' $a ([Drawing.Color]::Teal); OknoStatus '' }
            else { DopiszCzat 'LLMCleaner' (L '(brak odpowiedzi - szczegóły w zakładce Dziennik)' '(no answer - see the Log tab)') ([Drawing.Color]::Gray) }
        }
        $script:UI.Pytanie.Focus()
    })

    $btnAkt.Add_Click({ Akcja {
        if (ZainstalujAktualizacje) { $script:UI.Okno.Close() }
    } })

    $f.Add_Shown({
        UstawPrzyciski
        UlozPrzyciski
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
