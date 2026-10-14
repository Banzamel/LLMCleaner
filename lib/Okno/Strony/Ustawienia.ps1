<#
    LLMCleaner - strona Ustawienia: jezyk, motyw, model AI, asystent, aktualizacje, tryb podgladu
    Zapis do ustawienia.json (lib\Rdzen\Konfiguracja.ps1). Zmiany dzialaja po ponownym uruchomieniu.
#>

# Wiersz ustawienia: opis po lewej, kontrolka po prawej
function WierszUstawienia([string]$tytul, [string]$opis, $kontrolka) {
    $s = $script:Styl
    $w = Kontrolka Panel @{ Dock = 'Top'; Height = (Px 62); Padding = (Marg 0 6 0 6) }
    $lewy = Kontrolka Panel @{ Dock = 'Fill' }
    $t = Etykieta $tytul @{ Dock = 'Top'; Height = (Px 24); Font = $s.Pogrubiona }
    $o = Etykieta $opis @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; Font = $s.Mala; AutoEllipsis = $true }
    Dokuj $lewy @($t, $o)
    $prawy = Kontrolka Panel @{ Dock = 'Right'; Width = (Px 300); Padding = (Marg 0 10 0 0) }
    $kontrolka.Dock = 'Top'
    $prawy.Controls.Add($kontrolka)
    Dokuj $w @($prawy, $lewy)
    $w
}

function ListaUstawienia([string[]]$pozycje, [bool]$edycja = $false) {
    $s = $script:Styl
    $c = Kontrolka ComboBox @{ DropDownStyle = $(if ($edycja) { 'DropDown' } else { 'DropDownList' }); Font = $s.Czcionka; FlatStyle = 'Flat'; BackColor = $s.Kafelek; ForeColor = $s.Tekst }
    foreach ($p in $pozycje) { [void]$c.Items.Add($p) }
    $c
}

function PoleUstawienia([string]$tekst) {
    $s = $script:Styl
    Kontrolka CheckBox @{ Text = $tekst; Height = (Px 30); Font = $s.Czcionka; ForeColor = $s.Tekst; BackColor = $s.Karta; FlatStyle = 'Flat'; UseMnemonic = $false }
}

$WartosciJezyka = @('auto', 'pl', 'en')
$WartosciMotywu = @('auto', 'jasny', 'ciemny')

function StronaUstawienia {
    $s = $script:Styl
    $str = Strona
    $n = Naglowek (L 'Ustawienia' 'Settings') (L 'Zmiany zaczną działać po ponownym uruchomieniu programu.' 'Changes take effect after the program restarts.')
    $k = Karta @{ Dock = 'Fill'; Padding = (Marg 22 12 22 12) }
    $k.AutoScroll = $true

    $cboJ = ListaUstawienia @((L 'Jak w Windows' 'Same as Windows'), 'Polski', 'English')
    $cboM = ListaUstawienia @((L 'Jak w Windows' 'Same as Windows'), (L 'Jasny' 'Light'), (L 'Ciemny' 'Dark'))
    $cboModel = ListaUstawienia @(ModeleLokalne) $true
    $chkAi = PoleUstawienia (L 'Włączony' 'On')
    $chkAkt = PoleUstawienia (L 'Sprawdzaj przy starcie' 'Check at startup')
    $chkPod = PoleUstawienia (L 'Zawsze w trybie podglądu' 'Always in preview mode')
    $btnLogi = Przycisk (L 'Otwórz folder logów' 'Open the log folder') 'ramka' @{ Height = (Px 38) }
    $btnLogi.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })

    $wiersze = @(
        (WierszUstawienia (L 'Język' 'Language') (L 'Język okna i odpowiedzi asystenta AI.' 'The language of the window and of the AI assistant.') $cboJ)
        (WierszUstawienia (L 'Motyw' 'Theme') (L 'Jasny albo ciemny wygląd okna.' 'Light or dark look of the window.') $cboM)
        (WierszUstawienia (L 'Asystent AI' 'AI assistant') (L 'Lokalny model opisuje pozycje i odpowiada w czacie. Wyłączony nie zajmuje pamięci.' 'The local model describes items and answers in the chat. When off it uses no memory.') $chkAi)
        (WierszUstawienia (L 'Model AI' 'AI model') (L 'Model z folderu ai\models. Inny model pobierzesz instalatorem albo Install-AI.ps1.' 'A model from the ai\models folder. Get another one with the installer or Install-AI.ps1.') $cboModel)
        (WierszUstawienia (L 'Aktualizacje' 'Updates') (L 'Jedno zapytanie do GitHuba przy starcie, bez danych o komputerze.' 'One request to GitHub at startup, with no data about this computer.') $chkAkt)
        (WierszUstawienia (L 'Tryb podglądu' 'Preview mode') (L 'Skan i plan bez możliwości usuwania - bezpieczne do pokazania komuś programu.' 'Scan and plan without deleting anything - safe for showing the program to someone.') $chkPod)
        (WierszUstawienia (L 'Logi' 'Logs') ((L 'Dziennik każdego uruchomienia i kopie rejestru: {0}' 'The log of every run and registry backups: {0}') -f $LogDir) $btnLogi)
    )
    $el = @()
    foreach ($w in $wiersze) { $el += $w, (Kontrolka Panel @{ Dock = 'Top'; Height = (Px 1); BackColor = $s.Linia }) }
    Dokuj $k $el

    $dol = Kontrolka Panel @{ Dock = 'Bottom'; Height = (Px 50); Padding = (Marg 0 10 0 0) }
    $btnZ = Przycisk (L 'Zapisz' 'Save') 'drugi' @{ Dock = 'Right' }
    $btnR = Przycisk (L 'Zapisz i uruchom ponownie' 'Save and restart') 'glowny' @{ Dock = 'Right' }
    $info = Etykieta '' @{ Dock = 'Fill'; ForeColor = $s.TekstSlaby; TextAlign = 'MiddleLeft'; AutoEllipsis = $true }
    Dokuj $dol @($btnR, (Odstep 'Right' 10), $btnZ, $info)
    $btnZ.Add_Click({ ZapiszUstawieniaOkna; $script:UI.UstInfo.Text = L 'Zapisano. Zmiany zaczną działać po ponownym uruchomieniu.' 'Saved. Changes take effect after a restart.' })
    $btnR.Add_Click({ ZapiszUstawieniaOkna; $script:Restart = $true; $script:UI.Okno.Close() })

    $script:UI.UstJezyk = $cboJ; $script:UI.UstMotyw = $cboM; $script:UI.UstModel = $cboModel
    $script:UI.UstAi = $chkAi; $script:UI.UstAkt = $chkAkt; $script:UI.UstPodglad = $chkPod
    $script:UI.BtnUstZapisz = $btnZ; $script:UI.BtnUstRestart = $btnR; $script:UI.UstInfo = $info
    WypelnijUstawienia

    Dokuj $str @($n.Panel, $dol, (Odstep 'Bottom' 10), $k)
    $str
}

# Kontrolki pokazuja zapisane ustawienia (nie parametry tego uruchomienia, np. -Podglad ze skrotu)
function WypelnijUstawienia {
    $u = $script:UI; $k = $Konfiguracja
    $u.UstJezyk.SelectedIndex = [Math]::Max(0, [array]::IndexOf($WartosciJezyka, "$($k.Jezyk)"))
    $m = if ($k.Motyw) { "$($k.Motyw)" } elseif ($script:Ustawienia.Motyw) { "$($script:Ustawienia.Motyw)" } else { 'auto' }
    $u.UstMotyw.SelectedIndex = [Math]::Max(0, [array]::IndexOf($WartosciMotywu, $(if ($m -eq 'dark') { 'ciemny' } elseif ($m -eq 'light') { 'jasny' } else { $m })))
    $u.UstModel.Text = $(if ($k.Model) { "$($k.Model)" } else { $Model })
    $u.UstAi.Checked = $k.Asystent -ne $false
    $u.UstAkt.Checked = $k.Aktualizacje -ne $false
    $u.UstPodglad.Checked = $k.Podglad -eq $true
}

function ZapiszUstawieniaOkna {
    $u = $script:UI
    $Konfiguracja.Jezyk = $WartosciJezyka[[Math]::Max(0, $u.UstJezyk.SelectedIndex)]
    $Konfiguracja.Motyw = $WartosciMotywu[[Math]::Max(0, $u.UstMotyw.SelectedIndex)]
    # Model z instalatora nie trafia do pliku - kolejna instalacja z innym modelem nadal zadziala
    $m = $u.UstModel.Text.Trim()
    $Konfiguracja.Model = $(if ($m -eq (ModelInstalatora)) { '' } else { $m })
    $Konfiguracja.Asystent = $u.UstAi.Checked
    $Konfiguracja.Aktualizacje = $u.UstAkt.Checked
    $Konfiguracja.Podglad = $u.UstPodglad.Checked
    try { ZapiszKonfiguracje $Konfiguracja; Log "Ustawienia zapisane: $(ConvertTo-Json -InputObject $Konfiguracja -Compress)" }
    catch { Log "Zapis ustawien: $($_.Exception.Message)"; Komunikat ((L 'Nie udało się zapisać ustawień: {0}' 'Could not save the settings: {0}') -f $_.Exception.Message) 'Error' }
}

# Nowy proces ma juz uprawnienia administratora (dziedziczy je), wiec UAC nie pyta drugi raz
function UruchomPonownie {
    $argumenty = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $AppDir 'LLMCleaner.ps1')`"", '-Sid', $UzytkownikSid)
    if ($PodgladZParametru) { $argumenty += '-Podglad' }
    try { Start-Process powershell.exe -ArgumentList $argumenty; Log 'Ponowne uruchomienie po zmianie ustawien.' }
    catch { Log "Ponowne uruchomienie: $($_.Exception.Message)" }
}
