<#
    LLMCleaner - history of cleanups, %LOCALAPPDATA%\LLMCleaner\history.json (the last 20 runs)
#>

$HistoryFile = Join-Path $env:LOCALAPPDATA 'LLMCleaner\history.json'

# Newest first: Date, Total, FreeBefore, FreeAfter (bytes)
function Get-CleanupHistory {
    if (-not (Test-Path -LiteralPath $HistoryFile)) { return @() }
    try { @(Get-Content -LiteralPath $HistoryFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) } catch { @() }
}

function Add-CleanupHistory($w) {
    $entry = [pscustomobject]@{ Date = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Drive = $Sys; Total = [double]$w.Total
        FreeBefore = [double]$w.FreeBefore; FreeAfter = [double]$w.FreeAfter
    }
    $list = @($entry) + @(Get-CleanupHistory | Select-Object -First 19)
    try { [IO.File]::WriteAllText($HistoryFile, (ConvertTo-Json -InputObject $list), (New-Object Text.UTF8Encoding $false)) }
    catch { Write-Log "History: $($_.Exception.Message)" }
}
