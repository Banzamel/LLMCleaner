<#
    LLMCleaner - rozmiar, polozenie i motyw paska tytulu okna
#>

function PrzywrocOkno($f) {
    $u = $script:Ustawienia
    $obszar = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $f.Size = New-Object Drawing.Size([Math]::Min((Px 1240), $obszar.Width), [Math]::Min((Px 800), $obszar.Height))
    $f.StartPosition = 'CenterScreen'
    if (-not $u -or -not $u.W -or -not $u.H) { return }
    # Inne skalowanie niz przy zapisie - rozmiar przeliczony
    $k = if ($u.Skala) { $script:Skala / [double]$u.Skala } else { 1.0 }
    $r = New-Object Drawing.Rectangle([int]$u.X, [int]$u.Y, [int]([int]$u.W * $k), [int]([int]$u.H * $k))
    # Po zmianie skali okno moze wyjsc wieksze niz ekran - przyciete do obszaru roboczego
    $ekran = [Windows.Forms.Screen]::FromRectangle($r).WorkingArea
    $r.Width = [Math]::Min($r.Width, $ekran.Width); $r.Height = [Math]::Min($r.Height, $ekran.Height)
    # Tylko gdy okno trafi na ktorys z ekranow (monitor mogl zostac odlaczony)
    $widoczne = @([Windows.Forms.Screen]::AllScreens | Where-Object { $_.WorkingArea.IntersectsWith((New-Object Drawing.Rectangle($r.X, $r.Y, [Math]::Min($r.Width, (Px 200)), (Px 60)))) }).Count
    if ($widoczne -and $r.Width -ge $f.MinimumSize.Width -and $r.Height -ge $f.MinimumSize.Height) {
        $f.StartPosition = 'Manual'
        $f.Bounds = $r
        if ($u.Max) { $f.WindowState = 'Maximized' }
    }
}

function ZapiszOkno {
    $f = $script:UI.Okno
    $b = if ($f.WindowState -eq 'Normal') { $f.Bounds } else { $f.RestoreBounds }
    $motyw = if ($script:Ustawienia.Motyw) { "$($script:Ustawienia.Motyw)" } else { 'auto' }
    $strona = if ($script:Strona -in 'plan', 'czyszczenie') { 'przeglad' } else { $script:Strona }
    $dane = [ordered]@{ X = $b.X; Y = $b.Y; W = $b.Width; H = $b.Height; Max = ($f.WindowState -eq 'Maximized'); Skala = $script:Skala; Strona = $strona; Motyw = $motyw }
    try {
        New-Item -ItemType Directory -Force (Split-Path $script:OknoPlik) | Out-Null
        Set-Content -LiteralPath $script:OknoPlik -Value (ConvertTo-Json -InputObject $dane) -Encoding UTF8
    }
    catch { Log "Zapis okno.json: $($_.Exception.Message)" }
}

# Ciemny pasek tytulu i ciemne paski przewijania (Windows 10 1809+; starsze ignoruja)
function CiemnyTytul {
    if ($script:Ciemny) { try { [LlmWin.Natywne]::CiemnyPasekTytulu($script:UI.Okno.Handle) } catch { Log "Motyw ciemny: $($_.Exception.Message)" } }
}
function CiemnePrzewijanie {
    if (-not $script:Ciemny) { return }
    try { foreach ($c in $script:UI.Przewijane) { [void][LlmWin.Natywne]::SetWindowTheme($c.Handle, 'DarkMode_Explorer', [NullString]::Value) } }
    catch { Log "Motyw ciemny: $($_.Exception.Message)" }
}
