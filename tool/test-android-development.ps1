$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-development.ps1')
$checks = 0
function Assert-DevelopmentRejected([string]$Report, [string]$Mode = 'Release') {
  $rejected = $false
  try { $null = ConvertFrom-AndroidDevelopmentBadging $Report $Mode }
  catch { $rejected = $true }
  if (!$rejected) { throw 'Invalid development APK manifest was accepted.' }
  $script:checks++
}
$valid = @(
  "package: name='dev.bilisail.bilisail.test' versionCode='12104' versionName='1.2.1'"
  "application-label:'BiliSail 测试版'"
) -join "`n"
$identity = ConvertFrom-AndroidDevelopmentBadging $valid
if ($identity.PackageId -cne $AndroidDevelopmentPackageId -or $identity.VersionCode -ne 12104) {
  throw 'Valid development APK identity was rejected.'
}
$checks++
Assert-DevelopmentRejected ($valid.Replace('.test', ''))
Assert-DevelopmentRejected ($valid.Replace('.test', '.primaryswitch'))
Assert-DevelopmentRejected ($valid.Replace('BiliSail 测试版', 'BiliSail'))
Assert-DevelopmentRejected ($valid + "`napplication-debuggable")
Assert-DevelopmentRejected 'not an APK report'
$null = ConvertFrom-AndroidDevelopmentBadging ($valid + "`napplication-debuggable") 'Debug'
$checks++

Write-Output "Android development identity checks passed: $checks"
