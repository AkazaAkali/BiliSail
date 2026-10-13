$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
  $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  & flutter test integration_test/windows_video_frame_queue_test.dart -d windows --no-pub
  if ($LASTEXITCODE -ne 0) { throw "Windows frame queue validation failed: $LASTEXITCODE" }
} finally {
  Remove-Item Env:BILI_TEST_MEDIA_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
