<#
    LLMCleaner - sciezki programu, logi, stan wspolny i drobne funkcje pomocnicze
#>

$Sys = $env:SystemDrive          # zwykle C:, ale Windows moze stac na innym dysku
$WinDir = $env:windir
$script:Analyses = @{}            # wyniki analizy dyskow, tez dla czatu
$script:Categories = @()
$script:Leftovers = @()
$script:ProfileScan = $null
# Wlasna Ollama w folderze programu (instaluje ja Install-AI.ps1); osobny port, zeby nie
# kolidowac z Ollama zainstalowana w systemie
$AiDir = Join-Path $AppDir 'ai'
$OllamaExe = Join-Path $AiDir 'ollama\ollama.exe'
$OllamaUrl = 'http://127.0.0.1:11435'
# Logi i kopie rejestru poza folderem programu - przetrwaja aktualizacje i odinstalowanie
$LogDir = Join-Path $env:LOCALAPPDATA 'LLMCleaner\logs'
$REPARSE = [IO.FileAttributes]::ReparsePoint

New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("LLMCleaner_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))

function Write-Log($t) {
    Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) -Encoding UTF8
}

# Element skanu, ktorego nie da sie odczytac (dziwny folder, wpis rejestru, uszkodzony skrot), jest
# pomijany zamiast przerywac caly skan. Szczegoly z miejscem bledu ida do logu.
$script:ScanErrors = 0
function Add-ScanError([string]$what, $err) {
    $script:ScanErrors++
    Write-Log "Pominieto ($what): $($err.Exception.Message) $($err.ScriptStackTrace)"
}

function Format-Size([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    if ($b -gt 0) { return '{0:N0} KB' -f ($b / 1KB) }
    return '0'
}

function Get-SystemFreeSpace { [double](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Sys'").FreeSpace }
