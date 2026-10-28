$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ios-package-validation.ps1')
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-Rejected([scriptblock]$Action) {
  $rejected = $false
  try { & $Action } catch { $rejected = $true }
  if (!$rejected) { throw 'Invalid iOS framework layout was accepted.' }
}

$valid = @('BiliMux', 'Info.plist', 'COPYING.LGPLv2.1', 'source.txt', 'configure.log')
Confirm-IosMuxFrameworkEntries $valid
foreach ($missing in $valid) {
  Assert-Rejected { Confirm-IosMuxFrameworkEntries @($valid | Where-Object { $_ -cne $missing }) }
}
foreach ($legacy in @('Resources/', 'Resources/configure.log', 'Versions/A/BiliMux')) {
  Assert-Rejected { Confirm-IosMuxFrameworkEntries ($valid + $legacy) }
}
# The original output has a valid root plist but all three records in Resources.
Assert-Rejected { Confirm-IosMuxFrameworkEntries @('BiliMux', 'Info.plist', 'Resources/COPYING.LGPLv2.1', 'Resources/source.txt', 'Resources/configure.log') }

$work = Join-Path ([System.IO.Path]::GetTempPath()) "bilisail-ios-layout-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $framework = Join-Path $work 'BiliMux.framework'
  New-Item -ItemType Directory -Path $framework | Out-Null
  foreach ($file in $valid) { Set-Content -LiteralPath (Join-Path $framework $file) -Value 'fixture' }
  Copy-Item -LiteralPath (Join-Path $repoRoot 'packages/bili_mux/native/Info.ios.plist') -Destination (Join-Path $framework 'Info.plist') -Force
  Confirm-IosMuxFrameworkLayout $framework
  $archivePath = Join-Path $work 'framework.zip'
  [System.IO.Compression.ZipFile]::CreateFromDirectory($framework, $archivePath)
  $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try { Confirm-IosMuxFrameworkEntries @($archive.Entries.FullName) } finally { $archive.Dispose() }
  # Even an empty retained Resources directory must be rejected before zipping.
  $legacy = Join-Path $framework 'Resources'
  New-Item -ItemType Directory -Path $legacy | Out-Null
  Assert-Rejected { Confirm-IosMuxFrameworkLayout $framework }
  Remove-Item -LiteralPath $archivePath
  [System.IO.Compression.ZipFile]::CreateFromDirectory($framework, $archivePath)
  $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try { Assert-Rejected { Confirm-IosMuxFrameworkEntries @($archive.Entries.FullName) } } finally { $archive.Dispose() }
} finally {
  # This exact absolute directory was created above, under the system temp dir.
  Remove-Item -LiteralPath $work -Recurse -Force
}
Write-Output 'iOS framework directory and archive layout checks passed (14 cases).'
