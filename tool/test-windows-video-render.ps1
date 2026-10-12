param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [ValidateSet(720, 1080)][int]$Height = 720,
  [string]$MediaDir,
  [switch]$GenerateFixture,
  [string]$ExePath
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$validationDir = Join-Path $repoRoot 'build/validation'
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
if (!$MediaDir) { $MediaDir = Join-Path $repoRoot "build/validation/windows-render-$Height-media" }
$MediaDir = [IO.Path]::GetFullPath($MediaDir)
New-Item -ItemType Directory -Path $MediaDir -Force | Out-Null
$main = Join-Path $MediaDir 'main.mp4'
$preview = Join-Path $MediaDir 'preview.mp4'
if ($GenerateFixture) {
  $width = if ($Height -eq 1080) { 1920 } else { 1280 }
  if (!(Test-Path -LiteralPath $main)) {
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=${width}x${Height}:rate=60" -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 50 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -movflags +faststart $main
    if ($LASTEXITCODE -ne 0) { throw 'Main fixture generation failed.' }
  }
  if (!(Test-Path -LiteralPath $preview)) {
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=854x480:rate=30' -t 20 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -an -movflags +faststart $preview
    if ($LASTEXITCODE -ne 0) { throw 'Preview fixture generation failed.' }
  }
}
if (!(Test-Path -LiteralPath $main) -or !(Test-Path -LiteralPath $preview)) {
  throw 'main.mp4 and preview.mp4 are required; pass -GenerateFixture to create missing files.'
}
$mainHash = (Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
$previewHash = (Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash
Write-Host "Main SHA256: $mainHash"
Write-Host "Preview SHA256: $previewHash"

$report = Join-Path $repoRoot "build/validation/windows-video-render-$Label.json"
$gpuReport = Join-Path $repoRoot "build/validation/windows-gpu-engine-$Label.jsonl"
if ((Test-Path -LiteralPath $report) -or (Test-Path -LiteralPath $gpuReport)) {
  throw "Label '$Label' already has results; choose a new label to preserve measurements."
}
$fixtureReport = Join-Path $validationDir "windows-video-render-$Label.fixture.json"
if (Test-Path -LiteralPath $fixtureReport) {
  throw "Label '$Label' already has fixture metadata; choose a new label."
}
[pscustomobject]@{
  schemaVersion = 1
  label = $Label
  expectedMainHeight = $Height
  mainPath = $main
  mainBytes = (Get-Item -LiteralPath $main).Length
  mainSha256 = $mainHash
  previewPath = $preview
  previewBytes = (Get-Item -LiteralPath $preview).Length
  previewSha256 = $previewHash
  generationSpec = 'When -GenerateFixture creates missing files: main testsrc2 60fps H264 ultrafast yuv420p + 440Hz 48kHz AAC, 50s; preview testsrc2 854x480 30fps H264 ultrafast yuv420p silent, 20s.'
} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $fixtureReport -Encoding utf8
$log = Join-Path $repoRoot "build/validation/windows-video-render-$Label.log"
$sampler = Join-Path $PSScriptRoot 'validation/windows_gpu_engine_probe.ps1'
$oldMedia = $env:BILI_TEST_MEDIA_DIR
$oldLabel = $env:BILI_RENDER_LABEL
$oldTrace = $env:BILISAIL_VIDEO_RENDER_TRACE
$gpuJob = $null
$didBuild = !$ExePath
if ($ExePath) {
  $ExePath = [IO.Path]::GetFullPath($ExePath)
  if (!(Test-Path -LiteralPath $ExePath)) { throw "Executable not found: $ExePath" }
}
Push-Location $repoRoot
try {
  $env:BILI_TEST_MEDIA_DIR = $MediaDir
  $env:BILI_RENDER_LABEL = $Label
  $env:BILISAIL_VIDEO_RENDER_TRACE = '1'
  $launchedAfterUtc = [DateTimeOffset]::UtcNow.ToString('o')
  $gpuJob = Start-Job -ScriptBlock {
    param($samplerPath, $sampleLabel, $exe, $startedAfter)
    if ($exe) {
      & pwsh -NoProfile -File $samplerPath -Label $sampleLabel -Seconds 180 -ExePath $exe -ProcessStartAfterUtc $startedAfter
    } else {
      & pwsh -NoProfile -File $samplerPath -Label $sampleLabel -Seconds 180 -ProcessStartAfterUtc $startedAfter
    }
    if ($LASTEXITCODE -ne 0) { throw 'GPU Engine sampler failed.' }
  } -ArgumentList $sampler, $Label, $ExePath, $launchedAfterUtc
  if ($ExePath) {
    & $ExePath 2>&1 | Tee-Object -FilePath $log
  } else {
    & flutter run -d windows --profile --no-pub -t tool/validation/windows_video_render_probe.dart 2>&1 | Tee-Object -FilePath $log
  }
  if ($LASTEXITCODE -ne 0) { throw 'Windows Profile playback probe failed.' }
  if (!(Test-Path -LiteralPath $report)) { throw 'Playback probe did not write its report.' }
  Wait-Job -Job $gpuJob | Out-Null
  Receive-Job -Job $gpuJob -ErrorAction Stop | Out-Null
  if (!(Test-Path -LiteralPath $gpuReport)) { throw 'GPU Engine sampler did not write samples.' }
  Write-Host "Playback report: $report"
  Write-Host "GPU Engine samples: $gpuReport"
} finally {
  $env:BILI_TEST_MEDIA_DIR = $oldMedia
  $env:BILI_RENDER_LABEL = $oldLabel
  $env:BILISAIL_VIDEO_RENDER_TRACE = $oldTrace
  if ($gpuJob) {
    Stop-Job -Job $gpuJob -ErrorAction SilentlyContinue
    Remove-Job -Job $gpuJob -Force -ErrorAction SilentlyContinue
  }
  if ($didBuild) {
    & cmake -S windows -B build/windows/x64 > build/validation/windows-video-render-cmake-reset.log 2>&1
    $resetExitCode = $LASTEXITCODE
  }
  Pop-Location
  if ($didBuild -and $resetExitCode -ne 0) {
    throw 'CMake trace reset failed; inspect windows-video-render-cmake-reset.log.'
  }
}
