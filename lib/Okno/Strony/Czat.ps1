<#
    LLMCleaner - strona Czat z asystentem
#>

function DopiszCzat([string]$kto, [string]$tekst, $kolor) {
    $box = $script:UI.Czat
    $box.SelectionStart = $box.TextLength
    $box.SelectionFont = $script:Styl.Pogrubiona
    $box.SelectionColor = $kolor
    $box.AppendText("$kto`r`n")
    $box.SelectionFont = $box.Font
    $box.SelectionColor = $script:Styl.Tekst
    $box.AppendText("$tekst`r`n`r`n")
    $box.ScrollToCaret()
}

function StronaCzat {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Asystent AI' 'AI assistant') $(if ($BezLLM) { L 'Asystent jest wyłączony (uruchomiono z -BezLLM).' 'The assistant is disabled (started with -BezLLM).' }
        else { (L 'Lokalny model {0} - działa na tym komputerze, nic nie wysyła do internetu i niczego nie usuwa.' 'Local model {0} - runs on this computer, sends nothing to the internet and never deletes anything.') -f $Model })

    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 20 16 6 10) }
    $czat = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = $s.PoleTekstu }
    # Tekst powitalny wpisuje Shown - RichTextBox gubi kolory ustawione przed utworzeniem okna
    $czat.Tag = $(if ($BezLLM) { '' }
        else { L "Zapytaj o plan, foldery, programy albo gry. Asystent zna wyniki skanu, analizy dysku i listę autostartu.`r`nPrzed skanem odpowiada tylko ogólnie - żeby pytać o pliki tego komputera, najpierw kliknij `„Skanuj`”.`r`nPierwsze pytanie uruchamia model (ok. 10-20 s).`r`n`r`n" "Ask about the plan, folders, programs or games. The assistant knows the scan results, the disk analysis and the startup list.`r`nBefore a scan it only answers in general terms - to ask about the files on this computer, click ""Scan"" first.`r`nThe first question starts the model (about 10-20 s).`r`n`r`n" })
    $k.Controls.Add($czat)
    $script:UI.Czat = $czat
    $script:UI.Przewijane += $czat

    # Pole pytania: karta z polem bez ramki i przyciskiem
    $dol = Karta @{ Dock = 'Bottom'; Height = (Px 62); Padding = (Marg 20 10 10 10) }
    $btnW = Przycisk (L 'Wyślij' 'Send') 'glowny' @{ Dock = 'Right'; Width = (Px 120) }
    $pole = Kontrolka Panel @{ Dock = 'Fill'; Padding = (Marg 0 10 12 0) }
    $pyt = Kontrolka TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = $s.PoleTekstu }
    $pole.Controls.Add($pyt)
    Dokuj $dol @($btnW, $pole)
    $pyt.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; if ($script:UI.BtnWyslij.Enabled) { $script:UI.BtnWyslij.PerformClick() } } })
    $script:UI.Pytanie = $pyt; $script:UI.BtnWyslij = $btnW

    Dokuj $str @($n.Panel, $dol, (Odstep 'Bottom' 14), $k)
    $str
}
