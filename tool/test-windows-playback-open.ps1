param(
  [switch]$SkipBuild,
  [switch]$Maximized,
  [string]$Output = 'build/validation/window-open/results.json'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousOutput = $env:BILI_WINDOW_OPEN_OUTPUT
$previousMaximized = $env:BILI_WINDOW_OPEN_MAXIMIZED
Push-Location $repoRoot
try {
  $outputPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
  if (Test-Path -LiteralPath $outputPath) {
    throw "Choose a fresh result path: $outputPath"
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null
  if (!$SkipBuild) {
    & flutter build windows --profile --no-pub -t tool/validation/windows_playback_open_probe.dart
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the Profile window-open probe.' }
  }
  $executable = (Resolve-Path 'build/windows/x64/runner/Profile/bilisail.exe').Path
  $env:BILI_WINDOW_OPEN_OUTPUT = $outputPath
  $env:BILI_WINDOW_OPEN_MAXIMIZED = $Maximized.IsPresent.ToString().ToLowerInvariant()
  $probe = Start-Process -FilePath $executable -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput "$outputPath.stdout.log" -RedirectStandardError "$outputPath.stderr.log" -PassThru
  try {
    if (!$probe.WaitForExit(30000)) { throw 'Window-open probe exceeded 30 seconds.' }
    if ($probe.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) {
      throw "Window-open probe failed. See $outputPath.stderr.log"
    }
    Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json | ForEach-Object {
      [pscustomobject]@{
        sample = $_.sample
        visibleMs = [Math]::Round($_.visible / 1000, 2)
        createMs = [Math]::Round(($_.createEnd - $_.createStart) / 1000, 2)
        prepareMs = [Math]::Round(($_.prepareEnd - $_.prepareStart) / 1000, 2)
      }
    } | Format-Table
  } finally {
    if (!$probe.HasExited) { Stop-Process -Id $probe.Id -Force }
    $probe.Dispose()
  }
} finally {
  $env:BILI_WINDOW_OPEN_OUTPUT = $previousOutput
  $env:BILI_WINDOW_OPEN_MAXIMIZED = $previousMaximized
  try {
    if (!$SkipBuild) {
      & flutter build windows --profile --no-pub -t lib/main.dart
      if ($LASTEXITCODE -ne 0) { throw 'Could not restore the ordinary Profile entrypoint.' }
    }
  } finally { Pop-Location }
}
