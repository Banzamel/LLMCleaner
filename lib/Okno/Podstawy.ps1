<#
    LLMCleaner - stan okna, funkcje Windows (DPI, pasek zadan, ciemny pasek tytulu) i skalowanie wymiarow (Px)
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:UI = @{}
$script:Zeskanowano = $false
$script:Pracuje = $false
$script:Czyszczenie = $false
$script:InstalujeSterowniki = $false
$script:Kroki = @()
$script:WynikCzyszczenia = $null
$script:FiltrPlanu = 'wszystko'
$script:Strona = 'przeglad'
$script:Skala = 1.0

# Funkcje Windows: konsola, skalowanie, ciemny pasek tytulu i przewijania, postep na pasku zadan
if (-not ('LlmWin.Natywne' -as [type])) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Okno\cs\LlmWin.cs')))
}

# Skalowanie ekranu (DPI) - koniecznie przed pierwsza czcionka. GDI+ zapamietuje DPI przy pierwszym uzyciu:
# gdy czcionki powstawaly przed SetProcessDPIAware, wymiary (Px) i pola tekstowe byly liczone dla 100%,
# a etykiety rysowane dla 125-200% - tekst nachodzil na siebie i byl uciety, a czat malutki.
[void][LlmWin.Natywne]::SetProcessDPIAware()
$script:Skala = [Math]::Max(1.0, [LlmWin.Natywne]::DpiEkranu() / 96.0)

function Kolor([string]$hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function Px([double]$n) { [int][Math]::Round($n * $script:Skala) }
function Rozm([double]$w, [double]$h) { New-Object Drawing.Size((Px $w), (Px $h)) }
function Pkt([double]$x, [double]$y) { New-Object Drawing.Point((Px $x), (Px $y)) }
function Marg([double]$l, [double]$t, [double]$r, [double]$b) { New-Object Windows.Forms.Padding((Px $l), (Px $t), (Px $r), (Px $b)) }
