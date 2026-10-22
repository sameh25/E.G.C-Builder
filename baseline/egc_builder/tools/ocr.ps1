# Local text recognition with the OCR engine built into Windows 10/11 (Windows.Media.Ocr) - no internet, no API key, no extra install.
# powershell -NoProfile -ExecutionPolicy Bypass -File ocr.ps1 -Path <image> -Out <json> [-Passes "en-US:2,en-US:4,ar-SA:2"]
# Each pass = one OCR language at one enlargement (small dimension text and text crossed by dimension ticks read differently at different sizes).
# -> { "ok", "engine", "width", "height", "passes": [ { "lang", "scale", "angle", "lines": [ { "text", "words": [ { "text", "x", "y", "w", "h" } ] } ] } ] }
#    word positions in the pixels of the ORIGINAL image (each pass may deskew differently: the caller aligns the passes).
param([string]$Path, [string]$Out, [string]$Passes = 'en-US:2,en-US:4,ar-SA:2')
$ErrorActionPreference = 'Stop'
function W($o) { [IO.File]::WriteAllText($Out, ($o | ConvertTo-Json -Depth 9 -Compress), (New-Object Text.UTF8Encoding $false)) }
try {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op, [Type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
  [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
  [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
  [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
  [Windows.Graphics.Imaging.BitmapTransform, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
  [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync((Resolve-Path -LiteralPath $Path).ProviderPath)) ([Windows.Storage.StorageFile])
  $res_all = @()
  $pw = 0; $ph = 0
  foreach ($p in $Passes.Split(',')) {
    $lang, $sc = $p.Split(':')
    $lg = New-Object Windows.Globalization.Language $lang
    if (-not [Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($lg)) { $res_all += @{ lang = $lang; scale = $sc; error = "OCR language '$lang' not installed in Windows"; lines = @() }; continue }
    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $pw = $dec.PixelWidth; $ph = $dec.PixelHeight
    $k = [Math]::Min([double]$sc, [Math]::Floor([Windows.Media.Ocr.OcrEngine]::MaxImageDimension / [Math]::Max($pw, $ph) * 100) / 100)
    if ($k -lt 1) { $k = 1 }
    $tr = New-Object Windows.Graphics.Imaging.BitmapTransform
    $tr.ScaledWidth = [uint32]($pw * $k); $tr.ScaledHeight = [uint32]($ph * $k)
    $tr.InterpolationMode = [Windows.Graphics.Imaging.BitmapInterpolationMode]::Fant
    $bmp = Await ($dec.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied, $tr,
        [Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation, [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lg)
    $res = Await ($eng.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
    $lines = @($res.Lines | ForEach-Object { @{ text = $_.Text; words = @($_.Words | ForEach-Object { $r = $_.BoundingRect; @{ text = $_.Text; x = [Math]::Round($r.X / $k, 1); y = [Math]::Round($r.Y / $k, 1); w = [Math]::Round($r.Width / $k, 1); h = [Math]::Round($r.Height / $k, 1) } }) } })
    $res_all += @{ lang = $lang; scale = $k; angle = $res.TextAngle; lines = $lines }
    $stream.Dispose()
  }
  W @{ ok = $true; engine = 'Windows.Media.Ocr'; width = $pw; height = $ph; passes = $res_all }
} catch { W @{ ok = $false; error = "OCR_FAILED: $($_.Exception.Message)" } }
