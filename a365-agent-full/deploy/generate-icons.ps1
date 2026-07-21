# Copyright (c) Microsoft. All rights reserved.
# Generate placeholder Teams app-package icons (color.png 192x192, outline.png 32x32).
# Replace with real branding any time before `a365 publish`.
#   ./deploy/generate-icons.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot "../frontend/teams"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function New-Icon([int]$size, [string]$path, [System.Drawing.Color]$bg, [bool]$outline) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    if ($outline) {
        $g.Clear([System.Drawing.Color]::Transparent)
        $pen = New-Object System.Drawing.Pen($bg, [Math]::Max(2, $size / 12))
        $g.DrawEllipse($pen, 2, 2, $size - 5, $size - 5)
        $pen.Dispose()
    } else {
        $g.Clear($bg)
        $font = New-Object System.Drawing.Font("Segoe UI", ($size / 3), [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = "Center"; $sf.LineAlignment = "Center"
        $g.DrawString("A", $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 0, $size, $size)), $sf)
        $font.Dispose()
    }
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  wrote $path"
}

$brand = [System.Drawing.Color]::FromArgb(0x46, 0x4E, 0xB8)  # A365 indigo
New-Icon 192 (Join-Path $outDir "color.png")   $brand $false
New-Icon 32  (Join-Path $outDir "outline.png") $brand $true
Write-Host "Done. Icons in $outDir" -ForegroundColor Green
