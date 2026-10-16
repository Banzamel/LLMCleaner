<#
    LLMCleaner - window state, Windows functions (DPI, taskbar, dark title bar) and size scaling (Px)
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

# Windows functions: console, scaling, dark title bar and scrollbars, taskbar progress
if (-not ('LlmWin.Native' -as [type])) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Gui\cs\LlmWin.cs')))
}

# Screen scaling (DPI) - must run before the first font. GDI+ caches the DPI on first use:
# when fonts were created before SetProcessDPIAware, sizes (Px) and text boxes were computed for 100%
# while labels were drawn for 125-200% - text overlapped and got clipped, and the chat was tiny.
[void][LlmWin.Native]::SetProcessDPIAware()
$script:Scale = [Math]::Max(1.0, [LlmWin.Native]::ScreenDpi() / 96.0)

function ConvertTo-Color([string]$hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function Px([double]$n) { [int][Math]::Round($n * $script:Scale) }
function New-Size([double]$w, [double]$h) { New-Object Drawing.Size((Px $w), (Px $h)) }
function New-Point([double]$x, [double]$y) { New-Object Drawing.Point((Px $x), (Px $y)) }
function New-Padding([double]$l, [double]$t, [double]$r, [double]$b) { New-Object Windows.Forms.Padding((Px $l), (Px $t), (Px $r), (Px $b)) }
