<#
    LLMCleaner - UI language and output (Write-Line, Write-Status, Wait-Responsive).
    The core (lib\Core) has no UI: everything the user sees goes through Write-Line/Write-Status, and the UI
    (lib\Console or lib\Gui) decides where to show it.
#>

# Texts are written in the code in Polish and English. Other languages (lang\<code>.json) translate
# the English text; a missing entry falls back to English.
$LanguageNames = @{ pl = 'Polish'; en = 'English'; es = 'Spanish' }
$script:Translation = New-Object Collections.Hashtable ([StringComparer]::Ordinal)
if ($Language -notin 'pl', 'en') {
    $file = Join-Path $AppDir "lang\$Language.json"
    try { foreach ($p in (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { $script:Translation[$p.Name] = $p.Value } } catch { }
}
function Get-Translation([string]$en) { $t = $script:Translation[$en]; if ($t) { $t } else { $en } }
function L([string]$pl, [string]$en) { switch ($Language) { 'pl' { $pl } 'en' { $en } default { Get-Translation $en } } }

# AI prompts exist in Polish and English. Other languages get the English prompt with the answer language
# and the quoted values the model must return ($phrases - advice, "unknown program") translated.
function Convert-Prompt([string]$prompt, [string[]]$phrases = @()) {
    if ($Language -in 'pl', 'en') { return $prompt }
    $t = $prompt.Replace('in English', "in $($LanguageNames[$Language])")
    foreach ($p in $phrases) { $t = $t.Replace("`"$p`"", "`"$(Get-Translation $p)`"") }
    $t
}

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
