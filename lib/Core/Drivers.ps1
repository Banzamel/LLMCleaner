<#
    LLMCleaner - aktualizacje sterownikow z Windows Update
#>

# Nowsze sterowniki z Windows Update - te same, co Ustawienia > Windows Update > Aktualizacje opcjonalne.
# Szukanie i instalacja ida przez Windows Update Agent (COM) w osobnym watku: szukanie trwa zwykle 1-3 min.
# Zapytanie idzie do Windows Update tylko po kliknieciu "Sprawdz", nigdy przy starcie.
$script:Drivers = $null          # $null = jeszcze nie sprawdzano
$script:ProblemDevices = @()

# Wersja z tytulu aktualizacji, np. "Intel Corporation - Display - 31.0.101.4502"
function Get-VersionFromTitle([string]$t) { if ($t -match '(\d+(\.\d+){1,3})\s*$') { $Matches[1] } else { '' } }

function Get-ProblemDescription([int]$code) {
    switch ($code) {
        28 { L 'brak sterownika' 'no driver installed' }
        10 { L 'urządzenie nie może się uruchomić (kod 10)' 'the device cannot start (code 10)' }
        43 { L 'urządzenie zgłosiło problem (kod 43)' 'the device reported a problem (code 43)' }
        { $_ -in 1, 18, 31, 39, 52 } { (L 'sterownik nie działa poprawnie (kod {0})' 'the driver does not work properly (code {0})') -f $code }
        default { (L 'problem z urządzeniem (kod {0})' 'device problem (code {0})') -f $code }
    }
}

# Urzadzenia z bledem w Menedzerze urzadzen. Pomijamy wylaczone (22) i odlaczone (24, 45).
function Get-ProblemDevices {
    @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -notin 0, 22, 24, 45 -and $_.Present -ne $false } |
            ForEach-Object { @{ Name = $(if ($_.Name) { $_.Name } else { $_.DeviceID }); Id = $_.DeviceID; Code = [int]$_.ConfigManagerErrorCode; Description = (Get-ProblemDescription $_.ConfigManagerErrorCode) } })
}

# Szuka nowszych sterownikow i dopasowuje je do urzadzen (obecna wersja i data). Zwraca liczbe znalezionych.
function Find-DriverUpdates {
    Write-Log 'Sterowniki: szukanie w Windows Update'
    $found = @(Invoke-Background {
            $session = New-Object -ComObject Microsoft.Update.Session
            $session.ClientApplicationID = 'LLMCleaner'
            $searcher = $session.CreateUpdateSearcher()
            $searcher.ServerSelection = 2   # Windows Update, takze na komputerze z WSUS
            foreach ($u in $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0").Updates) {
                [pscustomobject]@{ Id = $u.Identity.UpdateID; Title = $u.Title; Model = $u.DriverModel; Provider = $u.DriverProvider
                    Class = $u.DriverClass; NewDate = $u.DriverVerDate; HwId = $u.DriverHardwareID; Bytes = [double]$u.MaxDownloadSize
                }
            }
        } | Where-Object { $_ })

    # Urzadzenie po identyfikatorze sprzetu (najpierw HardwareID, potem CompatibleID) i jego obecny sterownik
    $deviceDrivers = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver) { if ($d.DeviceID) { $deviceDrivers[$d.DeviceID] = $d } }
    $devices = @{}
    $entities = @(Get-CimInstance Win32_PnPEntity)
    foreach ($field in 'HardwareID', 'CompatibleID') {
        foreach ($e in $entities) { foreach ($h in @($e.$field)) { if ($h -and -not $devices.ContainsKey($h.ToLower())) { $devices[$h.ToLower()] = $e } } }
    }

    $script:Drivers = @(foreach ($z in $found) {
            $e = if ($z.HwId) { $devices["$($z.HwId)".ToLower()] }
            $installedDriver = if ($e) { $deviceDrivers[$e.DeviceID] }
            $problem = if ($e -and $e.ConfigManagerErrorCode -notin 0, 22) { Get-ProblemDescription $e.ConfigManagerErrorCode }
            @{ Id = $z.Id; Title = $z.Title; Name = $(if ($e -and $e.Name) { $e.Name } elseif ($z.Model) { $z.Model } else { $z.Title })
                Model = $z.Model; Provider = $z.Provider; Class = $z.Class; Bytes = $z.Bytes
                Version = (Get-VersionFromTitle $z.Title); NewDate = $z.NewDate
                CurrentVersion = $installedDriver.DriverVersion; CurrentDate = $installedDriver.DriverDate; Problem = $problem
                Selected = $true; State = 'new'; Error = ''
            }
        })
    $script:ProblemDevices = Get-ProblemDevices
    Write-Log "Sterowniki: $(($script:Drivers | ForEach-Object { "$($_.Title) [$($_.CurrentVersion)]" }) -join ', ')"
    Write-Log "Urzadzenia z problemem: $(($script:ProblemDevices | ForEach-Object { "$($_.Name) ($($_.Code))" }) -join ', ')"
    $script:Drivers.Count
}

function Format-DriverDate($d) { if ($d -is [datetime] -and $d -gt [datetime]'1990-01-01') { $d.ToString('yyyy-MM-dd') } else { '' } }
function Format-DriverVersion([string]$version, $dateText) {
    $dd = Format-DriverDate $dateText
    if ($version -and $dd) { "$version ($dd)" } elseif ($version) { $version } else { $dd }
}

function Get-DriverStateName([string]$state) {
    switch ($state) {
        'new' { L 'dostępny' 'available' }
        'waiting' { L 'czeka' 'waiting' }
        'searching' { L 'przygotowanie' 'preparing' }
        'downloading' { L 'pobieranie' 'downloading' }
        'installing' { L 'instalacja' 'installing' }
        'ok' { L 'zainstalowany' 'installed' }
        'restart' { L 'po restarcie' 'after restart' }
        'gone' { L 'już niedostępny' 'no longer offered' }
        default { L 'błąd' 'failed' }
    }
}

# Instaluje sterowniki po kolei (pobranie i instalacja przez Windows Update). Stan kazdego idzie do
# $stan (zsynchronizowana tablica: Id -> szukanie, pobieranie, instalacja, ok, restart, brak, blad:...),
# ktora okno odczytuje w trakcie. Zwraca liczbe zainstalowanych.
function Install-Drivers($list, [hashtable]$state) {
    $list = @($list)
    if (-not $list.Count) { return 0 }
    foreach ($s in $list) { $state[$s.Id] = 'searching' }
    Write-Log "Sterowniki: instalacja $(($list | ForEach-Object { $_.Title }) -join ', ')"
    try {
        Invoke-Background {
            param($ids, $state)
            $session = New-Object -ComObject Microsoft.Update.Session
            $session.ClientApplicationID = 'LLMCleaner'
            $searcher = $session.CreateUpdateSearcher()
            $searcher.ServerSelection = 2
            $available = @{}
            foreach ($u in $searcher.Search("IsInstalled=0 and Type='Driver'").Updates) { $available[$u.Identity.UpdateID] = $u }
            foreach ($id in $ids) { if (-not $available[$id]) { $state[$id] = 'gone' } else { $state[$id] = 'waiting' } }
            foreach ($id in $ids) {
                $u = $available[$id]
                if (-not $u) { continue }
                try {
                    if (-not $u.EulaAccepted) { $u.AcceptEula() }
                    $col = New-Object -ComObject Microsoft.Update.UpdateColl
                    [void]$col.Add($u)
                    $state[$id] = 'downloading'
                    $downloader = $session.CreateUpdateDownloader(); $downloader.Updates = $col
                    $downloadResult = $downloader.Download()
                    if ($downloadResult.ResultCode -notin 2, 3) { $state[$id] = 'fail:' + ('0x{0:X8}' -f $downloadResult.GetUpdateResult(0).HResult); continue }
                    $state[$id] = 'installing'
                    $installer = $session.CreateUpdateInstaller(); $installer.Updates = $col
                    $installResult = $installer.Install()
                    $state[$id] = if ($installResult.ResultCode -in 2, 3) { if ($installResult.RebootRequired) { 'restart' } else { 'ok' } }
                    else { 'fail:' + ('0x{0:X8}' -f $installResult.GetUpdateResult(0).HResult) }
                }
                catch { $state[$id] = 'fail:' + $_.Exception.Message }
            }
        } @(@($list | ForEach-Object { $_.Id }), $state) | Out-Null
    }
    catch {
        Write-Log "Sterowniki: blad instalacji: $($_.Exception.Message)"
        foreach ($s in $list) { if ($state[$s.Id] -in 'searching', 'waiting') { $state[$s.Id] = 'fail:' + $_.Exception.Message } }
    }
    $n = 0
    foreach ($s in $list) {
        $w = "$($state[$s.Id])"
        if ($w -like 'fail:*') { $s.State = 'fail'; $s.Error = $w.Substring(5) } else { $s.State = $w }
        if ($s.State -in 'ok', 'restart') { $n++; $s.Selected = $false }
        Write-Log "Sterownik $($s.Title): $w"
    }
    $n
}
