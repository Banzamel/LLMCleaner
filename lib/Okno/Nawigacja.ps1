<#
    LLMCleaner - pasek nawigacji
#>

function PasekNawigacji {
    $s = $script:Styl
    $nav = Kontrolka Panel @{ Dock = 'Left'; Width = (Px 240); BackColor = $s.Nawigacja; Padding = (Marg 12 20 12 14) }

    # Logo i nazwa; numer wersji jest na pasku tytulu okna
    $logo = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 60); BackColor = $s.Nawigacja }
    $ico = Join-Path $AppDir 'LLMCleaner.ico'
    if (Test-Path -LiteralPath $ico) {
        $pb = Kontrolka PictureBox @{ Location = (Pkt 6 4); Size = (Rozm 36 36); SizeMode = 'Zoom'; BackColor = $s.Nawigacja }
        $pb.Image = ObrazZIkony $ico 48
        $logo.Controls.Add($pb)
    }
    $logo.Controls.Add((Etykieta 'LLMCleaner' @{ Location = (Pkt 48 7); Size = (Rozm 160 30); AutoSize = $false; TextAlign = 'MiddleLeft'; ForeColor = [Drawing.Color]::White; BackColor = $s.Nawigacja; Font = $s.Logo }))

    $script:UI.Nav = [ordered]@{}
    $pozycje = @(
        @{ Id = 'przeglad'; T = (L 'Przegląd' 'Overview'); I = [char]0xE80F }
        @{ Id = 'plan'; T = (L 'Plan czyszczenia' 'Cleanup plan'); I = [char]0xE74D }
        @{ Id = 'analiza'; T = (L 'Co zajmuje miejsce' 'What takes up space'); I = [char]0xEDA2 }
        @{ Id = 'autostart'; T = (L 'Autostart' 'Startup apps'); I = [char]0xE7E8 }
        @{ Id = 'sterowniki'; T = (L 'Sterowniki' 'Drivers'); I = [char]0xE772 }
        @{ Id = 'czat'; T = (L 'Asystent AI' 'AI assistant'); I = [char]0xE8BD }
        @{ Id = 'log'; T = (L 'Dziennik' 'Log'); I = [char]0xE81C })
    $lista = Kontrolka Panel @{ Dock = 'Top'; Height = (Px (48 * $pozycje.Count)); BackColor = $s.Nawigacja }
    $el = @()
    $i = 0
    foreach ($p in $pozycje) {
        $i++
        $b = Przycisk $p.T 'nav' @{ Dock = 'Top'; Height = (Px 44); Font = $s.Nav; AccessibleName = "$($p.I)"; Name = $p.Id }
        $b.Add_Click({ PokazStrone $this.Name })
        $script:UI.Podpowiedz.SetToolTip($b, "Ctrl+$i")
        $script:UI.Nav[$p.Id] = $b
        $el += $b, (Kontrolka Panel @{ Dock = 'Top'; Height = (Px 4) })
    }
    Dokuj $lista $el
    $info = Etykieta (L 'Trwa czyszczenie. Nawigacja wróci po zakończeniu.' 'Cleaning in progress. Navigation comes back when it finishes.') @{
        Dock = 'Top'; Height = (Px 64); ForeColor = $s.NawTekst; BackColor = $s.Nawigacja; Padding = (Marg 10 8 6 0); Visible = $false
    }
    $script:UI.NavLista = $lista; $script:UI.NavInfo = $info

    # Dol paska: stan asystenta, tryb podgladu, aktualizacja
    $dol = Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 120); BackColor = $s.Nawigacja }
    $ai = Etykieta $(if ($BezLLM) { L 'Asystent AI: wyłączony' 'AI assistant: off' } else { (L "Asystent AI: na żądanie`r`n{0}" "AI assistant: on demand`r`n{0}") -f $Model }) @{
        Dock = 'Bottom'; Height = (Px 52); ForeColor = $s.NawSlaby; BackColor = $s.Nawigacja; Font = $s.Mala; Padding = (Marg 6 8 0 0)
    }
    $btnAkt = Przycisk '' 'zielony' @{ Dock = 'Bottom'; Height = (Px 40); Visible = $false }
    $dol.Controls.Add($btnAkt); $dol.Controls.Add((Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 8) }))
    if ($Podglad) {
        $dol.Controls.Add((Etykieta (L 'TRYB PODGLĄDU - nic nie zostanie usunięte' 'PREVIEW MODE - nothing will be deleted') @{ Dock = 'Bottom'; Height = (Px 34); ForeColor = (Kolor '#FBBF24'); BackColor = $s.Nawigacja; Font = $s.Mala }))
    }
    $dol.Controls.Add($ai)
    $script:UI.BtnAkt = $btnAkt

    Dokuj $nav @($logo, $lista, $info, $dol)
    $nav
}
