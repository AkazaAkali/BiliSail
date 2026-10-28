# Shared by the staged .app and final IPA checks; also runs without Xcode.
function Confirm-IosMuxFrameworkEntries([string[]]$Entries) {
  foreach ($entry in $Entries) {
    if ($entry -match '^(Resources|Versions)(/|$)') {
      throw "iOS BiliMux.framework must use a flat bundle layout: $entry"
    }
  }
  foreach ($required in @('BiliMux', 'Info.plist', 'COPYING.LGPLv2.1', 'source.txt', 'configure.log')) {
    if ($required -cnotin $Entries) { throw "iOS BiliMux.framework is missing: $required" }
  }
}

function Confirm-IosMuxFrameworkLayout([string]$Framework) {
  if (!(Test-Path -LiteralPath $Framework -PathType Container)) { throw 'iOS BiliMux.framework is missing.' }
  $entries = @(Get-ChildItem -LiteralPath $Framework -Recurse -Force | ForEach-Object {
    $relative = [System.IO.Path]::GetRelativePath($Framework, $_.FullName).Replace('\', '/')
    if ($_.PSIsContainer) { "$relative/" } else { $relative }
  })
  Confirm-IosMuxFrameworkEntries $entries
}
