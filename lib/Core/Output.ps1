<#
    LLMCleaner - jezyk interfejsu i wyjscie (Wypisz, Postep, CzekajNa).
    Rdzen (lib\Rdzen) nie ma interfejsu: wszystko, co widzi uzytkownik, idzie przez Wypisz/Postep, a interfejs
    (lib\Konsola albo lib\Okno) decyduje, gdzie to pokazac.
#>

function L([string]$pl, [string]$en) { if ($Language -eq 'en') { $en } else { $pl } }

$script:Mode = 'console'   # albo 'okno' - ustawia Okno.ps1

function Write-Line([string]$t = '', [string]$color = 'Gray') {
    if ($script:Mode -eq 'window') { Write-WindowLog $t $color } else { Write-Host $t -ForegroundColor $color }
}
# Linia postepu nadpisywana w miejscu
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
# Dlugie wywolanie bez dostepu do funkcji skryptu (HTTP do modelu, GitHub): w oknie w osobnym
# watku, zeby okno nie zamarzalo; w konsoli zwyczajnie.
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
