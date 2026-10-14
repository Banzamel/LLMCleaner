<#
    LLMCleaner - pomiar i usuwanie plikow, test blokady, poprzednia wersja Windows
#>

# Wszystkie pliki pod katalogiem. Nie wchodzi w junctions ani symlinki.
function Pliki($sciezka) {
    $stos = [System.Collections.Stack]::new()
    $stos.Push([IO.DirectoryInfo]$sciezka)
    while ($stos.Count) {
        $d = $stos.Pop()
        try { $elementy = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $elementy) {
            if ($e.Attributes -band $REPARSE) { continue }
            if ($e -is [IO.DirectoryInfo]) { $stos.Push($e) } else { $e }
        }
    }
}

# Czy pliku nie da sie teraz usunac: otwarty przez inny program bez zgody na usuniecie
# (np. swap.vhdx dzialajacego WSL) albo brak uprawnien. Otwiera z samym prawem DELETE - tak jak
# usuwanie - wiec nie czyta danych i antywirus go nie skanuje (~0,1 ms na plik zamiast ~2 ms).
function KompilujBlokade {
    if ('LlmBlokada' -as [type]) { return }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Rdzen\cs\LlmBlokada.cs')))
}

# Bajty - to, co UsunZawartosc faktycznie usunie; Zajete - pliki, ktorych teraz usunac sie nie da.
# Pliki mlodsze niz $minWiekDni nie naleza do kategorii i nie sa liczone wcale.
function Zmierz($sciezki, $minWiekDni = 0) {
    KompilujBlokade
    $bajty = 0.0; $n = 0; $zajete = 0.0; $zajetePliki = [System.Collections.Generic.List[object]]::new()
    $granica = (Get-Date).AddDays(-$minWiekDni)
    foreach ($s in $sciezki) {
        if (Test-Path -LiteralPath $s -PathType Leaf) { $pliki = @(Get-Item -LiteralPath $s -Force) }
        elseif (-not (Test-Path -LiteralPath $s -PathType Container)) { continue }
        elseif ((Get-Item -LiteralPath $s -Force).Attributes -band $REPARSE) { continue }
        else { $pliki = Pliki $s }
        foreach ($f in $pliki) {
            if ($minWiekDni -gt 0 -and $f.LastWriteTime -gt $granica) { continue }
            if ([LlmBlokada]::Zablokowany($f.FullName)) { $zajete += $f.Length; $zajetePliki.Add($f); continue }
            $bajty += $f.Length; $n++
        }
    }
    @{ Bajty = $bajty; Pliki = $n; Zajete = $zajete; ZajetePliki = $zajetePliki }
}

# Usuwa ZAWARTOSC katalogu (nie sam katalog) albo pojedynczy plik.
# Lacza (junctions/symlinki) usuwa jako lacza, nigdy nie wchodzi do ich celu.
# Pliki w uzyciu pomija. Przy $minWiekDni > 0 usuwa tylko pliki starsze niz tyle dni
# - sprawdzane dla KAZDEGO pliku, nie tylko dla folderu najwyzszego poziomu.
function UsunZawartosc($sciezka, $minWiekDni = 0) {
    $zwolniono = 0.0; $bledy = 0

    if (Test-Path -LiteralPath $sciezka -PathType Leaf) {
        $f = Get-Item -LiteralPath $sciezka -Force
        try { $dl = $f.Length; $f.Attributes = 'Normal'; $f.Delete(); $zwolniono += $dl } catch { $bledy++ }
        return @{ Bajty = $zwolniono; Bledy = $bledy }
    }
    if (-not (Test-Path -LiteralPath $sciezka -PathType Container)) { return @{ Bajty = 0.0; Bledy = 0 } }

    $korzen = [IO.DirectoryInfo]$sciezka
    if ($korzen.Attributes -band $REPARSE) { return @{ Bajty = 0.0; Bledy = 0 } }

    $granica = (Get-Date).AddDays(-$minWiekDni)
    $katalogi = [System.Collections.Generic.List[IO.DirectoryInfo]]::new()
    $stos = [System.Collections.Stack]::new()
    $stos.Push($korzen)
    $licznik = 0

    while ($stos.Count) {
        $d = $stos.Pop()
        if ((++$licznik % 200) -eq 0 -and $script:Tryb -eq 'okno') { [Windows.Forms.Application]::DoEvents() }
        try { $elementy = $d.GetFileSystemInfos() } catch { $bledy++; continue }
        foreach ($e in $elementy) {
            if ($e.Attributes -band $REPARSE) {
                if ($minWiekDni -eq 0) {
                    try {
                        if ($e -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($e.FullName, $false) } else { $e.Delete() }
                    }
                    catch { $bledy++ }
                }
                continue
            }
            if ($e -is [IO.DirectoryInfo]) {
                $stos.Push($e)
                if ($minWiekDni -eq 0 -or $e.LastWriteTime -le $granica) { $katalogi.Add($e) }
                continue
            }
            if ($minWiekDni -gt 0 -and $e.LastWriteTime -gt $granica) { continue }
            try {
                $dl = $e.Length
                if ($e.Attributes -band [IO.FileAttributes]::ReadOnly) { $e.Attributes = 'Normal' }
                $e.Delete()
                $zwolniono += $dl
            }
            catch { $bledy++ }
        }
    }

    # Puste katalogi - od najglebszych. Niepuste (pliki w uzyciu, swieze) zostaja.
    $katalogi.Reverse()
    foreach ($k in $katalogi) { try { [IO.Directory]::Delete($k.FullName, $false) } catch { } }

    @{ Bajty = $zwolniono; Bledy = $bledy }
}

# Windows.old i pliki instalatora aktualizacji usuwa Oczyszczanie dysku Windows (cleanmgr /sagerun),
# tak jak "Wyczysc pliki systemowe". Recznie byloby niebezpiecznie: junctions w Windows.old
# wskazuja na biezace C:\Users, a przejmowanie uprawnien mogloby je zmienic.
$SageId = 'StateFlags0777'
$SageKlucz = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$SageHandlery = @('Previous Installations', 'Temporary Setup Files')
function UsunPoprzedniWindows {
    foreach ($h in $SageHandlery) {
        if (Test-Path "$SageKlucz\$h") { Set-ItemProperty "$SageKlucz\$h" -Name $SageId -Value 2 -Type DWord }
    }
    $p = Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -PassThru
    if ($p) { while (-not $p.WaitForExit(500)) { Pauza 0 } }
    foreach ($h in $SageHandlery) { Remove-ItemProperty "$SageKlucz\$h" -Name $SageId }
}
