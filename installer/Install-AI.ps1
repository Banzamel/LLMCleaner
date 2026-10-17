<#
    Install-AI.ps1 - installs the LLMCleaner AI assistant in the program folder:
      ai\ollama\   Ollama engine (official zip, no installer, autostart or tray icon)
      ai\models\   models
    Nothing goes into the user profile or environment variables; uninstalling
    LLMCleaner removes the whole ai\ folder.

    Called by the installer; can also be run manually (e.g. in the portable version):
      powershell -ExecutionPolicy Bypass -File Install-AI.ps1 -Model qwen3:4b-instruct
#>
param(
    [string]$Model = 'qwen3:4b-instruct',
    [ValidateSet('en', 'pl', 'es')][string]$Lang = 'en',
    [string]$AppDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # in PS 5.1 the progress bar slows downloads many times over
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Package depends on CPU: ARM64 (e.g. Snapdragon) or x64; AMD GPUs also need the ROCm libraries
$Url = 'https://github.com/ollama/ollama/releases/latest/download'
$Arm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64'
$Packages = @(if ($Arm) { 'ollama-windows-arm64.zip' } else { 'ollama-windows-amd64.zip' })
if (-not $Arm -and (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'AMD|Radeon' })) { $Packages += 'ollama-windows-amd64-rocm.zip' }
$Port = '127.0.0.1:11435'                  # same as in LLMCleaner.ps1

$T = @{
    en = @{ Title = 'LLMCleaner - AI assistant setup'; Dir = 'Folder'; Have = 'AI engine (Ollama) is already installed.'
        Down = 'Downloading the AI engine (Ollama, about 1.4 GB)'; Unpack = 'Unpacking...'; Start = 'Starting the AI engine...'
        Pull = 'Downloading model {0} (about 2.5-5 GB, this can take a while)...'; Ok = 'Done. The AI assistant is ready.'
        Fail = 'AI setup failed: {0}'; Later = 'LLMCleaner works without AI. You can rerun this script later:'; Key = 'Press Enter to close'
    }
    pl = @{ Title = 'LLMCleaner - instalacja asystenta AI'; Dir = 'Folder'; Have = 'Silnik AI (Ollama) jest już zainstalowany.'
        Down = 'Pobieram silnik AI (Ollama, ok. 1,4 GB)'; Unpack = 'Rozpakowuję...'; Start = 'Uruchamiam silnik AI...'
        Pull = 'Pobieram model {0} (ok. 2,5-5 GB, to może chwilę potrwać)...'; Ok = 'Gotowe. Asystent AI jest gotowy.'
        Fail = 'Instalacja AI nie powiodła się: {0}'; Later = 'LLMCleaner działa bez AI. Ten skrypt możesz uruchomić później:'; Key = 'Enter zamyka okno'
    }
    es = @{ Title = 'LLMCleaner - instalación del asistente de IA'; Dir = 'Carpeta'; Have = 'El motor de IA (Ollama) ya está instalado.'
        Down = 'Descargando el motor de IA (Ollama, unos 1,4 GB)'; Unpack = 'Descomprimiendo...'; Start = 'Iniciando el motor de IA...'
        Pull = 'Descargando el modelo {0} (unos 2,5-5 GB, puede tardar un rato)...'; Ok = 'Listo. El asistente de IA está preparado.'
        Fail = 'La instalación de la IA ha fallado: {0}'; Later = 'LLMCleaner funciona sin IA. Puedes volver a ejecutar este script más tarde:'; Key = 'Pulsa Enter para cerrar'
    }
}[$Lang]

$Host.UI.RawUI.WindowTitle = $T.Title
Write-Host ""
Write-Host "  $($T.Title)" -ForegroundColor Cyan
Write-Host ""

$AiDir = Join-Path $AppDir 'ai'
$OllamaDir = Join-Path $AiDir 'ollama'
$ModelsDir = Join-Path $AiDir 'models'
$Exe = Join-Path $OllamaDir 'ollama.exe'
$zip = Join-Path $AiDir 'ollama-download.zip'
$server = $null

try {
    New-Item -ItemType Directory -Force $OllamaDir, $ModelsDir | Out-Null
    Write-Host "  $($T.Dir): $AiDir" -ForegroundColor DarkGray

    if (Test-Path -LiteralPath $Exe) {
        Write-Host "  $($T.Have)" -ForegroundColor Gray
    }
    else {
        foreach ($p in $Packages) {
            Write-Host "  $($T.Down) [$p]" -ForegroundColor Gray
            # curl.exe (built into Windows 10 1803+) shows progress; otherwise Invoke-WebRequest
            $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
            if (Test-Path -LiteralPath $curl) {
                & $curl -L --fail --progress-bar -o $zip "$Url/$p"
                if ($LASTEXITCODE -ne 0) { throw "download failed: $p (curl exit $LASTEXITCODE)" }
            }
            else { Invoke-WebRequest "$Url/$p" -OutFile $zip -UseBasicParsing }

            Write-Host "  $($T.Unpack)" -ForegroundColor Gray
            $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
            if (Test-Path -LiteralPath $tar) {
                & $tar -xf $zip -C $OllamaDir
                if ($LASTEXITCODE -ne 0) { throw "unpack failed: $p (tar exit $LASTEXITCODE)" }
            }
            else { Expand-Archive -LiteralPath $zip -DestinationPath $OllamaDir -Force }
            Remove-Item -LiteralPath $zip -Force
        }
        if (-not (Test-Path -LiteralPath $Exe)) { throw "ollama.exe not found in the downloaded archive" }
    }

    # Private server: own port, models and keys in ai\
    Write-Host "  $($T.Start)" -ForegroundColor Gray
    $env:OLLAMA_HOST = $Port
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, 'serve'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['OLLAMA_HOST'] = $Port
    $psi.EnvironmentVariables['OLLAMA_MODELS'] = $ModelsDir
    $psi.EnvironmentVariables['USERPROFILE'] = $AiDir
    $server = [Diagnostics.Process]::Start($psi)
    $ok = $false
    for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
        Start-Sleep -Milliseconds 500
        try { Invoke-RestMethod "http://$Port/api/version" -TimeoutSec 2 | Out-Null; $ok = $true } catch { }
    }
    if (-not $ok) { throw "Ollama server did not start" }

    Write-Host ("  " + $T.Pull -f $Model) -ForegroundColor Gray
    & $Exe pull $Model
    if ($LASTEXITCODE -ne 0) { throw "ollama pull $Model (exit $LASTEXITCODE)" }

    # Model used by LLMCleaner.ps1 when -Model is not given
    [IO.File]::WriteAllText((Join-Path $AppDir 'config.json'), "{ `"model`": `"$Model`" }")

    Write-Host ""
    Write-Host "  $($T.Ok)" -ForegroundColor Green
    Start-Sleep -Seconds 3
}
catch {
    Write-Host ""
    Write-Host ("  " + $T.Fail -f $_.Exception.Message) -ForegroundColor Yellow
    Write-Host "  $($T.Later)" -ForegroundColor Gray
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Model $Model" -ForegroundColor Gray
    Write-Host ""
    Read-Host "  $($T.Key)"
}
finally {
    # The server was only needed to pull the model; LLMCleaner starts it itself, on demand
    if ($server -and -not $server.HasExited) { $server.Kill(); $server.WaitForExit(5000) | Out-Null }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
}
