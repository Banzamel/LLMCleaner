<#
    LLMCleaner - dead startup entries (programs that no longer exist)
#>

# Points to a program that no longer exists. Only a certain absence counts: an absolute path on a drive
# that exists (an unplugged USB drive is not a dead entry), outside the Windows folder (System32/SysWOW64
# redirection would give false misses) and outside network shares.
function Test-MissingFile([string]$p) {
    if (-not $p -or $p.StartsWith('\\') -or -not [IO.Path]::IsPathRooted($p)) { return $false }
    if ($p -like "$WinDir\*") { return $false }
    try { if (-not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($p)))) { return $false } } catch { return $false }
    if (Test-Path -LiteralPath $p) { return $false }
    # Shortcuts of 32-bit programs may return Program Files instead of Program Files (x86) and vice versa
    if ($p -match '\\Program Files\\' -and (Test-Path -LiteralPath ($p -replace '\\Program Files\\', '\Program Files (x86)\'))) { return $false }
    if ($p -match '\\Program Files \(x86\)\\' -and (Test-Path -LiteralPath ($p -replace '\\Program Files \(x86\)\\', '\Program Files\'))) { return $false }
    $true
}

# Run keys with their StartupApproved counterparts (where Windows and Task Manager store the disabled state)
$StartupKeyBase = 'Software\Microsoft\Windows\CurrentVersion'
function Get-RunKeys {
    @{ RegKey = "$HKCUName\$StartupKeyBase\Run"; ApprovedKey = "$HKCUName\$StartupKeyBase\Explorer\StartupApproved\Run"; Source = (L 'Rejestr (użytkownik)' 'Registry (user)') }
    @{ RegKey = "HKEY_LOCAL_MACHINE\$StartupKeyBase\Run"; ApprovedKey = "HKEY_LOCAL_MACHINE\$StartupKeyBase\Explorer\StartupApproved\Run"; Source = (L 'Rejestr (wszyscy)' 'Registry (all users)') }
    @{ RegKey = "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; ApprovedKey = "HKEY_LOCAL_MACHINE\$StartupKeyBase\Explorer\StartupApproved\Run32"; Source = (L 'Rejestr (wszyscy, 32-bit)' 'Registry (all users, 32-bit)') }
}
function Get-StartupFolders {
    @{ Folder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; ApprovedKey = "$HKCUName\$StartupKeyBase\Explorer\StartupApproved\StartupFolder"; Source = (L 'Folder Autostart (użytkownik)' 'Startup folder (user)') }
    @{ Folder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"; ApprovedKey = "HKEY_LOCAL_MACHINE\$StartupKeyBase\Explorer\StartupApproved\StartupFolder"; Source = (L 'Folder Autostart (wszyscy)' 'Startup folder (all users)') }
}

# Task Scheduler tasks outside \Microsoft\ (those are part of Windows)
function Get-ThirdPartyTasks { Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } }
function Get-TaskPrograms($t) { @($t.Actions | Where-Object { $_.Execute } | ForEach-Object { Get-CommandPath $_.Execute }) }

function Find-DeadStartupEntries {
    foreach ($r in Get-RunKeys) {
        $k = Get-Item -LiteralPath "Registry::$($r.RegKey)"
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            try {
                if (-not $n) { continue }
                $target = Get-CommandPath ([string]$k.GetValue($n))
                if (-not (Test-MissingFile $target)) { continue }
                @{ Type = 'regvalue'; Path = $r.RegKey; ValueName = $n; Name = $n; Bytes = 0.0; Confidence = 'high'
                    Reason = ((L 'Martwy wpis autostartu: program {0} nie istnieje.' 'Dead startup entry: the program {0} no longer exists.') -f $target)
                }
            }
            catch { Add-ScanError "startup $($r.RegKey)\$n" $_ }
        }
    }

    # Shortcuts: certain in Startup folder and Start menu, medium on the desktop (someone may have made them)
    $sh = New-Object -ComObject WScript.Shell
    $places = @(Get-StartupFolders | ForEach-Object { @{ D = $_.Folder; P = 'high'; Recurse = $false } }) + @(
        @{ D = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"; P = 'high'; Recurse = $true }
        @{ D = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"; P = 'high'; Recurse = $true }
        @{ D = (Get-UserShellFolder 'Desktop' "$env:USERPROFILE\Desktop"); P = 'medium'; Recurse = $false }
        @{ D = "$env:PUBLIC\Desktop"; P = 'medium'; Recurse = $false })
    $seen = @{}
    foreach ($m in $places) {
        foreach ($l in Get-ChildItem -LiteralPath $m.D -Filter *.lnk -Force -File -Recurse:$m.Recurse) {
            try {
                if ($seen[$l.FullName]) { continue }
                $seen[$l.FullName] = 1
                $target = $sh.CreateShortcut($l.FullName).TargetPath   # empty for MSI shortcuts and Store apps
                if (-not (Test-MissingFile $target)) { continue }
                @{ Type = 'file'; Path = $l.FullName; Name = $l.BaseName; Bytes = [double]$l.Length; LastWrite = $l.LastWriteTime; Confidence = $m.P
                    Reason = ((L 'Skrót do programu, którego już nie ma ({0}).' 'Shortcut to a program that no longer exists ({0}).') -f $target)
                }
            }
            catch { Add-ScanError "shortcut $($l.FullName)" $_ }
        }
    }

    # Tasks: dead when none of their programs exist
    foreach ($t in Get-ThirdPartyTasks) {
        try {
            $progs = Get-TaskPrograms $t
            if (-not $progs.Count -or @($progs | Where-Object { -not (Test-MissingFile $_) }).Count) { continue }
            @{ Type = 'task'; Path = "$($t.TaskPath)$($t.TaskName)"; Name = $t.TaskName; Folder = $t.TaskPath; Bytes = 0.0; Confidence = 'high'
                Reason = ((L 'Zadanie Harmonogramu uruchamia program, którego już nie ma ({0}).' 'Scheduled task runs a program that no longer exists ({0}).') -f ($progs -join ', '))
            }
        }
        catch { Add-ScanError "task $($t.TaskPath)$($t.TaskName)" $_ }
    }
}
