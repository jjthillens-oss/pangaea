Add-Type -AssemblyName System.Drawing
$assetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$canvasColor = [System.Drawing.Color]::FromArgb(31, 37, 44)
$textColor = [System.Drawing.Color]::FromArgb(238, 235, 228)
$font = [System.Drawing.Font]::new('Arial', 18)
$small = [System.Drawing.Font]::new('Arial', 11)
$brush = [System.Drawing.SolidBrush]::new($textColor)
$back = [System.Drawing.SolidBrush]::new($canvasColor)

function Make-Sheet($name, $panels, $subtitle) {
    $bitmap = [System.Drawing.Bitmap]::new(1600, 850)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.Clear($canvasColor)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawString($name, $font, $brush, 28, 18)
    $g.DrawString($subtitle, $small, $brush, 30, 53)
    foreach ($p in $panels) {
        $img = [System.Drawing.Image]::FromFile((Join-Path $assetDir $p.File))
        $dest = [System.Drawing.Rectangle]::new($p.X, 100, $p.W, 650)
        $src = [System.Drawing.Rectangle]::new($p.SX, $p.SY, $p.SW, $p.SH)
        $g.FillRectangle($back, $dest)
        $g.DrawImage($img, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString($p.Label, $small, $brush, $p.X, 768)
        $img.Dispose()
    }
    $filename = $name.Replace(' ', '_').ToLowerInvariant() + '.png'
    $bitmap.Save((Join-Path $assetDir $filename), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bitmap.Dispose()
}

Make-Sheet 'Reference and rock' @(
    @{ File='reference_cc0.jpg'; X=30; W=750; SX=265; SY=60; SW=500; SH=510; Label='CC0 reference crop: actionbeard90, Boulder 2021-12-22.jpg' },
    @{ File='material_front.png'; X=820; W=750; SX=0; SY=0; SW=760; SH=760; Label='Original Blender rock, front view, neutral studio' }
) 'Compare broad cap, left recess, right lobe and undercut base; shapes are interpreted, not copied.'

Make-Sheet 'Recess detail' @(
    @{ File='reference_cc0.jpg'; X=30; W=490; SX=338; SY=130; SW=220; SH=290; Label='CC0 photo: natural front recess' },
    @{ File='gray_front.png'; X=550; W=490; SX=190; SY=230; SW=260; SH=315; Label='Original gray shape: inset geometry' },
    @{ File='godot_review.png'; X=1070; W=490; SX=140; SY=180; SW=420; SH=430; Label='Godot 4.7.2 import: same exported GLB' }
) 'Detail crops are enlarged for inspection; no source pixels were used as a texture or mesh input.'

$brush.Dispose()
$back.Dispose()
$font.Dispose()
$small.Dispose()
