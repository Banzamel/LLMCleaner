<#
    LLMCleaner - UI language and output (Write-Line, Write-Status, Wait-Responsive).
    The core (lib\Core) has no UI: everything the user sees goes through Write-Line/Write-Status, and the UI
    (lib\Console or lib\Gui) decides where to show it.
#>

function L([string]$pl, [string]$en) { if ($Language -eq 'en') { $en } else { $pl } }

$script:Mode = 'console'   # or 'window' - set by Window.ps1

function Write-Line([string]$t = '', [string]$color = 'Gray') {
    if ($script:Mode -eq 'window') { Write-WindowLog $t $color } else { Write-Host $t -ForegroundColor $color }
}
# Progress line overwritten in place
function Write-Status([string]$t) {
    if ($script:Mode -eq 'window') { Set-WindowStatus $t } else { Write-Host "`r$t" -NoNewline -ForegroundColor DarkGray }
}
function Complete-Status([string]$t) {
    if ($script:Mode -eq 'window') { Set-WindowStatus $t; Write-WindowLog $t 'DarkGray' } else { Write-Host "`r$t" -ForegroundColor DarkGray }
}
function Wait-Responsive([int]$ms) {
    if ($script:Mode -ne 'window') { Start-Sleep -Milliseconds $ms; return }
    $deadline = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
}
# Long call without access to script functions (HTTP to the model, GitHub): in the window it runs
# on a separate thread so the window doesn't freeze; in the console it runs normally.
function Invoke-Background([scriptblock]$sb, [object[]]$argList) {
    if ($script:Mode -ne 'window') { return & $sb @argList }
    $ps = [PowerShell]::Create().AddScript($sb.ToString())
    foreach ($a in $argList) { [void]$ps.AddArgument($a) }
    $h = $ps.BeginInvoke()
    while (-not $h.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
    try { $result = $ps.EndInvoke($h) }
    catch { throw $(if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }) }
    finally { $ps.Dispose() }
    if ($result.Count -eq 1) { $result[0] } else { $result }
}
