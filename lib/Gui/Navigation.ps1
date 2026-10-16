<#
    LLMCleaner - navigation bar
#>

function New-NavigationBar {
    $s = $script:Style
    $nav = New-Control Panel @{ Dock = 'Left'; Width = (Px 240); BackColor = $s.NavBack; Padding = (New-Padding 12 20 12 14) }

    # Logo and name; the version number is in the window title bar
    $logo = New-Control Panel @{ Dock = 'Top'; Height = (Px 60); BackColor = $s.NavBack }
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) {
        $pb = New-Control PictureBox @{ Location = (New-Point 6 4); Size = (New-Size 36 36); SizeMode = 'Zoom'; BackColor = $s.NavBack }
        $pb.Image = Get-IconImage $ico 48
        $logo.Controls.Add($pb)
    }
    $logo.Controls.Add((New-Label 'LLMCleaner' @{ Location = (New-Point 48 7); Size = (New-Size 160 30); AutoSize = $false; TextAlign = 'MiddleLeft'; ForeColor = [Drawing.Color]::White; BackColor = $s.NavBack; Font = $s.Logo }))

    $script:UI.Nav = [ordered]@{}
    $items = @(
        @{ Id = 'overview'; T = (L 'Przegląd' 'Overview'); I = [char]0xE80F }
        @{ Id = 'plan'; T = (L 'Plan czyszczenia' 'Cleanup plan'); I = [char]0xE74D }
        @{ Id = 'analysis'; T = (L 'Co zajmuje miejsce' 'What takes up space'); I = [char]0xEDA2 }
        @{ Id = 'startup'; T = (L 'Autostart' 'Startup apps'); I = [char]0xE7E8 }
        @{ Id = 'drivers'; T = (L 'Sterowniki' 'Drivers'); I = [char]0xE772 }
        @{ Id = 'chat'; T = (L 'Asystent AI' 'AI assistant'); I = [char]0xE8BD }
        @{ Id = 'log'; T = (L 'Dziennik' 'Log'); I = [char]0xE81C }
        @{ Id = 'settings'; T = (L 'Ustawienia' 'Settings'); I = [char]0xE713 })
    $list = New-Control Panel @{ Dock = 'Top'; Height = (Px (48 * $items.Count)); BackColor = $s.NavBack }
    $el = @()
    $i = 0
    foreach ($p in $items) {
        $i++
        $b = New-Button $p.T 'nav' @{ Dock = 'Top'; Height = (Px 44); Font = $s.Nav; AccessibleName = "$($p.I)"; Name = $p.Id }
        $b.Add_Click({ Show-Page $this.Name })
        $script:UI.Hint.SetToolTip($b, "Ctrl+$i")
        $script:UI.Nav[$p.Id] = $b
        $el += $b, (New-Control Panel @{ Dock = 'Top'; Height = (Px 4) })
    }
    Add-Docked $list $el
    $info = New-Label (L 'Trwa czyszczenie. Nawigacja wróci po zakończeniu.' 'Cleaning in progress. Navigation comes back when it finishes.') @{
        Dock = 'Top'; Height = (Px 64); ForeColor = $s.NavText; BackColor = $s.NavBack; Padding = (New-Padding 10 8 6 0); Visible = $false
    }
    $script:UI.NavList = $list; $script:UI.NavInfo = $info

    # Bottom of the bar: assistant status, preview mode, update
    $bottom = New-Control Panel @{ Dock = 'Bottom'; Height = (Px 120); BackColor = $s.NavBack }
    $ai = New-Label $(if ($NoAI) { L 'Asystent AI: wyłączony' 'AI assistant: off' } else { (L "Asystent AI: na żądanie`r`n{0}" "AI assistant: on demand`r`n{0}") -f $Model }) @{
        Dock = 'Bottom'; Height = (Px 52); ForeColor = $s.NavDim; BackColor = $s.NavBack; Font = $s.Small; Padding = (New-Padding 6 8 0 0)
    }
    $btnUpdate = New-Button '' 'green' @{ Dock = 'Bottom'; Height = (Px 40); Visible = $false }
    $bottom.Controls.Add($btnUpdate); $bottom.Controls.Add((New-Control Panel @{ Dock = 'Bottom'; Height = (Px 8) }))
    if ($Preview) {
        $bottom.Controls.Add((New-Label (L 'TRYB PODGLĄDU - nic nie zostanie usunięte' 'PREVIEW MODE - nothing will be deleted') @{ Dock = 'Bottom'; Height = (Px 34); ForeColor = (ConvertTo-Color '#FBBF24'); BackColor = $s.NavBack; Font = $s.Small }))
    }
    $bottom.Controls.Add($ai)
    $script:UI.BtnUpdate = $btnUpdate

    Add-Docked $nav @($logo, $list, $info, $bottom)
    $nav
}
