<#
    LLMCleaner - leftovers of uninstalled programs and games (folders, files, registry, Steam, Epic)
#>

function Get-ConfidenceName([string]$p) {
    switch ($p) { 'high' { L 'wysoka' 'high' } 'medium' { L 'średnia' 'medium' } 'low' { L 'niska' 'low' } default { $p } }
}

# Leftovers: folders and files go to the Recycle Bin; registry keys/values and Task Scheduler tasks
# get a backup (.reg / .xml) and a restore point
function Test-GoesToRecycleBin($p) { $p.Type -in 'folder', 'file' }
function Format-LeftoverSize($p) {
    switch ($p.Type) { 'registry' { L 'rejestr' 'registry' } 'regvalue' { L 'rejestr' 'registry' } 'task' { L 'zadanie' 'task' } default { Format-Size $p.Bytes } }
}
function Format-Leftover($p) {
    if ($p.Type -eq 'task') { return "$(L 'Harmonogram zadań' 'Task Scheduler'): $($p.Path)" }
    if ($p.Type -in 'registry', 'regvalue' -and $p.Name -ne (Split-Path $p.Path -Leaf)) { return "$($p.Name)  [$($p.Path)]" }
    $p.Path
}

# Detection is cautious: a folder is listed only if it matches NO installed program,
# Store app, service, process or Start menu shortcut.
# Folders go to the Recycle Bin, registry keys are exported to .reg before deletion.
$CommonWords = @('app', 'apps', 'data', 'studio', 'software', 'soft', 'games', 'game', 'the', 'inc', 'ltd', 'llc',
    'gmbh', 'corp', 'corporation', 'company', 'technologies', 'technology', 'systems', 'group', 'limited', 'edition',
    'launcher', 'client', 'free', 'pro', 'update', 'updater', 'helper', 'service', 'services', 'tools', 'tool',
    'common', 'files', 'program', 'programs', 'user', 'local', 'roaming', 'cache', 'x64', 'x86', 'win', 'windows',
    'desktop', 'setup', 'install', 'installer', 'version', 'sro', 'foundation', 'entertainment', 'interactive', 'digital')

# System folders and keys, drivers and tools we never suggest
$SkippedNames = @('microsoft*', 'windows*', 'packages', 'temp', 'tmp', 'programs', 'package cache', 'common files',
    'installshield*', 'd3dscache', 'crashdumps', 'connecteddevicesplatform', 'peerdistrepub', 'placeholdertilelogofolder',
    'comms', 'publishers', 'virtualstore', 'isolatedstorage', 'elevateddiagnostics', 'squirreltemp', 'history',
    'temporary internet files', 'application data', 'fontcache', 'identities', 'msbuild', 'reference assemblies',
    'uninstall information', 'internet explorer', 'modifiablewindowsapps', 'dotnet', 'ssh', 'regid.*', 'uso*',
    'softwaredistribution', 'desktop', 'documents', 'start menu', 'templates', 'favorites', 'npm', 'npm-cache', 'pip',
    'uv', 'yarn', 'nuget', 'node-gyp', 'pnpm*', 'fontconfig', 'nvidia*', 'intel*', 'amd', 'ati*', 'realtek', 'dell',
    'hp', 'lenovo', 'asus*', 'msi', 'gigabyte', 'claude*', 'anthropic*', 'chocolatey', 'scoop', 'classes', 'policies',
    'wow6432node', 'clients', 'registeredapplications', 'odbc', 'khronos', 'partner', 'defaultuserenvironment', 'setup',
    'oem', 'appdatalow', 'description', 'hardware', 'system', 'mozillaplugins', 'chromium', 'dolby', 'waves*',
    'conexant', 'synaptics', 'elantech', 'llmcleaner', 'ollama', 'ms-playwright', 'gtk*', 'cache', 'logs', 'crashpad',
    'javasoft', 'steam controller configs', 'steamworks shared', '.*')

function Get-NameTokens([string]$t) {
    if (-not $t) { return @() }
    $t = [regex]::Replace($t, '([a-z])([A-Z])', '$1 $2')
    @(($t.ToLower() -split '[^a-z0-9]+') | Where-Object { $_.Length -ge 3 -and $_ -notin $CommonWords -and $_ -notmatch '^\d+$' })
}
function ConvertTo-PlainName([string]$t) { ($t.ToLower() -replace '[^a-z0-9]', '') }
function Test-SkippedName([string]$name) { $n = $name.ToLower(); foreach ($w in $SkippedNames) { if ($n -like $w) { return $true } }; $false }

# File path from a command like '"C:\X\unins.exe" /S' or 'C:\X\app.exe,0'
function Get-CommandPath([string]$s) {
    if (-not $s) { return $null }
    $s = [Environment]::ExpandEnvironmentVariables($s.Trim())
    if ($s.StartsWith('"')) { $e = $s.IndexOf('"', 1); if ($e -gt 1) { return $s.Substring(1, $e - 1) } }
    $m = [regex]::Match($s, '^(.+?\.(exe|dll|ico|bat|cmd))', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    ($s -split ',')[0]
}

function Get-UninstallKeys {
    foreach ($r in 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        "$HKCUName\Software\Microsoft\Windows\CurrentVersion\Uninstall") {
        foreach ($k in Get-ChildItem "Registry::$r") {
            $v = Get-ItemProperty -LiteralPath $k.PSPath
            if ($v.DisplayName) { @{ RegKey = "$r\$($k.PSChildName)"; V = $v } }
        }
    }
}

# Dead entries in the program list: the uninstaller and install folder don't exist.
# MSI entries are skipped - removing them would make the Windows Installer database inconsistent.
function Find-DeadUninstallEntries($entries) {
    foreach ($w in $entries) {
        try {
            $v = $w.V
            if ($v.SystemComponent -eq 1 -or $v.WindowsInstaller -eq 1 -or "$($v.UninstallString)" -match 'msiexec') { continue }
            $exe = Get-CommandPath $v.UninstallString
            if (-not $exe -or (Test-Path -LiteralPath $exe)) { continue }
            $loc = "$($v.InstallLocation)".Trim('"', ' ')
            if ($loc -and (Test-Path -LiteralPath $loc)) { continue }
            @{ Type = 'registry'; Path = $w.RegKey; Name = $v.DisplayName; Bytes = 0.0
                Confidence = $(if ($loc) { 'high' } else { 'medium' })
                Reason = $(if ($loc) { L 'Martwy wpis na liście programów: deinstalator nie istnieje, folder instalacji też nie.' 'Dead entry in the program list: the uninstaller and the install folder are both gone.' }
                    else { L 'Martwy wpis na liście programów: deinstalator nie istnieje.' 'Dead entry in the program list: the uninstaller is gone.' })
            }
        }
        catch { Add-ScanError "entry $($w.RegKey)" $_ }
    }
}

function Get-InstalledPrograms($entries) {
    $tokens = [System.Collections.Generic.HashSet[string]]::new()
    $names = [System.Collections.Generic.List[string]]::new()
    $paths = [System.Collections.Generic.List[string]]::new()
    function Add-Entry([string]$text) { foreach ($x in Get-NameTokens $text) { [void]$tokens.Add($x) }; $n = ConvertTo-PlainName $text; if ($n.Length -ge 4) { $names.Add($n) } }
    function Add-PathEntry([string]$p) {
        if (-not $p) { return }
        $p = $p.Trim('"', ' ').TrimEnd('\')
        if ($p -match '\.\w{2,4}$') { $p = Split-Path $p -Parent }
        if ($p.Length -gt 3) { $paths.Add($p.ToLower()) }
    }
    foreach ($w in $entries) {
        Add-Entry $w.V.DisplayName; Add-Entry $w.V.Publisher
        Add-PathEntry $w.V.InstallLocation
        Add-PathEntry (Get-CommandPath $w.V.DisplayIcon)
        Add-PathEntry (Get-CommandPath $w.V.UninstallString)
    }
    $appx = if ($OtherUser) { Get-AppxPackage -User $UserSid } else { Get-AppxPackage }
    foreach ($a in $appx) { Add-Entry $a.Name; Add-PathEntry $a.InstallLocation }
    foreach ($g in Get-SteamGames) { Add-Entry $g }
    foreach ($p in Get-Process) {
        if ($p.Path) { try { Add-PathEntry $p.Path; Add-Entry ([IO.Path]::GetFileNameWithoutExtension($p.Path)) } catch { Add-ScanError "process $($p.Path)" $_ } }
    }
    foreach ($s in Get-CimInstance Win32_Service) { Add-PathEntry (Get-CommandPath $s.PathName) }
    # Start menu and desktop shortcuts - catch portable programs with no registry entry
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:ProgramData\Microsoft\Windows\Start Menu",
                   (Get-UserShellFolder 'Desktop' "$env:USERPROFILE\Desktop"), "$env:PUBLIC\Desktop") {
        foreach ($l in Get-ChildItem -LiteralPath $d -Recurse -Filter *.lnk -Force) {
            Add-Entry $l.BaseName
            try { $t = $sh.CreateShortcut($l.FullName).TargetPath; if ($t) { Add-PathEntry $t } }
            catch { Add-ScanError "shortcut $($l.FullName)" $_ }
        }
    }
    @{ Tokens = $tokens; Names = $names; Paths = $paths }
}

function Test-BelongsToProgram([string]$name, [string]$path, $installed) {
    foreach ($t in Get-NameTokens $name) { if ($installed.Tokens.Contains($t)) { return $true } }
    $n = ConvertTo-PlainName $name
    if ($n.Length -ge 4) { foreach ($z in $installed.Names) { if ($z.Contains($n) -or ($z.Length -ge 5 -and $n.Contains($z))) { return $true } } }
    if ($path) {
        $s = $path.ToLower().TrimEnd('\')
        foreach ($p in $installed.Paths) { if ($p -eq $s -or $p.StartsWith("$s\") -or $s.StartsWith("$p\")) { return $true } }
    }
    $false
}

function Measure-Folder($p) {
    $b = 0.0; $latest = [datetime]::MinValue; $exe = $false
    foreach ($f in Get-AllFiles $p) {
        $b += $f.Length; if ($f.LastWriteTime -gt $latest) { $latest = $f.LastWriteTime }
        if (-not $exe -and $f.Extension -eq '.exe') { $exe = $true }
    }
    if ($latest -eq [datetime]::MinValue) {
        # Empty or unreadable folder. If even its date can't be read, treat it as
        # recent - an unknown folder must not enter the plan as old
        $latest = (Get-Item -LiteralPath $p -Force).LastWriteTime
        if ($latest -isnot [datetime]) { $latest = Get-Date }
    }
    @{ Bytes = $b; LastWrite = $latest; HasExe = $exe }
}
