param(
  [string]$Adb,
  [string]$BuildTools,
  [string]$Serial,
  [string]$ExpectedAvd,
  [string]$ApplicationBinary,
  [string]$EvidenceDirectory,
  [switch]$LibraryOnly
)

# Read-only emulator update preflight. Never installs, uninstalls, clears,
# stops an application, or changes an AVD. Run immediately before Flutter's
# installer and retain its report; Flutter itself has no no-uninstall option.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AndroidGuardCommandRunner = $null

function Invoke-AndroidGuardCommand {
  param([string]$Executable, [string[]]$Arguments)
  if ($null -ne $script:AndroidGuardCommandRunner) {
    $result = & $script:AndroidGuardCommandRunner $Executable $Arguments
  } else {
    $nativeOutput = @(& $Executable @Arguments 2>&1)
    $nativeExit = $LASTEXITCODE
    $result = [pscustomobject]@{ ExitCode = $nativeExit; Output = ($nativeOutput -join "`n") }
  }
  if ($null -eq $result -or $result.ExitCode -isnot [int] -or $result.ExitCode -ne 0 -or $result.Output -isnot [string]) {
    throw 'native_read_failed'
  }
  return $result.Output
}

function Assert-AndroidGuardPlainPath {
  param([string]$Path, [switch]$File, [switch]$AllowMissingLeaf)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\')) { throw 'unsafe_local_path' }
  $full = [IO.Path]::GetFullPath($Path)
  # Reject alternate data streams and device paths, even when a file exists.
  if ($full.Substring(2).Contains(':') -or $full.StartsWith('\\') -or $full -notmatch '^[A-Za-z]:\\') { throw 'unsafe_local_path' }
  $current = $full
  $leaf = $true
  while (-not [string]::IsNullOrEmpty($current)) {
    $item = $null
    try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop } catch [Management.Automation.ItemNotFoundException] { }
    if ($null -ne $item) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_local_path' }
      if ($leaf -and $File -and $item.PSIsContainer) { throw 'expected_regular_file' }
      if ((-not $leaf -or -not $File) -and -not $item.PSIsContainer) { throw 'expected_directory' }
    } elseif (-not ($leaf -and $AllowMissingLeaf)) { throw 'missing_local_path' }
    $leaf = $false
    $parent = [IO.Path]::GetDirectoryName($current)
    if ($parent -ceq $current) { break }
    $current = $parent
  }
  return $full
}

function New-AndroidGuardWorkspace {
  param([string]$Path)
  $full = Assert-AndroidGuardPlainPath $Path -AllowMissingLeaf
  $repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
  $allowed = @((Join-Path $repository 'app/build'), (Join-Path $repository 'dist'))
  $inside = $false
  foreach ($root in $allowed) {
    if ($full.StartsWith(([IO.Path]::GetFullPath($root).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { $inside = $true }
  }
  if (-not $inside -or (Test-Path -LiteralPath $full)) { throw 'unsafe_evidence_directory' }
  # New-Item without Force refuses an existing directory; never adopt one.
  $null = New-Item -ItemType Directory -Path $full -ErrorAction Stop
  $null = Assert-AndroidGuardPlainPath $full
  Write-AndroidGuardJson (Join-Path $full 'ownership.json') ([ordered]@{ formatVersion = 1; owner = 'ImageHub Android install guard' })
  return $full
}

function Write-AndroidGuardJson {
  param([string]$Path, [object]$Value)
  $null = Assert-AndroidGuardPlainPath $Path -File -AllowMissingLeaf
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 5))
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Get-AndroidGuardApk {
  param([string]$Path, [string]$Aapt, [string]$ApkSigner, [switch]$RequireDebug)
  $full = Assert-AndroidGuardPlainPath $Path -File
  # Hold a read-only handle that denies writes/deletion through both native
  # inspectors. A source changing while it is inspected cannot pass.
  $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    if ($stream.Length -le 0) { throw 'empty_apk' }
    $badging = Invoke-AndroidGuardCommand $Aapt @('dump', 'badging', $full)
    $packageLines = @($badging -split '\r?\n' | Where-Object { $_ -match '^package:' })
    if ($packageLines.Count -ne 1 -or $packageLines[0] -notmatch "^package: name='(io\.imagehost\.imagehost)' versionCode='([1-9][0-9]*)' versionName='[^']*'(?: |$)") { throw 'invalid_apk_identity' }
    $id = $Matches[1]
    $version = 0L
    if (-not [long]::TryParse($Matches[2], [ref]$version) -or $version -gt 2100000000) { throw 'invalid_apk_version' }
    if ($RequireDebug -and @($badging -split '\r?\n' | Where-Object { $_ -ceq 'application-debuggable' }).Count -ne 1) { throw 'candidate_not_debug' }
    $signing = Invoke-AndroidGuardCommand $ApkSigner @('verify', '--verbose', '--print-certs', $full)
    $signerCount = @($signing -split '\r?\n' | Where-Object { $_ -match '^Number of signers: ' })
    $digests = @($signing -split '\r?\n' | Where-Object { $_ -match '^Signer #[0-9]+ certificate SHA-256 digest:' })
    if ($signerCount.Count -ne 1 -or $signerCount[0] -cne 'Number of signers: 1' -or $digests.Count -ne 1 -or $digests[0] -notmatch '^Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})$') { throw 'invalid_apk_certificate' }
    $digest = $Matches[1].ToLowerInvariant()
    if ($RequireDebug) {
      $dns = @($signing -split '\r?\n' | Where-Object { $_ -match '^Signer #1 certificate DN:' })
      if ($dns.Count -ne 1) { throw 'candidate_not_debug_certificate' }
      $rdns = @($dns[0].Substring('Signer #1 certificate DN:'.Length).Trim() -split ',\s*' | Sort-Object)
      if (($rdns -join '|') -cne 'C=US|CN=Android Debug|O=Android') { throw 'candidate_not_debug_certificate' }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    return [pscustomobject]@{ ApplicationId = $id; VersionCode = $version; CertificateSha256 = $digest; ApkSha256 = $hash }
  } finally { $stream.Dispose() }
}

function Assert-AndroidGuardAvd {
  param([string]$AdbPath, [string]$DeviceSerial, [string]$Avd)
  if ($DeviceSerial -notmatch '^emulator-[0-9]+$' -or $Avd -cne 'ImageHost_API36') { throw 'unowned_emulator' }
  $state = Invoke-AndroidGuardCommand $AdbPath @('-s', $DeviceSerial, 'get-state')
  if ($state.Trim() -cne 'device') { throw 'emulator_not_ready' }
  $name = Invoke-AndroidGuardCommand $AdbPath @('-s', $DeviceSerial, 'emu', 'avd', 'name')
  $lines = @($name -split '\r?\n' | Where-Object { $_.Length -ne 0 })
  if ($lines.Count -ne 2 -or $lines[0] -cne $Avd -or $lines[1] -cne 'OK') { throw 'unowned_emulator' }
}

function Get-AndroidGuardInstalledMetadata {
  param([string]$AdbPath, [string]$DeviceSerial)
  $id = 'io.imagehost.imagehost'
  # On API36, pm path returns exit 1 for an absent application. Establish
  # absence only through the successful exact-filter package list command.
  $listing = Invoke-AndroidGuardCommand $AdbPath @('-s', $DeviceSerial, 'shell', 'pm', 'list', 'packages', $id)
  if ([string]::IsNullOrWhiteSpace($listing)) { return $null }
  $listed = @($listing -split '\r?\n' | Where-Object { $_.Length -ne 0 })
  if ($listed.Count -ne 1 -or $listed[0] -cne ('package:' + $id)) { throw 'invalid_installed_package_identity' }
  $paths = Invoke-AndroidGuardCommand $AdbPath @('-s', $DeviceSerial, 'shell', 'pm', 'path', $id)
  $lines = @($paths -split '\r?\n' | Where-Object { $_.Length -ne 0 })
  if ($lines.Count -ne 1 -or $lines[0] -notmatch '^package:(/data/app/[^\s\r\n]+/base\.apk)$' -or $Matches[1].Contains('/../') -or $Matches[1].Contains('/./')) { throw 'unsupported_installed_apk_paths' }
  $remotePath = $Matches[1]
  $dump = Invoke-AndroidGuardCommand $AdbPath @('-s', $DeviceSerial, 'shell', 'dumpsys', 'package', $id)
  $headers = @($dump -split '\r?\n' | Where-Object { $_ -match '^\s*Package \[' })
  if ($headers.Count -ne 1 -or $headers[0] -notmatch '^\s*Package \[io\.imagehost\.imagehost\] \([0-9a-fA-F]+\):\s*$') { throw 'invalid_installed_package_identity' }
  # Parse only the selected Packages block, not historical or other packages.
  $block = [regex]::Match($dump, '(?ms)^\s*Package \[io\.imagehost\.imagehost\] \([0-9a-fA-F]+\):\s*\r?\n(?<body>.*?)(?=^\S|\z)')
  if (-not $block.Success) { throw 'invalid_installed_package_identity' }
  $versions = @($block.Groups['body'].Value -split '\r?\n' | Where-Object { $_ -match '^\s+versionCode=' })
  if ($versions.Count -ne 1 -or $versions[0] -notmatch '^\s+versionCode=([1-9][0-9]*)(?:\s|$)') { throw 'invalid_installed_version' }
  $version = 0L
  if (-not [long]::TryParse($Matches[1], [ref]$version) -or $version -gt 2100000000) { throw 'invalid_installed_version' }
  return [pscustomobject]@{ RemotePath = $remotePath; VersionCode = $version }
}

function Get-AndroidGuardInstalledSnapshot {
  param([string]$AdbPath, [string]$DeviceSerial, [string]$Aapt, [string]$ApkSigner, [string]$Workspace, [int]$Sequence)
  $before = Get-AndroidGuardInstalledMetadata $AdbPath $DeviceSerial
  if ($null -eq $before) { return $null }
  $destination = Join-Path $Workspace "installed-$Sequence.apk"
  if (Test-Path -LiteralPath $destination) { throw 'existing_evidence_file' }
  $null = Invoke-AndroidGuardCommand $AdbPath @('-s', $DeviceSerial, 'pull', $before.RemotePath, $destination)
  $apk = Get-AndroidGuardApk $destination $Aapt $ApkSigner
  $after = Get-AndroidGuardInstalledMetadata $AdbPath $DeviceSerial
  if ($null -eq $after -or $after.RemotePath -cne $before.RemotePath -or $after.VersionCode -ne $before.VersionCode -or $apk.VersionCode -ne $before.VersionCode) { throw 'installed_package_changed' }
  return $apk
}

function Get-AndroidGuardDesiredVersion {
  $versionsPath = Assert-AndroidGuardPlainPath ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../versions.json'))) -File
  $versions = Get-Content -LiteralPath $versionsPath -Raw | ConvertFrom-Json
  $wantedVersion = $versions.platforms.android.build
  if ($versions.formatVersion -ne 1 -or ($wantedVersion -isnot [int] -and $wantedVersion -isnot [long]) -or $wantedVersion -le 0 -or $wantedVersion -gt 2100000000) { throw 'invalid_version_manifest' }
  return $wantedVersion
}

function Invoke-AndroidTestInstallGuard {
  param([string]$AdbPath, [string]$BuildToolsPath, [string]$DeviceSerial, [string]$Avd, [string]$Binary, [string]$Evidence)
  $workspace = $null
  $report = [ordered]@{ formatVersion = 1; guardPassed = $false; reason = 'preflight_not_complete'; applicationId = 'io.imagehost.imagehost'; candidateVersionCode = $null; candidateCertificateSha256 = $null; installedVersionCode = $null; installedCertificateSha256 = $null }
  try {
    $adbFile = Assert-AndroidGuardPlainPath $AdbPath -File
    $tools = Assert-AndroidGuardPlainPath $BuildToolsPath
    $aapt = Assert-AndroidGuardPlainPath (Join-Path $tools 'aapt.exe') -File
    $signer = Assert-AndroidGuardPlainPath (Join-Path $tools 'apksigner.bat') -File
    $workspace = New-AndroidGuardWorkspace $Evidence
    $wantedVersion = Get-AndroidGuardDesiredVersion
    $candidate = Get-AndroidGuardApk $Binary $aapt $signer -RequireDebug
    $report.candidateVersionCode = $candidate.VersionCode
    $report.candidateCertificateSha256 = $candidate.CertificateSha256
    if ($candidate.VersionCode -ne $wantedVersion) { throw 'candidate_manifest_version_mismatch' }
    Assert-AndroidGuardAvd $adbFile $DeviceSerial $Avd
    $installed = Get-AndroidGuardInstalledSnapshot $adbFile $DeviceSerial $aapt $signer $workspace 1
    if ($null -ne $installed) {
      $report.installedVersionCode = $installed.VersionCode
      $report.installedCertificateSha256 = $installed.CertificateSha256
      if ($installed.VersionCode -gt $wantedVersion) { throw 'version_downgrade_refused' }
      if ($installed.CertificateSha256 -cne $candidate.CertificateSha256) { throw 'certificate_mismatch_refused' }
    }
    # A second complete APK/certificate snapshot rejects replacement while the
    # first read was in flight, including changes at the same versionCode.
    Assert-AndroidGuardAvd $adbFile $DeviceSerial $Avd
    $final = Get-AndroidGuardInstalledSnapshot $adbFile $DeviceSerial $aapt $signer $workspace 2
    if (($null -eq $installed) -ne ($null -eq $final)) { throw 'installed_package_changed' }
    if ($null -ne $installed -and ($final.VersionCode -ne $installed.VersionCode -or $final.CertificateSha256 -cne $installed.CertificateSha256 -or $final.ApkSha256 -cne $installed.ApkSha256)) { throw 'installed_package_changed' }
    $candidateAgain = Get-AndroidGuardApk $Binary $aapt $signer -RequireDebug
    if ($candidateAgain.ApkSha256 -cne $candidate.ApkSha256) { throw 'candidate_apk_changed' }
    $report.guardPassed = $true
    $report.reason = $(if ($null -eq $installed) { 'application_absent' } else { 'compatible_debug_update' })
    Write-AndroidGuardJson (Join-Path $workspace 'guard-report.json') $report
    return [pscustomobject]$report
  } catch {
    $known = @('native_read_failed', 'unsafe_local_path', 'linked_local_path', 'expected_regular_file', 'expected_directory', 'missing_local_path', 'unsafe_evidence_directory', 'empty_apk', 'invalid_apk_identity', 'invalid_apk_version', 'candidate_not_debug', 'invalid_apk_certificate', 'candidate_not_debug_certificate', 'unowned_emulator', 'emulator_not_ready', 'unsupported_installed_apk_paths', 'invalid_installed_package_identity', 'invalid_installed_version', 'existing_evidence_file', 'installed_package_changed', 'invalid_version_manifest', 'candidate_manifest_version_mismatch', 'version_downgrade_refused', 'certificate_mismatch_refused', 'candidate_apk_changed')
    $report.reason = $(if ($_.Exception.Message -cin $known) { $_.Exception.Message } else { 'local_read_or_evidence_failed' })
    if ($null -ne $workspace) {
      try { Write-AndroidGuardJson (Join-Path $workspace 'guard-report.json') $report } catch { }
    }
    # Do not echo native output, host paths, dumpsys, or exception objects.
    throw ('Android install guard refused: ' + $report.reason)
  }
}

if (-not $LibraryOnly) {
  try {
    Invoke-AndroidTestInstallGuard $Adb $BuildTools $Serial $ExpectedAvd $ApplicationBinary $EvidenceDirectory | ConvertTo-Json
    $global:LASTEXITCODE = 0
  } catch {
    Write-Error $_.Exception.Message
    exit 1
  }
}
