<#
    Install-AI.ps1 - instaluje Ollame (jesli jej nie ma) i pobiera model dla LLMCleanera.
    Wywolywany przez instalator, mozna tez uruchomic recznie:
      powershell -ExecutionPolicy Bypass -File Install-AI.ps1 -Model qwen3:4b-instruct -ModelDir D:\Ollama\models
#>
param(
    [string]$Model = 'qwen3:4b-instruct',
    [string]$ModelDir,
    [ValidateSet('en', 'pl')][string]$Lang = 'en'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # w PS 5.1 pasek postepu wielokrotnie spowalnia pobieranie
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$T = @{
    en = @{ Title = 'LLMCleaner - AI assistant setup'; Dir = 'Model folder'; Have = 'Ollama is already installed.'
            Down = 'Downloading Ollama...'; Inst = 'Installing Ollama...'; Start = 'Starting the Ollama server...'
            Pull = 'Downloading model {0} (about 2.5-5 GB, this can take a while)...'; Ok = 'Done. The AI assistant is ready.'
            Fail = 'AI setup failed: {0}'; Later = 'LLMCleaner works without AI. You can rerun this script later:'; Key = 'Press Enter to close' }
    pl = @{ Title = 'LLMCleaner - instalacja asystenta AI'; Dir = 'Folder modeli'; Have = 'Ollama jest już zainstalowana.'
            Down = 'Pobieram Ollamę...'; Inst = 'Instaluję Ollamę...'; Start = 'Uruchamiam serwer Ollamy...'
            Pull = 'Pobieram model {0} (ok. 2,5-5 GB, to może chwilę potrwać)...'; Ok = 'Gotowe. Asystent AI jest gotowy.'
            Fail = 'Instalacja AI nie powiodła się: {0}'; Later = 'LLMCleaner działa bez AI. Ten skrypt możesz uruchomić później:'; Key = 'Enter zamyka okno' }
}[$Lang]

$Host.UI.RawUI.WindowTitle = $T.Title
Write-Host ""
Write-Host "  $($T.Title)" -ForegroundColor Cyan
Write-Host ""

try {
    if ($ModelDir) {
        New-Item -ItemType Directory -Force $ModelDir | Out-Null
        [Environment]::SetEnvironmentVariable('OLLAMA_MODELS', $ModelDir, 'User')
        $env:OLLAMA_MODELS = $ModelDir
        Write-Host "  $($T.Dir): $ModelDir" -ForegroundColor DarkGray
    }

    $exe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
    if (Test-Path -LiteralPath $exe) {
        Write-Host "  $($T.Have)" -ForegroundColor Gray
    }
    else {
        Write-Host "  $($T.Down)" -ForegroundColor Gray
        $setup = Join-Path $env:TEMP 'OllamaSetup.exe'
        Invoke-WebRequest 'https://ollama.com/download/OllamaSetup.exe' -OutFile $setup -UseBasicParsing
        Write-Host "  $($T.Inst)" -ForegroundColor Gray
        Start-Process $setup -ArgumentList '/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES' -Wait
        Remove-Item $setup -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $exe)) { throw "ollama.exe not found after install" }
    }

    # Restart serwera, zeby na pewno widzial OLLAMA_MODELS
    Write-Host "  $($T.Start)" -ForegroundColor Gray
    Get-Process 'ollama', 'ollama app' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process $exe -ArgumentList 'serve' -WindowStyle Hidden
    $ok = $false
    for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
        Start-Sleep -Milliseconds 500
        try { Invoke-RestMethod 'http://127.0.0.1:11434/api/version' -TimeoutSec 2 | Out-Null; $ok = $true } catch { }
    }
    if (-not $ok) { throw "Ollama server did not start" }

    Write-Host ("  " + $T.Pull -f $Model) -ForegroundColor Gray
    & $exe pull $Model
    if ($LASTEXITCODE -ne 0) { throw "ollama pull $Model (exit $LASTEXITCODE)" }

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
