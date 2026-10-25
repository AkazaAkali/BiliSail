param()
$ErrorActionPreference = 'Stop'
$previousMediaDirectory = $env:BILI_TEST_MEDIA_DIR
Push-Location (Join-Path $PSScriptRoot '..')
try {
  $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  & flutter test integration_test/windows_main_close_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows main-window close regression failed: $LASTEXITCODE" }
} finally {
  $env:BILI_TEST_MEDIA_DIR = $previousMediaDirectory
  Pop-Location
}
