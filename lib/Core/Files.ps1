<#
    LLMCleaner - measuring and deleting files, lock test, previous Windows version
#>

# All files under a folder. Does not follow junctions or symlinks.
function Get-AllFiles($path) {
    $stack = [System.Collections.Stack]::new()
    $stack.Push([IO.DirectoryInfo]$path)
    while ($stack.Count) {
        $d = $stack.Pop()
        try { $fsItems = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $fsItems) {
            if ($e.Attributes -band $REPARSE) { continue }
            if ($e -is [IO.DirectoryInfo]) { $stack.Push($e) } else { $e }
        }
    }
}

# Whether a file can't be deleted right now: opened by another program without delete sharing
# (e.g. swap.vhdx of a running WSL) or no permission. Opens with DELETE access only - like a
# delete does - so no data is read and antivirus doesn't scan it (~0.1 ms per file instead of ~2 ms).
function Initialize-FileLockType {
    if ('LlmFileLock' -as [type]) { return }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Core\cs\LlmFileLock.cs')))
}

# Bytes - what Remove-FolderContent will actually delete; InUse - files that can't be deleted now.
# Files newer than $minAgeDays are not part of the category and are not counted at all.
function Measure-Paths($paths, $minAgeDays = 0) {
    Initialize-FileLockType
    $bytes = 0.0; $n = 0; $usedBytes = 0.0; $lockedFiles = [System.Collections.Generic.List[object]]::new()
    $cutoff = (Get-Date).AddDays(-$minAgeDays)
    foreach ($s in $paths) {
        if (Test-Path -LiteralPath $s -PathType Leaf) { $files = @(Get-Item -LiteralPath $s -Force) }
        elseif (-not (Test-Path -LiteralPath $s -PathType Container)) { continue }
        elseif ((Get-Item -LiteralPath $s -Force).Attributes -band $REPARSE) { continue }
        else { $files = Get-AllFiles $s }
        foreach ($f in $files) {
            if ($minAgeDays -gt 0 -and $f.LastWriteTime -gt $cutoff) { continue }
            if ([LlmFileLock]::IsLocked($f.FullName)) { $usedBytes += $f.Length; $lockedFiles.Add($f); continue }
            $bytes += $f.Length; $n++
        }
    }
    @{ Bytes = $bytes; Files = $n; InUse = $usedBytes; InUseFiles = $lockedFiles }
}

# Deletes the CONTENTS of a folder (not the folder itself) or a single file.
# Links (junctions/symlinks) are deleted as links; their targets are never entered.
# Files in use are skipped. With $minAgeDays > 0 only files older than that are deleted
# - checked for EVERY file, not just the top-level folder.
function Remove-FolderContent($path, $minAgeDays = 0) {
    $freed = 0.0; $errors = 0

    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $f = Get-Item -LiteralPath $path -Force
        try { $len = $f.Length; $f.Attributes = 'Normal'; $f.Delete(); $freed += $len } catch { $errors++ }
        return @{ Bytes = $freed; Errors = $errors }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return @{ Bytes = 0.0; Errors = 0 } }

    $root = [IO.DirectoryInfo]$path
    if ($root.Attributes -band $REPARSE) { return @{ Bytes = 0.0; Errors = 0 } }

    $cutoff = (Get-Date).AddDays(-$minAgeDays)
    $dirs = [System.Collections.Generic.List[IO.DirectoryInfo]]::new()
    $stack = [System.Collections.Stack]::new()
    $stack.Push($root)
    $counter = 0

    while ($stack.Count) {
        $d = $stack.Pop()
        if ((++$counter % 200) -eq 0 -and $script:Mode -eq 'window') { [Windows.Forms.Application]::DoEvents() }
        try { $fsItems = $d.GetFileSystemInfos() } catch { $errors++; continue }
        foreach ($e in $fsItems) {
            if ($e.Attributes -band $REPARSE) {
                if ($minAgeDays -eq 0) {
                    try {
                        if ($e -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($e.FullName, $false) } else { $e.Delete() }
                    }
                    catch { $errors++ }
                }
                continue
            }
            if ($e -is [IO.DirectoryInfo]) {
                $stack.Push($e)
                if ($minAgeDays -eq 0 -or $e.LastWriteTime -le $cutoff) { $dirs.Add($e) }
                continue
            }
            if ($minAgeDays -gt 0 -and $e.LastWriteTime -gt $cutoff) { continue }
            try {
                $len = $e.Length
                if ($e.Attributes -band [IO.FileAttributes]::ReadOnly) { $e.Attributes = 'Normal' }
                $e.Delete()
                $freed += $len
            }
            catch { $errors++ }
        }
    }

    # Empty folders - deepest first. Non-empty ones (files in use, recent) stay.
    $dirs.Reverse()
    foreach ($k in $dirs) { try { [IO.Directory]::Delete($k.FullName, $false) } catch { } }

    @{ Bytes = $freed; Errors = $errors }
}

# Windows.old and update installer files are removed by Windows Disk Cleanup (cleanmgr /sagerun),
# like "Clean up system files". Doing it by hand is dangerous: junctions in Windows.old
# point to the current C:\Users, and taking ownership could change them.
$SageId = 'StateFlags0777'
$SageKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$SageHandlers = @('Previous Installations', 'Temporary Setup Files')
function Remove-PreviousWindows {
    foreach ($h in $SageHandlers) {
        if (Test-Path "$SageKey\$h") { Set-ItemProperty "$SageKey\$h" -Name $SageId -Value 2 -Type DWord }
    }
    $p = Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -PassThru
    if ($p) { while (-not $p.WaitForExit(500)) { Wait-Responsive 0 } }
    foreach ($h in $SageHandlers) { Remove-ItemProperty "$SageKey\$h" -Name $SageId }
}
