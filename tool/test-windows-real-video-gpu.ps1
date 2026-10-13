param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [Parameter(Mandatory)][string]$ExePath,
  [string]$Bvid = 'home',
  [ValidateRange(8, 86400)][int]$StartSeconds = 30,
  [int]$Quality = 80,
  [ValidateRange(0.0, 1.0)][Nullable[double]]$Opacity = $null
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$validation = Join-Path $repoRoot 'build/validation'
$ExePath = [IO.Path]::GetFullPath($ExePath)
if (!(Test-Path -LiteralPath $ExePath)) { throw 'Build and copy the complete Release probe bundle first.' }
New-Item -ItemType Directory -Path $validation -Force | Out-Null
$playback = Join-Path $validation "windows-real-playback-$Label.jsonl"
$gpu = Join-Path $validation "windows-gpu-engine-$Label.jsonl"
$clocks = Join-Path $validation "windows-real-clocks-$Label.csv"
$metadata = Join-Path $validation "windows-real-fixture-$Label.json"
if (@($playback, $gpu, $clocks, $metadata) | Where-Object { Test-Path -LiteralPath $_ }) { throw 'Use a fresh label.' }
[pscustomobject]@{
  bvid = $Bvid
  startSeconds = $StartSeconds
  sampleSeconds = 30
  warmupSeconds = 8
  opacityOverride = $Opacity
  exeSha256 = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash
  snapshotSha256 = (Get-FileHash -LiteralPath (Join-Path (Split-Path $ExePath) 'data/app.so') -Algorithm SHA256).Hash
  mpvSha256 = (Get-FileHash -LiteralPath (Join-Path (Split-Path $ExePath) 'libmpv-2.dll') -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath $metadata -Encoding utf8
$probe = $null
$gpuJob = $null
$clockJob = $null
try {
  $env:BILI_REAL_LABEL = $Label
  $env:BILI_REAL_BVID = $Bvid
  $env:BILI_REAL_START = "$StartSeconds"
  $env:BILI_REAL_QUALITY = if ($Quality) { "$Quality" } else { $null }
  $env:BILI_REAL_OPACITY = if ($null -ne $Opacity) { "$Opacity" } else { $null }
  $probe = Start-Process -FilePath $ExePath -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $validation "windows-real-$Label.log") `
    -RedirectStandardError (Join-Path $validation "windows-real-$Label.err")
  $sampler = Join-Path $PSScriptRoot 'validation/windows_gpu_engine_probe.ps1'
  $gpuJob = Start-Job -ScriptBlock {
    param($scriptPath, $sampleLabel, $probePid)
    & pwsh -NoProfile -File $scriptPath -Label $sampleLabel -Seconds 360 -TargetProcessId $probePid -Continuous
    if ($LASTEXITCODE -ne 0) { throw 'Continuous GPU sampling failed.' }
  } -ArgumentList $sampler, $Label, $probe.Id
  $clockJob = Start-Job -ScriptBlock {
    param($probePid)
    while (Get-Process -Id $probePid -ErrorAction SilentlyContinue) {
      & nvidia-smi '--query-gpu=timestamp,pstate,clocks.gr,clocks.mem,utilization.gpu,utilization.decoder,power.draw' '--format=csv,noheader'
      Start-Sleep -Seconds 1
    }
  } -ArgumentList $probe.Id
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(360)
  while (!$probe.WaitForExit(500)) {
    if ([DateTimeOffset]::UtcNow -ge $deadline) { throw 'Real playback probe exceeded its deadline.' }
  }
  if ($probe.ExitCode -ne 0) { throw "Real playback probe failed: $($probe.ExitCode)." }
  if (!(Test-Path -LiteralPath $playback) -or !(Test-Path -LiteralPath $gpu)) { throw 'Samples are missing.' }
  Write-Output "Completed real video probe: $Label"
} finally {
  if ($probe -and !$probe.HasExited) { $probe.Kill(); $probe.WaitForExit() }
  foreach ($job in @($gpuJob, $clockJob)) { if ($job) { Stop-Job $job -ErrorAction SilentlyContinue } }
  if ($gpuJob) { Receive-Job $gpuJob -ErrorAction Stop | Out-Null }
  if ($clockJob) { Receive-Job $clockJob | Set-Content -LiteralPath $clocks -Encoding utf8 }
  foreach ($job in @($gpuJob, $clockJob)) { if ($job) { Remove-Job $job -Force -ErrorAction SilentlyContinue } }
  Remove-Item Env:BILI_REAL_LABEL, Env:BILI_REAL_BVID, Env:BILI_REAL_START, Env:BILI_REAL_QUALITY, Env:BILI_REAL_OPACITY -ErrorAction SilentlyContinue
}
