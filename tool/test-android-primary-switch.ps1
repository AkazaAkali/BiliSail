param(
  [Parameter(Mandatory)]
  [string]$DeviceId,
  [ValidatePattern('^[a-z0-9-]+$')]
  [string]$Label = 'optimized',
  [switch]$SkipMuxBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')

function Invoke-ValidationCommand([string]$Executable, [string[]]$Parameters) {
  & $Executable @Parameters
  if ($LASTEXITCODE -ne 0) { throw "$Executable failed: $LASTEXITCODE" }
}

Push-Location $repoRoot
$powerState = $null
try {
  $adb = (Get-Command adb -ErrorAction Stop).Source
  Invoke-ValidationCommand $adb @('-s', $DeviceId, 'get-state')
  $powerState = (& $adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim()
  Invoke-ValidationCommand $adb @('-s', $DeviceId, 'shell', 'svc', 'power', 'stayon', 'usb')
  Invoke-ValidationCommand $adb @('-s', $DeviceId, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
  if (!$SkipMuxBuild) { & (Join-Path $PSScriptRoot 'build-download-mux.ps1') -Target android-arm64 }
  # Always preserve a fresh normal entry point before replacing the APK with a
  # deterministic fixture. All variants share the installed test app's data.
  & (Join-Path $PSScriptRoot 'build-android-development.ps1') -Mode Release -SkipMuxBuild
  $restorePackage = Join-Path $repoRoot 'build/development/android-arm64/BiliSail-test-arm64-release.apk'

  Invoke-ValidationCommand flutter @(
    'build', 'apk', '--profile', '--target-platform', 'android-arm64', '--split-per-abi',
    '--target', 'integration_test/android_primary_switch_test.dart',
    "--dart-define=SWITCH_LABEL=$Label",
    $AndroidDevelopmentBuildArgument
  )
  $apk = Join-Path $repoRoot "build/validation/primary-switch-$Label.apk"
  New-Item -ItemType Directory -Force -Path (Split-Path $apk) | Out-Null
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' -Destination $apk
  # Flutter drive can uninstall after a signature mismatch. Fail here first,
  # so neither the production app nor an incompatible validation app is erased.
  Install-AndroidDevelopmentApk $DeviceId $apk 'Profile'
  try {
    Invoke-ValidationCommand flutter @(
      'drive', '--profile', '--no-pub', '--keep-app-running', '-d', $DeviceId,
      '--driver', 'tool/validation/primary_switch_driver.dart',
      '--use-application-binary', $apk
    )
  } finally {
    Install-AndroidDevelopmentApk $DeviceId $restorePackage 'Release'
    Invoke-ValidationCommand $adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $AndroidDevelopmentPackageId)
    Invoke-ValidationCommand $adb @('-s', $DeviceId, 'shell', 'am', 'start', '-n', "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity")
  }
  Write-Output "Profile results: build/validation/primary-switch-$Label.json"
} finally {
  if ($null -ne $powerState -and
      (& $adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim() -eq '2') {
    if ($powerState -eq 'null') { & $adb -s $DeviceId shell settings delete global stay_on_while_plugged_in }
    else { & $adb -s $DeviceId shell settings put global stay_on_while_plugged_in $powerState }
  }
  Pop-Location
}
