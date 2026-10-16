<#
    LLMCleaner - AI descriptions and advice for startup entries
#>

# As in disk analysis: advice only from this list; for protected entries the program sets it
$StartupAdvice = if ($Language -eq 'en') {
    @('keep it on', 'can be turned off - start it by hand when needed', 'check whether you use it')
}
else {
    @('zostaw włączone', 'można wyłączyć - uruchomisz ręcznie, gdy potrzebne', 'sprawdź, czy go używasz')
}

$StartupSchema = @{
    type       = 'object'
    properties = @{
        items = @{ type = 'array'; items = @{ type = 'object'
                properties                         = @{ id = @{ type = 'string' }; description = @{ type = 'string' }; advice = @{ type = 'string'; enum = $StartupAdvice } }
                required                           = @('id', 'description', 'advice')
            }
        }
    }
    required   = @('items')
}

$PromptStartup = if ($Language -eq 'en') {
    @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of programs that start when the user signs in
(name, command, publisher, source). For EACH item give:
- "description": what the program is and why it starts with Windows - based on the name, command and publisher,
- "advice": one of the allowed values.
Rules:
- Chat apps, game launchers, cloud storage clients, update helpers of apps the user opens by hand and
  "helper"/"tray" tools usually do not need to start with Windows: "can be turned off - start it by hand when needed".
- Security software, drivers, audio, touchpad, keyboard or graphics panels: "keep it on".
- If you do not know the program, write "unknown program" and choose "check whether you use it".
- Do not invent program names that are not in the data. Description max. 12 words, in English.
'@
}
else {
    @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę programów uruchamianych przy logowaniu
(nazwa, polecenie, wydawca, źródło). Dla KAŻDEJ pozycji podaj:
- "description": czym jest program i po co startuje z Windows - na podstawie nazwy, polecenia i wydawcy,
- "advice": jedna z dozwolonych wartości.
Zasady:
- Komunikatory, launchery gier, klienty chmury, pomocniki aplikacji otwieranych ręcznie i narzędzia
  w zasobniku zwykle nie muszą startować z Windows: "można wyłączyć - uruchomisz ręcznie, gdy potrzebne".
- Ochrona antywirusowa, sterowniki, panele dźwięku, touchpada, klawiatury i grafiki: "zostaw włączone".
- Jeśli nie znasz programu, napisz "nieznany program" i wybierz "sprawdź, czy go używasz".
- Nie zmyślaj nazw programów, których nie ma w danych. Opis maks. 12 słów, po polsku.
'@
}

# Model descriptions and advice for startup entries. Returns the number of described items (or -1 on error).
function Invoke-StartupAi($entries) {
    if (-not @($entries).Count) { return 0 }
    if (-not (Initialize-Model)) { return -1 }
    $list = @($entries | ForEach-Object { @{ id = $_.Id; name = $_.Name; command = $_.Command; publisher = $_.Publisher; source = $_.Source } })
    Write-Line ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $list.Count) 'DarkGray'
    try {
        $answer = Invoke-Ollama @(@{ role = 'system'; content = $PromptStartup },
            @{ role = 'user'; content = (ConvertTo-Json -InputObject $list -Depth 5 -Compress) }) $StartupSchema
        $n = 0
        foreach ($o in @(($answer | ConvertFrom-Json -ErrorAction Stop).items)) {
            $w = $entries | Where-Object { $_.Id -eq $o.id } | Select-Object -First 1
            if ($w -and $o.description) {
                $advice = if ($w.Protected) { $StartupAdvice[0] } elseif ($o.advice -in $StartupAdvice) { $o.advice } else { $StartupAdvice[2] }
                $w.Ai = "$($o.description.Trim().TrimEnd('.;')). $(L 'Rada' 'Advice'): $advice."; $n++
            }
        }
        Write-Line ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        Write-Log "Startup - model descriptions: $answer"
        $script:Conversation = $null
        $n
    }
    catch { Write-Log "Model error: $($_.Exception.Message)"; Write-Line ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}
