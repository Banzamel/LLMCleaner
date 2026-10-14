<#
    LLMCleaner - naglowki, potwierdzenie i zakonczenie
#>

function Naglowek($t) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}

function PotwierdzKonsola {
    Naglowek (L 'PODSUMOWANIE PRZED CZYSZCZENIEM' 'SUMMARY BEFORE CLEANING')
    $linie = Podsumowanie
    if (-not $linie) { Write-Host (L '   Nic nie jest zaznaczone - nie ma czego czyścić.' '   Nothing is selected - there is nothing to clean.') -ForegroundColor Yellow; return $false }
    foreach ($x in $linie) { Write-Host "   $($x.T)" -ForegroundColor $x.K }
    Write-Host ""
    $t = Read-Host (L '   Uruchomić czyszczenie? [t/N]' '   Start cleaning? [y/N]')
    if ($t -match '^[TtYy]') { return $true }
    Write-Host (L '   Wracam do planu.' '   Back to the plan.') -ForegroundColor DarkGray
    $false
}

function Koniec([string]$tekst, [string]$kolor = 'Gray') {
    ZatrzymajOllama
    Write-Host "`n   $tekst`n" -ForegroundColor $kolor
    Read-Host (L '   Enter kończy' '   Press Enter to exit') | Out-Null
    exit
}
