<#
    LLMCleaner - pomiar i usuwanie plikow, test blokady, poprzednia wersja Windows
#>

# Wszystkie pliki pod katalogiem. Nie wchodzi w junctions ani symlinki.
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

# Czy pliku nie da sie teraz usunac: otwarty przez inny program bez zgody na usuniecie
# (np. swap.vhdx dzialajacego WSL) albo brak uprawnien. Otwiera z samym prawem DELETE - tak jak
# usuwanie - wiec nie czyta danych i antywirus go nie skanuje (~0,1 ms na plik zamiast ~2 ms).
function Initialize-FileLockType {
    if ('LlmFileLock' -as [type]) { return }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Core\cs\LlmFileLock.cs')))
}

# Bajty - to, co UsunZawartosc faktycznie usunie; Zajete - pliki, ktorych teraz usunac sie nie da.
# Pliki mlodsze niz $minWiekDni nie naleza do kategorii i nie sa liczone wcale.
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

# Usuwa ZAWARTOSC katalogu (nie sam katalog) albo pojedynczy plik.
# Lacza (junctions/symlinki) usuwa jako lacza, nigdy nie wchodzi do ich celu.
# Pliki w uzyciu pomija. Przy $minWiekDni > 0 usuwa tylko pliki starsze niz tyle dni
# - sprawdzane dla KAZDEGO pliku, nie tylko dla folderu najwyzszego poziomu.
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

    # Puste katalogi - od najglebszych. Niepuste (pliki w uzyciu, swieze) zostaja.
    $dirs.Reverse()
    foreach ($k in $dirs) { try { [IO.Directory]::Delete($k.FullName, $false) } catch { } }

    @{ Bytes = $freed; Errors = $errors }
}

# Windows.old i pliki instalatora aktualizacji usuwa Oczyszczanie dysku Windows (cleanmgr /sagerun),
# tak jak "Wyczysc pliki systemowe". Recznie byloby niebezpiecznie: junctions w Windows.old
# wskazuja na biezace C:\Users, a przejmowanie uprawnien mogloby je zmienic.
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
