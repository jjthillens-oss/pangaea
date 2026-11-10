param(
    [string]$PackageRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$reference = Join-Path $PackageRoot 'reference\cc0-steak-and-herbs.jpg'
$gray = Join-Path $PackageRoot 'renders\gray-three-quarter.png'
$material = Join-Path $PackageRoot 'renders\material-three-quarter.png'
$game = Join-Path $PackageRoot 'renders\godot-gameplay.png'
$output = Join-Path $PackageRoot 'comparison.png'

foreach ($path in @($reference, $gray, $material, $game)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing final comparison input: $path" }
}

$width = 1600
$height = 1060
$canvas = [System.Drawing.Bitmap]::new($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.Clear([System.Drawing.Color]::FromArgb(247, 244, 238))
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [System.Drawing.Font]::new('Arial', 21)
$subfont = [System.Drawing.Font]::new('Arial', 14)
$ink = [System.Drawing.Brushes]::Black

function Draw-Tile([string]$imagePath, [string]$title, [int]$x, [int]$y, [int]$w, [int]$h, [System.Drawing.Rectangle]$crop) {
    $photo = [System.Drawing.Image]::FromFile($imagePath)
    try {
        $scale = [Math]::Min(($w - 14) / $crop.Width, ($h - 43) / $crop.Height)
        $drawW = [int]($crop.Width * $scale)
        $drawH = [int]($crop.Height * $scale)
        $drawX = $x + [int](($w - $drawW) / 2)
        $drawY = $y + 33 + [int](($h - 43 - $drawH) / 2)
        $graphics.DrawString($title, $subfont, $ink, $x + 6, $y + 4)
        $dest = [System.Drawing.Rectangle]::new($drawX, $drawY, $drawW, $drawH)
        $graphics.DrawImage($photo, $dest, $crop, [System.Drawing.GraphicsUnit]::Pixel)
    } finally {
        $photo.Dispose()
    }
}

try {
    $graphics.DrawString('Red meat food prop — reference and final review', $font, $ink, 24, 16)
    Draw-Tile $reference 'CC0 reference: Jez Timms, 2015' 24 70 750 450 ([System.Drawing.Rectangle]::new(180, 0, 650, 600))
    Draw-Tile $game 'Godot elevated gameplay view' 820 70 750 450 ([System.Drawing.Rectangle]::new(155, 205, 665, 520))
    Draw-Tile $gray 'Blender gray shape, three-quarter' 24 550 750 450 ([System.Drawing.Rectangle]::new(145, 220, 665, 490))
    Draw-Tile $material 'Blender neutral material, three-quarter' 820 550 750 450 ([System.Drawing.Rectangle]::new(145, 220, 665, 490))
    $canvas.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $output
} finally {
    $graphics.Dispose()
    $canvas.Dispose()
    $font.Dispose()
    $subfont.Dispose()
}
