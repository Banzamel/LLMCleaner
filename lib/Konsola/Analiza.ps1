<#
    LLMCleaner - analiza dysku
#>

function PokazAnalize($a) {
    Naglowek ((L 'CO ZAJMUJE MIEJSCE NA {0}:   zajęte {1} z {2}, wolne {3}' 'WHAT TAKES UP SPACE ON {0}:   {1} used of {2}, {3} free') -f $a.Litera, (Rozmiar ($a.Rozmiar - $a.Wolne)), (Rozmiar $a.Rozmiar), (Rozmiar $a.Wolne))
    Write-Host ((L '   Tylko do wglądu - nic stąd nie jest usuwane. Pokazane są najbardziej konkretne foldery od {0}.' '   Read-only - nothing here is deleted. The most specific folders from {0} up are shown.') -f (Rozmiar $a.Prog)) -ForegroundColor DarkGray
    $sekcje = @(@{ T = (L 'NAJWIĘKSZE FOLDERY' 'LARGEST FOLDERS'); L = $a.Foldery }, @{ T = (L 'NAJWIĘKSZE PLIKI' 'LARGEST FILES'); L = $a.Pliki })
    foreach ($s in $sekcje) {
        if (-not $s.L.Count) { continue }
        Write-Host ""
        Write-Host "   $($s.T)" -ForegroundColor Cyan
        foreach ($p in $s.L) {
            $dop = if ($p.Reszta) { L '  (pliki poza wymienionymi podfolderami)' '  (files outside the listed subfolders)' } else { '' }
            $data = if ($p.Ostatnio -gt [datetime]'1980-01-01') { $p.Ostatnio.ToString('yyyy-MM-dd') } else { '          ' }
            Write-Host ("  {0,4}. {1,10}  {2}  {3}{4}" -f $p.Id, (Rozmiar $p.Bajty), $data, $p.Sciezka, $dop) -ForegroundColor Gray
            if ($p.Podpowiedz) { Write-Host "                            $($p.Podpowiedz)" -ForegroundColor DarkGray }
            if ($p.Ai) { Write-Host "                            $EtykietaAi`: $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    if ($a.Cienie -gt 0) {
        Write-Host ""
        Write-Host ((L '   Punkty przywracania systemu: {0} (Ochrona systemu w Ustawieniach)' '   System Restore points: {0} (System Protection in Settings)') -f (Rozmiar $a.Cienie)) -ForegroundColor Gray
    }
    $niewidoczne = ($a.Rozmiar - $a.Wolne) - $a.Zeskanowane - $a.Cienie
    if ($niewidoczne -gt 2GB) {
        Write-Host ((L '   Niedostępne dla skanera (pliki systemowe, chronione foldery): ok. {0}' '   Not readable by the scanner (system files, protected folders): about {0}') -f (Rozmiar $niewidoczne)) -ForegroundColor DarkGray
    }
}

function AnalizaKonsola {
    $lista = @(DyskiWybrane)
    Write-Host ""
    Write-Host ("   " + (($lista | ForEach-Object { OpisDysku $_ }) -join ' | ')) -ForegroundColor Gray
    $dom = $Sys.TrimEnd(':')
    $l = (Read-Host ((L '   Który dysk przeanalizować? [{0}]' '   Which drive to analyse? [{0}]') -f $dom)).Trim().TrimEnd(':', '\').ToUpper()
    if (-not $l) { $l = $dom }
    if (-not ($lista | Where-Object { $_.DeviceID -eq "$l`:" })) { Write-Host ((L '   Dysk {0}: nie jest wybrany do skanowania.' '   Drive {0}: is not selected for scanning.') -f $l) -ForegroundColor Yellow; return }
    $a = Analizuj $l
    while ($true) {
        PokazAnalize $a
        Write-Host ""
        $pomoc = if ($BezLLM) { L 'Enter = powrót do planu' 'Enter = back to the plan' } else { L 'w = AI opisze te pozycje i doradzi | Enter = powrót do planu' 'w = AI describes these items and advises | Enter = back to the plan' }
        Write-Host "   $pomoc" -ForegroundColor Yellow
        $w = (Read-Host (L '   Wybór' '   Choice')).Trim()
        if ($w -match '^[wW]$' -and -not $BezLLM) { [void](AnalizaAi $a); continue }
        return
    }
}
