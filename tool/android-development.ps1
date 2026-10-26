# Local device validation must use this identity across every build mode.
$AndroidDevelopmentPackageId = 'dev.bilisail.bilisail.test'
$AndroidDevelopmentDisplayName = 'BiliSail 测试版'
$AndroidDevelopmentBuildArgument = '--android-project-arg=bilisailDevelopmentBuild=true'

function Get-AndroidDevelopmentAapt {
  $adb = (Get-Command adb -ErrorAction Stop).Source
  $sdk = Split-Path (Split-Path $adb)
  $name = if ($IsWindows) { 'aapt.exe' } else { 'aapt' }
  $tool = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
    Sort-Object { $_.Name -as [version] } -Descending |
    ForEach-Object { Join-Path $_.FullName $name } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
  if (!$tool) { throw 'Android SDK aapt is required to verify the development identity.' }
  return $tool
}

function ConvertFrom-AndroidDevelopmentBadging([string]$Report, [string]$Mode = 'Release') {
  $entry = [regex]::Match($Report, "(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'")
  if (!$entry.Success -or $entry.Groups[1].Value -cne $AndroidDevelopmentPackageId) {
    throw "Development APK must use $AndroidDevelopmentPackageId. Installation was cancelled."
  }
  $label = [regex]::Match($Report, "(?m)^application-label:'([^']+)'\r?$")
  if (!$label.Success -or $label.Groups[1].Value -cne $AndroidDevelopmentDisplayName) {
    throw "Development APK must be named $AndroidDevelopmentDisplayName."
  }
  if ($Mode -eq 'Release' -and $Report -match '(?m)^application-debuggable\s*$') {
    throw 'The development Release APK must not be debuggable.'
  }
  return [pscustomobject]@{
    PackageId = $entry.Groups[1].Value
    VersionCode = [int]$entry.Groups[2].Value
    VersionName = $entry.Groups[3].Value
    DisplayName = $label.Groups[1].Value
  }
}

function Confirm-AndroidDevelopmentApk([string]$Package, [string]$Mode = 'Release') {
  $aapt = Get-AndroidDevelopmentAapt
  $report = & $aapt dump badging $Package
  if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the development APK.' }
  return ConvertFrom-AndroidDevelopmentBadging ($report -join [Environment]::NewLine) $Mode
}

function Install-AndroidDevelopmentApk([string]$DeviceId, [string]$Package, [string]$Mode = 'Release') {
  $null = Confirm-AndroidDevelopmentApk $Package $Mode
  & adb -s $DeviceId install -r $Package
  if ($LASTEXITCODE -ne 0) {
    throw 'Development APK install failed. Preserve installed data; do not uninstall or clear data automatically.'
  }
}
