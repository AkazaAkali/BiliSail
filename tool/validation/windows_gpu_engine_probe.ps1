param(
  [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [int]$Seconds = 90,
  [string]$ExePath,
  [string]$ProcessStartAfterUtc
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$report = Join-Path $repoRoot "build/validation/windows-gpu-engine-$Label.jsonl"
$profileExe = [IO.Path]::GetFullPath((Join-Path $repoRoot 'build/windows/x64/runner/Profile/bilisail.exe'))
if ($ExePath) { $profileExe = [IO.Path]::GetFullPath($ExePath) }
$startedAfter = if ($ProcessStartAfterUtc) { [DateTimeOffset]::Parse($ProcessStartAfterUtc).UtcDateTime } else { [DateTime]::MinValue }
New-Item -ItemType Directory -Path (Split-Path $report) -Force | Out-Null
Remove-Item -LiteralPath $report -ErrorAction SilentlyContinue
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($Seconds)
$targetPid = $null
while ([DateTimeOffset]::UtcNow -lt $deadline) {
  if ($null -eq $targetPid) {
    $candidate = Get-Process bilisail -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $profileExe -and $_.StartTime.ToUniversalTime() -ge $startedAfter } | Select-Object -First 1
    if ($null -eq $candidate) {
      Start-Sleep -Milliseconds 500
      continue
    }
    $targetPid = $candidate.Id
  }
  $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
  if ($null -eq $process) { break }
  try {
    $sample = Get-Counter -Counter '\GPU Engine(*)\Utilization Percentage' -SampleInterval 1 -MaxSamples 1
  } catch {
    # Adapter instances can disappear while the player exits. Keep earlier samples.
    continue
  }
  foreach ($counter in $sample.CounterSamples) {
      if ($counter.Status -ne 0 -or
          [double]::IsNaN($counter.CookedValue) -or
          [double]::IsInfinity($counter.CookedValue) -or
          $counter.CookedValue -lt 0) { continue }
      if ($counter.Path -notmatch "pid_$($targetPid)_luid_(.+?)_phys_(\d+)_eng_(\d+)_engtype_([^\)]+)\)") { continue }
      [pscustomobject]@{
        timeUtc = $sample.Timestamp.ToUniversalTime().ToString('o')
        pid = $targetPid
        luid = $Matches[1]
        physicalAdapter = [int]$Matches[2]
        engine = [int]$Matches[3]
        engineType = $Matches[4]
        percent = $counter.CookedValue
        cpuSeconds = $process.CPU
        workingSetBytes = $process.WorkingSet64
      } | ConvertTo-Json -Compress | Add-Content -LiteralPath $report
  }
}
