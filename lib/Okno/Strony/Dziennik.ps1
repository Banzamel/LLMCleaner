<#
    LLMCleaner - strona Dziennik
#>

function StronaDziennik {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Dziennik' 'Log') ((L 'Przebieg skanu i czyszczenia. Pełny log: {0}' 'Scan and cleaning progress. Full log: {0}') -f $LogPlik)
    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 18 14 6 10) }
    $log = Kontrolka RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Karta; ForeColor = $s.Tekst; Font = $s.Mono; WordWrap = $false }
    $k.Controls.Add($log)
    $script:UI.Log = $log
    $script:UI.Przewijane += $log
    Dokuj $str @($n.Panel, $k)
    $str
}
