param(
  [int]$Samples = 3,
  [int]$StartupSeconds = 3,
  [int]$MaxExitMilliseconds = 2000,
  [string]$Output = 'build/validation/exit-latency/results.json'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
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
  $executable = (Resolve-Path 'build/windows/x64/runner/Release/bilisail.exe').Path
  $results = @()
  for ($sample = 1; $sample -le $Samples; $sample++) {
    $probe = Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable) -WindowStyle Hidden -PassThru
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
    $results += [pscustomobject]@{ sample = $sample; startupSeconds = $StartupSeconds; elapsedMilliseconds = $elapsed; exitCode = $probe.ExitCode }
    Write-Output "sample=$sample exitMs=$elapsed exitCode=$($probe.ExitCode)"
  }
  $outputPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Output))
  New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null
  $results | ConvertTo-Json -AsArray | Set-Content -LiteralPath $outputPath -Encoding utf8
  if (@($results | Where-Object { $_.elapsedMilliseconds -gt $MaxExitMilliseconds -or $_.exitCode -ne 0 }).Count) {
    throw "Release exit exceeded ${MaxExitMilliseconds}ms or returned a nonzero exit code. See $outputPath"
  }
} finally { Pop-Location }
