<#
    LLMCleaner - plan czyszczenia
#>

function PokazPlan {
    Naglowek (L 'PLAN CZYSZCZENIA' 'CLEANUP PLAN')
    $i = 0
    foreach ($k in $script:Kategorie) {
        $i++
        $znak = if ($k.Wybrana) { '[x]' } else { '[ ]' }
        $kolor = if ($k.Wybrana) { 'Green' } elseif ($k.TylkoRecznie) { 'Gray' } else { 'DarkGray' }
        Write-Host ("  {0} {1,2}. {2,-52} {3,10}" -f $znak, $i, $k.Nazwa, (RozmiarKategorii $k)) -ForegroundColor $kolor
        if ($k.Blokada) { Write-Host "           ! $($k.Blokada)" -ForegroundColor Yellow }
        else { Write-Host "           $(if ($k.TylkoRecznie) { L '(tylko na Twoje życzenie) ' '(only if you choose it) ' })$($k.Opis)" -ForegroundColor DarkGray }
        if ($k.Uwaga -and -not $k.Blokada) { Write-Host "           ! $($k.Uwaga)" -ForegroundColor Yellow }
    }
    if ($script:Pozostalosci.Count) {
        Write-Host ""
        Write-Host (L '   POZOSTAŁOŚCI PO ODINSTALOWANYCH PROGRAMACH I GRACH' '   LEFTOVERS OF UNINSTALLED PROGRAMS AND GAMES') -ForegroundColor Cyan
        Write-Host (L '   (foldery i pliki idą do Kosza, wpisy rejestru i zadania są wcześniej zapisywane do pliku .reg / .xml)' '   (folders and files go to the Recycle Bin, registry entries and tasks are first saved to a .reg / .xml file)') -ForegroundColor DarkGray
        foreach ($p in $script:Pozostalosci) {
            $i++
            $znak = if ($p.Wybrana) { '[x]' } else { '[ ]' }
            $kolor = if ($p.Wybrana) { 'Green' } elseif ($p.Pewnosc -eq 'niska') { 'DarkYellow' } else { 'DarkGray' }
            $roz = RozmiarPozostalosci $p
            $pokaz = PokazPozostalosc $p
            Write-Host ("  {0} {1,2}. {2,-52} {3,10}  {4}: {5}" -f $znak, $i, $pokaz, $roz, (L 'pewność' 'confidence'), (NazwaPewnosci $p.Pewnosc)) -ForegroundColor $kolor
            Write-Host "           $($p.Dlaczego)" -ForegroundColor DarkGray
            if ($p.Ai) { Write-Host "           $EtykietaAi`: $($p.Ai)" -ForegroundColor DarkCyan }
        }
    }
    Write-Host ""
    Write-Host ((L '   Zaznaczone razem: ok. {0}' '   Selected in total: about {0}') -f (Rozmiar (SumaZaznaczonych))) -ForegroundColor White
}
