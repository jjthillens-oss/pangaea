param(
    [Parameter(Mandatory = $true)]
    [string]$GodotImage
)

# Create a final-revision paired sheet after actual image inspection. The
# Godot image is copied from a separate review project, never substituted with
# a second Blender beauty render.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$reference = Join-Path $assetDirectory 'reference/cc0-bush-reference.jpg'
$gray = Join-Path $assetDirectory 'views/gray-three-quarter.png'
$material = Join-Path $assetDirectory 'views/material-three-quarter.png'
$inputs = @($reference, $gray, $material, $GodotImage)
foreach ($path in $inputs) { if (-not (Test-Path -LiteralPath $path)) { throw "Missing sheet image: $path" } }

$sheet = New-Object System.Drawing.Bitmap 2020, 1170
$drawing = [System.Drawing.Graphics]::FromImage($sheet)
$drawing.Clear([System.Drawing.Color]::FromArgb(234, 237, 239))
$drawing.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font('Segoe UI', 19)
$smallFont = New-Object System.Drawing.Font('Segoe UI', 15)
$ink = [System.Drawing.Brushes]::Black
$labels = @('CC0 reference', 'Blender clay', 'Blender PBR', 'Godot import render')
try {
    $drawing.DrawString('Bush 2 | dense bronzeleaf | final-revision comparison', $font, $ink, 24, 14)
    for ($index = 0; $index -lt 4; $index++) {
        $image = [System.Drawing.Image]::FromFile($inputs[$index])
        try {
            $cellX = 20 + $index * 500
            $drawing.DrawString($labels[$index], $smallFont, $ink, $cellX + 5, 61)
            # Review renders include intentional framing space. Crop only that
            # empty margin so the reference and result plants have comparable
            # display height; leave every part of the asset in frame.
            if ($index -eq 0) {
                $frame = New-Object System.Drawing.Rectangle 0, 0, $image.Width, $image.Height
            } elseif ($index -eq 3) {
                $frame = New-Object System.Drawing.Rectangle 260, 125, 500, 550
            } else {
                $frame = New-Object System.Drawing.Rectangle 165, 105, 500, 590
            }
            $scale = [Math]::Min(485.0 / $frame.Width, 700.0 / $frame.Height)
            $width = [int]($frame.Width * $scale)
            $height = [int]($frame.Height * $scale)
            $targetFull = New-Object System.Drawing.Rectangle ($cellX + [int]((485 - $width) / 2)), 100, $width, $height
            $drawing.DrawImage($image, $targetFull, $frame, [System.Drawing.GraphicsUnit]::Pixel)
            if ($index -eq 0 -or $index -eq 2) {
                # Crops compare crown layering/color separately from framing.
                $source = New-Object System.Drawing.Rectangle ([int]($image.Width * 0.17)), ([int]($image.Height * 0.14)), ([int]($image.Width * 0.66)), ([int]($image.Height * 0.48))
                $target = New-Object System.Drawing.Rectangle ($cellX + 30), 855, 420, 255
                $drawing.DrawImage($image, $target, $source, [System.Drawing.GraphicsUnit]::Pixel)
                $drawing.DrawString('upper crown detail', $smallFont, $ink, $cellX + 31, 1118)
            }
        } finally { $image.Dispose() }
    }
    $output = Join-Path $assetDirectory 'comparison-sheet.png'
    $sheet.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $output
} finally {
    $font.Dispose()
    $smallFont.Dispose()
    $drawing.Dispose()
    $sheet.Dispose()
}
