param(
  [int]$Samples = 3,
  [int]$StartupSeconds = 3,
  [int]$MaxExitMilliseconds = 2000,
  [switch]$WithPlayback,
  [ValidateSet('normal', 'minimized', 'fullscreen')]
  [string[]]$PlaybackPresentations = @('normal', 'minimized', 'fullscreen'),
  [string]$Output = 'build/validation/exit-latency/results.json'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousMediaDirectory = $env:BILI_TEST_MEDIA_DIR
$previousProbeOutput = $env:BILI_EXIT_PROBE_OUTPUT
$previousPresentation = $env:BILI_EXIT_PROBE_PRESENTATION
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class BiliExitLatencyNative {
  public delegate bool EnumProc(IntPtr window, IntPtr parameter);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder name, int length);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
}
'@
Push-Location $repoRoot
try {
  $outputPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
  New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null
  if ($WithPlayback) {
    & flutter build windows --release --no-pub -t tool/validation/windows_exit_probe.dart
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the AOT playback exit probe.' }
    $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  }
  $executable = (Resolve-Path 'build/windows/x64/runner/Release/bilisail.exe').Path
  $results = @()
  $presentations = if ($WithPlayback) { $PlaybackPresentations } else { @('none') }
  foreach ($presentation in $presentations) {
    for ($sample = 1; $sample -le $Samples; $sample++) {
      if ($WithPlayback) {
        $env:BILI_EXIT_PROBE_PRESENTATION = $presentation
        $env:BILI_EXIT_PROBE_OUTPUT = Join-Path (Split-Path $outputPath) "playback-$([Guid]::NewGuid()).txt"
      }
      $probe = Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable) -WindowStyle Hidden -PassThru
      try {
        if ($WithPlayback) {
          $startup = [Diagnostics.Stopwatch]::StartNew()
          while (!(Test-Path -LiteralPath $env:BILI_EXIT_PROBE_OUTPUT) -or
              !(Select-String -LiteralPath $env:BILI_EXIT_PROBE_OUTPUT -Pattern ' ready$' -Quiet)) {
            if ($probe.HasExited -or $startup.ElapsedMilliseconds -gt 30000) {
              throw "Playback exit probe did not become ready. See $env:BILI_EXIT_PROBE_OUTPUT"
            }
            Start-Sleep -Milliseconds 50
          }
        }
        Start-Sleep -Seconds $StartupSeconds
        $windows = [Collections.Generic.List[IntPtr]]::new()
        [BiliExitLatencyNative]::EnumWindows({
          param($window, $parameter)
          [uint32]$ownerProcess = 0
          [void][BiliExitLatencyNative]::GetWindowThreadProcessId($window, [ref]$ownerProcess)
          if ($ownerProcess -eq $probe.Id) {
            $className = [Text.StringBuilder]::new(256)
            [void][BiliExitLatencyNative]::GetClassName($window, $className, 256)
            if ($className.ToString() -eq 'FLUTTER_RUNNER_WIN32_WINDOW') { $windows.Add($window) }
          }
          return $true
        }, [IntPtr]::Zero) | Out-Null
        if ($windows.Count -ne 1) { throw "Expected one main window in probe process $($probe.Id), found $($windows.Count)." }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        if (![BiliExitLatencyNative]::PostMessage($windows[0], 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) {
          throw "Could not send WM_CLOSE to probe process $($probe.Id)."
        }
        if (!$probe.WaitForExit(30000)) { throw "Probe process $($probe.Id) did not exit within 30 seconds." }
        $elapsed = $watch.ElapsedMilliseconds
        if ($WithPlayback -and !(Select-String -LiteralPath $env:BILI_EXIT_PROBE_OUTPUT -Pattern ' dependenciesClosed$' -Quiet)) {
          throw 'Playback exit did not complete dependency/view cleanup.'
        }
        $results += [pscustomobject]@{ sample = $sample; playbackPresentation = $presentation; startupSeconds = $StartupSeconds; elapsedMilliseconds = $elapsed; exitCode = $probe.ExitCode }
        Write-Output "playback=$presentation sample=$sample exitMs=$elapsed exitCode=$($probe.ExitCode)"
      } finally {
        if (!$probe.HasExited) { Stop-Process -Id $probe.Id -Force }
        $probe.Dispose()
      }
    }
  }
  $results | ConvertTo-Json -AsArray | Set-Content -LiteralPath $outputPath -Encoding utf8
  if (@($results | Where-Object { $_.elapsedMilliseconds -gt $MaxExitMilliseconds -or $_.exitCode -ne 0 }).Count) {
    throw "Release exit exceeded ${MaxExitMilliseconds}ms or returned a nonzero exit code. See $outputPath"
  }
} finally {
  $env:BILI_TEST_MEDIA_DIR = $previousMediaDirectory
  $env:BILI_EXIT_PROBE_OUTPUT = $previousProbeOutput
  $env:BILI_EXIT_PROBE_PRESENTATION = $previousPresentation
  try {
    if ($WithPlayback) {
      # Keep the ordinary application as the final Release artifact, even when
      # a fixture launch or latency assertion fails.
      & flutter build windows --release --no-pub -t lib/main.dart
      if ($LASTEXITCODE -ne 0) { throw 'Could not restore the ordinary Release entrypoint.' }
    }
  } finally { Pop-Location }
}
