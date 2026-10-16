<#
    LLMCleaner - settings page: language, theme, AI model, assistant, updates, preview mode
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

$LanguageValues = @('auto', 'pl', 'en')
$ThemeValues = @('auto', 'light', 'dark')

function New-SettingsPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Ustawienia' 'Settings') (L 'Zmiany zaczną działać po ponownym uruchomieniu programu.' 'Changes take effect after the program restarts.')
    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 22 12 22 12) }
    $k.AutoScroll = $true

    $cboLanguage = New-SettingsList @((L 'Jak w Windows' 'Same as Windows'), 'Polski', 'English')
    $cboTheme = New-SettingsList @((L 'Jak w Windows' 'Same as Windows'), (L 'Jasny' 'Light'), (L 'Ciemny' 'Dark'))
    $cboModel = New-SettingsList @(Get-LocalModels) $true
    $chkAi = New-SettingsCheckBox (L 'Włączony' 'On')
    $chkUpdates = New-SettingsCheckBox (L 'Sprawdzaj przy starcie' 'Check at startup')
    $chkPreview = New-SettingsCheckBox (L 'Zawsze w trybie podglądu' 'Always in preview mode')
    $btnLogs = New-Button (L 'Otwórz folder logów' 'Open the log folder') 'outline' @{ Height = (Px 38) }
    $btnLogs.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })

    $rows = @(
        (New-SettingsRow (L 'Język' 'Language') (L 'Język okna i odpowiedzi asystenta AI.' 'The language of the window and of the AI assistant.') $cboLanguage)
        (New-SettingsRow (L 'Motyw' 'Theme') (L 'Jasny albo ciemny wygląd okna.' 'Light or dark look of the window.') $cboTheme)
        (New-SettingsRow (L 'Asystent AI' 'AI assistant') (L 'Lokalny model opisuje pozycje i odpowiada w czacie. Wyłączony nie zajmuje pamięci.' 'The local model describes items and answers in the chat. When off it uses no memory.') $chkAi)
        (New-SettingsRow (L 'Model AI' 'AI model') (L 'Model z folderu ai\models. Inny model pobierzesz instalatorem albo Install-AI.ps1.' 'A model from the ai\models folder. Get another one with the installer or Install-AI.ps1.') $cboModel)
        (New-SettingsRow (L 'Aktualizacje' 'Updates') (L 'Jedno zapytanie do GitHuba przy starcie, bez danych o komputerze.' 'One request to GitHub at startup, with no data about this computer.') $chkUpdates)
        (New-SettingsRow (L 'Tryb podglądu' 'Preview mode') (L 'Skan i plan bez możliwości usuwania - bezpieczne do pokazania komuś programu.' 'Scan and plan without deleting anything - safe for showing the program to someone.') $chkPreview)
        (New-SettingsRow (L 'Logi' 'Logs') ((L 'Dziennik każdego uruchomienia i kopie rejestru: {0}' 'The log of every run and registry backups: {0}') -f $LogDir) $btnLogs)
    )
    $el = @()
    foreach ($w in $rows) { $el += $w, (New-Control Panel @{ Dock = 'Top'; Height = (Px 1); BackColor = $s.Line }) }
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
