<#
    LLMCleaner - asystent AI: opisy pozostalosci i czat
#>

$AiLabel = L 'AI (może się mylić)' 'AI (may be wrong)'

$LeftoverSchema = @{
    type       = 'object'
    properties = @{
        explanations = @{ type = 'array'; items = @{ type = 'object'
                properties                               = @{ id = @{ type = 'string' }; description = @{ type = 'string' } }
                required                                 = @('id', 'description')
            }
        }
    }
    required   = @('explanations')
}

$PromptLeftovers = if ($Language -eq 'en') {
    @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of leftovers of uninstalled programs and games
(folders, files and registry keys). For EACH item write in the "opis" field what the program, game or vendor was.
Rules:
- Rely FIRST on the "zawiera" field (registry subkey names - usually names of games or programs) and on the name
  itself. Example: name "Studio X", zawiera ["Game Y"] -> "Studio X - the game Game Y".
- Do NOT add game or product titles that are not in the data unless you are absolutely sure.
  "game developer" is better than an invented title.
- If nothing is known, write exactly: "unknown program".
- Max. 12 words, in English. Do not judge whether to delete.
'@
}
else {
    @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę pozostałości po odinstalowanych programach i grach
(foldery, pliki i klucze rejestru). Dla KAŻDEJ pozycji napisz w polu "opis", czym był ten program, gra albo producent.
Zasady:
- Opieraj się PRZEDE WSZYSTKIM na polu "zawiera" (nazwy podkluczy rejestru - zwykle to nazwy gier lub programów)
  i na samej nazwie. Przykład: nazwa "Studio X", zawiera ["Gra Y"] -> "Studio X - gra Gra Y".
- NIE dopisuj tytułów gier ani produktów, których nie ma w danych, chyba że jesteś absolutnie pewien.
  Lepiej "producent gier" niż zmyślony tytuł.
- Jeśli nic nie wiadomo, napisz dokładnie: "nieznany program".
- Maks. 12 słów, po polsku. Nie oceniasz, czy usuwać.
'@
}

$PromptChat = if ($Language -eq 'en') {
    @'
You are LLMCleaner, a Windows cleanup assistant running locally.
Below is the scanner report and the current cleanup plan. Answer the user's questions about files, folders, programs,
games and the plan briefly and specifically, in English. You cannot delete or run anything - the user changes the plan.
If they want to remove something outside the plan, explain how to do it safely by hand (e.g. uninstalling a program
in Settings). Use only numbers from the report. If you do not know something, say so.
The report lists only the largest leftovers - "podsumowanie" says how many more there are and their total size.
'@
}
else {
    @'
Jesteś LLMCleaner - asystentem sprzątania systemu Windows działającym lokalnie.
Poniżej masz raport skanera i aktualny plan czyszczenia. Odpowiadaj krótko i konkretnie po polsku na pytania
użytkownika o pliki, foldery, programy, gry i plan. Nie możesz niczego usuwać ani uruchamiać - plan zmienia
użytkownik. Jeśli chce usunąć coś spoza planu, wyjaśnij, jak zrobić to bezpiecznie ręcznie
(np. odinstalowanie programu w Ustawieniach). Używaj tylko liczb z raportu. Jeśli czegoś nie wiesz, powiedz to wprost.
Raport zawiera tylko największe pozostałości - w „podsumowanie” jest, ile pozycji pominięto i ile razem zajmują.
'@
}

# Opisy pozostalosci przez model. Zwraca liczbe opisanych pozycji (albo -1 przy bledzie).
function Invoke-LeftoverAi {
    if (-not $script:Leftovers.Count) { Write-Line (L '   Brak pozostałości do wyjaśnienia.' '   No leftovers to explain.') 'DarkGray'; return 0 }
    if (-not (Initialize-Model)) { return -1 }
    $list = @($script:Leftovers | ForEach-Object { @{ id = $_.Id; type = $_.Type; name = $_.Name; path = $_.Path; contains = @($_.Subkeys) } })
    Write-Line ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $list.Count) 'DarkGray'
    try {
        # Po 30 pozycji naraz - cala lista po duzym skanie nie miesci sie w oknie kontekstu modelu
        $n = 0
        for ($i = 0; $i -lt $list.Count; $i += 30) {
            $chunk = @($list | Select-Object -Skip $i -First 30)
            $answer = Invoke-Ollama @(@{ role = 'system'; content = $PromptLeftovers },
                @{ role = 'user'; content = (ConvertTo-Json -InputObject $chunk -Depth 5 -Compress) }) $LeftoverSchema
            Write-Log "Wyjasnienia modelu: $answer"
            foreach ($w in @(($answer | ConvertFrom-Json -ErrorAction Stop).explanations)) {
                $p = $script:Leftovers | Where-Object { $_.Id -eq $w.id } | Select-Object -First 1
                if ($p -and $w.description) { $p.Ai = $w.description; $n++ }
            }
        }
        Write-Line ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        $n
    }
    catch { Write-Log "Blad modelu: $($_.Exception.Message)"; Write-Line ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}

# Rozmowa: $script:Rozmowa trzyma historie; Zapytaj zwraca odpowiedz albo $null
$script:Conversation = $null
function Start-Chat {
    $script:Conversation = [System.Collections.ArrayList]::new()
    # Czat dziala tez przed skanem - model wie wtedy, ze nie zna jeszcze plikow komputera
    $report = if ($script:ProfileScan) { Get-ChatReport } else {
        L 'Skan nie został jeszcze wykonany - nie znasz plików tego komputera. Odpowiadaj ogólnie, a przy pytaniach o konkretne pliki, foldery lub plan poproś użytkownika, żeby najpierw kliknął „Skanuj”.' 'No scan has been run yet - you do not know the files on this computer. Answer in general terms; for questions about specific files, folders or the plan, ask the user to click "Scan" first.'
    }
    [void]$script:Conversation.Add(@{ role = 'system'; content = "$PromptChat`n`n$(L 'RAPORT I PLAN' 'REPORT AND PLAN'):`n$report" })
}
# Do modelu idzie raport i tylko ostatnie wymiany - dluga rozmowa tez nie moze przepelnic okna kontekstu
$ChatTurns = 6
function Send-ChatQuestion([string]$question) {
    if (-not (Initialize-Model)) { return $null }
    if (-not $script:Conversation) { Start-Chat; Write-Log "Czat: raport dla modelu $($script:Conversation[0].content.Length) znakow" }
    [void]$script:Conversation.Add(@{ role = 'user'; content = $question })
    $messages = @($script:Conversation[0]) + @($script:Conversation | Select-Object -Skip 1 | Select-Object -Last (2 * $ChatTurns + 1))
    try {
        $a = Invoke-Ollama $messages
        if (-not "$a".Trim()) { throw (L 'model zwrócił pustą odpowiedź' 'the model returned an empty answer') }
        [void]$script:Conversation.Add(@{ role = 'assistant'; content = $a })
        $a
    }
    catch {
        [void]$script:Conversation.RemoveAt($script:Conversation.Count - 1)
        Write-Log "Czat - blad modelu: $($_.Exception.Message)"
        Write-Line ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'
        $null
    }
}
