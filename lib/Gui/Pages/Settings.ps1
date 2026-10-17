<#
    LLMCleaner - settings page: language, theme, AI model, assistant, updates, preview mode,
    what the scan covers, excluded folders and logs
    Saved to settings.json (lib\Core\Config.ps1). Changes take effect after a restart.
#>

# Settings row: description on the left, control on the right
function New-SettingsRow([string]$title, [string]$desc, $control) {
    $s = $script:Style
    $w = New-Control Panel @{ Dock = 'Top'; Height = (Px 62); Padding = (New-Padding 0 6 0 6) }
    $leftPart = New-Control Panel @{ Dock = 'Fill' }
    $t = New-Label $title @{ Dock = 'Top'; Height = (Px 24); Font = $s.Bold }
    $o = New-Label $desc @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small; AutoEllipsis = $true }
    Add-Docked $leftPart @($t, $o)
    $rightPart = New-Control Panel @{ Dock = 'Right'; Width = (Px 300); Padding = (New-Padding 0 10 0 0) }
    $control.Dock = 'Top'
    $rightPart.Controls.Add($control)
    Add-Docked $w @($rightPart, $leftPart)
    $w
}

function New-SettingsList([string[]]$items, [bool]$editable = $false) {
    $s = $script:Style
    $c = New-Control ComboBox @{ DropDownStyle = $(if ($editable) { 'DropDown' } else { 'DropDownList' }); Font = $s.Body; FlatStyle = 'Flat'; BackColor = $s.Tile; ForeColor = $s.Text }
    foreach ($p in $items) { [void]$c.Items.Add($p) }
    $c
}

function New-SettingsCheckBox([string]$text) {
    $s = $script:Style
    New-Control CheckBox @{ Text = $text; Height = (Px 30); Font = $s.Body; ForeColor = $s.Text; BackColor = $s.Card; FlatStyle = 'Flat'; UseMnemonic = $false }
}

# Section title between groups of rows
function New-SettingsHeading([string]$text) {
    $s = $script:Style
    New-Label $text @{ Dock = 'Top'; Height = (Px 44); Font = $s.CardTitle; ForeColor = $s.Text; TextAlign = 'BottomLeft'; Padding = (New-Padding 0 0 0 6) }
}

# Wrapping grid of checkboxes; each box carries its id in Tag
function New-SettingsChecks([object[]]$items) {
    $f = New-Control FlowLayoutPanel @{ Dock = 'Top'; AutoSize = $true; AutoSizeMode = 'GrowAndShrink'; WrapContents = $true; Padding = (New-Padding 0 4 0 10) }
    foreach ($x in $items) {
        $c = New-SettingsCheckBox $x.Name
        $c.Width = (Px 330); $c.AutoEllipsis = $true; $c.Tag = $x.Id
        $f.Controls.Add($c)
    }
    $f
}

# Excluded folders: one path per line, plus a folder picker
function New-ExcludedFoldersBox {
    $s = $script:Style
    $w = New-Control Panel @{ Dock = 'Top'; Height = (Px 150); Padding = (New-Padding 0 4 0 12) }
    $t = New-Label (L 'Pomijane foldery' 'Excluded folders') @{ Dock = 'Top'; Height = (Px 24); Font = $s.Bold }
    $o = New-Label (L 'Jedna ścieżka w wierszu. Program ich nie mierzy, nie pokazuje w planie i nigdy nie usuwa - także gdy leżą w folderze z cache.' 'One path per line. The program does not measure them, does not list them in the plan and never deletes them - also when they lie inside a cache folder.') @{ Dock = 'Top'; Height = (Px 22); ForeColor = $s.TextDim; Font = $s.Small; AutoEllipsis = $true }
    $box = New-Control TextBox @{ Dock = 'Fill'; Multiline = $true; ScrollBars = 'Vertical'; WordWrap = $false; Font = $s.Body; BackColor = $s.Tile; ForeColor = $s.Text; BorderStyle = 'FixedSingle' }
    $right = New-Control Panel @{ Dock = 'Right'; Width = (Px 170); Padding = (New-Padding 10 0 0 0) }
    $btn = New-Button (L 'Dodaj folder...' 'Add a folder...') 'outline' @{ Dock = 'Top'; Height = (Px 38) }
    $btn.Add_Click({
            $d = New-Object Windows.Forms.FolderBrowserDialog
            $d.Description = L 'Folder, który program ma pomijać' 'A folder the program should skip'
            if ($d.ShowDialog() -eq 'OK') {
                $b = $script:UI.SetExcluded
                $b.Text = (@($b.Lines | Where-Object { $_.Trim() }) + $d.SelectedPath) -join "`r`n"
            }
        })
    $right.Controls.Add($btn)
    $middle = New-Control Panel @{ Dock = 'Fill' }
    Add-Docked $middle @($right, $box)
    Add-Docked $w @($t, $o, $middle)
    $script:UI.SetExcluded = $box
    $w
}

$LanguageValues = @('auto', 'pl', 'en', 'es')
$ThemeValues = @('auto', 'light', 'dark')

function New-SettingsPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Ustawienia' 'Settings') (L 'Zmiany zaczną działać po ponownym uruchomieniu programu.' 'Changes take effect after the program restarts.')
    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 22 12 22 12) }
    $k.AutoScroll = $true

    $cboLanguage = New-SettingsList @((L 'Jak w Windows' 'Same as Windows'), 'Polski', 'English', 'Español')
    $cboTheme = New-SettingsList @((L 'Jak w Windows' 'Same as Windows'), (L 'Jasny' 'Light'), (L 'Ciemny' 'Dark'))
    $cboModel = New-SettingsList @(Get-LocalModels) $true
    $chkAi = New-SettingsCheckBox (L 'Włączony' 'On')
    $chkUpdates = New-SettingsCheckBox (L 'Sprawdzaj przy starcie' 'Check at startup')
    $chkPreview = New-SettingsCheckBox (L 'Zawsze w trybie podglądu' 'Always in preview mode')
    $chkOldLogs = New-SettingsCheckBox (L 'Usuwaj starsze niż 30 dni' 'Delete ones older than 30 days')
    $logButtons = New-Control Panel @{ Height = (Px 38) }
    $btnLogs = New-Button (L 'Otwórz folder' 'Open the folder') 'outline' @{ Dock = 'Left'; Width = (Px 145) }
    $btnLogs.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })
    $btnClearLogs = New-Button (L 'Wyczyść logi' 'Clear the logs') 'outline' @{ Dock = 'Right'; Width = (Px 145) }
    $btnClearLogs.Add_Click({
            $n = Remove-OldLogs 0
            Write-Log "Deleted $n logs from Settings."
            $script:UI.SetInfo.Text = (L 'Usunięto logi: {0}. Dziennik bieżącego uruchomienia i kopie rejestru zostały.' 'Logs deleted: {0}. The log of this run and the registry backups were kept.') -f $n
        })
    Add-Docked $logButtons @($btnLogs, $btnClearLogs)

    $scanItems = @(New-Categories | ForEach-Object { @{ Id = $_.Id; Name = $_.Name } })
    $scanItems += @{ Id = '#leftovers'; Name = (L 'Pozostałości po odinstalowanych programach i grach' 'Leftovers of uninstalled programs and games') }
    $scanItems += @{ Id = '#large'; Name = (L 'Duże pliki w profilu i w Pobranych' 'Large files in the profile and in Downloads') }
    $scanChecks = New-SettingsChecks $scanItems

    $rows = @(
        (New-SettingsRow (L 'Język' 'Language') (L 'Język okna i odpowiedzi asystenta AI.' 'The language of the window and of the AI assistant.') $cboLanguage)
        (New-SettingsRow (L 'Motyw' 'Theme') (L 'Jasny albo ciemny wygląd okna.' 'Light or dark look of the window.') $cboTheme)
        (New-SettingsRow (L 'Asystent AI' 'AI assistant') (L 'Lokalny model opisuje pozycje i odpowiada w czacie. Wyłączony nie zajmuje pamięci.' 'The local model describes items and answers in the chat. When off it uses no memory.') $chkAi)
        (New-SettingsRow (L 'Model AI' 'AI model') (L 'Model z folderu ai\models. Inny model pobierzesz instalatorem albo Install-AI.ps1.' 'A model from the ai\models folder. Get another one with the installer or Install-AI.ps1.') $cboModel)
        (New-SettingsRow (L 'Aktualizacje' 'Updates') (L 'Jedno zapytanie do GitHuba przy starcie, bez danych o komputerze.' 'One request to GitHub at startup, with no data about this computer.') $chkUpdates)
        (New-SettingsRow (L 'Tryb podglądu' 'Preview mode') (L 'Skan i plan bez możliwości usuwania - bezpieczne do pokazania komuś programu.' 'Scan and plan without deleting anything - safe for showing the program to someone.') $chkPreview)
        (New-SettingsRow (L 'Logi' 'Logs') ((L 'Dziennik każdego uruchomienia i kopie rejestru: {0}' 'The log of every run and registry backups: {0}') -f $LogDir) $logButtons)
        (New-SettingsRow (L 'Stare logi' 'Old logs') (L 'Przy starcie usuwa dzienniki starsze niż 30 dni. Kopie rejestru zostają.' 'At startup deletes logs older than 30 days. Registry backups are kept.') $chkOldLogs)
    )
    $el = @()
    foreach ($w in $rows) { $el += $w, (New-Control Panel @{ Dock = 'Top'; Height = (Px 1); BackColor = $s.Line }) }
    $el += New-SettingsHeading (L 'Co skanować' 'What to scan')
    $el += New-Label (L 'Odznaczone pozycje są pomijane przy skanie i nie trafiają do planu.' 'Unticked items are skipped by the scan and never reach the plan.') @{ Dock = 'Top'; Height = (Px 22); ForeColor = $s.TextDim; Font = $s.Small }
    $el += $scanChecks
    $el += New-ExcludedFoldersBox
    Add-Docked $k $el

    $bottom = New-Control Panel @{ Dock = 'Bottom'; Height = (Px 50); Padding = (New-Padding 0 10 0 0) }
    $btnSave = New-Button (L 'Zapisz' 'Save') 'secondary' @{ Dock = 'Right' }
    $btnRestart = New-Button (L 'Zapisz i uruchom ponownie' 'Save and restart') 'primary' @{ Dock = 'Right' }
    $info = New-Label '' @{ Dock = 'Fill'; ForeColor = $s.TextDim; TextAlign = 'MiddleLeft'; AutoEllipsis = $true }
    Add-Docked $bottom @($btnRestart, (New-Spacer 'Right' 10), $btnSave, $info)
    $btnSave.Add_Click({ Save-SettingsPage; $script:UI.SetInfo.Text = L 'Zapisano. Zmiany zaczną działać po ponownym uruchomieniu.' 'Saved. Changes take effect after a restart.' })
    $btnRestart.Add_Click({ Save-SettingsPage; $script:Restart = $true; $script:UI.Window.Close() })

    $script:UI.SetLanguage = $cboLanguage; $script:UI.SetTheme = $cboTheme; $script:UI.SetModel = $cboModel
    $script:UI.SetAi = $chkAi; $script:UI.SetUpdates = $chkUpdates; $script:UI.SetPreview = $chkPreview
    $script:UI.SetOldLogs = $chkOldLogs; $script:UI.SetScan = $scanChecks
    $script:UI.BtnSettingsSave = $btnSave; $script:UI.BtnSettingsRestart = $btnRestart; $script:UI.SetInfo = $info
    Update-SettingsPage

    Add-Docked $page @($n.Panel, $bottom, (New-Spacer 'Bottom' 10), $k)
    $page
}

# Controls show the saved settings (not this run's parameters, e.g. -Preview from a shortcut)
function Update-SettingsPage {
    $u = $script:UI; $k = $Config
    $u.SetLanguage.SelectedIndex = [Math]::Max(0, [array]::IndexOf($LanguageValues, "$($k.Language)"))
    $m = if ($k.Theme) { "$($k.Theme)" } elseif ($script:WindowPrefs.Theme) { "$($script:WindowPrefs.Theme)" } else { 'auto' }
    $u.SetTheme.SelectedIndex = [Math]::Max(0, [array]::IndexOf($ThemeValues, $m))
    $u.SetModel.Text = $(if ($k.Model) { "$($k.Model)" } else { $Model })
    $u.SetAi.Checked = $k.Assistant -ne $false
    $u.SetUpdates.Checked = $k.CheckUpdates -ne $false
    $u.SetPreview.Checked = $k.Preview -eq $true
    $u.SetOldLogs.Checked = [int]$k.LogDays -gt 0
    foreach ($c in $u.SetScan.Controls) {
        $c.Checked = switch ($c.Tag) { '#leftovers' { $k.ScanLeftovers -ne $false } '#large' { $k.ScanLargeFiles -ne $false } default { $c.Tag -notin @($k.SkipCategories) } }
    }
    $u.SetExcluded.Text = @($k.ExcludedFolders) -join "`r`n"
}

function Save-SettingsPage {
    $u = $script:UI
    $Config.Language = $LanguageValues[[Math]::Max(0, $u.SetLanguage.SelectedIndex)]
    $Config.Theme = $ThemeValues[[Math]::Max(0, $u.SetTheme.SelectedIndex)]
    # The installer's model is not written to the file - a later install with another model still works
    $m = $u.SetModel.Text.Trim()
    $Config.Model = $(if ($m -eq (Get-InstallerModel)) { '' } else { $m })
    $Config.Assistant = $u.SetAi.Checked
    $Config.CheckUpdates = $u.SetUpdates.Checked
    $Config.Preview = $u.SetPreview.Checked
    $Config.LogDays = $(if (-not $u.SetOldLogs.Checked) { 0 } elseif ([int]$Config.LogDays -gt 0) { [int]$Config.LogDays } else { 30 })
    $skip = @()
    foreach ($c in $u.SetScan.Controls) {
        switch ($c.Tag) { '#leftovers' { $Config.ScanLeftovers = $c.Checked } '#large' { $Config.ScanLargeFiles = $c.Checked } default { if (-not $c.Checked) { $skip += $c.Tag } } }
    }
    # Categories that do not exist on this computer (e.g. Docker) keep their saved choice
    $here = @($u.SetScan.Controls | ForEach-Object { $_.Tag })
    $Config.SkipCategories = @(@($Config.SkipCategories | Where-Object { $_ -notin $here }) + $skip)
    $Config.ExcludedFolders = @($u.SetExcluded.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    try { Save-Config $Config; Write-Log "Settings saved: $(ConvertTo-Json -InputObject $Config -Compress)" }
    catch { Write-Log "Saving settings: $($_.Exception.Message)"; Show-Message ((L 'Nie udało się zapisać ustawień: {0}' 'Could not save the settings: {0}') -f $_.Exception.Message) 'Error' }
}

# The new process already has admin rights (inherited), so UAC does not ask again
function Restart-App {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $AppDir 'LLMCleaner.ps1')`"", '-Sid', $UserSid)
    if ($PreviewFromParam) { $argList += '-Preview' }
    try { Start-Process powershell.exe -ArgumentList $argList; Write-Log 'Restarting after settings change.' }
    catch { Write-Log "Restart: $($_.Exception.Message)" }
}
