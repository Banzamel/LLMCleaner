<#
    LLMCleaner - aktualizacje sterownikow z Windows Update
#>

# Nowsze sterowniki z Windows Update - te same, co Ustawienia > Windows Update > Aktualizacje opcjonalne.
# Szukanie i instalacja ida przez Windows Update Agent (COM) w osobnym watku: szukanie trwa zwykle 1-3 min.
# Zapytanie idzie do Windows Update tylko po kliknieciu "Sprawdz", nigdy przy starcie.
$script:Sterowniki = $null          # $null = jeszcze nie sprawdzano
$script:UrzadzeniaZProblemem = @()

# Wersja z tytulu aktualizacji, np. "Intel Corporation - Display - 31.0.101.4502"
function WersjaZTytulu([string]$t) { if ($t -match '(\d+(\.\d+){1,3})\s*$') { $Matches[1] } else { '' } }

function OpisProblemu([int]$kod) {
    switch ($kod) {
        28 { L 'brak sterownika' 'no driver installed' }
        10 { L 'urządzenie nie może się uruchomić (kod 10)' 'the device cannot start (code 10)' }
        43 { L 'urządzenie zgłosiło problem (kod 43)' 'the device reported a problem (code 43)' }
        { $_ -in 1, 18, 31, 39, 52 } { (L 'sterownik nie działa poprawnie (kod {0})' 'the driver does not work properly (code {0})') -f $kod }
        default { (L 'problem z urządzeniem (kod {0})' 'device problem (code {0})') -f $kod }
    }
}

# Urzadzenia z bledem w Menedzerze urzadzen. Pomijamy wylaczone (22) i odlaczone (24, 45).
function UrzadzeniaZProblemem {
    @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -notin 0, 22, 24, 45 -and $_.Present -ne $false } |
            ForEach-Object { @{ Nazwa = $(if ($_.Name) { $_.Name } else { $_.DeviceID }); Id = $_.DeviceID; Kod = [int]$_.ConfigManagerErrorCode; Opis = (OpisProblemu $_.ConfigManagerErrorCode) } })
}

# Szuka nowszych sterownikow i dopasowuje je do urzadzen (obecna wersja i data). Zwraca liczbe znalezionych.
function SzukajSterownikow {
    Log 'Sterowniki: szukanie w Windows Update'
    $znalezione = @(CzekajNa {
            $sesja = New-Object -ComObject Microsoft.Update.Session
            $sesja.ClientApplicationID = 'LLMCleaner'
            $sz = $sesja.CreateUpdateSearcher()
            $sz.ServerSelection = 2   # Windows Update, takze na komputerze z WSUS
            foreach ($u in $sz.Search("IsInstalled=0 and Type='Driver' and IsHidden=0").Updates) {
                [pscustomobject]@{ Id = $u.Identity.UpdateID; Tytul = $u.Title; Model = $u.DriverModel; Dostawca = $u.DriverProvider
                    Klasa = $u.DriverClass; Data = $u.DriverVerDate; HwId = $u.DriverHardwareID; Bajty = [double]$u.MaxDownloadSize
                }
            }
        } | Where-Object { $_ })

    # Urzadzenie po identyfikatorze sprzetu (najpierw HardwareID, potem CompatibleID) i jego obecny sterownik
    $sterUrz = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver) { if ($d.DeviceID) { $sterUrz[$d.DeviceID] = $d } }
    $urz = @{}
    $encje = @(Get-CimInstance Win32_PnPEntity)
    foreach ($pole in 'HardwareID', 'CompatibleID') {
        foreach ($e in $encje) { foreach ($h in @($e.$pole)) { if ($h -and -not $urz.ContainsKey($h.ToLower())) { $urz[$h.ToLower()] = $e } } }
    }

    $script:Sterowniki = @(foreach ($z in $znalezione) {
            $e = if ($z.HwId) { $urz["$($z.HwId)".ToLower()] }
            $obecny = if ($e) { $sterUrz[$e.DeviceID] }
            $problem = if ($e -and $e.ConfigManagerErrorCode -notin 0, 22) { OpisProblemu $e.ConfigManagerErrorCode }
            @{ Id = $z.Id; Tytul = $z.Tytul; Nazwa = $(if ($e -and $e.Name) { $e.Name } elseif ($z.Model) { $z.Model } else { $z.Tytul })
                Model = $z.Model; Dostawca = $z.Dostawca; Klasa = $z.Klasa; Bajty = $z.Bajty
                Wersja = (WersjaZTytulu $z.Tytul); Data = $z.Data
                ObecnaWersja = $obecny.DriverVersion; ObecnaData = $obecny.DriverDate; Problem = $problem
                Wybrana = $true; Stan = 'nowy'; Blad = ''
            }
        })
    $script:UrzadzeniaZProblemem = UrzadzeniaZProblemem
    Log "Sterowniki: $(($script:Sterowniki | ForEach-Object { "$($_.Tytul) [$($_.ObecnaWersja)]" }) -join ', ')"
    Log "Urzadzenia z problemem: $(($script:UrzadzeniaZProblemem | ForEach-Object { "$($_.Nazwa) ($($_.Kod))" }) -join ', ')"
    $script:Sterowniki.Count
}

function DataSterownika($d) { if ($d -is [datetime] -and $d -gt [datetime]'1990-01-01') { $d.ToString('yyyy-MM-dd') } else { '' } }
function OpisWersji([string]$wersja, $data) {
    $dd = DataSterownika $data
    if ($wersja -and $dd) { "$wersja ($dd)" } elseif ($wersja) { $wersja } else { $dd }
}

function NazwaStanuSterownika([string]$stan) {
    switch ($stan) {
        'nowy' { L 'dostępny' 'available' }
        'czeka' { L 'czeka' 'waiting' }
        'szukanie' { L 'przygotowanie' 'preparing' }
        'pobieranie' { L 'pobieranie' 'downloading' }
        'instalacja' { L 'instalacja' 'installing' }
        'ok' { L 'zainstalowany' 'installed' }
        'restart' { L 'po restarcie' 'after restart' }
        'brak' { L 'już niedostępny' 'no longer offered' }
        default { L 'błąd' 'failed' }
    }
}

# Instaluje sterowniki po kolei (pobranie i instalacja przez Windows Update). Stan kazdego idzie do
# $stan (zsynchronizowana tablica: Id -> szukanie, pobieranie, instalacja, ok, restart, brak, blad:...),
# ktora okno odczytuje w trakcie. Zwraca liczbe zainstalowanych.
function ZainstalujSterowniki($lista, [hashtable]$stan) {
    $lista = @($lista)
    if (-not $lista.Count) { return 0 }
    foreach ($s in $lista) { $stan[$s.Id] = 'szukanie' }
    Log "Sterowniki: instalacja $(($lista | ForEach-Object { $_.Tytul }) -join ', ')"
    try {
        CzekajNa {
            param($ids, $stan)
            $sesja = New-Object -ComObject Microsoft.Update.Session
            $sesja.ClientApplicationID = 'LLMCleaner'
            $sz = $sesja.CreateUpdateSearcher()
            $sz.ServerSelection = 2
            $dostepne = @{}
            foreach ($u in $sz.Search("IsInstalled=0 and Type='Driver'").Updates) { $dostepne[$u.Identity.UpdateID] = $u }
            foreach ($id in $ids) { if (-not $dostepne[$id]) { $stan[$id] = 'brak' } else { $stan[$id] = 'czeka' } }
            foreach ($id in $ids) {
                $u = $dostepne[$id]
                if (-not $u) { continue }
                try {
                    if (-not $u.EulaAccepted) { $u.AcceptEula() }
                    $kol = New-Object -ComObject Microsoft.Update.UpdateColl
                    [void]$kol.Add($u)
                    $stan[$id] = 'pobieranie'
                    $pob = $sesja.CreateUpdateDownloader(); $pob.Updates = $kol
                    $rp = $pob.Download()
                    if ($rp.ResultCode -notin 2, 3) { $stan[$id] = 'blad:' + ('0x{0:X8}' -f $rp.GetUpdateResult(0).HResult); continue }
                    $stan[$id] = 'instalacja'
                    $inst = $sesja.CreateUpdateInstaller(); $inst.Updates = $kol
                    $ri = $inst.Install()
                    $stan[$id] = if ($ri.ResultCode -in 2, 3) { if ($ri.RebootRequired) { 'restart' } else { 'ok' } }
                    else { 'blad:' + ('0x{0:X8}' -f $ri.GetUpdateResult(0).HResult) }
                }
                catch { $stan[$id] = 'blad:' + $_.Exception.Message }
            }
        } @(@($lista | ForEach-Object { $_.Id }), $stan) | Out-Null
    }
    catch {
        Log "Sterowniki: blad instalacji: $($_.Exception.Message)"
        foreach ($s in $lista) { if ($stan[$s.Id] -in 'szukanie', 'czeka') { $stan[$s.Id] = 'blad:' + $_.Exception.Message } }
    }
    $n = 0
    foreach ($s in $lista) {
        $w = "$($stan[$s.Id])"
        if ($w -like 'blad:*') { $s.Stan = 'blad'; $s.Blad = $w.Substring(5) } else { $s.Stan = $w }
        if ($s.Stan -in 'ok', 'restart') { $n++; $s.Wybrana = $false }
        Log "Sterownik $($s.Tytul): $w"
    }
    $n
}
