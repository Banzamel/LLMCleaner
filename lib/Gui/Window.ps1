<#
    LLMCleaner - main window and events (Windows Forms, built into Windows). The logic is in lib\Core.
    Layout per the 1.5 mockups: dark navigation bar on the left, pages with cards (lib\Gui\Pages), owner-drawn
    lists (two text lines, type badges, size bars, toggles), cleanup progress screen.
    The window knows the screen scaling (DPI) - all pixel sizes go through Px - and the Windows theme
    (light or dark). Size, position and last page are remembered in window.json.
    Long AI operations run in a separate thread (Invoke-Background), scan and cleanup refresh the window (DoEvents).
#>

function Show-MainWindow {
    $script:Mode = 'window'
    # The PowerShell console is not needed when there is a window
    if (-not $script:TestAfterStart) { [void][LlmWin.Native]::ShowWindow([LlmWin.Native]::GetConsoleWindow(), 0) }
    # The scale is computed when this file loads (before fonts); GDI+ should see the same DPI
    $gr = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:DpiGdiPlus = $gr.DpiX
    $gr.Dispose()

    [Windows.Forms.Application]::EnableVisualStyles()
    $s = $script:Style
    $script:UI.Hint = New-Object Windows.Forms.ToolTip
    $script:UI.Hint.AutoPopDelay = 15000
    $script:UI.Scrollables = @()
    # Minimum size no larger than the screen (e.g. 175% on a 1920x1080 screen)
    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $min = New-Object Drawing.Size([Math]::Min((Px 1080), $area.Width), [Math]::Min((Px 680), $area.Height))
    $f = New-Control Form @{ Text = "LLMCleaner $Version"; MinimumSize = $min; AutoScaleMode = 'None'; Font = $s.Body; BackColor = $s.Background; KeyPreview = $true }
    Restore-WindowBounds $f
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) { $f.Icon = New-Object Drawing.Icon $ico }
    $script:UI.Window = $f
    $f.SuspendLayout()

    # Pages (all Fill, one visible) and the status bar below them
    $content = New-Control Panel @{ Dock = 'Fill'; BackColor = $s.Background }
    $script:UI.Pages = [ordered]@{ overview = (New-OverviewPage); plan = (New-PlanPage); analysis = (New-AnalysisPage); startup = (New-StartupPage)
        drivers = (New-DriversPage); chat = (New-ChatPage); log = (New-LogPage); settings = (New-SettingsPage); cleanup = (New-CleanupPage)
    }
    $state = New-Control Panel @{ Dock = 'Bottom'; Height = (Px 30); BackColor = $s.Background; Padding = (New-Padding 32 0 32 10) }
    $st = New-Label (L 'Gotowy. Wybierz dyski i kliknij „Skanuj” (F5).' 'Ready. Pick the drives and click "Scan" (F5).') @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small; AutoEllipsis = $true; TextAlign = 'MiddleLeft' }
    $pb = New-Control ProgressBar @{ Dock = 'Right'; Width = (Px 160); Style = 'Marquee'; MarqueeAnimationSpeed = 30; Visible = $false }
    Add-Docked $state @($pb, $st)
    Add-Docked $content (@($state) + @($script:UI.Pages.Values))
    Add-Docked $f @((New-NavigationBar), $content)
    $script:UI.Status = $st; $script:UI.Progress = $pb
    $f.ResumeLayout()
    $u = $script:UI
    $script:UI.ActionButtons = @($u.BtnScan, $u.BtnStart, $u.BtnToPlan, $u.BtnCleanNow, $u.BtnClean, $u.BtnExplain, $u.BtnRecommended, $u.BtnClearSelection,
        $u.BtnAnalyse, $u.BtnAnalysisAi, $u.BtnSend, $u.BtnUpdate, $u.BtnStartupRefresh, $u.BtnStartupAi, $u.BtnResultScan,
        $u.BtnDriverCheck, $u.BtnDriverInstall, $u.BtnSettingsSave, $u.BtnSettingsRestart)

    # ---------- EVENTS ----------
    $u.BtnScan.Add_Click({ Invoke-UiAction {
                Set-SelectedDrives @($script:UI.DriveList.Tag.Rows | Where-Object { $_.Obj.Ticked } | ForEach-Object { $_.Obj.Id })
                Show-Page 'overview'
                $script:UI.Log.Clear()
                $script:UI.Stats.Visible = $false
                $script:UI.BtnStart.Visible = $script:UI.BtnToPlan.Visible = $script:UI.BtnCleanNow.Visible = $false
                $script:UI.ResultSmall.Text = L 'Trwa skan - niczego nie usuwa' 'Scanning - nothing is deleted'
                $script:UI.Result.Text = L 'Skanowanie...' 'Scanning...'
                $script:UI.Result.ForeColor = $script:Style.Text
                $script:UI.Scanning = $true
                Set-TaskbarProgress 1
                $ok = $false
                try {
                    Write-WindowLog ((L '1/2  Skanowanie dysków: {0}' '1/2  Scanning drives: {0}') -f ($script:SelectedDrives -join ', ')) 'Cyan'
                    Invoke-FullScan
                    $ok = $true
                }
                finally {
                    $script:UI.Scanning = $false
                    Set-TaskbarProgress 0
                    if (-not $ok) {
                        $script:UI.Result.Text = L 'Skan nie powiódł się' 'The scan failed'
                        $script:UI.Result.ForeColor = $script:Style.Red
                        $script:UI.Stage.Text = L 'Szczegóły są w Dzienniku.' 'See the Log for details.'
                    }
                }
                $script:Scanned = $true
                $script:Cleaned = $false
                $script:CleanupResult = $null
                $script:Conversation = $null
                $script:UI.OverviewDesc.Text = (L 'Ostatni skan: dziś, {0} · dyski {1} · nic nie zostało jeszcze usunięte' 'Last scan: today, {0} · drives {1} · nothing has been deleted yet') -f (Get-Date -Format 'HH:mm'), ($script:SelectedDrives -join ', ')
                # Startup entries for the overview tile (a few seconds, read-only)
                if ($null -eq $script:Startup) {
                    Set-WindowStatus (L 'Wczytuję programy uruchamiane przy logowaniu...' 'Reading the programs that start at sign-in...')
                    try { [void](Get-StartupEntries); Update-StartupPage } catch { Add-ScanError 'startup' $_ }
                }
                Update-PlanPage
                $script:UI.CboDrive.Items.Clear()
                foreach ($d in Get-SelectedDrives) { [void]$script:UI.CboDrive.Items.Add((Format-Drive $d)) }
                $script:UI.CboDrive.SelectedIndex = 0
                Set-WindowStatus ((L 'Skan zakończony. Sprawdź plan i kliknij „Wyczyść zaznaczone...”.' 'Scan finished. Review the plan and click "Clean selected...".'))
            } })

    $u.BtnStart.Add_Click({ $script:UI.BtnScan.PerformClick() })
    $u.BtnToPlan.Add_Click({ Show-Page 'plan' })
    $u.BtnCleanNow.Add_Click({ $script:UI.BtnClean.PerformClick() })
    $u.BtnRecommended.Add_Click({ Build-Plan; Update-PlanPage })
    $u.BtnClearSelection.Add_Click({ foreach ($x in @($script:Categories) + @($script:Leftovers)) { if ($x) { $x.Selected = $false } }; Update-PlanPage })

    $u.BtnExplain.Add_Click({ Invoke-UiAction {
                Set-WindowStatus (L 'Model opisuje pozostałości (ok. 20-40 s)...' 'The model is describing the leftovers (about 20-40 s)...')
                $n = Invoke-LeftoverAi
                Update-PlanPage
                Set-WindowStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji (druga linia, dopisek AI).' '{0} items described (second line, AI note).') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
            } })

    $u.BtnClean.Add_Click({
            $lines = Get-Summary
            if (-not $lines) { Show-Message (L 'Nic nie jest zaznaczone - nie ma czego czyścić.' 'Nothing is selected - there is nothing to clean.'); return }
            $text = (($lines | ForEach-Object { $_.T -replace '\s{2,}', '  ' }) -join "`r`n") + "`r`n`r`n" + (L 'Uruchomić czyszczenie?' 'Start cleaning?')
            $answer = [Windows.Forms.MessageBox]::Show($script:UI.Window, $text, (L 'LLMCleaner - podsumowanie przed czyszczeniem' 'LLMCleaner - summary before cleaning'), 'YesNo', 'Warning', 'Button2')
            if ($answer -ne 'Yes') { return }
            Invoke-UiAction { Start-WindowCleanup }
        })

    $u.BtnAnalyse.Add_Click({ Invoke-UiAction {
                $i = $script:UI.CboDrive.SelectedIndex
                if ($i -lt 0) { return }
                $l = @(Get-SelectedDrives)[$i].DeviceID.TrimEnd(':')
                $a = Get-DriveAnalysis $l
                Update-AnalysisPage $a
                Set-WindowStatus ((L 'Analiza dysku {0}: gotowa.' 'Drive {0}: analysis ready.') -f $l)
            } })

    $u.BtnAnalysisAi.Add_Click({ Invoke-UiAction {
                $a = $script:UI.AnalysisData
                if (-not $a) { return }
                Set-WindowStatus (L 'Model opisuje pozycje (ok. 20-40 s)...' 'The model is describing the items (about 20-40 s)...')
                $n = Invoke-AnalysisAi $a
                Update-AnalysisPage $a
                Set-WindowStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji.' '{0} items described.') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
            } })

    $u.BtnSend.Add_Click({
            $q = $script:UI.Question.Text.Trim()
            if (-not $q) { return }
            $script:UI.Question.Clear()
            Add-ChatMessage (L 'Ty' 'You') $q $script:Style.Accent
            Invoke-UiAction {
                Set-WindowStatus (L 'Asystent myśli...' 'The assistant is thinking...')
                $a = Send-ChatQuestion $q
                if ($a) { Add-ChatMessage 'LLMCleaner' $a $script:Style.Ai; Set-WindowStatus '' }
                else { Add-ChatMessage 'LLMCleaner' (L '(brak odpowiedzi - szczegóły w Dzienniku)' '(no answer - see the Log)') $script:Style.TextDim }
            }
            $script:UI.Question.Focus()
        })

    $u.BtnStartupRefresh.Add_Click({ Invoke-UiAction {
                Set-WindowStatus (L 'Wczytuję programy uruchamiane przy logowaniu...' 'Reading the programs that start at sign-in...')
                [void](Get-StartupEntries)
                Update-StartupPage
                Set-WindowStatus (L 'Autostart wczytany. Przełącznik po prawej włącza i wyłącza program.' 'Startup apps loaded. The switch on the right turns a program on or off.')
            } })
    $u.BtnStartupAi.Add_Click({ Invoke-UiAction {
                Set-WindowStatus (L 'Model opisuje programy (ok. 20-40 s)...' 'The model is describing the programs (about 20-40 s)...')
                $n = Invoke-StartupAi $script:Startup
                Update-StartupPage
                Set-WindowStatus $(if ($n -ge 0) { (L 'Opisano {0} pozycji.' '{0} items described.') -f $n } else { L 'Asystent niedostępny - szczegóły w Dzienniku.' 'The assistant is unavailable - see the Log.' })
            } })

    $u.BtnDriverCheck.Add_Click({ Invoke-UiAction {
                Set-WindowStatus (L 'Szukam nowszych sterowników w Windows Update (zwykle 1-3 minuty)...' 'Looking for newer drivers on Windows Update (usually 1-3 minutes)...')
                $lv = $script:UI.LvDrivers
                $lv.Tag.EmptyText = L 'Szukam w Windows Update... Trwa to zwykle 1-3 minuty.' 'Searching Windows Update... It usually takes 1-3 minutes.'
                Set-Rows $lv @()
                Set-TaskbarProgress 1
                try { $n = Find-DriverUpdates }
                catch {
                    Write-Log "Drivers - search error: $($_.Exception.Message)"
                    $lv.Tag.EmptyText = (L 'Nie udało się sprawdzić Windows Update: {0}. Sprawdź połączenie z internetem i czy usługa Windows Update działa.' 'Could not check Windows Update: {0}. Check the internet connection and that the Windows Update service is running.') -f $_.Exception.Message.Trim()
                    $lv.Invalidate()
                    Set-WindowStatus (L 'Sprawdzanie sterowników nie powiodło się.' 'Checking for drivers failed.')
                    return
                }
                finally { Set-TaskbarProgress 0 }
                Update-DriversPage
                Write-WindowLog ((L '  Sterowniki: nowszych {0}, urządzeń z problemem {1}' '  Drivers: {0} newer, {1} devices with a problem') -f $n, @($script:ProblemDevices).Count) 'Cyan'
                Set-WindowStatus $(if ($n) { (L 'Znaleziono nowszych sterowników: {0}. Sprawdź listę i kliknij „Zainstaluj zaznaczone...”.' 'Newer drivers found: {0}. Review the list and click "Install selected...".') -f $n }
                    else { L 'Windows Update nie ma nowszych sterowników dla tego komputera.' 'Windows Update has no newer drivers for this PC.' })
            } })
    $u.BtnDriverInstall.Add_Click({
            $chosen = @($script:Drivers | Where-Object { $_ -and $_.Selected -and $_.State -in 'new', 'fail' })
            if (-not $chosen.Count) { return }
            $list = ($chosen | ForEach-Object { "  - $($_.Name)  $($_.Version)" }) -join "`r`n"
            $text = (L "Zainstalować sterowniki z Windows Update:`r`n`r`n{0}`r`n`r`nNajpierw powstanie punkt przywracania systemu. Przy sterowniku karty graficznej ekran może na chwilę zgasnąć. Nie wyłączaj komputera w trakcie instalacji." "Install drivers from Windows Update:`r`n`r`n{0}`r`n`r`nA System Restore point is created first. With a graphics driver the screen may go blank for a moment. Do not turn off the computer while installing.") -f $list
            $answer = [Windows.Forms.MessageBox]::Show($script:UI.Window, $text, (L 'LLMCleaner - instalacja sterowników' 'LLMCleaner - install drivers'), 'YesNo', 'Question', 'Button2')
            if ($answer -ne 'Yes') { return }
            Invoke-UiAction { Install-DriversFromWindow $chosen }
        })

    $u.BtnUpdate.Add_Click({ Invoke-UiAction {
                if (Install-AppUpdate) { $script:UI.Window.Close() }
            } })

    # Shortcuts: F5 scans, Ctrl+1..7 switches pages
    $f.Add_KeyDown({
            if ($script:Cleaning) { return }
            if ($_.KeyCode -eq 'F5') {
                $_.Handled = $true
                if ($script:UI.BtnScan.Enabled) { $script:UI.BtnScan.PerformClick() }
            }
            elseif ($_.Control -and $_.KeyValue -ge 49 -and $_.KeyValue -lt 49 + $script:UI.Nav.Count) {
                $_.Handled = $true; $_.SuppressKeyPress = $true
                Show-Page @($script:UI.Nav.Keys)[$_.KeyValue - 49]
            }
        })

    $f.Add_HandleCreated({ Set-DarkTitleBar })
    $f.Add_Shown({
            Set-DarkScrollbars
            $page = "$($script:WindowPrefs.Page)"
            Show-Page $(if ($page -in 'analysis', 'startup', 'drivers', 'chat', 'log', 'settings') { $page } else { 'overview' })
            Update-PlanPage
            Update-DriversPage
            Update-Buttons
            Update-StartupCard
            $c = $script:UI.Chat
            $c.AppendText($c.Tag)
            $c.SelectAll(); $c.SelectionColor = $script:Style.TextDim; $c.Select($c.TextLength, 0)
            # Placeholder hints in empty fields (EM_SETCUEBANNER)
            [void][LlmWin.Native]::SendMessage($script:UI.Question.Handle, 0x1501, [IntPtr]1, (L 'Napisz pytanie i naciśnij Enter...' 'Type a question and press Enter...'))
            [void][LlmWin.Native]::SendMessage($script:UI.Search.Handle, 0x1501, [IntPtr]1, (L 'Szukaj, np. Steam, cache, rejestr' 'Search, e.g. Steam, cache, registry'))
            if (-not $NoUpdateCheck) {
                Set-WindowStatus (L 'Sprawdzam aktualizacje...' 'Checking for updates...')
                Find-AppUpdate
                if ($script:AppUpdate) {
                    $script:UI.BtnUpdate.Text = (L 'Zainstaluj wersję {0}' 'Install version {0}') -f $script:AppUpdate.Version
                    $script:UI.BtnUpdate.Visible = $true
                }
                Set-WindowStatus (L 'Gotowy. Wybierz dyski i kliknij „Skanuj” (F5).' 'Ready. Pick the drives and click "Scan" (F5).')
            }
            # Tests only: set by the test script in the same process (never from environment variables)
            if ($script:TestAfterStart) { & $script:TestAfterStart }
        })
    # The window does not close during cleanup (Windows Update services, Explorer, half-deleted files)
    $f.Add_FormClosing({
            if ($script:InstallingDrivers) {
                $_.Cancel = $true
                Show-Message (L 'Poczekaj na koniec instalacji sterowników.' 'Wait for the driver installation to finish.') 'Warning'
                return
            }
            if ($script:Cleaning) {
                $_.Cancel = $true
                Show-Message (L 'Poczekaj na koniec czyszczenia - przerwanie w połowie zostawiłoby wstrzymane usługi albo wyłączony Eksplorator.' 'Wait for the cleaning to finish - stopping halfway could leave services paused or File Explorer closed.') 'Warning'
                return
            }
            Save-WindowState
        })
    $f.Add_FormClosed({ Stop-Ollama; Write-Log 'End (window).' })

    Write-Log "Start (window). Model: $Model, Preview: $Preview, NoAI: $NoAI, Language: $Language, Scale: $($script:Scale) (GDI+ $($script:DpiGdiPlus) dpi), Dark: $($script:Dark)"
    [void]$f.ShowDialog()
    # "Save and restart" on the settings page - the new window starts after window.json is saved
    if ($script:Restart) { Restart-App }
}
