<#
    LLMCleaner - plan czyszczenia (reguly, bez modelu), raport i podsumowanie
#>

# Kategorie: zaznaczone, gdy cokolwiek zawieraja. Kosz (nieodwracalny), DNS i kategorie
# "tylko recznie" zawsze odznaczone. Pozostalosci: zaznaczone przy pewnosci wysokiej i sredniej.
function UlozPlan {
    foreach ($k in $script:Kategorie) {
        $k.Wybrana = -not $k.TylkoRecznie -and -not $k.Blokada -and $k.Typ -in 'folder', 'miniatury' -and $k.Bajty -gt 0
    }
    foreach ($p in $script:Pozostalosci) { $p.Wybrana = $p.Pewnosc -in 'wysoka', 'srednia' }
}

function SumaZablokowanych { [double](@($script:Kategorie | Where-Object { $_.Wybrana } | ForEach-Object { [double]$_.Zablokowane }) | Measure-Object -Sum).Sum }

function SumaZaznaczonych { [double](@($script:Kategorie) + @($script:Pozostalosci) | Where-Object { $_.Wybrana } | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum }

function RaportJson {
    # Gotowa lista od najwiekszej - maly model zle porownuje rozmiary zapisane tekstem w roznych sekcjach
    $odNajwiekszej = @(@($script:Kategorie) + @($script:Pozostalosci) | Where-Object { $_.Bajty -gt 0 } |
            Sort-Object { [double]$_.Bajty } -Descending | Select-Object -First 15 | ForEach-Object {
                @{ pozycja = $(if ($_.Sciezka -and -not $_.Opis) { $_.Sciezka } else { $_.Nazwa }); rozmiar = (Rozmiar $_.Bajty); zaznaczona = [bool]$_.Wybrana } })
    $raport = @{
        plan_od_najwiekszej        = $odNajwiekszej
        zaznaczone_razem           = (Rozmiar (SumaZaznaczonych))
        dyski                      = $script:Dysk.Dyski
        kategorie                  = @($script:Kategorie | ForEach-Object {
                @{ id = $_.Id; nazwa = $_.Nazwa; opis = $_.Opis; zaznaczona = [bool]$_.Wybrana
                    rozmiar = (RozmiarKategorii $_); tylko_recznie = [bool]$_.TylkoRecznie; blokada = $_.Blokada
                } })
        pozostalosci               = @($script:Pozostalosci | ForEach-Object {
                @{ id = $_.Id; typ = $_.Typ; sciezka = $_.Sciezka; zaznaczona = [bool]$_.Wybrana
                    rozmiar = $(if (NaKosz $_) { Rozmiar $_.Bajty } else { '-' })
                    ostatnia_zmiana = $(if ($_.Ostatnio) { $_.Ostatnio.ToString('yyyy-MM-dd') }); pewnosc = $_.Pewnosc
                    dlaczego = $_.Dlaczego; czym_jest = $_.Ai
                } })
        najwieksze_foldery_profilu = $script:Dysk.Profil
        duze_foldery_appdata       = $script:Dysk.AppData
        najwieksze_programy        = $script:Dysk.Programy
        system                     = $script:Dysk.System
        analiza_dyskow             = @($script:Analizy.Values | ForEach-Object {
                @{ dysk = "$($_.Litera):"; pozycje = @(@($_.Foldery) + @($_.Pliki) | ForEach-Object {
                            @{ sciezka = $_.Sciezka; rozmiar = (Rozmiar $_.Bajty); podpowiedz = $_.Podpowiedz; czym_jest = $_.Ai } })
                } })
        autostart                  = @($script:Autostart | Where-Object { $_ } | ForEach-Object {
                @{ nazwa = $_.Nazwa; wlaczony = [bool]$_.Wlaczony; wydawca = $_.Wydawca; zrodlo = $_.Zrodlo; polecenie = $_.Polecenie
                    chroniony = $_.Chroniony; czym_jest = $_.Ai
                } })
    }
    ConvertTo-Json -InputObject $raport -Depth 10 -Compress
}

# Podsumowanie przed czyszczeniem: lista linii @{ T = tekst; K = kolor } albo $null, gdy nic nie zaznaczono
function Podsumowanie {
    $wybrane = @($script:Kategorie | Where-Object { $_.Wybrana })
    $wybranePoz = @($script:Pozostalosci | Where-Object { $_.Wybrana })
    if (-not $wybrane.Count -and -not $wybranePoz.Count) { return $null }
    $linie = [System.Collections.Generic.List[object]]::new()
    function Dodaj($t, $k = 'Gray') { $linie.Add(@{ T = $t; K = $k }) }
    if ($wybrane.Count) {
        Dodaj (L 'Zostanie wyczyszczone:' 'To be cleaned:') 'White'
        foreach ($k in $wybrane) {
            $roz = if (MierzalnaKategoria $k) { Rozmiar $k.Bajty } elseif ($k.Typ -eq 'dns') { '-' } else { L 'nieznane' 'unknown' }
            Dodaj ("  - {0,-52} {1,10}" -f $k.Nazwa, $roz)
        }
        $suma = ($wybrane | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
        Dodaj ''
        Dodaj ((L 'Zwolnione miejsce   : ok. {0}' 'Space freed         : about {0}') -f (Rozmiar $suma)) 'Green'
        Dodaj ((L 'Wolne na {1} teraz  : {0}' 'Free on {1} now     : {0}') -f (Rozmiar $script:WolnePrzed), $Sys)
        Dodaj ((L 'Wolne na {1} po     : ok. {0}' 'Free on {1} after   : about {0}') -f (Rozmiar ($script:WolnePrzed + $suma)), $Sys)
        $zablokowane = SumaZablokowanych
        if ($zablokowane) { Dodaj ((L 'Zablokowane         : {0} (pliki w użyciu - nie zostaną usunięte, nie są wliczone)' 'Locked              : {0} (files in use - not deleted, not included)') -f (Rozmiar $zablokowane)) 'Yellow' }
        Dodaj (L '(część plików może być w użyciu - wtedy zostaną pominięte i zysk będzie mniejszy)' '(some files may be in use - they are skipped and the gain will be smaller)') 'DarkGray'
    }
    $doKosza = @($wybranePoz | Where-Object { NaKosz $_ })
    $pozRejestr = @($wybranePoz | Where-Object { $_.Typ -in 'rejestr', 'wartosc' })
    $pozZadania = @($wybranePoz | Where-Object { $_.Typ -eq 'zadanie' })
    if ($wybranePoz.Count) {
        Dodaj ''
        Dodaj (L 'Pozostałości po odinstalowanych programach i grach:' 'Leftovers of uninstalled programs and games:') 'White'
        foreach ($p in $wybranePoz) {
            Dodaj ("  - {0,-52} {1,10}" -f (PokazPozostalosc $p), (RozmiarPozostalosci $p))
        }
        if ($doKosza.Count) {
            $sp = ($doKosza | ForEach-Object { [double]$_.Bajty } | Measure-Object -Sum).Sum
            Dodaj ((L 'Do Kosza            : {0} ({1}) - miejsce zwolni się po opróżnieniu Kosza' 'To the Recycle Bin  : {0} ({1}) - the space is freed when you empty the Recycle Bin') -f $doKosza.Count, (Rozmiar $sp))
        }
        if ($pozRejestr.Count) {
            Dodaj ((L 'Klucze rejestru     : {0} - kopia .reg w logs\kopie_rejestru + punkt przywracania systemu' 'Registry keys       : {0} - .reg backup in logs\kopie_rejestru + System Restore point') -f $pozRejestr.Count)
        }
        if ($pozZadania.Count) {
            Dodaj ((L 'Zadania Harmonogramu: {0} - kopia .xml w logs\kopie_rejestru' 'Scheduled tasks     : {0} - .xml backup in logs\kopie_rejestru') -f $pozZadania.Count)
        }
    }
    $uwagi = @()
    if ($wybrane | Where-Object { $_.Id -eq 'kosz' }) { $uwagi += L 'Kosz zostanie opróżniony NIEODWRACALNIE (przed przeniesieniem pozostałości).' 'The Recycle Bin is emptied PERMANENTLY (before leftovers are moved to it).' }
    if ($wybrane | Where-Object { $_.Typ -eq 'miniatury' }) { $uwagi += L 'Eksplorator zostanie zrestartowany - pasek zadań zniknie na kilka sekund.' 'File Explorer restarts - the taskbar disappears for a few seconds.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'dism' }) { $uwagi += L 'DISM potrwa kilka minut; potem nie odinstalujesz starszych aktualizacji.' 'DISM takes a few minutes; older updates can no longer be uninstalled afterwards.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'driverstore' }) { $uwagi += L 'Usunięte starsze wersje sterowników nie wrócą - przed usunięciem powstanie punkt przywracania.' 'Removed older driver versions cannot be brought back - a System Restore point is created first.' }
    if ($wybrane | Where-Object { $_.Typ -eq 'winold' }) { $uwagi += L 'Po usunięciu Windows.old nie da się wrócić do poprzedniej wersji Windows.' 'After removing Windows.old you cannot go back to the previous Windows version.' }
    if ($wybrane | Where-Object { $_.Procesy }) { $uwagi += L 'Nie otwieraj przeglądarki w trakcie czyszczenia.' 'Do not open a browser while cleaning.' }
    if ($wybranePoz | Where-Object { $_.Pewnosc -eq 'niska' }) { $uwagi += L 'Zaznaczono pozycje o niskiej pewności (zapisy gier / duże pliki) - upewnij się, że ich nie potrzebujesz.' 'Low-confidence items are selected (game saves / large files) - make sure you do not need them.' }
    if ($uwagi.Count) { Dodaj ''; foreach ($u in $uwagi) { Dodaj "! $u" 'Yellow' } }
    , $linie
}
