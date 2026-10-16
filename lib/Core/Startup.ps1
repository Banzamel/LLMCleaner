<#
    LLMCleaner - dead startup entries, startup manager and AI descriptions of entries
#>

# Programs started at sign-in. Nothing is deleted here: Run and Startup folder entries are disabled
# like Task Manager does (value in StartupApproved, odd first byte = disabled), Task Scheduler
# tasks via Disable-ScheduledTask. Enabling restores exactly the previous state.

# Security, drivers and hardware panels: disabling them can break the touchpad, sound or protection
$ProtectedStartup = @('securityhealth*', '*defender*', 'msmpeng*', '*antivirus*', 'avast*', 'avg*', 'egui*', 'eset*',
    'avp*', 'kaspersky*', 'bdagent*', 'bitdefender*', 'norton*', 'mcafee*', 'mbam*', 'malwarebytes*', 'sophos*',
    'rthdvcpl*', 'rtkaud*', 'rtkngui*', 'realtek*', 'igfx*', 'synaptics*', 'syntp*', 'etdctrl*', 'elan*', 'waves*',
    'maxxaudio*', 'dolby*')
$script:Startup = $null

function Get-StartupProtection($w) {
    if ($w.File -like "$WinDir\*") { return L 'część Windows' 'part of Windows' }
    foreach ($x in @($w.Name, $(if ($w.File) { [IO.Path]::GetFileNameWithoutExtension($w.File) })) | Where-Object { $_ }) {
        foreach ($pattern in $ProtectedStartup) {
            if ($x -like $pattern) { return L 'ochrona, sterownik albo panel sprzętu - wyłączenie może coś zepsuć' 'security software, a driver or a hardware panel - turning it off may break something' }
        }
    }
    if ($w.Name -match 'update') { return L 'aktualizacje programu - bez nich nie dostanie poprawek bezpieczeństwa' 'program updates - without them it gets no security fixes' }
    $null
}

function Complete-StartupEntry([hashtable]$w) {
    $w.Exists = [bool]($w.File -and (Test-Path -LiteralPath $w.File))
    # Dead the same way as in the plan (Find-DeadStartupEntries): an empty MSI shortcut target or a path without a drive is not dead
    if ($null -eq $w.Dead) { $w.Dead = [bool](Test-MissingFile $w.File) }
    $w.Publisher = if ($w.Exists) { (Get-Item -LiteralPath $w.File -Force).VersionInfo.CompanyName } else { '' }
    $w.Protected = Get-StartupProtection $w
    $w
}

# Disabled by the user (Task Manager, Settings > Apps > Startup or LLMCleaner)
function Test-StartupApproved([string]$key, [string]$name) {
    $b = (Get-ItemProperty -LiteralPath "Registry::$key" -Name $name).$name
    -not ($b -is [byte[]] -and $b.Length -and ($b[0] -band 1))
}
function Set-StartupApproved([string]$key, [string]$name, [bool]$enable) {
    if (-not (Test-Path -LiteralPath "Registry::$key")) { New-Item -Path "Registry::$key" -Force -ErrorAction Stop | Out-Null }
    $b = [byte[]]::new(12)
    if ($enable) { $b[0] = 2 } else { $b[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($b, 4) }
    Set-ItemProperty -LiteralPath "Registry::$key" -Name $name -Value $b -Type Binary -ErrorAction Stop
}

function Get-StartupEntries {
    $startupList = [System.Collections.Generic.List[object]]::new()
    foreach ($r in Get-RunKeys) {
        $k = Get-Item -LiteralPath "Registry::$($r.RegKey)"
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            try {
                if (-not $n) { continue }
                $command = [string]$k.GetValue($n)
                $startupList.Add((Complete-StartupEntry @{ Kind = 'run'; Name = $n; Command = $command; File = (Get-CommandPath $command); Source = $r.Source; RegKey = $r.RegKey
                            ApprovedKey = $r.ApprovedKey; ApprovedName = $n; IsEnabled = (Test-StartupApproved $r.ApprovedKey $n)
                        }))
            }
            catch { Add-ScanError "autostart $($r.RegKey)\$n" $_ }
        }
    }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($f in Get-StartupFolders) {
        foreach ($l in Get-ChildItem -LiteralPath $f.Folder -File -Force | Where-Object { $_.Name -ne 'desktop.ini' }) {
            try {
                $target = if ($l.Extension -eq '.lnk') { $sh.CreateShortcut($l.FullName).TargetPath } else { $l.FullName }
                $startupList.Add((Complete-StartupEntry @{ Kind = 'folder'; Name = $l.BaseName; Command = $l.FullName; File = $target; Source = $f.Source
                            ApprovedKey = $f.ApprovedKey; ApprovedName = $l.Name; IsEnabled = (Test-StartupApproved $f.ApprovedKey $l.Name)
                        }))
            }
            catch { Add-ScanError "autostart $($l.FullName)" $_ }
        }
    }
    foreach ($t in Get-ThirdPartyTasks) {
        try {
            if (-not @($t.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' }).Count) { continue }
            $progs = Get-TaskPrograms $t
            $startupList.Add((Complete-StartupEntry @{ Kind = 'task'; Name = $t.TaskName; Folder = $t.TaskPath; File = $(if ($progs.Count) { $progs[0] })
                        Dead = [bool]($progs.Count -and -not @($progs | Where-Object { -not (Test-MissingFile $_) }).Count)
                        Command = (@($t.Actions | Where-Object { $_.Execute } | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; ')
                        Source = (L 'Harmonogram zadań' 'Task Scheduler'); IsEnabled = ($t.State -ne 'Disabled')
                    }))
        }
        catch { Add-ScanError "task $($t.TaskPath)$($t.TaskName)" $_ }
    }
    $n = 0; foreach ($w in $startupList) { $n++; $w.Id = "S$n" }
    Write-Log ("Startup: {0} entries, {1} enabled" -f $startupList.Count, @($startupList | Where-Object { $_.IsEnabled }).Count)
    $script:Startup = $startupList.ToArray()
    $script:Conversation = $null   # new data for the chat
    $script:Startup
}

function Set-StartupEnabled($w, [bool]$enable) {
    if ($w.Protected) { throw ((L '{0}: nie zmieniam ({1})' '{0}: not changed ({1})') -f $w.Name, $w.Protected) }
    if ($w.Kind -eq 'task') {
        if ($enable) { Enable-ScheduledTask -TaskName $w.Name -TaskPath $w.Folder -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskName $w.Name -TaskPath $w.Folder -ErrorAction Stop | Out-Null }
    }
    else { Set-StartupApproved $w.ApprovedKey $w.ApprovedName $enable }
    $w.IsEnabled = $enable
    $script:Conversation = $null
    Write-Log ("Startup {0}: {1} ({2}, {3})" -f $(if ($enable) { 'enabled' } else { 'disabled' }), $w.Name, $w.Source, $w.Command)
}

# Removes a startup entry permanently, with a backup: Run value - .reg, shortcut - Recycle Bin, task - .xml.
# Returns a description of where the backup is.
function Remove-StartupEntry($w) {
    if ($w.Protected) { throw ((L '{0}: nie usuwam ({1})' '{0}: not removed ({1})') -f $w.Name, $w.Protected) }
    $backups = Join-Path $LogDir ("kopie_rejestru\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    $safeName = $w.Name -replace '[^\w\-\. ]', '_'
    switch ($w.Kind) {
        'run' {
            New-Item -ItemType Directory -Force $backups | Out-Null
            $file = Join-Path $backups ("autostart_{0}.reg" -f $safeName)
            Backup-RegistryValue $w.RegKey $w.Name $file
            Remove-ItemProperty -LiteralPath "Registry::$($w.RegKey)" -Name $w.Name -Force -ErrorAction Stop
            $backupPlace = $file
        }
        'folder' {
            Add-Type -AssemblyName Microsoft.VisualBasic
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($w.Command, 'OnlyErrorDialogs', 'SendToRecycleBin')
            $backupPlace = L 'Kosz' 'Recycle Bin'
        }
        'task' {
            New-Item -ItemType Directory -Force $backups | Out-Null
            $file = Join-Path $backups ("autostart_{0}.xml" -f $safeName)
            $xml = Export-ScheduledTask -TaskName $w.Name -TaskPath $w.Folder
            if (-not $xml) { throw (L 'nie udało się zrobić kopii - zadanie zostawione' 'backup failed - task kept') }
            [IO.File]::WriteAllText($file, $xml, [Text.Encoding]::Unicode)
            Unregister-ScheduledTask -TaskName $w.Name -TaskPath $w.Folder -Confirm:$false -ErrorAction Stop
            $backupPlace = $file
        }
    }
    # The Task Manager on/off state is no longer needed
    if ($w.ApprovedKey) { Remove-ItemProperty -LiteralPath "Registry::$($w.ApprovedKey)" -Name $w.ApprovedName -Force }
    $script:Startup = @($script:Startup | Where-Object { $_ -ne $w })
    $script:Conversation = $null
    Write-Log ("Startup entry removed: {0} ({1}, {2}), backup: {3}" -f $w.Name, $w.Source, $w.Command, $backupPlace)
    $backupPlace
}

# Backs up one registry value as .reg - a double-click restores only it, not the whole Run key.
# Unusual types (binary, numbers) are exported by reg.exe together with the key.
function Backup-RegistryValue([string]$key, [string]$name, [string]$file) {
    $k = Get-Item -LiteralPath "Registry::$key" -ErrorAction Stop
    $kind = $k.GetValueKind($name)
    $text = [string]$k.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
    $n = $name.Replace('\', '\\').Replace('"', '\"')
    $entry = switch ($kind) {
        'String' { '"{0}"="{1}"' -f $n, $text.Replace('\', '\\').Replace('"', '\"') }
        'ExpandString' { '"{0}"=hex(2):{1}' -f $n, (([Text.Encoding]::Unicode.GetBytes($text) + 0, 0 | ForEach-Object { '{0:x2}' -f $_ }) -join ',') }
        default { $null }
    }
    if ($entry) {
        [IO.File]::WriteAllText($file, "Windows Registry Editor Version 5.00`r`n`r`n[$key]`r`n$entry`r`n", [Text.Encoding]::Unicode)
    }
    else { & reg.exe export $key $file /y 2>&1 | Out-Null }
    if (-not (Test-Path -LiteralPath $file)) { throw (L 'nie udało się zrobić kopii - wpis zostawiony' 'backup failed - entry kept') }
}
