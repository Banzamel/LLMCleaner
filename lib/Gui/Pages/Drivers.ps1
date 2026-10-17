<#
    LLMCleaner - drivers page
#>

function Get-DriverStateColors([string]$state) {
    $s = $script:Style
    switch ($state) {
        'new' { return @{ T = $s.BlueBack; K = $s.BlueText } }
        'waiting' { return @{ T = $s.NeutralBack; K = $s.NeutralText } }
        'ok' { return @{ T = $s.OkBack; K = $s.OkText } }
        'restart' { return @{ T = $s.WarnBack; K = $s.WarnText } }
    }
    if ($state -in 'searching', 'downloading', 'installing') { return @{ T = $s.AccentLight; K = $s.AccentText } }
    @{ T = $s.ErrorBack; K = $s.ErrorText }
}

# A driver can be selected until it is installed (a failure can be retried)
function Test-DriverSelectable($d) { -not $Preview -and -not $script:Working -and $d.State -in 'new', 'fail' }

function Draw-DriverRow($g, $w, $r, [bool]$hover) {
    if ($w.Section) { Draw-Section $g $w $r; return }
    $s = $script:Style; $d = $w.Obj
    Draw-RowBackground $g $r $hover
    $mid = $r.Y + [int]($r.Height / 2)
    $xName = Px 64
    if ($w.Problem) {
        # Device with an error in Device Manager - view only
        Draw-Rect $g (Px 20) ($mid - (Px 16)) (Px 32) (Px 32) $s.WarnBack (Px 8)
        if ($s.Icons) { Draw-Text $g ([string][char]0xE7BA) $s.Icons $s.WarnText (Px 20) ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
        else { Draw-Text $g '!' $s.Bold $s.WarnText (Px 20) ($mid - (Px 16)) (Px 32) (Px 32) 'HorizontalCenter' }
        $width = $r.Width - $xName - (Px 18)
        Draw-Text $g $d.Name $s.Bold $s.Text $xName ($mid - (Px 21)) $width (Px 21)
        Draw-Text $g $d.Description $s.Small $s.Warning $xName ($mid + (Px 1)) $width (Px 20)
        return
    }
    Draw-CheckBox $g (Px 26) ($mid - (Px 9)) ([bool]$d.Selected) (-not (Test-DriverSelectable $d))
    $xState = $r.Width - (Px 20) - (Px 124)
    $xSize = $xState - (Px 12) - (Px 84)
    $nameW = $xSize - (Px 14) - $xName
    Draw-Text $g $d.Name $s.Bold $(if ($d.State -in 'ok', 'restart') { $s.TextDim } else { $s.Text }) $xName ($mid - (Px 31)) $nameW (Px 22)
    $line2 = (@($d.Provider, $d.Class) | Where-Object { $_ }) -join ' · '
    Draw-Text $g $line2 $s.Small $s.TextDim $xName ($mid - (Px 9)) $nameW (Px 20)
    if ($d.State -eq 'fail') { $line3 = (L 'Nie udało się: {0}' 'Failed: {0}') -f $d.Error; $col = $s.Red }
    else {
        $now = if ($d.CurrentVersion) { Format-DriverVersion $d.CurrentVersion $d.CurrentDate } elseif ($d.Problem) { $d.Problem } else { L 'nieznany' 'unknown' }
        $line3 = (L 'Teraz: {0}   →   nowy: {1}' 'Now: {0}   →   new: {1}') -f $now, (Format-DriverVersion $d.Version $d.NewDate)
        $col = if ($d.Problem -and -not $d.CurrentVersion) { $s.Warning } else { $s.Text }
    }
    Draw-Text $g $line3 $s.Small $col $xName ($mid + (Px 11)) $nameW (Px 20)
    Draw-Text $g $(if ($d.Bytes -gt 0) { Format-Size $d.Bytes } else { '' }) $s.Body $s.TextDim $xSize ($mid - (Px 12)) (Px 84) (Px 24) 'Right'
    $k = Get-DriverStateColors $d.State
    [void](Draw-Pill $g (Get-DriverStateName $d.State) $xState $mid $k.T $k.K)
}

function Draw-DriverSummary($g, $p) {
    $st = @($script:Drivers | Where-Object { $_ })
    $unchecked = $null -eq $script:Drivers
    $data = @(
        @{ W = $(if ($unchecked) { '-' } else { "$(@($st | Where-Object { $_.State -notin 'ok', 'restart' }).Count)" }); O = (L 'nowszych sterowników' 'newer drivers') }
        @{ W = $(if ($unchecked) { '-' } else { "$(@($st | Where-Object { $_.Selected }).Count)" }); O = (L 'zaznaczone do instalacji' 'selected to install') }
        @{ W = $(if ($unchecked) { '-' } else { "$(@($script:ProblemDevices | Where-Object { $_ }).Count)" }); O = (L 'urządzenia z problemem' 'devices with a problem') })
    $t = if ($Preview) { L 'Tryb podglądu - możesz sprawdzić sterowniki, ale nie instalować.' 'Preview mode - you can check for drivers but not install them.' }
    else { L 'Sterowniki z Windows Update, jak aktualizacje opcjonalne w Ustawieniach. Przed instalacją powstaje punkt przywracania.' 'Drivers from Windows Update, like the optional updates in Settings. A restore point is created before installing.' }
    Draw-TilesWithNote $g $p $data $t
}

function Update-DriversPage {
    $rows = [System.Collections.Generic.List[object]]::new()
    $st = @($script:Drivers | Where-Object { $_ })
    $problems = @($script:ProblemDevices | Where-Object { $_ })
    if ($st.Count) {
        $rows.Add(@{ Section = $true; H = (Px 40); Text = (L 'Nowsze sterowniki z Windows Update' 'Newer drivers from Windows Update'); RightText = { Get-GroupTotal $script:Drivers } })
        foreach ($d in ($st | Sort-Object { $_.Class }, { $_.Name })) { $rows.Add(@{ H = (Px 74); Obj = $d }) }
    }
    elseif ($null -ne $script:Drivers -and $problems.Count) {
        $rows.Add(@{ Section = $true; H = (Px 40); Text = (L 'Windows Update nie ma nowszych sterowników dla tego komputera' 'Windows Update has no newer drivers for this PC') })
    }
    if ($problems.Count) {
        $rows.Add(@{ Section = $true; H = (Px 44); Text = (L 'Urządzenia z problemem w Menedżerze urządzeń' 'Devices with a problem in Device Manager') })
        foreach ($p in $problems) { $rows.Add(@{ H = (Px 58); Obj = $p; Problem = $true }) }
    }
    $script:UI.LvDrivers.Tag.EmptyText = if ($null -eq $script:Drivers) { L 'Kliknij „Sprawdź”, żeby poszukać nowszych sterowników w Windows Update. Trwa to zwykle 1-3 minuty i niczego nie instaluje.' 'Click "Check" to look for newer drivers on Windows Update. It usually takes 1-3 minutes and installs nothing.' }
    else { L 'Sterowniki są aktualne według Windows Update i żadne urządzenie nie zgłasza problemu.' 'Your drivers are up to date according to Windows Update and no device reports a problem.' }
    Set-Rows $script:UI.LvDrivers $rows
    Update-DriverTotal
}

function Update-DriverTotal {
    $u = $script:UI
    $chosen = @($script:Drivers | Where-Object { $_ -and $_.Selected })
    if ($null -eq $script:Drivers) {
        $u.DriverTotal.Text = L 'Nie sprawdzono' 'Not checked yet'
        $u.DriverNote.Text = L 'Sprawdzenie łączy się z Windows Update. Wcześniej żadne dane nie są wysyłane.' 'Checking connects to Windows Update. Nothing is sent before that.'
    }
    else {
        $u.DriverTotal.Text = (L 'Zaznaczone: {0}' 'Selected: {0}') -f $chosen.Count
        $u.DriverNote.Text = (L 'Do pobrania do {0}. Przy sterowniku karty graficznej ekran może na chwilę zgasnąć. Część sterowników zadziała po ponownym uruchomieniu.' 'Up to {0} to download. With a graphics driver the screen may go blank for a moment. Some drivers take effect after a restart.') -f
            (Format-Size ([double]($chosen | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum))
    }
    $u.DriverSummary.Invalidate()
    $u.LvDrivers.Invalidate()
    if (-not $script:Working) { Update-Buttons }
}

# Install selected: restore point, then download and install one by one. Row state is
# refreshed by the window timer, because installation runs in a separate thread.
function Install-DriversFromWindow($chosen) {
    $u = $script:UI
    $script:InstallingDrivers = $true
    try {
        foreach ($d in $chosen) { $d.State = 'waiting'; $d.Error = '' }
        $u.LvDrivers.Invalidate()
        Set-WindowStatus (L 'Tworzę punkt przywracania systemu...' 'Creating a System Restore point...')
        $restore = New-RestorePoint
        Write-Log "Restore point (drivers): $($restore.Description)"
        Write-WindowLog ((L '  Punkt przywracania: {0}' '  Restore point: {0}') -f $restore.Description) $(if ($restore.Ok) { 'Green' } else { 'Yellow' })
        Set-WindowStatus (L 'Instaluję sterowniki z Windows Update. Nie wyłączaj komputera...' 'Installing drivers from Windows Update. Do not turn off the computer...')
        Set-TaskbarProgress 1
        $state = [hashtable]::Synchronized(@{})
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 400
        $timer.Tag = @{ State = $state; List = $chosen }
        $timer.Add_Tick({
                foreach ($d in $this.Tag.List) { $w = "$($this.Tag.State[$d.Id])"; if ($w -and $w -notlike 'fail:*') { $d.State = $w } }
                $script:UI.LvDrivers.Invalidate()
            })
        $timer.Start()
        try { [void](Install-Drivers $chosen $state) }
        finally { $timer.Stop(); $timer.Dispose(); Set-TaskbarProgress 0 }
    }
    finally { $script:InstallingDrivers = $false }

    foreach ($d in $chosen) {
        $col = switch ($d.State) { 'ok' { 'Green' } 'restart' { 'Green' } default { 'Yellow' } }
        $suffix = if ($d.Error) { ": $($d.Error)" } else { '' }
        Write-WindowLog ("  {0} {1}: {2}{3}" -f $d.Name, $d.Version, (Get-DriverStateName $d.State), $suffix) $col
    }
    Update-DriversPage
    $ok = @($chosen | Where-Object { $_.State -eq 'ok' }).Count
    $restarts = @($chosen | Where-Object { $_.State -eq 'restart' }).Count
    $failed = $chosen.Count - $ok - $restarts
    $t = (L 'Zainstalowano sterowników: {0} z {1}.' 'Drivers installed: {0} of {1}.') -f ($ok + $restarts), $chosen.Count
    if ($restarts) { $t += ' ' + ((L 'Uruchom ponownie komputer, żeby dokończyć instalację ({0}).' 'Restart the computer to finish installing ({0}).') -f $restarts) }
    if ($failed) { $t += ' ' + (L 'Nie wszystkie się udały - szczegóły na liście i w Dzienniku.' 'Not all of them worked - see the list and the Log.') }
    Set-WindowStatus $t
    Show-Message $t $(if ($failed) { 'Warning' } else { 'Information' })
}

function New-DriversPage {
    $s = $script:Style
    $page = New-Page
    $btnWu = New-Button 'Windows Update' 'outline' @{ Width = (Px 160) }
    $btnCheck = New-Button (L 'Sprawdź' 'Check') 'primary' @{ Width = (Px 130) }
    $n = New-PageHeader (L 'Sterowniki' 'Drivers') (L 'Nowsze sterowniki dla urządzeń tego komputera z Windows Update - podpisane, te same co w aktualizacjach opcjonalnych. Pole po lewej zaznacza sterownik, kliknięcie nazwy pokazuje pełny opis. Dwuklik otwiera Menedżera urządzeń.' 'Newer drivers for the devices in this PC from Windows Update - signed, the same as the optional updates. The box on the left ticks a driver; click its name for the full description. Double-click opens Device Manager.') @($btnWu, $btnCheck)
    $btnWu.Add_Click({ Start-Process 'ms-settings:windowsupdate-optionalupdates' })
    $script:UI.BtnDriverCheck = $btnCheck

    $sumCanvas = New-Canvas @{ Dock = 'Top'; Height = (Px 66); BackColor = $s.Background } { param($g, $p) Draw-DriverSummary $g $p }
    $script:UI.DriverSummary = $sumCanvas

    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 2 4 2 8) }
    $lv = New-RowList { param($g, $w, $r, $h) Draw-DriverRow $g $w $r $h }
    $lv.Tag.Click = {
        param($w, $x, $r)
        # The box ticks the driver; a click on its name shows the full description
        if ($x -ge (Px 56) -or $w.Problem -or -not (Test-DriverSelectable $w.Obj)) { return }
        $w.Obj.Selected = -not $w.Obj.Selected
        Update-DriverTotal
    }
    $lv.Tag.HandCursor = { param($w, $x, $r) $x -ge (Px 56) -or (-not $w.Problem -and (Test-DriverSelectable $w.Obj)) }
    $lv.Tag.HintArea = { param($w, $x, $r) $x -ge (Px 56) }
    $lv.Tag.DoubleClick = { param($w) Start-Process devmgmt.msc }
    $lv.Tag.Hint = {
        param($w)
        $d = $w.Obj
        if ($w.Problem) { (@($d.Name, $d.Description, $d.Id) | Where-Object { $_ }) -join "`n" }
        else { (@($d.Name, $d.Title, $d.Model, $d.Problem, $d.Error) | Where-Object { $_ } | Select-Object -Unique) -join "`n" }
    }
    $k.Controls.Add($lv)
    $script:UI.LvDrivers = $lv

    $bottom = New-Card @{ Dock = 'Bottom'; Height = (Px 74); Padding = (New-Padding 20 14 14 14) }
    $btnInstall = New-Button $(if ($Preview) { L 'Podgląd - instalacja wyłączona' 'Preview - installing disabled' } else { L 'Zainstaluj zaznaczone...' 'Install selected...' }) 'primary' @{ Dock = 'Right'; Width = (Px 230) }
    $texts = New-Control Panel @{ Dock = 'Fill' }
    $total = New-Label '' @{ Dock = 'Top'; Height = (Px 26); Font = $s.Medium }
    $desc = New-Label '' @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small; AutoEllipsis = $true }
    Add-Docked $texts @($total, $desc)
    Add-Docked $bottom @($btnInstall, $texts)
    $script:UI.DriverTotal = $total; $script:UI.DriverNote = $desc; $script:UI.BtnDriverInstall = $btnInstall

    Add-Docked $page @($n.Panel, $sumCanvas, (New-Spacer 'Top' 14), $bottom, (New-Spacer 'Bottom' 14), $k)
    $page
}
