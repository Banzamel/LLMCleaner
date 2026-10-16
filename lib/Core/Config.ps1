<#
    LLMCleaner - program settings (Settings page in the window), file %LOCALAPPDATA%\LLMCleaner\settings.json
    Loaded at the very start, before elevation. Command-line parameters take precedence.
#>

$ConfigFile = Join-Path $env:LOCALAPPDATA 'LLMCleaner\settings.json'

# Polish values saved by versions before 1.6.4 (theme and page ids)
$OldPrefValues = @{
    jasny = 'light'; ciemny = 'dark'; przeglad = 'overview'; analiza = 'analysis'; autostart = 'startup'
    sterowniki = 'drivers'; czat = 'chat'; ustawienia = 'settings'; czyszczenie = 'cleanup'; dziennik = 'log'
}

# Reads a JSON settings file into a hashtable. If it does not exist yet, reads the file an older version
# saved instead, renaming its Polish keys ($oldKeys) and values.
function Read-PrefsFile([string]$file, [string]$oldFile, [hashtable]$oldKeys) {
    $old = -not (Test-Path -LiteralPath $file)
    $path = if ($old) { $oldFile } else { $file }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    $h = @{}
    foreach ($p in $json.PSObject.Properties) {
        $name = if ($old -and $oldKeys.ContainsKey($p.Name)) { $oldKeys[$p.Name] } else { $p.Name }
        $value = $p.Value
        if ($old -and $value -is [string] -and $OldPrefValues.ContainsKey($value)) { $value = $OldPrefValues[$value] }
        $h[$name] = $value
    }
    $h
}

# Fields: Language (auto/pl/en), Theme (auto/light/dark), Model, Assistant, CheckUpdates, Preview
function Read-Config {
    $k = [ordered]@{ Language = 'auto'; Theme = ''; Model = ''; Assistant = $true; CheckUpdates = $true; Preview = $false }
    $oldKeys = @{ Jezyk = 'Language'; Motyw = 'Theme'; Asystent = 'Assistant'; Aktualizacje = 'CheckUpdates'; Podglad = 'Preview' }
    $file = Read-PrefsFile $ConfigFile (Join-Path $env:LOCALAPPDATA 'LLMCleaner\ustawienia.json') $oldKeys
    if ($file) { foreach ($n in $file.Keys) { if ($k.Contains($n) -and $null -ne $file[$n]) { $k[$n] = $file[$n] } } }
    $k
}

function Save-Config($k) {
    New-Item -ItemType Directory -Force (Split-Path $ConfigFile) | Out-Null
    [IO.File]::WriteAllText($ConfigFile, (ConvertTo-Json -InputObject $k), (New-Object Text.UTF8Encoding $false))
}

# Model chosen in the installer (config.json next to the script) or the default
function Get-InstallerModel {
    $cfg = Join-Path $AppDir 'config.json'
    $m = $null
    if (Test-Path -LiteralPath $cfg) { try { $m = (Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).model } catch { $m = $null } }
    if ($m) { "$m" } else { 'qwen3:4b-instruct' }
}

# Models downloaded to ai\models (manifests\registry.ollama.ai\library\qwen3\4b-instruct -> qwen3:4b-instruct)
function Get-LocalModels {
    $man = Join-Path $AppDir 'ai\models\manifests'
    if (-not (Test-Path -LiteralPath $man)) { return @() }
    @(foreach ($f in Get-ChildItem -LiteralPath $man -Recurse -File) {
            $c = @($f.FullName.Substring($man.Length).Trim('\') -split '\\')
            if ($c.Count -ne 4) { continue }
            if ($c[1] -eq 'library') { "$($c[2]):$($c[3])" } else { "$($c[1])/$($c[2]):$($c[3])" }
        }) | Sort-Object -Unique
}
