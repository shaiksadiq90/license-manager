<#
  Screen recorder used by demo.ps1: saves a JPEG of the primary screen's working area (everything above the taskbar)
  every IntervalMs, named f_<unix-ms>.jpg, until a file called STOP appears in OutDir or MaxMinutes passes.
#>
param([Parameter(Mandatory)][string]$OutDir, [int]$IntervalMs = 1000, [int]$MaxMinutes = 25)

Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class CapDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][CapDpi]::SetProcessDPIAware()   # capture in physical pixels
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

New-Item -ItemType Directory -Force $OutDir | Out-Null
$area  = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$enc   = New-Object System.Drawing.Imaging.EncoderParameters(1)
$enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
$bmp = New-Object System.Drawing.Bitmap($area.Width, $area.Height)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$stop = Join-Path $OutDir "STOP"
$end  = (Get-Date).AddMinutes($MaxMinutes)

while (-not (Test-Path $stop) -and (Get-Date) -lt $end) {
  $t0 = [Environment]::TickCount
  try {
    $g.CopyFromScreen($area.X, $area.Y, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $OutDir ("f_{0}.jpg" -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())), $codec, $enc)
  } catch { }   # screen locked or session briefly unavailable: skip this frame
  $left = $IntervalMs - ([Environment]::TickCount - $t0)
  if ($left -gt 0) { Start-Sleep -Milliseconds $left }
}
$g.Dispose(); $bmp.Dispose()
