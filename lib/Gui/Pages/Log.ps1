<#
    LLMCleaner - strona Dziennik
#>

function New-LogPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Dziennik' 'Log') ((L 'Przebieg skanu i czyszczenia. Pełny log: {0}' 'Scan and cleaning progress. Full log: {0}') -f $LogFile)
    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 18 14 6 10) }
    $log = New-Control RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Card; ForeColor = $s.Text; Font = $s.Mono; WordWrap = $false }
    $k.Controls.Add($log)
    $script:UI.Log = $log
    $script:UI.Scrollables += $log
    Add-Docked $page @($n.Panel, $k)
    $page
}
