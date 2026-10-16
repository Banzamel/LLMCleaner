<#
    LLMCleaner - window state: busy state, buttons, actions, page switching
#>

# Disables buttons while working and shows the progress bar
function Set-Busy([bool]$z) {
    $script:Working = $z
    foreach ($b in $script:UI.ActionButtons) { if ($b) { $b.Enabled = -not $z } }
    $script:UI.Progress.Visible = $z
    $script:UI.Window.Cursor = $(if ($z) { [Windows.Forms.Cursors]::AppStarting } else { [Windows.Forms.Cursors]::Default })
    $script:UI.DriveList.Invalidate()
    if (-not $z) { Update-Buttons }
    [Windows.Forms.Application]::DoEvents()
}

# Button enabled only when it makes sense (after a scan, with AI, not in preview mode)
function Update-Buttons {
    $u = $script:UI
    $ai = -not $NoAI
    $z = $script:Scanned
    $u.BtnExplain.Enabled = $z -and $ai -and [bool]@($script:Leftovers).Count
    $u.BtnClean.Enabled = $z -and -not $Preview -and -not $script:Cleaned
    $u.BtnCleanNow.Enabled = $u.BtnClean.Enabled
    $u.BtnRecommended.Enabled = $z -and -not $script:Cleaned
    $u.BtnClearSelection.Enabled = $u.BtnRecommended.Enabled
    $u.BtnAnalyse.Enabled = $z
    $u.BtnAnalysisAi.Enabled = $z -and $ai -and [bool]$u.AnalysisData
    $u.BtnSend.Enabled = $ai
    $u.BtnStartupAi.Enabled = $ai -and [bool]$script:Startup
    $u.BtnDriverInstall.Enabled = -not $Preview -and [bool]@($script:Drivers | Where-Object { $_ -and $_.Selected -and $_.State -in 'new', 'fail' }).Count
    $u.BtnScan.Text = $(if ($z) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj' 'Scan' })
    $u.BtnStart.Visible = (-not $z) -or [bool]$script:Cleaned
    $u.BtnStart.Text = $(if ($z) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj teraz' 'Scan now' })
    $u.BtnToPlan.Visible = $z -and -not $script:Cleaned
    $u.BtnCleanNow.Visible = $u.BtnToPlan.Visible
}

# Button action: window lock, error handling
function Invoke-UiAction([scriptblock]$sb) {
    Set-Busy $true
    try { & $sb }
    catch {
        Write-Log "Window error: $($_.Exception.Message) $($_.ScriptStackTrace)"
        Show-Message ((L 'Wystąpił błąd: {0}' 'An error occurred: {0}') -f $_.Exception.Message) 'Error'
    }
    finally { Set-Busy $false }
}

function Show-Page([string]$id) {
    if ($script:Cleaning -and $id -ne 'cleanup') { return }
    $script:CurrentPage = $id
    foreach ($k in $script:UI.Pages.Keys) { $script:UI.Pages[$k].Visible = ($k -eq $id) }
    foreach ($k in $script:UI.Nav.Keys) { $script:UI.Nav[$k].Tag.Selected = ($k -eq $id); $script:UI.Nav[$k].Invalidate() }
    $script:UI.Pages[$id].BringToFront()
    if ($id -eq 'chat') { $script:UI.Question.Focus() }
    # The startup list loads on the first visit to the page (a few seconds, no disk scan)
    if ($id -eq 'startup' -and $null -eq $script:Startup -and -not $script:UI.Scanning) { $script:UI.BtnStartupRefresh.PerformClick() }
}

# During cleanup the navigation bar only shows information
function Lock-Navigation([bool]$z) {
    $script:Cleaning = $z
    $script:UI.NavList.Visible = -not $z
    $script:UI.NavInfo.Visible = $z
}
