<#
    LLMCleaner - ustawienia programu (strona Ustawienia w oknie), plik %LOCALAPPDATA%\LLMCleaner\ustawienia.json
    Wczytywane na samym poczatku, przed podniesieniem uprawnien. Parametry z wiersza polecen maja pierwszenstwo.
#>

$ConfigFile = Join-Path $env:LOCALAPPDATA 'LLMCleaner\ustawienia.json'

# Pola: Jezyk (auto/pl/en), Motyw (auto/jasny/ciemny), Model, Asystent, Aktualizacje, Podglad
function Read-Config {
    $k = [ordered]@{ Language = 'auto'; Theme = ''; Model = ''; Assistant = $true; CheckUpdates = $true; Preview = $false }
    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $file = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $file.PSObject.Properties) { if ($k.Contains($p.Name) -and $null -ne $p.Value) { $k[$p.Name] = $p.Value } }
        }
        catch { $null = $_ }
    }
    $k
}

function Save-Config($k) {
    New-Item -ItemType Directory -Force (Split-Path $ConfigFile) | Out-Null
    [IO.File]::WriteAllText($ConfigFile, (ConvertTo-Json -InputObject $k), (New-Object Text.UTF8Encoding $false))
}

# Model wybrany w instalatorze (config.json obok skryptu) albo domyslny
function Get-InstallerModel {
    $cfg = Join-Path $AppDir 'config.json'
    $m = $null
    if (Test-Path -LiteralPath $cfg) { try { $m = (Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).model } catch { $m = $null } }
    if ($m) { "$m" } else { 'qwen3:4b-instruct' }
}

# Modele pobrane do ai\models (manifests\registry.ollama.ai\library\qwen3\4b-instruct -> qwen3:4b-instruct)
function Get-LocalModels {
    $man = Join-Path $AppDir 'ai\models\manifests'
    if (-not (Test-Path -LiteralPath $man)) { return @() }
    @(foreach ($f in Get-ChildItem -LiteralPath $man -Recurse -File) {
            $c = @($f.FullName.Substring($man.Length).Trim('\') -split '\\')
            if ($c.Count -ne 4) { continue }
            if ($c[1] -eq 'library') { "$($c[2]):$($c[3])" } else { "$($c[1])/$($c[2]):$($c[3])" }
        }) | Sort-Object -Unique
}
