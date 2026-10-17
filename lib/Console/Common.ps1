<#
    LLMCleaner - headers, confirmation and exit
#>

function Write-Header($t) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}

function Confirm-Cleanup {
    Write-Header (L 'PODSUMOWANIE PRZED CZYSZCZENIEM' 'SUMMARY BEFORE CLEANING')
    $lines = Get-Summary
    if (-not $lines) { Write-Host (L '   Nic nie jest zaznaczone - nie ma czego czyścić.' '   Nothing is selected - there is nothing to clean.') -ForegroundColor Yellow; return $false }
    foreach ($x in $lines) { Write-Host "   $($x.T)" -ForegroundColor $x.K }
    Write-Host ""
    $t = Read-Host (L '   Uruchomić czyszczenie? [t/N]' '   Start cleaning? [y/N]')
    if ($t -match '^[TtYySs]') { return $true }
    Write-Host (L '   Wracam do planu.' '   Back to the plan.') -ForegroundColor DarkGray
    $false
}

function Exit-Console([string]$text, [string]$color = 'Gray') {
    Stop-Ollama
    Write-Host "`n   $text`n" -ForegroundColor $color
    Read-Host (L '   Enter kończy' '   Press Enter to exit') | Out-Null
    exit
}
