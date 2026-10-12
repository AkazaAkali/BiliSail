param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [Parameter(Mandatory)][string]$ExePath,
  [Parameter(Mandatory)][string]$MediaPath,
  [ValidateRange(10, 40)][int]$Seconds = 40
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$validation = Join-Path $repoRoot 'build/validation'
$ExePath = [IO.Path]::GetFullPath($ExePath)
$MediaPath = [IO.Path]::GetFullPath($MediaPath)
if (!(Test-Path -LiteralPath $ExePath) -or !(Test-Path -LiteralPath $MediaPath)) {
  throw 'The probe bundle and local media must already exist.'
}
New-Item -ItemType Directory -Path $validation -Force | Out-Null
$playback = Join-Path $validation "windows-gpu-playback-$Label.jsonl"
$gpu = Join-Path $validation "windows-gpu-engine-$Label.jsonl"
$metadata = Join-Path $validation "windows-gpu-playback-$Label.fixture.json"
if ((Test-Path -LiteralPath $playback) -or (Test-Path -LiteralPath $gpu) -or (Test-Path -LiteralPath $metadata)) {
  throw 'Choose a fresh label to preserve existing results.'
}
[pscustomobject]@{
  label = $Label
  seconds = $Seconds
  mediaPath = $MediaPath
  mediaBytes = (Get-Item -LiteralPath $MediaPath).Length
  mediaSha256 = (Get-FileHash -LiteralPath $MediaPath -Algorithm SHA256).Hash
  exePath = $ExePath
  mpvSha256 = (Get-FileHash -LiteralPath (Join-Path (Split-Path $ExePath) 'libmpv-2.dll') -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath $metadata -Encoding utf8
$oldMedia = $env:BILI_GPU_MEDIA
$oldLabel = $env:BILI_GPU_LABEL
$oldSeconds = $env:BILI_GPU_SECONDS
$gpuJob = $null
$clockJob = $null
$probe = $null
try {
  $env:BILI_GPU_MEDIA = $MediaPath
  $env:BILI_GPU_LABEL = $Label
  $env:BILI_GPU_SECONDS = "$Seconds"
  $after = [DateTimeOffset]::UtcNow.ToString('o')
  $probe = Start-Process -FilePath $ExePath -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $validation "windows-gpu-playback-$Label.log") `
    -RedirectStandardError (Join-Path $validation "windows-gpu-playback-$Label.err")
  $sampler = Join-Path $PSScriptRoot 'validation/windows_gpu_engine_probe.ps1'
  $gpuJob = Start-Job -ScriptBlock {
    param($scriptPath, $sampleLabel, $exe, $startedAfter)
    & pwsh -NoProfile -File $scriptPath -Label $sampleLabel -Seconds 180 -ExePath $exe -ProcessStartAfterUtc $startedAfter
    if ($LASTEXITCODE -ne 0) { throw 'GPU sampling failed.' }
  } -ArgumentList $sampler, $Label, $ExePath, $after
  if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $clockJob = Start-Job -ScriptBlock {
      param($probePid)
      while (Get-Process -Id $probePid -ErrorAction SilentlyContinue) {
        & nvidia-smi '--query-gpu=timestamp,pstate,clocks.gr,clocks.mem,utilization.gpu,utilization.decoder,power.draw' '--format=csv,noheader'
        Start-Sleep -Seconds 1
      }
    } -ArgumentList $probe.Id
  }
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(180)
  while (!$probe.WaitForExit(500)) {
    if ([DateTimeOffset]::UtcNow -ge $deadline) { throw 'Playback probe exceeded its deadline.' }
  }
  if ($probe.ExitCode -ne 0) { throw "Playback probe exited with $($probe.ExitCode)." }
  Wait-Job $gpuJob -Timeout 10 | Out-Null
  Receive-Job $gpuJob -ErrorAction Stop | Out-Null
  if (!(Test-Path -LiteralPath $playback) -or !(Test-Path -LiteralPath $gpu)) {
    throw 'Playback or GPU samples are missing.'
  }
  Write-Host "Completed GPU probe: $Label"
} finally {
  if ($probe -and !$probe.HasExited) { $probe.Kill(); $probe.WaitForExit() }
  foreach ($job in @($gpuJob, $clockJob)) {
    if ($job) { Stop-Job $job -ErrorAction SilentlyContinue }
  }
  if ($clockJob) {
    Receive-Job $clockJob | Set-Content -LiteralPath (Join-Path $validation "windows-gpu-clocks-$Label.csv")
  }
  foreach ($job in @($gpuJob, $clockJob)) {
    if ($job) { Remove-Job $job -Force -ErrorAction SilentlyContinue }
  }
  $env:BILI_GPU_MEDIA = $oldMedia
  $env:BILI_GPU_LABEL = $oldLabel
  $env:BILI_GPU_SECONDS = $oldSeconds
}
