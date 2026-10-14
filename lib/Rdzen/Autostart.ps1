<#
    LLMCleaner - martwe wpisy startowe, menedzer autostartu i opisy AI wpisow
#>

# Wskazuja na program, ktorego juz nie ma. Liczy sie tylko pewny brak: sciezka bezwzgledna na dysku,
# ktory istnieje (odlaczony dysk USB to nie martwy wpis), poza folderem Windows (przekierowanie
# System32/SysWOW64 dawaloby falszywe braki) i poza udzialami sieciowymi.
function BrakujacyPlik([string]$p) {
    if (-not $p -or $p.StartsWith('\\') -or -not [IO.Path]::IsPathRooted($p)) { return $false }
    if ($p -like "$WinDir\*") { return $false }
    try { if (-not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($p)))) { return $false } } catch { return $false }
    if (Test-Path -LiteralPath $p) { return $false }
    # Skroty 32-bitowych programow potrafia zwracac Program Files zamiast Program Files (x86) i odwrotnie
    if ($p -match '\\Program Files\\' -and (Test-Path -LiteralPath ($p -replace '\\Program Files\\', '\Program Files (x86)\'))) { return $false }
    if ($p -match '\\Program Files \(x86\)\\' -and (Test-Path -LiteralPath ($p -replace '\\Program Files \(x86\)\\', '\Program Files\'))) { return $false }
    $true
}

# Klucze Run z ich odpowiednikami StartupApproved (tam Windows i Menedzer zadan zapisuja wylaczenie)
$AutostartKlucz = 'Software\Microsoft\Windows\CurrentVersion'
function KluczeRun {
    @{ Klucz = "$HKCUNazwa\$AutostartKlucz\Run"; Zgoda = "$HKCUNazwa\$AutostartKlucz\Explorer\StartupApproved\Run"; Zrodlo = (L 'Rejestr (użytkownik)' 'Registry (user)') }
    @{ Klucz = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Run"; Zgoda = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Explorer\StartupApproved\Run"; Zrodlo = (L 'Rejestr (wszyscy)' 'Registry (all users)') }
    @{ Klucz = "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Zgoda = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Explorer\StartupApproved\Run32"; Zrodlo = (L 'Rejestr (wszyscy, 32-bit)' 'Registry (all users, 32-bit)') }
}
function FolderyAutostartu {
    @{ Folder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Zgoda = "$HKCUNazwa\$AutostartKlucz\Explorer\StartupApproved\StartupFolder"; Zrodlo = (L 'Folder Autostart (użytkownik)' 'Startup folder (user)') }
    @{ Folder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"; Zgoda = "HKEY_LOCAL_MACHINE\$AutostartKlucz\Explorer\StartupApproved\StartupFolder"; Zrodlo = (L 'Folder Autostart (wszyscy)' 'Startup folder (all users)') }
}

# Zadania Harmonogramu poza \Microsoft\ (tamte sa czescia Windows)
function ZadaniaInnychFirm { Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } }
function ProgramyZadania($t) { @($t.Actions | Where-Object { $_.Execute } | ForEach-Object { SciezkaPliku $_.Execute }) }

function MartweAutostarty {
    foreach ($r in KluczeRun) {
        $k = Get-Item -LiteralPath "Registry::$($r.Klucz)"
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            try {
                if (-not $n) { continue }
                $cel = SciezkaPliku ([string]$k.GetValue($n))
                if (-not (BrakujacyPlik $cel)) { continue }
                @{ Typ = 'wartosc'; Sciezka = $r.Klucz; Wartosc = $n; Nazwa = $n; Bajty = 0.0; Pewnosc = 'wysoka'
                    Dlaczego = ((L 'Martwy wpis autostartu: program {0} nie istnieje.' 'Dead startup entry: the program {0} no longer exists.') -f $cel)
                }
            }
            catch { BladSkanu "autostart $($r.Klucz)\$n" $_ }
        }
    }

    # Skroty: w Autostarcie i menu Start pewne, na pulpicie srednie (moze je ktos sam zrobil)
    $sh = New-Object -ComObject WScript.Shell
    $miejsca = @(FolderyAutostartu | ForEach-Object { @{ D = $_.Folder; P = 'wysoka'; Rek = $false } }) + @(
        @{ D = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"; P = 'wysoka'; Rek = $true }
        @{ D = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"; P = 'wysoka'; Rek = $true }
        @{ D = (FolderUzytkownika 'Desktop' "$env:USERPROFILE\Desktop"); P = 'srednia'; Rek = $false }
        @{ D = "$env:PUBLIC\Desktop"; P = 'srednia'; Rek = $false })
    $widziane = @{}
    foreach ($m in $miejsca) {
        foreach ($l in Get-ChildItem -LiteralPath $m.D -Filter *.lnk -Force -File -Recurse:$m.Rek) {
            try {
                if ($widziane[$l.FullName]) { continue }
                $widziane[$l.FullName] = 1
                $cel = $sh.CreateShortcut($l.FullName).TargetPath   # pusty u skrotow MSI i aplikacji ze Sklepu
                if (-not (BrakujacyPlik $cel)) { continue }
                @{ Typ = 'plik'; Sciezka = $l.FullName; Nazwa = $l.BaseName; Bajty = [double]$l.Length; Ostatnio = $l.LastWriteTime; Pewnosc = $m.P
                    Dlaczego = ((L 'Skrót do programu, którego już nie ma ({0}).' 'Shortcut to a program that no longer exists ({0}).') -f $cel)
                }
            }
            catch { BladSkanu "skrot $($l.FullName)" $_ }
        }
    }

    # Zadania: martwe, gdy zaden z ich programow nie istnieje
    foreach ($t in ZadaniaInnychFirm) {
        try {
            $progs = ProgramyZadania $t
            if (-not $progs.Count -or @($progs | Where-Object { -not (BrakujacyPlik $_) }).Count) { continue }
            @{ Typ = 'zadanie'; Sciezka = "$($t.TaskPath)$($t.TaskName)"; Nazwa = $t.TaskName; Folder = $t.TaskPath; Bajty = 0.0; Pewnosc = 'wysoka'
                Dlaczego = ((L 'Zadanie Harmonogramu uruchamia program, którego już nie ma ({0}).' 'Scheduled task runs a program that no longer exists ({0}).') -f ($progs -join ', '))
            }
        }
        catch { BladSkanu "zadanie $($t.TaskPath)$($t.TaskName)" $_ }
    }
}

# Programy uruchamiane przy logowaniu. Niczego tu nie usuwamy: wpisy Run i folderu Autostart wylaczamy
# tak jak Menedzer zadan (wartosc w StartupApproved, nieparzysty pierwszy bajt = wylaczony), zadania
# Harmonogramu - Disable-ScheduledTask. Wlaczenie przywraca dokladnie poprzedni stan.

# Ochrona, sterowniki i panele sprzetu: wylaczenie potrafi zepsuc touchpad, dzwiek albo ochrone
$ChronioneAutostart = @('securityhealth*', '*defender*', 'msmpeng*', '*antivirus*', 'avast*', 'avg*', 'egui*', 'eset*',
    'avp*', 'kaspersky*', 'bdagent*', 'bitdefender*', 'norton*', 'mcafee*', 'mbam*', 'malwarebytes*', 'sophos*',
    'rthdvcpl*', 'rtkaud*', 'rtkngui*', 'realtek*', 'igfx*', 'synaptics*', 'syntp*', 'etdctrl*', 'elan*', 'waves*',
    'maxxaudio*', 'dolby*')
$script:Autostart = $null

function OchronaAutostartu($w) {
    if ($w.Plik -like "$WinDir\*") { return L 'część Windows' 'part of Windows' }
    foreach ($x in @($w.Nazwa, $(if ($w.Plik) { [IO.Path]::GetFileNameWithoutExtension($w.Plik) })) | Where-Object { $_ }) {
        foreach ($wz in $ChronioneAutostart) {
            if ($x -like $wz) { return L 'ochrona, sterownik albo panel sprzętu - wyłączenie może coś zepsuć' 'security software, a driver or a hardware panel - turning it off may break something' }
        }
    }
    if ($w.Nazwa -match 'update') { return L 'aktualizacje programu - bez nich nie dostanie poprawek bezpieczeństwa' 'program updates - without them it gets no security fixes' }
    $null
}

function WpisAutostartu([hashtable]$w) {
    $w.Istnieje = [bool]($w.Plik -and (Test-Path -LiteralPath $w.Plik))
    # Martwy tak samo jak w planie (MartweAutostarty): pusty cel skrotu MSI albo sciezka bez dysku to nie martwy wpis
    if ($null -eq $w.Martwy) { $w.Martwy = [bool](BrakujacyPlik $w.Plik) }
    $w.Wydawca = if ($w.Istnieje) { (Get-Item -LiteralPath $w.Plik -Force).VersionInfo.CompanyName } else { '' }
    $w.Chroniony = OchronaAutostartu $w
    $w
}

# Wylaczony przez uzytkownika (Menedzer zadan, Ustawienia > Aplikacje > Uruchamianie albo LLMCleaner)
function StanZgody([string]$klucz, [string]$nazwa) {
    $b = (Get-ItemProperty -LiteralPath "Registry::$klucz" -Name $nazwa).$nazwa
    -not ($b -is [byte[]] -and $b.Length -and ($b[0] -band 1))
}
function UstawZgode([string]$klucz, [string]$nazwa, [bool]$wlacz) {
    if (-not (Test-Path -LiteralPath "Registry::$klucz")) { New-Item -Path "Registry::$klucz" -Force -ErrorAction Stop | Out-Null }
    $b = [byte[]]::new(12)
    if ($wlacz) { $b[0] = 2 } else { $b[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4) }
    Set-ItemProperty -LiteralPath "Registry::$klucz" -Name $nazwa -Value $b -Type Binary -ErrorAction Stop
}

function WpisyAutostartu {
    $wyn = [System.Collections.Generic.List[object]]::new()
    foreach ($r in KluczeRun) {
        $k = Get-Item -LiteralPath "Registry::$($r.Klucz)"
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            try {
                if (-not $n) { continue }
                $pol = [string]$k.GetValue($n)
                $wyn.Add((WpisAutostartu @{ Rodzaj = 'run'; Nazwa = $n; Polecenie = $pol; Plik = (SciezkaPliku $pol); Zrodlo = $r.Zrodlo; Klucz = $r.Klucz
                            Zgoda = $r.Zgoda; ZgodaNazwa = $n; Wlaczony = (StanZgody $r.Zgoda $n)
                        }))
            }
            catch { BladSkanu "autostart $($r.Klucz)\$n" $_ }
        }
    }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($f in FolderyAutostartu) {
        foreach ($l in Get-ChildItem -LiteralPath $f.Folder -File -Force | Where-Object { $_.Name -ne 'desktop.ini' }) {
            try {
                $cel = if ($l.Extension -eq '.lnk') { $sh.CreateShortcut($l.FullName).TargetPath } else { $l.FullName }
                $wyn.Add((WpisAutostartu @{ Rodzaj = 'folder'; Nazwa = $l.BaseName; Polecenie = $l.FullName; Plik = $cel; Zrodlo = $f.Zrodlo
                            Zgoda = $f.Zgoda; ZgodaNazwa = $l.Name; Wlaczony = (StanZgody $f.Zgoda $l.Name)
                        }))
            }
            catch { BladSkanu "autostart $($l.FullName)" $_ }
        }
    }
    foreach ($t in ZadaniaInnychFirm) {
        try {
            if (-not @($t.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' }).Count) { continue }
            $progs = ProgramyZadania $t
            $wyn.Add((WpisAutostartu @{ Rodzaj = 'zadanie'; Nazwa = $t.TaskName; Folder = $t.TaskPath; Plik = $(if ($progs.Count) { $progs[0] })
                        Martwy = [bool]($progs.Count -and -not @($progs | Where-Object { -not (BrakujacyPlik $_) }).Count)
                        Polecenie = (@($t.Actions | Where-Object { $_.Execute } | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; ')
                        Zrodlo = (L 'Harmonogram zadań' 'Task Scheduler'); Wlaczony = ($t.State -ne 'Disabled')
                    }))
        }
        catch { BladSkanu "zadanie $($t.TaskPath)$($t.TaskName)" $_ }
    }
    $n = 0; foreach ($w in $wyn) { $n++; $w.Id = "S$n" }
    Log ("Autostart: {0} wpisow, wlaczonych {1}" -f $wyn.Count, @($wyn | Where-Object { $_.Wlaczony }).Count)
    $script:Autostart = $wyn.ToArray()
    $script:Rozmowa = $null   # nowe dane dla czatu
    $script:Autostart
}

function PrzelaczAutostart($w, [bool]$wlacz) {
    if ($w.Chroniony) { throw ((L '{0}: nie zmieniam ({1})' '{0}: not changed ({1})') -f $w.Nazwa, $w.Chroniony) }
    if ($w.Rodzaj -eq 'zadanie') {
        if ($wlacz) { Enable-ScheduledTask -TaskName $w.Nazwa -TaskPath $w.Folder -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskName $w.Nazwa -TaskPath $w.Folder -ErrorAction Stop | Out-Null }
    }
    else { UstawZgode $w.Zgoda $w.ZgodaNazwa $wlacz }
    $w.Wlaczony = $wlacz
    $script:Rozmowa = $null
    Log ("Autostart {0}: {1} ({2}, {3})" -f $(if ($wlacz) { 'wlaczony' } else { 'wylaczony' }), $w.Nazwa, $w.Zrodlo, $w.Polecenie)
}

# Usuwa wpis autostartu na stale, z kopia: wartosc Run - .reg, skrot - do Kosza, zadanie - .xml.
# Zwraca opis, gdzie jest kopia.
function UsunAutostart($w) {
    if ($w.Chroniony) { throw ((L '{0}: nie usuwam ({1})' '{0}: not removed ({1})') -f $w.Nazwa, $w.Chroniony) }
    $kopie = Join-Path $LogDir ("kopie_rejestru\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    $bezp = $w.Nazwa -replace '[^\w\-\. ]', '_'
    switch ($w.Rodzaj) {
        'run' {
            New-Item -ItemType Directory -Force $kopie | Out-Null
            $plik = Join-Path $kopie ("autostart_{0}.reg" -f $bezp)
            KopiaWartosci $w.Klucz $w.Nazwa $plik
            Remove-ItemProperty -LiteralPath "Registry::$($w.Klucz)" -Name $w.Nazwa -Force -ErrorAction Stop
            $gdzie = $plik
        }
        'folder' {
            Add-Type -AssemblyName Microsoft.VisualBasic
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($w.Polecenie, 'OnlyErrorDialogs', 'SendToRecycleBin')
            $gdzie = L 'Kosz' 'Recycle Bin'
        }
        'zadanie' {
            New-Item -ItemType Directory -Force $kopie | Out-Null
            $plik = Join-Path $kopie ("autostart_{0}.xml" -f $bezp)
            $xml = Export-ScheduledTask -TaskName $w.Nazwa -TaskPath $w.Folder
            if (-not $xml) { throw (L 'nie udało się zrobić kopii - zadanie zostawione' 'backup failed - task kept') }
            [IO.File]::WriteAllText($plik, $xml, [Text.Encoding]::Unicode)
            Unregister-ScheduledTask -TaskName $w.Nazwa -TaskPath $w.Folder -Confirm:$false -ErrorAction Stop
            $gdzie = $plik
        }
    }
    # Stan wl./wyl. z Menedzera zadan nie jest juz potrzebny
    if ($w.Zgoda) { Remove-ItemProperty -LiteralPath "Registry::$($w.Zgoda)" -Name $w.ZgodaNazwa -Force }
    $script:Autostart = @($script:Autostart | Where-Object { $_ -ne $w })
    $script:Rozmowa = $null
    Log ("Autostart usuniety: {0} ({1}, {2}), kopia: {3}" -f $w.Nazwa, $w.Zrodlo, $w.Polecenie, $gdzie)
    $gdzie
}

# Kopia jednej wartosci rejestru jako .reg - dwuklik przywraca tylko ja, a nie caly klucz Run.
# Nietypowe rodzaje (binarne, liczby) eksportuje reg.exe razem z kluczem.
function KopiaWartosci([string]$klucz, [string]$nazwa, [string]$plik) {
    $k = Get-Item -LiteralPath "Registry::$klucz" -ErrorAction Stop
    $rodzaj = $k.GetValueKind($nazwa)
    $tekst = [string]$k.GetValue($nazwa, $null, 'DoNotExpandEnvironmentNames')
    $n = $nazwa.Replace('\', '\\').Replace('"', '\"')
    $wpis = switch ($rodzaj) {
        'String' { '"{0}"="{1}"' -f $n, $tekst.Replace('\', '\\').Replace('"', '\"') }
        'ExpandString' { '"{0}"=hex(2):{1}' -f $n, (([Text.Encoding]::Unicode.GetBytes($tekst) + 0, 0 | ForEach-Object { '{0:x2}' -f $_ }) -join ',') }
        default { $null }
    }
    if ($wpis) {
        [IO.File]::WriteAllText($plik, "Windows Registry Editor Version 5.00`r`n`r`n[$klucz]`r`n$wpis`r`n", [Text.Encoding]::Unicode)
    }
    else { & reg.exe export $klucz $plik /y 2>&1 | Out-Null }
    if (-not (Test-Path -LiteralPath $plik)) { throw (L 'nie udało się zrobić kopii - wpis zostawiony' 'backup failed - entry kept') }
}

# Jak w analizie dysku: rada tylko z tej listy, a dla wpisow chronionych ustala ja program
$RadyAutostartu = if ($Jezyk -eq 'en') {
    @('keep it on', 'can be turned off - start it by hand when needed', 'check whether you use it')
}
else {
    @('zostaw włączone', 'można wyłączyć - uruchomisz ręcznie, gdy potrzebne', 'sprawdź, czy go używasz')
}

$SchematAutostartu = @{
    type       = 'object'
    properties = @{
        pozycje = @{ type = 'array'; items = @{ type = 'object'
                properties                           = @{ id = @{ type = 'string' }; opis = @{ type = 'string' }; rada = @{ type = 'string'; enum = $RadyAutostartu } }
                required                             = @('id', 'opis', 'rada')
            }
        }
    }
    required   = @('pozycje')
}

$SysAutostart = if ($Jezyk -eq 'en') {
    @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of programs that start when the user signs in
(name, command, publisher, source). For EACH item give:
- "opis": what the program is and why it starts with Windows - based on the name, command and publisher,
- "rada": one of the allowed values.
Rules:
- Chat apps, game launchers, cloud storage clients, update helpers of apps the user opens by hand and
  "helper"/"tray" tools usually do not need to start with Windows: "can be turned off - start it by hand when needed".
- Security software, drivers, audio, touchpad, keyboard or graphics panels: "keep it on".
- If you do not know the program, write "unknown program" and choose "check whether you use it".
- Do not invent program names that are not in the data. Description max. 12 words, in English.
'@
}
else {
    @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę programów uruchamianych przy logowaniu
(nazwa, polecenie, wydawca, źródło). Dla KAŻDEJ pozycji podaj:
- "opis": czym jest program i po co startuje z Windows - na podstawie nazwy, polecenia i wydawcy,
- "rada": jedna z dozwolonych wartości.
Zasady:
- Komunikatory, launchery gier, klienty chmury, pomocniki aplikacji otwieranych ręcznie i narzędzia
  w zasobniku zwykle nie muszą startować z Windows: "można wyłączyć - uruchomisz ręcznie, gdy potrzebne".
- Ochrona antywirusowa, sterowniki, panele dźwięku, touchpada, klawiatury i grafiki: "zostaw włączone".
- Jeśli nie znasz programu, napisz "nieznany program" i wybierz "sprawdź, czy go używasz".
- Nie zmyślaj nazw programów, których nie ma w danych. Opis maks. 12 słów, po polsku.
'@
}

# Opisy i rady modelu dla autostartu. Zwraca liczbe opisanych pozycji (albo -1 przy bledzie).
function AutostartAi($wpisy) {
    if (-not @($wpisy).Count) { return 0 }
    if (-not (ZapewnijModel)) { return -1 }
    $lista = @($wpisy | ForEach-Object { @{ id = $_.Id; nazwa = $_.Nazwa; polecenie = $_.Polecenie; wydawca = $_.Wydawca; zrodlo = $_.Zrodlo } })
    Wypisz ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $lista.Count) 'DarkGray'
    try {
        $odp = Ollama @(@{ role = 'system'; content = $SysAutostart },
            @{ role = 'user'; content = (ConvertTo-Json -InputObject $lista -Depth 5 -Compress) }) $SchematAutostartu
        $n = 0
        foreach ($o in @(($odp | ConvertFrom-Json -ErrorAction Stop).pozycje)) {
            $w = $wpisy | Where-Object { $_.Id -eq $o.id } | Select-Object -First 1
            if ($w -and $o.opis) {
                $rada = if ($w.Chroniony) { $RadyAutostartu[0] } elseif ($o.rada -in $RadyAutostartu) { $o.rada } else { $RadyAutostartu[2] }
                $w.Ai = "$($o.opis.Trim().TrimEnd('.;')). $(L 'Rada' 'Advice'): $rada."; $n++
            }
        }
        Wypisz ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        Log "Autostart - opisy modelu: $odp"
        $script:Rozmowa = $null
        $n
    }
    catch { Wypisz ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}
