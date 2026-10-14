<#
    LLMCleaner - stan okna: zajetosc, przyciski, akcje, przelaczanie stron
#>

# Blokuje przyciski na czas pracy i pokazuje pasek postepu
function Zajety([bool]$z) {
    $script:Pracuje = $z
    foreach ($b in $script:UI.Akcje) { if ($b) { $b.Enabled = -not $z } }
    $script:UI.Pasek.Visible = $z
    $script:UI.Okno.Cursor = $(if ($z) { [Windows.Forms.Cursors]::AppStarting } else { [Windows.Forms.Cursors]::Default })
    $script:UI.ListaDyskow.Invalidate()
    if (-not $z) { UstawPrzyciski }
    [Windows.Forms.Application]::DoEvents()
}

# Przycisk wlaczony tylko wtedy, gdy ma sens (po skanie, z AI, bez trybu podgladu)
function UstawPrzyciski {
    $u = $script:UI
    $ai = -not $BezLLM
    $z = $script:Zeskanowano
    $u.BtnWyjasnij.Enabled = $z -and $ai -and [bool]@($script:Pozostalosci).Count
    $u.BtnWyczysc.Enabled = $z -and -not $Podglad -and -not $script:PoCzyszczeniu
    $u.BtnOdRazu.Enabled = $u.BtnWyczysc.Enabled
    $u.BtnZalecane.Enabled = $z -and -not $script:PoCzyszczeniu
    $u.BtnOdznacz.Enabled = $u.BtnZalecane.Enabled
    $u.BtnAnalizuj.Enabled = $z
    $u.BtnAnalizaAi.Enabled = $z -and $ai -and [bool]$u.AnalizaDane
    $u.BtnWyslij.Enabled = $ai
    $u.BtnAutoAi.Enabled = $ai -and [bool]$script:Autostart
    $u.BtnSterInstaluj.Enabled = -not $Podglad -and [bool]@($script:Sterowniki | Where-Object { $_ -and $_.Wybrana -and $_.Stan -in 'nowy', 'blad' }).Count
    $u.BtnSkan.Text = $(if ($z) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj' 'Scan' })
    $u.BtnStart.Visible = (-not $z) -or [bool]$script:PoCzyszczeniu
    $u.BtnStart.Text = $(if ($z) { L 'Skanuj ponownie' 'Scan again' } else { L 'Skanuj teraz' 'Scan now' })
    $u.BtnDoPlanu.Visible = $z -and -not $script:PoCzyszczeniu
    $u.BtnOdRazu.Visible = $u.BtnDoPlanu.Visible
}

# Akcja przycisku: blokada okna, obsluga bledow
function Akcja([scriptblock]$sb) {
    Zajety $true
    try { & $sb }
    catch {
        Log "Blad okna: $($_.Exception.Message) $($_.ScriptStackTrace)"
        Komunikat ((L 'Wystąpił błąd: {0}' 'An error occurred: {0}') -f $_.Exception.Message) 'Error'
    }
    finally { Zajety $false }
}

function PokazStrone([string]$id) {
    if ($script:Czyszczenie -and $id -ne 'czyszczenie') { return }
    $script:Strona = $id
    foreach ($k in $script:UI.Strony.Keys) { $script:UI.Strony[$k].Visible = ($k -eq $id) }
    foreach ($k in $script:UI.Nav.Keys) { $script:UI.Nav[$k].Tag.Wybrany = ($k -eq $id); $script:UI.Nav[$k].Invalidate() }
    $script:UI.Strony[$id].BringToFront()
    if ($id -eq 'czat') { $script:UI.Pytanie.Focus() }
    # Lista autostartu wczytuje sie przy pierwszym wejsciu na strone (kilka sekund, bez skanu dyskow)
    if ($id -eq 'autostart' -and $null -eq $script:Autostart -and -not $script:UI.Skanuje) { $script:UI.BtnAutoOdswiez.PerformClick() }
}

# Na czas czyszczenia pasek nawigacji pokazuje tylko informacje
function ZablokujNawigacje([bool]$z) {
    $script:Czyszczenie = $z
    $script:UI.NavLista.Visible = -not $z
    $script:UI.NavInfo.Visible = $z
}
