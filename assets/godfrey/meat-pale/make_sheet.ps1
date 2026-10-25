param([string]$Root = $PSScriptRoot)

Add-Type -AssemblyName System.Drawing
$output = Join-Path $Root 'reference_result_sheet.png'
$canvas = [System.Drawing.Bitmap]::new(1800, 900)
$gfx = [System.Drawing.Graphics]::FromImage($canvas)
$gfx.Clear([System.Drawing.Color]::FromArgb(221, 224, 224))
$gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [System.Drawing.Font]::new('Arial', 15)
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(30, 40, 45))

function Add-Tile([int]$x, [int]$y, [string]$file, [string]$caption, [bool]$crop = $false) {
    $image = [System.Drawing.Image]::FromFile((Join-Path $Root $file))
    try {
        $width = 570.0
        $height = 390.0
        if ($crop) {
            $ratio = 1.35 * [Math]::Max($width / $image.Width, $height / $image.Height)
        } else {
            $ratio = [Math]::Min($width / $image.Width, $height / $image.Height)
        }
        $scaledW = [float]($image.Width * $ratio)
        $scaledH = [float]($image.Height * $ratio)
        $drawX = [float]($x + 15 + ($width - $scaledW) / 2)
        $drawY = [float]($y + 45 + ($height - $scaledH) / 2)
        $region = [System.Drawing.Rectangle]::new($x + 15, $y + 45, 570, 390)
        $gfx.SetClip($region)
        $gfx.DrawImage($image, $drawX, $drawY, $scaledW, $scaledH)
        $gfx.ResetClip()
        $gfx.DrawString($caption, $font, $brush, [float]($x + 15), [float]($y + 12))
    } finally {
        $image.Dispose()
    }
}

try {
    Add-Tile 0 0 'reference_cc0.jpg' 'CC0 source: kakyusei, form only'
    Add-Tile 600 0 'gray_three_quarter.png' 'Original gray shape'
    Add-Tile 1200 0 'material_three_quarter.png' 'Original PBR under neutral light'
    Add-Tile 0 450 'reference_cc0.jpg' 'Source center: overlap and pale ridge' $true
    Add-Tile 600 450 'godot_review.png' 'Godot isolated close view'
    Add-Tile 1200 450 'godot_gameplay.png' 'Godot 14 m gameplay view'
    $canvas.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $brush.Dispose()
    $font.Dispose()
    $gfx.Dispose()
    $canvas.Dispose()
}
Write-Output $output
