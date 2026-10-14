<#
    LLMCleaner - prywatny serwer Ollama w folderze programu
#>

function OllamaDziala {
    try { Invoke-RestMethod "$OllamaUrl/api/version" -TimeoutSec 2 -ErrorAction Stop | Out-Null; $true } catch { $false }
}

# Job Object z KILL_ON_JOB_CLOSE: serwer (i jego procesy runner) ginie razem z LLMCleanerem,
# takze gdy okno zostanie zamkniete krzyzykiem
function PrzypnijDoZadania([Diagnostics.Process]$proces) {
    if (-not ('LlmJob' -as [type])) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Rdzen\cs\LlmJob.cs')))
    }
    [LlmJob]::Attach($proces.Handle)
}

function UruchomOllama {
    if (OllamaDziala) { return $true }
    if (-not (Test-Path -LiteralPath $OllamaExe)) { return $false }
    # Modele i klucze Ollamy zostaja w folderze ai\ - nic nie trafia do profilu uzytkownika
    $psi = New-Object Diagnostics.ProcessStartInfo $OllamaExe, 'serve'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['OLLAMA_HOST'] = $OllamaUrl -replace '^http://', ''
    $psi.EnvironmentVariables['OLLAMA_MODELS'] = Join-Path $AiDir 'models'
    $psi.EnvironmentVariables['USERPROFILE'] = $AiDir
    $proces = [Diagnostics.Process]::Start($psi)
    if (-not (PrzypnijDoZadania $proces)) { Log 'Job Object: nie udalo sie przypiac serwera' }
    for ($i = 0; $i -lt 40; $i++) { Pauza 500; if (OllamaDziala) { return $true } }
    $false
}

function ZatrzymajOllama { if ('LlmJob' -as [type]) { [LlmJob]::Close() }; $script:llmStan = $null }

function MaModel {
    try { $t = Invoke-RestMethod "$OllamaUrl/api/tags" -TimeoutSec 5 -ErrorAction Stop } catch { return $false }
    [bool]($t.models | Where-Object { $_.name -eq $Model -or $_.name -eq "$Model`:latest" })
}

function Ollama($wiadomosci, $format) {
    $body = @{ model = $Model; messages = @($wiadomosci); stream = $false; keep_alive = '5m'
        options = @{ temperature = 0.2; num_ctx = 12288 }
    }
    if ($format) { $body.format = $format }
    $json = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 20 -Compress))
    $r = CzekajNa {
        param($url, $json)
        Invoke-RestMethod $url -Method Post -TimeoutSec 600 -ErrorAction Stop -Body $json -ContentType 'application/json; charset=utf-8'
    } @("$OllamaUrl/api/chat", $json)
    $r.message.content
}

# Model ladowany dopiero przy pierwszym uzyciu
$script:llmStan = $null
function ZapewnijModel {
    if ($BezLLM) { Wypisz (L '   Model jest wyłączony (uruchomiono z -BezLLM).' '   The AI model is disabled (started with -BezLLM).') 'Yellow'; return $false }
    if ($null -ne $script:llmStan) { return $script:llmStan }
    Wypisz ((L '   Uruchamiam model {0} (pierwsze użycie trwa ok. 10-20 s)...' '   Starting model {0} (the first use takes about 10-20 s)...') -f $Model) 'DarkGray'
    if (-not (Test-Path -LiteralPath $OllamaExe)) {
        Wypisz (L '   Asystent AI nie jest zainstalowany. Uruchom ponownie instalator i zaznacz asystenta AI (albo Install-AI.ps1 z folderu programu).' '   The AI assistant is not installed. Run the installer again and tick the AI assistant (or run Install-AI.ps1 from the program folder).') 'Yellow'
        $script:llmStan = $false
    }
    elseif (-not (UruchomOllama)) {
        Wypisz (L '   Nie udało się uruchomić Ollamy z folderu ai\ - asystent niedostępny.' '   Could not start Ollama from the ai\ folder - the assistant is unavailable.') 'Yellow'
        $script:llmStan = $false
    }
    elseif (-not (MaModel)) {
        Wypisz ((L '   Brak modelu {0} w folderze ai\models (Install-AI.ps1 -Model {0}) - asystent niedostępny.' '   Model {0} is missing in ai\models (Install-AI.ps1 -Model {0}) - the assistant is unavailable.') -f $Model) 'Yellow'
        $script:llmStan = $false
    }
    else { $script:llmStan = $true }
    Log "Model: $($script:llmStan)"
    $script:llmStan
}
