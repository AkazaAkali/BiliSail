$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-msix-identity.ps1')
[xml]$manifest = Get-Content (Join-Path $PSScriptRoot '../windows/packaging/AppxManifest.xml') -Raw
$manifest.Package.Identity.Version = '1.0.2.0'
$previousPublisher = $env:MSIX_PUBLISHER
try {
  # The legacy Actions variable must not change the Store identity.
  $env:MSIX_PUBLISHER = 'CN=BiliSail'
  $actual = Confirm-WindowsMsixIdentity $manifest '1.0.2+0'
  if ($actual.publisher -cne 'CN=D34F8E82-088B-4DC8-9296-620B8683A539') { throw 'Legacy publisher override was accepted.' }
} finally { $env:MSIX_PUBLISHER = $previousPublisher }

$mutations = @(
  { param($xml) $xml.Package.Identity.Publisher = 'CN=BiliSail' },
  { param($xml) $xml.Package.Identity.Name = 'Another.App' },
  { param($xml) $xml.Package.Properties.PublisherDisplayName = 'Another Publisher' },
  { param($xml) $xml.Package.Identity.Version = '1.0.2.1' }
)
foreach ($mutate in $mutations) {
  [xml]$invalid = $manifest.OuterXml
  & $mutate $invalid
  $rejected = $false
  try { Confirm-WindowsMsixIdentity $invalid '1.0.2+0' | Out-Null } catch { $rejected = $true }
  if (!$rejected) { throw 'An invalid MSIX identity or version was accepted.' }
}
Write-Output 'MSIX identity checks passed (valid identity, legacy override isolation, four invalid manifests).'
if ($IsWindows) {
  $family = Get-WindowsMsixFamilyName $actual.name $actual.publisher
  if ($family -cne 'JerryHsu.BiliSail_e5wcspfxwa6kj') { throw "Store PFN mismatch: $family" }
  $oldFamily = Get-WindowsMsixFamilyName $actual.name 'CN=BiliSail'
  if ($oldFamily -cne 'JerryHsu.BiliSail_0xpj25ymnhe84') { throw 'Legacy PFN regression failed.' }
  Write-Output 'Windows native package family checks passed.'
}
