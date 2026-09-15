using namespace System
using namespace System.IO
using namespace Windows.Graphics.Imaging
using namespace Windows.Media.Ocr
using namespace Windows.Storage

$imgPath = 'C:\Users\HYM\.gemini\antigravity\brain\fa5e9227-a130-4b62-a6de-d36f8e057889\.user_uploaded\media_1788152736510.png'
$file = [StorageFile]::GetFileFromPathAsync($imgPath).GetAwaiter().GetResult()
$stream = $file.OpenAsync([FileAccessMode]::Read).GetAwaiter().GetResult()
$decoder = [BitmapDecoder]::CreateAsync($stream).GetAwaiter().GetResult()
$bitmap = $decoder.GetSoftwareBitmapAsync().GetAwaiter().GetResult()

$engine = [OcrEngine]::TryCreateFromUserProfileLanguages()
$result = $engine.RecognizeAsync($bitmap).GetAwaiter().GetResult()

$result.Lines | ForEach-Object { $_.Text }