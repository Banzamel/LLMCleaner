<#
    LLMCleaner - strona Czat z asystentem
#>

function Add-ChatMessage([string]$who, [string]$text, $color) {
    $box = $script:UI.Chat
    $box.SelectionStart = $box.TextLength
    $box.SelectionFont = $script:Style.Bold
    $box.SelectionColor = $color
    $box.AppendText("$who`r`n")
    $box.SelectionFont = $box.Font
    $box.SelectionColor = $script:Style.Text
    $box.AppendText("$text`r`n`r`n")
    $box.ScrollToCaret()
}

function New-ChatPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Asystent AI' 'AI assistant') $(if ($NoAI) { L 'Asystent jest wyłączony (uruchomiono z -BezLLM).' 'The assistant is disabled (started with -BezLLM).' }
        else { (L 'Lokalny model {0} - działa na tym komputerze, nic nie wysyła do internetu i niczego nie usuwa.' 'Local model {0} - runs on this computer, sends nothing to the internet and never deletes anything.') -f $Model })

    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 20 16 6 10) }
    $chat = New-Control RichTextBox @{ Dock = 'Fill'; ReadOnly = $true; BorderStyle = 'None'; BackColor = $s.Card; ForeColor = $s.Text; Font = $s.Input }
    # Tekst powitalny wpisuje Shown - RichTextBox gubi kolory ustawione przed utworzeniem okna
    $chat.Tag = $(if ($NoAI) { '' }
        else { L "Zapytaj o plan, foldery, programy albo gry. Asystent zna wyniki skanu, analizy dysku i listę autostartu.`r`nPrzed skanem odpowiada tylko ogólnie - żeby pytać o pliki tego komputera, najpierw kliknij `„Skanuj`”.`r`nPierwsze pytanie uruchamia model (ok. 10-20 s).`r`n`r`n" "Ask about the plan, folders, programs or games. The assistant knows the scan results, the disk analysis and the startup list.`r`nBefore a scan it only answers in general terms - to ask about the files on this computer, click ""Scan"" first.`r`nThe first question starts the model (about 10-20 s).`r`n`r`n" })
    $k.Controls.Add($chat)
    $script:UI.Chat = $chat
    $script:UI.Scrollables += $chat

    # Pole pytania: karta z polem bez ramki i przyciskiem
    $bottom = New-Card @{ Dock = 'Bottom'; Height = (Px 62); Padding = (New-Padding 20 10 10 10) }
    $btnSend = New-Button (L 'Wyślij' 'Send') 'primary' @{ Dock = 'Right'; Width = (Px 120) }
    $field = New-Control Panel @{ Dock = 'Fill'; Padding = (New-Padding 0 10 12 0) }
    $questionBox = New-Control TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Card; ForeColor = $s.Text; Font = $s.Input }
    $field.Controls.Add($questionBox)
    Add-Docked $bottom @($btnSend, $field)
    $questionBox.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; if ($script:UI.BtnSend.Enabled) { $script:UI.BtnSend.PerformClick() } } })
    $script:UI.Question = $questionBox; $script:UI.BtnSend = $btnSend

    Add-Docked $page @($n.Panel, $bottom, (New-Spacer 'Bottom' 14), $k)
    $page
}
