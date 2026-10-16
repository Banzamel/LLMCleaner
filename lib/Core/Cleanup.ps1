<#
    LLMCleaner - restore point and running the cleanup
#>

# System restore point before registry changes (in addition to .reg backups). Returns a result description.
function New-RestorePoint {
    $getLast = { Get-ComputerRestorePoint | Sort-Object SequenceNumber | Select-Object -Last 1 }
    $before = & $getLast
    try {
        Checkpoint-Computer -Description "LLMCleaner $Version" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
    }
    catch { return @{ Ok = $false; Description = ((L 'nie utworzono ({0}) - ochrona systemu może być wyłączona' 'not created ({0}) - System Protection may be turned off') -f $_.Exception.Message.Trim()) } }
    $after = & $getLast
    if ($after -and (-not $before -or $after.SequenceNumber -ne $before.SequenceNumber)) {
        return @{ Ok = $true; Description = ((L 'utworzony (nr {0})' 'created (no. {0})') -f $after.SequenceNumber) }
    }
    $when = if ($before) { $before.ConvertToDateTime($before.CreationTime).ToString('dd.MM HH:mm') } else { '?' }
    @{ Ok = $false; Description = ((L 'pominięty przez Windows - limit jednego punktu na dobę (ostatni: {0})' 'skipped by Windows - one restore point per day (last: {0})') -f $when) }
}

# Step-by-step progress for the window (cleanup screen); does nothing in the console.
# State: running, ok, partial (done with skips), skipped, error.
$script:OnStep = $null
function Write-Step([string]$id, [string]$state, [double]$bytes = 0, [string]$note = '') {
    if ($script:OnStep) { & $script:OnStep $id $state $bytes $note }
}

# Restore point before changes the Recycle Bin cannot undo: registry, tasks, drivers
function Test-RestorePointNeeded {
    [bool](@($script:Leftovers | Where-Object { $_.Selected -and -not (Test-GoesToRecycleBin $_) }).Count -or
        @($script:Categories | Where-Object { $_.Selected -and $_.Type -eq 'driverstore' }).Count)
}

# Cleans the selected categories and leftovers. Returns a summary.
function Invoke-Cleanup {
    Stop-Ollama   # the assistant is no longer needed - frees VRAM and RAM for the cleanup
    Write-Log ("Plan: categories [{0}], leftovers [{1}]" -f (($script:Categories | Where-Object { $_.Selected } | ForEach-Object { $_.Id }) -join ', '),
        (($script:Leftovers | Where-Object { $_.Selected } | ForEach-Object { $_.Id }) -join ', '))
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $total = 0.0

    # First what goes to the Recycle Bin, then registry and tasks (separate steps on the progress screen)
    $selectedLeftovers = @(@($script:Leftovers | Where-Object { $_.Selected -and (Test-GoesToRecycleBin $_) }) +
        @($script:Leftovers | Where-Object { $_.Selected -and -not (Test-GoesToRecycleBin $_) }))
    if (Test-RestorePointNeeded) {
        Write-Step 'restorepoint' 'running'
        Write-Line (L '  Tworzę punkt przywracania systemu (do 30 s)...' '  Creating a System Restore point (up to 30 s)...') 'Gray'
        $restore = New-RestorePoint
        Write-Line ((L '  Punkt przywracania: {0}' '  Restore point: {0}') -f $restore.Description) $(if ($restore.Ok) { 'Green' } else { 'Yellow' })
        Write-Log "Restore point: $($restore.Description)"
        Write-Step 'restorepoint' $(if ($restore.Ok) { 'ok' } else { 'partial' }) 0 $restore.Description
    }

    foreach ($k in ($script:Categories | Where-Object { $_.Selected })) {
        $gain = 0.0; $errors = 0
        Write-Status ("   {0}..." -f $k.Name)
        Write-Step $k.Id 'running'
        if ($k.Processes -and (Get-Process $k.Processes)) {
            Write-Line ("  {0,-52} {1}" -f $k.Name, (L 'pominięto (przeglądarka działa)' 'skipped (a browser is running)')) 'Yellow'
            Write-Log "$($k.Id): skipped - a browser is running"
            Write-Step $k.Id 'skipped' 0 (L 'pominięto: działa przeglądarka' 'skipped: a browser is running')
            continue
        }
        $skippedApps = @()
        switch ($k.Type) {
            'folder' {
                foreach ($u in $k.Services) { Stop-Service $u -Force }
                if ($k.Services) { Wait-Responsive 2000 }
                $paths = $k.Paths
                if ($k.Groups) {
                    $paths = @()
                    foreach ($g in $k.Groups) {
                        if (Get-Process $g.Processes) { $skippedApps += $g.Name } else { $paths += $g.Paths }
                    }
                }
                foreach ($s in $paths) {
                    $r = Remove-FolderContent $s ([int]$k.MinAge)
                    $gain += $r.Bytes; $errors += $r.Errors
                }
                foreach ($u in $k.Services) { Start-Service $u }
            }
            'recyclebin' {
                $gain = $k.Bytes
                if ($OtherUser) { foreach ($s in Get-RecycleBinFolders) { [void](Remove-FolderContent $s) } } else { Clear-RecycleBin -Force -Confirm:$false }
            }
            'thumbnails' {
                Stop-Process -Name explorer -Force
                Wait-Responsive 3000
                foreach ($f in Get-ThumbnailFiles) { try { $len = $f.Length; $f.Delete(); $gain += $len } catch { $errors++ } }
                # Windows restarts the shell itself; manually only on our own account (otherwise it would run as administrator)
                for ($i = 0; $i -lt 10 -and -not (Get-Process explorer); $i++) { Wait-Responsive 1000 }
                if (-not (Get-Process explorer) -and -not $OtherUser) { Start-Process explorer.exe }
            }
            'dns' { ipconfig /flushdns | Out-Null }
            'winold' {
                Write-Line (L '  Oczyszczanie dysku Windows usuwa poprzednią wersję systemu - to potrwa kilka minut...' '  Windows Disk Cleanup is removing the previous Windows version - this takes a few minutes...') 'Gray'
                $before = Get-SystemFreeSpace
                Remove-PreviousWindows
                $errors = @($k.Paths | Where-Object { Test-Path -LiteralPath $_ }).Count
                $gain = [math]::Max(0.0, (Get-SystemFreeSpace) - $before)
            }
            'dism' {
                Write-Line (L '  DISM pracuje - to potrwa kilka minut...' '  DISM is working - this takes a few minutes...') 'Gray'
                $before = Get-SystemFreeSpace
                $p = Start-Process Dism.exe -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase' -WindowStyle Hidden -PassThru
                while (-not $p.WaitForExit(500)) { Wait-Responsive 0 }
                $gain = [math]::Max(0.0, (Get-SystemFreeSpace) - $before)
            }
            'docker' {
                $before = (Get-DockerUsage).Cache
                docker builder prune -a -f 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Line "  $_" 'DarkGray' }
                $gain = [math]::Max(0.0, $before - (Get-DockerUsage).Cache)
            }
            'dockerall' {
                $before = (Get-DockerUsage).InUse
                $containers = @(docker ps -aq 2>$null | Where-Object { $_ })
                if ($containers.Count) {
                    Write-Line ((L '  Docker zatrzymuje i usuwa kontenery: {0}...' '  Docker is stopping and removing containers: {0}...') -f $containers.Count) 'Gray'
                    docker rm -f -v @containers 2>&1 | Out-Null
                    Write-Log "Docker: removed containers ($($containers.Count))"
                }
                Write-Line (L '  Docker usuwa obrazy, wolumeny, sieci i cache...' '  Docker is removing images, volumes, networks and cache...') 'Gray'
                docker system prune -a --volumes -f 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Line "  $_" 'DarkGray' }
                # Since Docker 23 prune --volumes removes only anonymous volumes; named ones must be removed separately
                $volumes = @(docker volume ls -q 2>$null | Where-Object { $_ })
                if ($volumes.Count) {
                    Write-Line ((L '  Docker usuwa wolumeny: {0}...' '  Docker is removing volumes: {0}...') -f $volumes.Count) 'Gray'
                    docker volume rm -f @volumes 2>&1 | Out-Null
                    Write-Log "Docker: removed volumes ($($volumes.Count))"
                }
                # Build history (the Builds list in Docker Desktop) for each builder; older buildx lacks this command
                $builders = @(docker buildx ls --format '{{.Name}}' 2>$null | Where-Object { $_ -and $_ -notmatch '\s' } | Select-Object -Unique)
                if (-not $builders.Count) { $builders = @('') }
                foreach ($b in $builders) {
                    $arg = @('buildx', 'history', 'rm', '--all') + $(if ($b) { '--builder', $b })
                    docker @arg 2>&1 | Out-Null
                }
                $gain = [math]::Max(0.0, $before - (Get-DockerUsage).InUse)
            }
            'driverstore' {
                foreach ($d in $k.Packages) {
                    Wait-Responsive 0
                    $output = & pnputil.exe /delete-driver $d.Inf 2>&1
                    if ($LASTEXITCODE -eq 0) { $gain += $d.Bytes; Write-Log "Driver removed: $($d.Inf) $($d.Name) $($d.Version) ($(Format-Size $d.Bytes))" }
                    else { $errors++; Write-Log "Driver kept: $($d.Inf) $($d.Name) $($d.Version): $($output -join ' ')" }
                }
            }
        }
        $total += $gain
        $color = if ($gain -gt 50MB) { 'Green' } else { 'Gray' }
        $suffix = if ($errors) { (L '  ({0} w użyciu, pominięte)' '  ({0} in use, skipped)') -f $errors } else { '' }
        if ($skippedApps) {
            $suffix += (L '  (pominięto - działa: {0})' '  (skipped - running: {0})') -f ($skippedApps -join ', ')
            Write-Log "$($k.Id): skipped running $($skippedApps -join ', ')"
        }
        Write-Line ("  {0,-52} {1,10}{2}" -f $k.Name, (Format-Size $gain), $suffix) $color
        Write-Log ("{0}: {1} freed, {2} skipped" -f $k.Id, (Format-Size $gain), $errors)
        $notes = @()
        if ($errors) { $notes += (L '{0} w użyciu - pominięte' '{0} in use - skipped') -f $errors }
        if ($skippedApps) { $notes += (L 'pominięto: działa {0}' 'skipped: {0} is running') -f ($skippedApps -join ', ') }
        $state = if ($skippedApps -and -not $gain) { 'skipped' } elseif ($notes.Count) { 'partial' } else { 'ok' }
        Write-Step $k.Id $state $gain ($notes -join '; ')
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $backups = $null
    if ($selectedLeftovers.Count) {
        Write-Line ''
        Write-Line (L '  Pozostałości po odinstalowanych programach i grach:' '  Leftovers of uninstalled programs and games:') 'Cyan'
        $backups = Join-Path $LogDir ("kopie_rejestru\{0}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
        $toBin = L '-> Kosz' '-> Recycle Bin'
        $step = $null; $stepBytes = 0.0; $stepErrors = 0
        $finishStep = {
            Write-Step $step $(if ($stepErrors) { 'partial' } else { 'ok' }) $stepBytes $(if ($stepErrors) { (L 'nie udało się: {0} - szczegóły w Dzienniku' 'failed: {0} - see the Log') -f $stepErrors } else { '' })
        }
        foreach ($p in $selectedLeftovers) {
            Wait-Responsive 0
            $id = if (Test-GoesToRecycleBin $p) { 'leftovers-bin' } else { 'leftovers-backup' }
            if ($id -ne $step) {
                if ($step) { & $finishStep }
                $step = $id; $stepBytes = 0.0; $stepErrors = 0
                Write-Step $step 'running'
            }
            try {
                if ($p.Type -eq 'folder') {
                    # Last safeguard: never delete a drive root, the Recycle Bin or system folders
                    if (Test-ProtectedFolder $p.Path) { throw (L 'folder chroniony - zostawiony' 'protected folder - kept') }
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    Write-Line ("  {0,-60} {1,10}  {2}" -f $p.Path, (Format-Size $p.Bytes), $toBin) 'Green'
                    Write-Log "To Recycle Bin (folder): $($p.Path) ($(Format-Size $p.Bytes))"
                    $stepBytes += [double]$p.Bytes
                }
                elseif ($p.Type -eq 'file') {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                    Write-Line ("  {0,-60} {1,10}  {2}" -f $p.Path, (Format-Size $p.Bytes), $toBin) 'Green'
                    Write-Log "To Recycle Bin (file): $($p.Path) ($(Format-Size $p.Bytes))"
                    $stepBytes += [double]$p.Bytes
                }
                elseif ($p.Type -eq 'registry') {
                    New-Item -ItemType Directory -Force $backups | Out-Null
                    $file = Join-Path $backups ("{0}_{1}.reg" -f $p.Id, ($p.Name -replace '[^\w\-\. ]', '_'))
                    & reg.exe export $p.Path $file /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw (L 'nie udało się zrobić kopii - klucz zostawiony' 'backup failed - key kept') }
                    Remove-Item -LiteralPath "Registry::$($p.Path)" -Recurse -Force -ErrorAction Stop
                    Write-Line ("  {0,-60} {1,10}" -f $p.Path, (L 'usunięty' 'deleted')) 'Green'
                    Write-Log "Registry removed: $($p.Path) (backup: $file)"
                }
                elseif ($p.Type -eq 'regvalue') {
                    New-Item -ItemType Directory -Force $backups | Out-Null
                    $file = Join-Path $backups ("{0}_{1}.reg" -f $p.Id, ($p.Name -replace '[^\w\-\. ]', '_'))
                    Backup-RegistryValue $p.Path $p.ValueName $file
                    Remove-ItemProperty -LiteralPath "Registry::$($p.Path)" -Name $p.ValueName -Force -ErrorAction Stop
                    Write-Line ("  {0,-60} {1,10}" -f (Format-Leftover $p), (L 'usunięty' 'deleted')) 'Green'
                    Write-Log "Registry removed: $($p.Path) -> $($p.ValueName) (backup: $file)"
                }
                elseif ($p.Type -eq 'task') {
                    New-Item -ItemType Directory -Force $backups | Out-Null
                    $file = Join-Path $backups ("{0}_{1}.xml" -f $p.Id, ($p.Name -replace '[^\w\-\. ]', '_'))
                    $xml = Export-ScheduledTask -TaskName $p.Name -TaskPath $p.Folder
                    if (-not $xml) { throw (L 'nie udało się zrobić kopii - zadanie zostawione' 'backup failed - task kept') }
                    [IO.File]::WriteAllText($file, $xml, [Text.Encoding]::Unicode)
                    Unregister-ScheduledTask -TaskName $p.Name -TaskPath $p.Folder -Confirm:$false -ErrorAction Stop
                    Write-Line ("  {0,-60} {1,10}" -f (Format-Leftover $p), (L 'usunięte' 'deleted')) 'Green'
                    Write-Log "Task removed: $($p.Path) (backup: $file)"
                }
            }
            catch {
                Write-Line ("  {0}: {1}" -f $p.Path, $_.Exception.Message) 'Yellow'
                Write-Log "Leftover error $($p.Path): $($_.Exception.Message)"
                $stepErrors++
            }
        }
        if ($step) { & $finishStep }
        if (@($selectedLeftovers | Where-Object { $_.Type -in 'registry', 'regvalue' }).Count) {
            Write-Line ((L '  Kopie rejestru: {0} (dwuklik na pliku .reg przywraca klucz)' '  Registry backups: {0} (double-click a .reg file to restore the key)') -f $backups) 'DarkGray'
        }
        if (@($selectedLeftovers | Where-Object { $_.Type -eq 'task' }).Count) {
            Write-Line ((L '  Kopie zadań: {0} (Harmonogram zadań > Importuj zadanie przywraca zadanie z pliku .xml)' '  Task backups: {0} (Task Scheduler > Import Task restores a task from its .xml file)') -f $backups) 'DarkGray'
        }
    }

    $timer.Stop()
    $freeAfter = Get-SystemFreeSpace
    Write-Log ("Done. Removed {0}, free on {1}: {2} -> {3}" -f (Format-Size $total), $Sys, (Format-Size $script:FreeBefore), (Format-Size $freeAfter))
    @{ Total = $total; Duration = $timer.Elapsed; FreeBefore = $script:FreeBefore; FreeAfter = $freeAfter; Backups = $backups }
}

# Summary text after cleanup (lines)
function Get-CleanupSummary($w) {
    @(
        (L 'Usunięte dane       : {0}' 'Data removed        : {0}') -f (Format-Size $w.Total)
        (L 'Czas                : {0}m {1}s' 'Time                : {0}m {1}s') -f $w.Duration.Minutes, $w.Duration.Seconds
        (L 'Wolne na {1} przed  : {0}' 'Free on {1} before  : {0}') -f (Format-Size $w.FreeBefore), $Sys
        (L 'Wolne na {1} po     : {0}' 'Free on {1} after   : {0}') -f (Format-Size $w.FreeAfter), $Sys
    )
}
