<#
    LLMCleaner - czat z asystentem
#>

function Invoke-ChatConsole {
    if (-not (Initialize-Model)) { return }
    Start-Chat
    Write-Host ""
    Write-Host (L '   Rozmowa z asystentem. Pusta linia = powrót do planu.' '   Chat with the assistant. An empty line returns to the plan.') -ForegroundColor Cyan
    while ($true) {
        Write-Host ""
        $q = Read-Host (L '   Ty' '   You')
        if (-not $q) { return }
        $a = Send-ChatQuestion $q
        if ($a) { Write-Host ""; Write-Host "   LLMCleaner: $a" -ForegroundColor White }
    }
}
