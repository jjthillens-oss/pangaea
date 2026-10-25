param(
    [Parameter(Mandatory = $true)]
    [string]$GodotScreenshot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$shotPath = (Resolve-Path -LiteralPath $GodotScreenshot).Path
$outputPath = Join-Path $assetDir 'comparison-sheet.png'

$canvas = [System.Drawing.Bitmap]::new(2000, 2250)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.Clear([System.Drawing.Color]::FromArgb(236, 235, 230))
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$titleFont = [System.Drawing.Font]::new('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
$labelFont = [System.Drawing.Font]::new('Segoe UI', 17)
$ink = [System.Drawing.Brushes]::Black

function Draw-Panel([string]$imagePath, [string]$label, [int]$x, [int]$y) {
    if (-not (Test-Path -LiteralPath $imagePath)) { throw "Missing sheet input: $imagePath" }
    $image = [System.Drawing.Image]::FromFile($imagePath)
    try {
        $maxWidth = 910
        $maxHeight = 590
        $scale = [Math]::Min($maxWidth / $image.Width, $maxHeight / $image.Height)
        $width = [int][Math]::Round($image.Width * $scale)
        $height = [int][Math]::Round($image.Height * $scale)
        $graphics.FillRectangle([System.Drawing.Brushes]::White, $x, $y + 42, $maxWidth, $maxHeight)
        $graphics.DrawImage($image, $x + [int](($maxWidth - $width) / 2),
            $y + 42 + [int](($maxHeight - $height) / 2), $width, $height)
        $graphics.DrawString($label, $labelFont, $ink, $x, $y)
    } finally {
        $image.Dispose()
    }
}

try {
    $graphics.DrawString('Nest-straw prop: reference and review', $titleFont, $ink, 65, 20)
    $graphics.DrawString('CC0 photo: Jerry Kiesewetter, Empty Nest (Unsplash), 2017.', $labelFont, $ink, 65, 70)
    $graphics.DrawString('Photo is monochrome; palette and unseen surfaces are original inference.', $labelFont, $ink, 65, 100)

    Draw-Panel (Join-Path $assetDir 'reference-cc0.jpg') 'CC0 reference' 65 165
    Draw-Panel (Join-Path $assetDir 'gray-threequarter.png') 'Gray shape, three-quarter' 1030 165
    Draw-Panel (Join-Path $assetDir 'material-threequarter.png') 'Blender PBR, same silhouette' 65 835
    Draw-Panel $shotPath 'Isolated Godot render, gameplay distance' 1030 835
    Draw-Panel (Join-Path $assetDir 'gray-front.png') 'Gray front profile' 65 1505
    Draw-Panel (Join-Path $assetDir 'gray-side.png') 'Gray side profile' 1030 1505
    $canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $outputPath
} finally {
    $graphics.Dispose()
    $canvas.Dispose()
    $titleFont.Dispose()
    $labelFont.Dispose()
}
