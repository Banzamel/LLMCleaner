<#
    LLMCleaner - jezyk interfejsu i wyjscie (Wypisz, Postep, CzekajNa).
    Rdzen (lib\Rdzen) nie ma interfejsu: wszystko, co widzi uzytkownik, idzie przez Wypisz/Postep, a interfejs
    (lib\Konsola albo lib\Okno) decyduje, gdzie to pokazac.
#>

function L([string]$pl, [string]$en) { if ($Jezyk -eq 'en') { $en } else { $pl } }

$script:Tryb = 'konsola'   # albo 'okno' - ustawia Okno.ps1

function Wypisz([string]$t = '', [string]$kolor = 'Gray') {
    if ($script:Tryb -eq 'okno') { OknoWypisz $t $kolor } else { Write-Host $t -ForegroundColor $kolor }
}
# Linia postepu nadpisywana w miejscu
function Postep([string]$t) {
    if ($script:Tryb -eq 'okno') { OknoStatus $t } else { Write-Host "`r$t" -NoNewline -ForegroundColor DarkGray }
}
function KoniecPostepu([string]$t) {
    if ($script:Tryb -eq 'okno') { OknoStatus $t; OknoWypisz $t 'DarkGray' } else { Write-Host "`r$t" -ForegroundColor DarkGray }
}
function Pauza([int]$ms) {
    if ($script:Tryb -ne 'okno') { Start-Sleep -Milliseconds $ms; return }
    $koniec = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $koniec) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
}
# Dlugie wywolanie bez dostepu do funkcji skryptu (HTTP do modelu, GitHub): w oknie w osobnym
# watku, zeby okno nie zamarzalo; w konsoli zwyczajnie.
function CzekajNa([scriptblock]$sb, [object[]]$argumenty) {
    if ($script:Tryb -ne 'okno') { return & $sb @argumenty }
    $ps = [PowerShell]::Create().AddScript($sb.ToString())
    foreach ($a in $argumenty) { [void]$ps.AddArgument($a) }
    $h = $ps.BeginInvoke()
    while (-not $h.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
    try { $wynik = $ps.EndInvoke($h) }
    catch { throw $(if ($_.Exception.InnerException) { $_.Exception.InnerException } else { $_.Exception }) }
    finally { $ps.Dispose() }
    if ($wynik.Count -eq 1) { $wynik[0] } else { $wynik }
}
