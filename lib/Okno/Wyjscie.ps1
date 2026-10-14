<#
    LLMCleaner - wyjscie rdzenia (Wypisz, Postep) pokazywane w oknie
#>

function OknoWypisz([string]$t, [string]$kolor) {
    $box = $script:UI.Log
    if (-not $box) { return }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $(if ($KoloryOkna[$kolor]) { $KoloryOkna[$kolor] } else { $KoloryOkna.Gray })
    $box.AppendText("$t`r`n")
    $box.ScrollToCaret()
    if ($script:UI.Skanuje -and $t.Trim()) { $script:UI.Etap.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}
function OknoStatus([string]$t) {
    if ($script:UI.Status) { $script:UI.Status.Text = $t.Trim() }
    if ($script:UI.Skanuje -and $t.Trim()) { $script:UI.Etap.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}
