<#
    LLMCleaner - stan okna, funkcje Windows (DPI, pasek zadan, ciemny pasek tytulu) i skalowanie wymiarow (Px)
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:UI = @{}
$script:Scanned = $false
$script:Working = $false
$script:Cleaning = $false
$script:InstallingDrivers = $false
$script:Steps = @()
$script:CleanupResult = $null
$script:PlanFilter = 'all'
$script:CurrentPage = 'overview'
$script:Scale = 1.0

# Funkcje Windows: konsola, skalowanie, ciemny pasek tytulu i przewijania, postep na pasku zadan
if (-not ('LlmWin.Native' -as [type])) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Gui\cs\LlmWin.cs')))
}

# Skalowanie ekranu (DPI) - koniecznie przed pierwsza czcionka. GDI+ zapamietuje DPI przy pierwszym uzyciu:
# gdy czcionki powstawaly przed SetProcessDPIAware, wymiary (Px) i pola tekstowe byly liczone dla 100%,
# a etykiety rysowane dla 125-200% - tekst nachodzil na siebie i byl uciety, a czat malutki.
[void][LlmWin.Native]::SetProcessDPIAware()
$script:Scale = [Math]::Max(1.0, [LlmWin.Native]::ScreenDpi() / 96.0)

function ConvertTo-Color([string]$hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function Px([double]$n) { [int][Math]::Round($n * $script:Scale) }
function New-Size([double]$w, [double]$h) { New-Object Drawing.Size((Px $w), (Px $h)) }
function New-Point([double]$x, [double]$y) { New-Object Drawing.Point((Px $x), (Px $y)) }
function New-Padding([double]$l, [double]$t, [double]$r, [double]$b) { New-Object Windows.Forms.Padding((Px $l), (Px $t), (Px $r), (Px $b)) }
