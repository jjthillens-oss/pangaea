# Make the matched reference/model/Godot comparison with built-in Windows GDI+.
# Run after visually inspecting every source image.
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sheetDir = Join-Path $root 'sheets'
New-Item -ItemType Directory -Force -Path $sheetDir | Out-Null
$items = @(
    @{ File = 'reference_salvia_cc0.jpg'; Title = 'CC0 reference - Cecelia Alexander' },
    @{ File = 'views/gray-three_quarter.png'; Title = 'Original model - gray shape' },
    @{ File = 'views/material-three_quarter.png'; Title = 'Original model - material' },
    @{ File = 'views/gray-front.png'; Title = 'Gray - front' },
    @{ File = 'views/gray-side.png'; Title = 'Gray - side' },
    @{ File = 'views/godot-review.png'; Title = 'Isolated Godot 4.7.2 render' }
)
$tileWidth = 640
$tileHeight = 520
$sheet = [System.Drawing.Bitmap]::new($tileWidth * 3, $tileHeight * 2)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([System.Drawing.Color]::FromArgb(216, 220, 221))
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [System.Drawing.Font]::new('Arial', 18)
$ink = [System.Drawing.Brushes]::Black
try {
    for ($index = 0; $index -lt $items.Count; $index++) {
        $item = $items[$index]
        $x = ($index % 3) * $tileWidth
        $y = [Math]::Floor($index / 3) * $tileHeight
        $graphics.DrawString($item.Title, $font, $ink, ($x + 16), ($y + 14))
        $bitmap = [System.Drawing.Bitmap]::new((Join-Path $root $item.File))
        try {
            $ratio = [Math]::Min(($tileWidth - 32) / $bitmap.Width, ($tileHeight - 62) / $bitmap.Height)
            $width = [int]($bitmap.Width * $ratio)
            $height = [int]($bitmap.Height * $ratio)
            $left = $x + [int](($tileWidth - $width) / 2)
            $top = $y + 48 + [int](($tileHeight - 62 - $height) / 2)
            $graphics.DrawImage($bitmap, $left, $top, $width, $height)
        } finally {
            $bitmap.Dispose()
        }
    }
    $sheet.Save((Join-Path $sheetDir 'reference-result.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $font.Dispose()
    $graphics.Dispose()
    $sheet.Dispose()
}
