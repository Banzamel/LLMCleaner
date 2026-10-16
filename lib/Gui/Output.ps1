<#
    LLMCleaner - wyjscie rdzenia (Wypisz, Postep) pokazywane w oknie
#>

function Write-WindowLog([string]$t, [string]$color) {
    $box = $script:UI.Log
    if (-not $box) { return }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $(if ($LogColors[$color]) { $LogColors[$color] } else { $LogColors.Gray })
    $box.AppendText("$t`r`n")
    $box.ScrollToCaret()
    if ($script:UI.Scanning -and $t.Trim()) { $script:UI.Stage.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}
function Set-WindowStatus([string]$t) {
    if ($script:UI.Status) { $script:UI.Status.Text = $t.Trim() }
    if ($script:UI.Scanning -and $t.Trim()) { $script:UI.Stage.Text = $t.Trim() }
    [Windows.Forms.Application]::DoEvents()
}
