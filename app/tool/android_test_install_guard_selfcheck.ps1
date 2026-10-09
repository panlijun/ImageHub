# Pure synthetic checks. No real SDK, adb, emulator, signing key or application
# data is read. Fixture/evidence directories are new and remain in app/build.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$guardPath = Join-Path $PSScriptRoot 'android_test_install_guard.ps1'
$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($guardPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw 'Android install guard has PowerShell syntax errors.' }
. $guardPath -LibraryOnly

function Assert-AndroidGuardSelfcheck {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

$build = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build'))
$null = Assert-AndroidGuardPlainPath $build
$fixture = Join-Path $build ('android-guard-selfcheck-' + [Guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $fixture
$tools = Join-Path $fixture 'mock-tools'
$null = New-Item -ItemType Directory -Path $tools
foreach ($name in @('adb.exe', 'aapt.exe', 'apksigner.bat', 'candidate.apk')) {
  $path = $(if ($name -in @('aapt.exe', 'apksigner.bat')) { Join-Path $tools $name } else { Join-Path $fixture $name })
  $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $bytes = [Text.Encoding]::ASCII.GetBytes('SYNTHETIC_FIXTURE'); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}
$candidate = Join-Path $fixture 'candidate.apk'
$adb = Join-Path $fixture 'adb.exe'
$script:AndroidGuardScenario = $null
$script:AndroidGuardCommands = [Collections.Generic.List[string]]::new()

# The production manifest reader is tested before replacing it locally for
# version fixtures. The real versions.json is never rewritten.
$manifestVersion = Get-AndroidGuardDesiredVersion
Assert-AndroidGuardSelfcheck ($manifestVersion -ge 1) 'Production version manifest did not parse.'
function Get-AndroidGuardDesiredVersion {
  if ($script:AndroidGuardScenario.Kind -ceq 'manifest-mismatch') { return [int]($script:AndroidGuardScenario.CandidateVersion + 1) }
  return [int]$script:AndroidGuardScenario.CandidateVersion
}

$script:AndroidGuardCommandRunner = {
  param($executable, $arguments)
  $tool = [IO.Path]::GetFileName($executable)
  $script:AndroidGuardCommands.Add($tool + ' ' + ($arguments -join ' '))
  $scenario = $script:AndroidGuardScenario
  if ($tool -ceq 'adb.exe') {
    Assert-AndroidGuardSelfcheck ($arguments.Count -ge 3 -and $arguments[0] -ceq '-s' -and $arguments[1] -ceq 'emulator-5554') 'ADB did not use the exact selected serial.'
    if ($scenario.Kind -ceq 'adb-failed') { return [pscustomobject]@{ ExitCode = 7; Output = 'SYNTHETIC_FAILURE_PRIVATE_PATH' } }
    $command = $arguments[2..($arguments.Count - 1)] -join ' '
    switch -Regex ($command) {
      '^get-state$' { return [pscustomobject]@{ ExitCode = 0; Output = $(if ($scenario.Kind -ceq 'device-offline') { 'offline' } else { 'device' }) } }
      '^emu avd name$' { return [pscustomobject]@{ ExitCode = 0; Output = $(if ($scenario.Kind -ceq 'wrong-avd') { "Other_AVD`nOK" } else { "ImageHost_API36`nOK" }) } }
      '^shell pm list packages io\.imagehost\.imagehost$' {
        $script:AndroidGuardScenario.PathCalls++
        if ($scenario.Kind -ceq 'package-list-failed') { return [pscustomobject]@{ ExitCode = 1; Output = 'SYNTHETIC_FAILURE_PRIVATE_PATH' } }
        $output = 'package:io.imagehost.imagehost'
        if ($scenario.Kind -ceq 'absent' -or ($scenario.Kind -ceq 'absent-changed' -and $scenario.PathCalls -eq 1)) { $output = '' }
        if ($scenario.Kind -ceq 'package-list-malformed') { $output = 'SYNTHETIC_FAILURE_PRIVATE_PATH' }
        return [pscustomobject]@{ ExitCode = 0; Output = $output }
      }
      '^shell pm path io\.imagehost\.imagehost$' {
        if ($scenario.Kind -ceq 'package-missing-after-list') { return [pscustomobject]@{ ExitCode = 1; Output = '' } }
        $output = 'package:/data/app/~~opaque/io.imagehost.imagehost-opaque/base.apk'
        if ($scenario.Kind -ceq 'multiple-base') { $output += "`npackage:/data/app/~~other/io.imagehost.imagehost-other/base.apk" }
        if ($scenario.Kind -ceq 'split') { $output += "`npackage:/data/app/~~opaque/io.imagehost.imagehost-opaque/split_config.arm64_v8a.apk" }
        if ($scenario.Kind -ceq 'malformed-path') { $output = 'SYNTHETIC_FAILURE_PRIVATE_PATH' }
        return [pscustomobject]@{ ExitCode = 0; Output = $output }
      }
      '^shell dumpsys package io\.imagehost\.imagehost$' {
        $version = $scenario.InstalledVersion
        $output = "Packages:`n  Package [io.imagehost.imagehost] (abc123):`n    versionCode=$version minSdk=29 targetSdk=36`n    versionName=0.1.0`nQueries:"
        if ($scenario.Kind -ceq 'malformed-version') { $output = $output.Replace("versionCode=$version", 'versionCode=unknown') }
        if ($scenario.Kind -ceq 'wrong-package') { $output = $output.Replace('[io.imagehost.imagehost]', '[other.package]') }
        return [pscustomobject]@{ ExitCode = 0; Output = $output }
      }
      '^pull /data/app/' {
        Assert-AndroidGuardSelfcheck ($arguments.Count -eq 5) 'Unexpected pull argument count.'
        $stream = [IO.File]::Open($arguments[4], [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $bytes = [Text.Encoding]::ASCII.GetBytes('SYNTHETIC_INSTALLED_APK'); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        return [pscustomobject]@{ ExitCode = 0; Output = '1 file pulled' }
      }
      default { throw 'Unexpected synthetic ADB command.' }
    }
  }
  $isCandidate = $arguments[-1] -ceq $candidate
  if ($tool -ceq 'aapt.exe') {
    Assert-AndroidGuardSelfcheck ($arguments.Count -eq 3 -and $arguments[0] -ceq 'dump' -and $arguments[1] -ceq 'badging') 'Unexpected aapt command.'
    $version = $(if ($isCandidate) { $scenario.CandidateVersion } else { $scenario.InstalledVersion })
    if (-not $isCandidate -and $scenario.Kind -ceq 'apk-version-mismatch') { $version++ }
    $output = "package: name='io.imagehost.imagehost' versionCode='$version' versionName='0.1.0' platformBuildVersionName='16'`napplication-debuggable"
    if ($scenario.Kind -ceq 'not-debug' -and $isCandidate) { $output = $output.Replace("`napplication-debuggable", '') }
    return [pscustomobject]@{ ExitCode = 0; Output = $output }
  }
  if ($tool -ceq 'apksigner.bat') {
    Assert-AndroidGuardSelfcheck ($arguments.Count -eq 4 -and ($arguments[0..2] -join ' ') -ceq 'verify --verbose --print-certs') 'Unexpected apksigner command.'
    $digest = 'a' * 64
    if (-not $isCandidate -and $scenario.Kind -ceq 'different-cert') { $digest = 'b' * 64 }
    if (-not $isCandidate -and $scenario.Kind -ceq 'cert-changed' -and [IO.Path]::GetFileName($arguments[-1]) -ceq 'installed-2.apk') { $digest = 'b' * 64 }
    $output = "Verifies`nNumber of signers: 1`nSigner #1 certificate DN: CN=Android Debug, O=Android, C=US`nSigner #1 certificate SHA-256 digest: $digest"
    if ($scenario.Kind -ceq 'malformed-cert') { $output = $output.Replace($digest, 'invalid') }
    if (-not $isCandidate -and $scenario.Kind -ceq 'missing-installed-cert') { $output = 'Verifies' }
    if ($scenario.Kind -ceq 'wrong-debug-dn') { $output = $output.Replace('CN=Android Debug', 'CN=Other') }
    if ($scenario.Kind -ceq 'signer-failed') { return [pscustomobject]@{ ExitCode = 1; Output = $output } }
    return [pscustomobject]@{ ExitCode = 0; Output = $output }
  }
  throw 'Unexpected synthetic executable.'
}

$cases = @(
  @{ Name = 'absent'; Candidate = 1; Installed = 1; Passed = $true; Reason = 'application_absent' },
  @{ Name = 'same-version'; Candidate = 1; Installed = 1; Passed = $true; Reason = 'compatible_debug_update' },
  @{ Name = 'higher-candidate'; Candidate = 2; Installed = 1; Passed = $true; Reason = 'compatible_debug_update' },
  @{ Name = 'downgrade'; Candidate = 1; Installed = 4001; Passed = $false; Reason = 'version_downgrade_refused' },
  @{ Name = 'different-cert'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'certificate_mismatch_refused' },
  @{ Name = 'adb-failed'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'native_read_failed' },
  @{ Name = 'wrong-avd'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'unowned_emulator' },
  @{ Name = 'malformed-path'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'unsupported_installed_apk_paths' },
  @{ Name = 'multiple-base'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'unsupported_installed_apk_paths' },
  @{ Name = 'split'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'unsupported_installed_apk_paths' },
  @{ Name = 'malformed-version'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'invalid_installed_version' },
  @{ Name = 'wrong-package'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'invalid_installed_package_identity' },
  @{ Name = 'apk-version-mismatch'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'installed_package_changed' },
  @{ Name = 'malformed-cert'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'invalid_apk_certificate' },
  @{ Name = 'not-debug'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'candidate_not_debug' },
  @{ Name = 'cert-changed'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'installed_package_changed' },
  @{ Name = 'absent-changed'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'installed_package_changed' },
  @{ Name = 'manifest-mismatch'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'candidate_manifest_version_mismatch' },
  @{ Name = 'device-offline'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'emulator_not_ready' },
  @{ Name = 'missing-installed-cert'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'invalid_apk_certificate' },
  @{ Name = 'wrong-debug-dn'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'candidate_not_debug_certificate' },
  @{ Name = 'signer-failed'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'native_read_failed' },
  @{ Name = 'package-list-failed'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'native_read_failed' },
  @{ Name = 'package-list-malformed'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'invalid_installed_package_identity' },
  @{ Name = 'package-missing-after-list'; Candidate = 1; Installed = 1; Passed = $false; Reason = 'native_read_failed' }
)
foreach ($case in $cases) {
  $script:AndroidGuardScenario = [pscustomobject]@{ Kind = $case.Name; CandidateVersion = $case.Candidate; InstalledVersion = $case.Installed; PathCalls = 0 }
  $evidence = Join-Path $fixture ('case-' + $case.Name)
  $passed = $false; $reason = $null
  try {
    $result = Invoke-AndroidTestInstallGuard $adb $tools 'emulator-5554' 'ImageHost_API36' $candidate $evidence
    $passed = $result.guardPassed
    $reason = $result.reason
  } catch { $reason = $_.Exception.Message.Replace('Android install guard refused: ', '') }
  Assert-AndroidGuardSelfcheck ($passed -eq $case.Passed -and $reason -ceq $case.Reason) ('Unexpected guard outcome: ' + $case.Name + ' / ' + $reason)
  $reportText = Get-Content -LiteralPath (Join-Path $evidence 'guard-report.json') -Raw
  $report = $reportText | ConvertFrom-Json
  Assert-AndroidGuardSelfcheck ($report.guardPassed -eq $case.Passed -and $report.reason -ceq $case.Reason) ('Unexpected persisted report: ' + $case.Name)
  Assert-AndroidGuardSelfcheck (-not $reportText.Contains($fixture) -and -not $reportText.Contains('/data/app/') -and -not $reportText.Contains('SYNTHETIC_FAILURE_PRIVATE_PATH')) 'Report exposed a path or raw native output.'
}
Assert-AndroidGuardSelfcheck (@($script:AndroidGuardCommands | Where-Object { $_ -match '\b(install|uninstall|clear|kill|force-stop)\b' }).Count -eq 0) 'Guard issued a destructive ADB command.'

# Reject an existing evidence directory before any native command and retain
# its sentinel. Reject evidence outside the two authorized build roots.
$sentinel = Join-Path $fixture 'sentinel.txt'
[IO.File]::WriteAllText($sentinel, 'SYNTHETIC_DO_NOT_OVERWRITE')
foreach ($badEvidence in @($fixture, (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) ('unexpected-guard-' + [Guid]::NewGuid().ToString())))) {
  $countBefore = $script:AndroidGuardCommands.Count
  $reason = $null
  try { $null = Invoke-AndroidTestInstallGuard $adb $tools 'emulator-5554' 'ImageHost_API36' $candidate $badEvidence } catch { $reason = $_.Exception.Message }
  Assert-AndroidGuardSelfcheck ($reason -ceq 'Android install guard refused: unsafe_evidence_directory' -and $script:AndroidGuardCommands.Count -eq $countBefore) 'Unsafe evidence directory was accepted or touched the emulator.'
}
Assert-AndroidGuardSelfcheck ([IO.File]::ReadAllText($sentinel) -ceq 'SYNTHETIC_DO_NOT_OVERWRITE') 'Existing evidence was overwritten.'

# Inject only the reparse metadata at a synthetic ancestor. This validates the
# rejection without creating a real link (the filesystem sandbox denies that).
$junction = Join-Path $fixture 'linked-tools'
function Get-Item {
  [CmdletBinding()]
  param([string]$LiteralPath, [switch]$Force)
  if ($LiteralPath -ceq $junction) { return [pscustomobject]@{ Attributes = [IO.FileAttributes]::ReparsePoint; PSIsContainer = $true } }
  if ($LiteralPath -ceq (Join-Path $junction 'aapt.exe')) { return [pscustomobject]@{ Attributes = [IO.FileAttributes]::Normal; PSIsContainer = $false } }
  return Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
}
foreach ($badPath in @((Join-Path $junction 'aapt.exe'), (Join-Path $junction 'new-evidence'))) {
  $linkedRefused = $false
  try { $null = Assert-AndroidGuardPlainPath $badPath -File -AllowMissingLeaf } catch { $linkedRefused = $_.Exception.Message -ceq 'linked_local_path' }
  Assert-AndroidGuardSelfcheck $linkedRefused 'A linked source or evidence ancestor was accepted.'
}
Write-Output ('Android install guard synthetic selfcheck passed: ' + $cases.Count + ' scenarios, evidence ownership/privacy checks; no SDK or emulator commands executed.')
$global:LASTEXITCODE = 0
