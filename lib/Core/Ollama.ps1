<#
    LLMCleaner - private Ollama server in the program folder
#>

function Test-Ollama {
    try { Invoke-RestMethod "$OllamaUrl/api/version" -TimeoutSec 2 -ErrorAction Stop | Out-Null; $true } catch { $false }
}

# Job Object with KILL_ON_JOB_CLOSE: the server (and its runner processes) dies with LLMCleaner,
# also when the window is closed with the X button
function Add-ToJob([Diagnostics.Process]$proc) {
    if (-not ('LlmJob' -as [type])) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Core\cs\LlmJob.cs')))
    }
    [LlmJob]::Attach($proc.Handle)
}

function Start-Ollama {
    if (Test-Ollama) { return $true }
    if (-not (Test-Path -LiteralPath $OllamaExe)) { return $false }
    # Ollama models and keys stay in the ai\ folder - nothing goes to the user profile
    $psi = New-Object Diagnostics.ProcessStartInfo $OllamaExe, 'serve'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['OLLAMA_HOST'] = $OllamaUrl -replace '^http://', ''
    $psi.EnvironmentVariables['OLLAMA_MODELS'] = Join-Path $AiDir 'models'
    $psi.EnvironmentVariables['USERPROFILE'] = $AiDir
    $proc = [Diagnostics.Process]::Start($psi)
    if (-not (Add-ToJob $proc)) { Write-Log 'Job Object: failed to attach the server' }
    for ($i = 0; $i -lt 40; $i++) { Wait-Responsive 500; if (Test-Ollama) { return $true } }
    $false
}

function Stop-Ollama { if ('LlmJob' -as [type]) { [LlmJob]::Close() }; $script:ModelState = $null }

function Test-Model {
    try { $t = Invoke-RestMethod "$OllamaUrl/api/tags" -TimeoutSec 5 -ErrorAction Stop } catch { return $false }
    [bool]($t.models | Where-Object { $_.name -eq $Model -or $_.name -eq "$Model`:latest" })
}

function Invoke-Ollama($messages, $format) {
    $body = @{ model = $Model; messages = @($messages); stream = $false; keep_alive = '5m'
        options = @{ temperature = 0.2; num_ctx = 12288 }
    }
    if ($format) { $body.format = $format }
    $json = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 20 -Compress))
    $r = Invoke-Background {
        param($url, $json)
        try { Invoke-RestMethod $url -Method Post -TimeoutSec 600 -ErrorAction Stop -Body $json -ContentType 'application/json; charset=utf-8' }
        catch {
            # Ollama describes the error in the response body ({"error": "..."}) - without it only "(500)" remains
            $content = "$($_.ErrorDetails.Message)"
            if (-not $content) { try { $content = (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch { $content = '' } }
            if ($content) { throw "$($_.Exception.Message) $content" }
            throw
        }
    } @("$OllamaUrl/api/chat", $json)
    if ($r.message.content) { return $r.message.content }
    if ($r.done_reason -and $r.done_reason -ne 'stop') { throw "Ollama: done_reason=$($r.done_reason)" }
    $r.message.content
}

# Model is loaded only on first use
$script:ModelState = $null
function Initialize-Model {
    if ($NoAI) { Write-Line (L '   Model jest wyłączony (uruchomiono z -BezLLM).' '   The AI model is disabled (started with -BezLLM).') 'Yellow'; return $false }
    if ($null -ne $script:ModelState) { return $script:ModelState }
    Write-Line ((L '   Uruchamiam model {0} (pierwsze użycie trwa ok. 10-20 s)...' '   Starting model {0} (the first use takes about 10-20 s)...') -f $Model) 'DarkGray'
    if (-not (Test-Path -LiteralPath $OllamaExe)) {
        Write-Line (L '   Asystent AI nie jest zainstalowany. Uruchom ponownie instalator i zaznacz asystenta AI (albo Install-AI.ps1 z folderu programu).' '   The AI assistant is not installed. Run the installer again and tick the AI assistant (or run Install-AI.ps1 from the program folder).') 'Yellow'
        $script:ModelState = $false
    }
    elseif (-not (Start-Ollama)) {
        Write-Line (L '   Nie udało się uruchomić Ollamy z folderu ai\ - asystent niedostępny.' '   Could not start Ollama from the ai\ folder - the assistant is unavailable.') 'Yellow'
        $script:ModelState = $false
    }
    elseif (-not (Test-Model)) {
        Write-Line ((L '   Brak modelu {0} w folderze ai\models (Install-AI.ps1 -Model {0}) - asystent niedostępny.' '   Model {0} is missing in ai\models (Install-AI.ps1 -Model {0}) - the assistant is unavailable.') -f $Model) 'Yellow'
        $script:ModelState = $false
    }
    else { $script:ModelState = $true }
    Write-Log "Model: $($script:ModelState)"
    $script:ModelState
}
