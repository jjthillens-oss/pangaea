# Assemble review evidence after build_plant.py renders six neutral views.
# This does not alter the source photo or use it as a texture.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Draw-FittedImage($graphics, $file, $left, $top, $width, $height) {
    $img = [System.Drawing.Image]::FromFile((Join-Path $assetDir $file))
    try {
        $scale = [Math]::Min($width / $img.Width, $height / $img.Height)
        $drawWidth = [int]($img.Width * $scale)
        $drawHeight = [int]($img.Height * $scale)
        $x = $left + [int](($width - $drawWidth) / 2)
        $y = $top + [int](($height - $drawHeight) / 2)
        $graphics.DrawImage($img, $x, $y, $drawWidth, $drawHeight)
    } finally { $img.Dispose() }
}

foreach ($mode in @('gray', 'beauty')) {
    $canvas = [System.Drawing.Bitmap]::new(1560, 900)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $background = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(27, 31, 36))
    $light = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(235, 235, 229))
    $subtle = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(182, 190, 195))
    $titleFont = [System.Drawing.Font]::new('Arial', 24, [System.Drawing.FontStyle]::Bold)
    $labelFont = [System.Drawing.Font]::new('Arial', 15)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(27, 31, 36))
        $graphics.DrawString("Tideleaf | $mode", $titleFont, $light, 28, 24)
        $graphics.DrawString('Original marine-flora prop; CC0 morphology reference at left', $labelFont, $subtle, 30, 68)
        Draw-FittedImage $graphics 'reference-smithora-naiadum.jpg' 30 135 360 620
        $graphics.DrawString('Reference: Al Kordesch / CC0 1.0', $labelFont, $light, 30, 780)
        $views = @('front', 'side', 'top')
        for ($i = 0; $i -lt $views.Count; $i++) {
            $left = 420 + $i * 375
            $view = $views[$i]
            Draw-FittedImage $graphics "renders/$mode-$view.png" $left 140 355 620
            $graphics.DrawString($view.ToUpperInvariant(), $labelFont, $light, $left + 8, 780)
        }
        $graphics.DrawString('Reference informs broad frond behavior only; no photo pixels or traced geometry in GLB.', $labelFont, $subtle, 30, 846)
        $canvas.Save((Join-Path $assetDir "$mode-comparison.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $titleFont.Dispose(); $labelFont.Dispose(); $light.Dispose(); $subtle.Dispose();
        $background.Dispose(); $graphics.Dispose(); $canvas.Dispose()
    }
}
