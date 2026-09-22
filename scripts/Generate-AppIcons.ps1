[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../FlowMuse-App'))
$source = [Drawing.Bitmap]::new((Join-Path $appRoot 'assets/images/flowmuse-app-icon.png'))

# Only resize/pad the checked-in artwork; never redraw it or change the source.
# Android's foreground is a 108dp layer with the artwork scaled to 72dp.
# Web maskable icons have an opaque background and 10% padding on each side.
$targets = @(
    @('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48, 1.0),
    @('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72, 1.0),
    @('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96, 1.0),
    @('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144, 1.0),
    @('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192, 1.0),
    @('android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png', 432, (2.0 / 3.0)),
    @('ohos/AppScope/resources/base/media/app_icon.png', 512, 0.8),
    @('ohos/entry/src/main/resources/base/media/icon.png', 512, 0.8),
    @('web/favicon.png', 48, 1.0),
    @('web/icons/Icon-192.png', 192, 1.0),
    @('web/icons/Icon-512.png', 512, 1.0),
    @('web/icons/Icon-maskable-192.png', 192, 0.8),
    @('web/icons/Icon-maskable-512.png', 512, 0.8)
)

try {
    if ($source.Width -ne $source.Height) { throw 'The source icon must be square.' }
    foreach ($target in $targets) {
        $relativePath, $size, $scale = $target
        $outputPath = Join-Path $appRoot $relativePath
        $bitmap = [Drawing.Bitmap]::new($size, $size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $attributes = [Drawing.Imaging.ImageAttributes]::new()
        $stream = [IO.MemoryStream]::new()
        try {
            $background = $source.GetPixel(0, 0)
            if ($relativePath.EndsWith('ic_launcher_foreground.png')) {
                $background = [Drawing.Color]::Transparent
            }
            $graphics.Clear($background)
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $contentSize = [int][Math]::Round($size * $scale)
            $offset = [int][Math]::Floor(($size - $contentSize) / 2)
            $destination = [Drawing.Rectangle]::new($offset, $offset, $contentSize, $contentSize)
            $graphics.DrawImage($source, $destination, 0, 0, $source.Width, $source.Height,
                [Drawing.GraphicsUnit]::Pixel, $attributes)
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            $bytes = $stream.ToArray()
            if ($Check) {
                if (!(Test-Path -LiteralPath $outputPath) -or
                    [Convert]::ToBase64String([IO.File]::ReadAllBytes($outputPath)) -cne
                    [Convert]::ToBase64String($bytes)) {
                    throw "Icon is missing or out of date: $relativePath"
                }
            } else {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
                [IO.File]::WriteAllBytes($outputPath, $bytes)
            }
            Write-Output "$relativePath (${size}x${size}) OK"
        } finally {
            $stream.Dispose()
            $attributes.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
} finally {
    $source.Dispose()
}
