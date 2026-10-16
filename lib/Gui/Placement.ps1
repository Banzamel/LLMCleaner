<#
    LLMCleaner - rozmiar, polozenie i motyw paska tytulu okna
#>

function Restore-WindowBounds($f) {
    $u = $script:WindowPrefs
    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $f.Size = New-Object Drawing.Size([Math]::Min((Px 1240), $area.Width), [Math]::Min((Px 800), $area.Height))
    $f.StartPosition = 'CenterScreen'
    if (-not $u -or -not $u.W -or -not $u.H) { return }
    # Inne skalowanie niz przy zapisie - rozmiar przeliczony
    $k = if ($u.Scale) { $script:Scale / [double]$u.Scale } else { 1.0 }
    $r = New-Object Drawing.Rectangle([int]$u.X, [int]$u.Y, [int]([int]$u.W * $k), [int]([int]$u.H * $k))
    # Po zmianie skali okno moze wyjsc wieksze niz ekran - przyciete do obszaru roboczego
    $screen = [Windows.Forms.Screen]::FromRectangle($r).WorkingArea
    $r.Width = [Math]::Min($r.Width, $screen.Width); $r.Height = [Math]::Min($r.Height, $screen.Height)
    # Tylko gdy okno trafi na ktorys z ekranow (monitor mogl zostac odlaczony)
    $visible = @([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith((New-Object Drawing.Rectangle($r.X, $r.Y, [Math]::Min($r.Width, (Px 200)), (Px 60)))) }).Count
    if ($visible -and $r.Width -ge $f.MinimumSize.Width -and $r.Height -ge $f.MinimumSize.Height) {
        $f.StartPosition = 'Manual'
        $f.Bounds = $r
        if ($u.Max) { $f.WindowState = 'Maximized' }
    }
}

function Save-WindowState {
    $f = $script:UI.Window
    $b = if ($f.WindowState -eq 'Normal') { $f.Bounds } else { $f.RestoreBounds }
    $theme = if ($script:WindowPrefs.Theme) { "$($script:WindowPrefs.Theme)" } else { 'auto' }
    $currentPage = if ($script:CurrentPage -in 'plan', 'cleanup') { 'overview' } else { $script:CurrentPage }
    $data = [ordered]@{ X = $b.X; Y = $b.Y; W = $b.Width; H = $b.Height; Max = ($f.WindowState -eq 'Maximized'); Scale = $script:Scale; Page = $currentPage; Theme = $theme }
    try {
        New-Item -ItemType Directory -Force (Split-Path $script:WindowFile) | Out-Null
        Set-Content -LiteralPath $script:WindowFile -Value (ConvertTo-Json -InputObject $data) -Encoding UTF8
    }
    catch { Write-Log "Zapis okno.json: $($_.Exception.Message)" }
}

# Ciemny pasek tytulu i ciemne paski przewijania (Windows 10 1809+; starsze ignoruja)
function Set-DarkTitleBar {
    if ($script:Dark) { try { [LlmWin.Native]::DarkTitleBar($script:UI.Window.Handle) } catch { Write-Log "Motyw ciemny: $($_.Exception.Message)" } }
}
function Set-DarkScrollbars {
    if (-not $script:Dark) { return }
    try { foreach ($c in $script:UI.Scrollables) { [void][LlmWin.Native]::SetWindowTheme($c.Handle, 'DarkMode_Explorer', [NullString]::Value) } }
    catch { Write-Log "Motyw ciemny: $($_.Exception.Message)" }
}
