<#
    LLMCleaner - program paths, logs, shared state and small helpers
#>

$Sys = $env:SystemDrive          # usually C:, but Windows may be on another drive
$WinDir = $env:windir
$script:Analyses = @{}            # drive analysis results, also used by the chat
$script:Categories = @()
$script:Leftovers = @()
$script:ProfileScan = $null
# Private Ollama in the program folder (installed by Install-AI.ps1); separate port so it doesn't
# clash with a system-wide Ollama
$AiDir = Join-Path $AppDir 'ai'
$OllamaExe = Join-Path $AiDir 'ollama\ollama.exe'
$OllamaUrl = 'http://127.0.0.1:11435'
# Logs and registry backups live outside the program folder - they survive updates and uninstall
$LogDir = Join-Path $env:LOCALAPPDATA 'LLMCleaner\logs'
$REPARSE = [IO.FileAttributes]::ReparsePoint

New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("LLMCleaner_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))

function Write-Log($t) {
    Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) -Encoding UTF8
}

# Run logs older than $days (all of them with 0), never the current one. Registry backups stay.
function Remove-OldLogs([int]$days = 0) {
    $cutoff = (Get-Date).AddDays(-$days)
    $old = @(Get-ChildItem -LiteralPath $LogDir -Filter 'LLMCleaner_*.log' -File -Force |
            Where-Object { $_.FullName -ne $LogFile -and ($days -le 0 -or $_.LastWriteTime -lt $cutoff) })
    $n = 0
    foreach ($f in $old) { try { $f.Delete(); $n++ } catch { } }
    $n
}
if ([int]$Config.LogDays -gt 0) { $n = Remove-OldLogs ([int]$Config.LogDays); if ($n) { Write-Log "Deleted $n logs older than $($Config.LogDays) days." } }

# Folders excluded in Settings: never measured, listed or deleted. Stored with a trailing \ for prefix checks.
$script:ExcludedFolders = @(foreach ($f in @($Config.ExcludedFolders)) { $t = "$f".Trim().TrimEnd('\'); if ($t) { "$t\" } })
# Path is an excluded folder or lies inside one
function Test-Excluded([string]$path) {
    if (-not $script:ExcludedFolders.Count -or -not $path) { return $false }
    $p = $path.TrimEnd('\') + '\'
    foreach ($e in $script:ExcludedFolders) { if ($p.StartsWith($e, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    $false
}
# Deleting the whole folder would also take an excluded folder inside it
function Test-HoldsExcluded([string]$path) {
    if (-not $script:ExcludedFolders.Count -or -not $path) { return $false }
    $p = $path.TrimEnd('\') + '\'
    foreach ($e in $script:ExcludedFolders) { if ($e.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    $false
}

# A scan item that can't be read (odd folder, registry entry, broken shortcut) is skipped
# instead of aborting the whole scan. Details with the error location go to the log.
$script:ScanErrors = 0
function Add-ScanError([string]$what, $err) {
    $script:ScanErrors++
    Write-Log "Skipped ($what): $($err.Exception.Message) $($err.ScriptStackTrace)"
}

function Format-Size([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N0} MB' -f ($b / 1MB) }
    if ($b -gt 0) { return '{0:N0} KB' -f ($b / 1KB) }
    return '0'
}

function Get-SystemFreeSpace { [double](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Sys'").FreeSpace }
