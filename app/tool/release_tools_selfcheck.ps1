# Pure PowerShell/native Windows checks. No Flutter/Dart/Gradle/keytool command,
# release keystore, real credentials, build output, or published artifact.
trap { $global:LASTEXITCODE = 1; throw $_ }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_signing.ps1')
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'package_release.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Release package script has PowerShell syntax errors.' }
foreach ($name in @('Write-ReleaseText', 'Invoke-ReleaseCommand', 'Copy-ReleaseFile', 'Get-ReleaseTree', 'New-ReleaseWorkspace', 'New-VerifiedWindowsZip', 'Assert-AndroidRelease', 'Assert-WindowsReleaseVersion')) {
  $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true)
  if ($null -eq $definition) { throw "Missing release helper: $name" }
  . ([scriptblock]::Create($definition.Extent.Text))
}

function Assert-Selfcheck {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}
function Assert-SelfcheckThrows {
  param([scriptblock]$Action, [string]$Message)
  $threw = $false
  try { $null = & $Action } catch { $threw = $true }
  Assert-Selfcheck $threw $Message
}

function Test-ImageHubEnvironmentRestore {
  param([string[]]$Names, [scriptblock]$Action)
  $original = Save-ImageHubProcessEnvironment $Names
  try {
    foreach ($kind in @('missing', 'empty', 'value')) {
      $fixture = @{}
      foreach ($name in $Names) {
        $fixture[$name] = [pscustomobject]@{ Exists = $kind -ne 'missing'; Value = $(if ($kind -eq 'value') { 'SYNTHETIC_ORIGINAL_VALUE' } elseif ($kind -eq 'empty') { '' } else { $null }) }
      }
      foreach ($fail in @($false, $true)) {
        Restore-ImageHubProcessEnvironment $fixture
        $before = [Environment]::GetEnvironmentVariables('Process')
        foreach ($name in $Names) {
          Assert-Selfcheck ($before.Contains($name) -eq $fixture[$name].Exists -and $before[$name] -ceq $fixture[$name].Value) 'Could not establish the synthetic environment state.'
        }
        $threw = $false
        try { $null = & $Action $fail } catch { $threw = $true }
        Assert-Selfcheck ($threw -eq $fail) 'Environment fixture did not take the expected success or exception path.'
        $after = [Environment]::GetEnvironmentVariables('Process')
        foreach ($name in $Names) {
          Assert-Selfcheck ($after.Contains($name) -eq $fixture[$name].Exists -and $after[$name] -ceq $fixture[$name].Value) 'Environment existence or value changed after a scoped operation.'
        }
      }
    }
  } finally { Restore-ImageHubProcessEnvironment $original }
}

$syntheticEnvironmentNames = @('IMAGEHUB_SELFCHECK_ENV_MISSING', 'IMAGEHUB_SELFCHECK_ENV_EMPTY', 'IMAGEHUB_SELFCHECK_ENV_VALUE')
Test-ImageHubEnvironmentRestore $syntheticEnvironmentNames {
  param($fail)
  $saved = Save-ImageHubProcessEnvironment $syntheticEnvironmentNames
  try {
    foreach ($name in $syntheticEnvironmentNames) { [Environment]::SetEnvironmentVariable($name, 'SYNTHETIC_TEMPORARY_VALUE', 'Process') }
    if ($fail) { throw 'Synthetic environment operation failed.' }
  } finally { Restore-ImageHubProcessEnvironment $saved }
}
Test-ImageHubEnvironmentRestore @('IMAGEHUB_KEYTOOL_STORE_PASSWORD', 'IMAGEHUB_KEYTOOL_KEY_PASSWORD') {
  param($fail)
  # A local PowerShell function replaces the native executable only within
  # this fixture's scope; the real keytool is never invoked.
  function Invoke-SyntheticKeytool {
    Assert-Selfcheck ([Environment]::GetEnvironmentVariable('IMAGEHUB_KEYTOOL_STORE_PASSWORD', 'Process') -ceq 'SYNTHETIC_STORE') 'Keytool store password was not scoped to the operation.'
    Assert-Selfcheck ([Environment]::GetEnvironmentVariable('IMAGEHUB_KEYTOOL_KEY_PASSWORD', 'Process') -ceq 'SYNTHETIC_KEY') 'Keytool key password was not scoped to the operation.'
    $global:LASTEXITCODE = $(if ($fail) { 12 } else { 0 })
    'SYNTHETIC_STORE SYNTHETIC_KEY'
  }
  $result = Invoke-ImageHubKeytool 'Invoke-SyntheticKeytool' @() 'SYNTHETIC_STORE' 'SYNTHETIC_KEY'
  Assert-Selfcheck ($result -ceq '[REDACTED] [REDACTED]') 'Synthetic keytool output was not redacted.'
}

# Run the production packaging setup/finally statements with synthetic work.
# This exercises all six names without invoking SDK tools or package creation.
$packageEnvironmentSetup = [scriptblock]::Create((@($ast.EndBlock.Statements | Where-Object {
  $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -in @('$environmentNames', '$previousEnvironment')
} | ForEach-Object { $_.Extent.Text }) -join "`n"))
$packageTry = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })
Assert-Selfcheck ($packageTry.Count -eq 1 -and $null -ne $packageTry[0].Finally) 'Packaging scope/finally fixture is missing.'
$packageEnvironmentFinally = [scriptblock]::Create($packageTry[0].Finally.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
Test-ImageHubEnvironmentRestore @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_USER_HOME', 'ANDROID_AVD_HOME', 'GRADLE_USER_HOME', 'PATH') {
  param($fail)
  . $packageEnvironmentSetup
  Assert-Selfcheck ($environmentNames.Count -eq 6 -and $previousEnvironment.Count -eq 6) 'Packaging environment snapshot lost a required variable.'
  $location = Get-Location
  try {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, 'SYNTHETIC_PACKAGE_VALUE', 'Process') }
    if ($fail) { throw 'Synthetic packaging operation failed.' }
  } finally { . $packageEnvironmentFinally }
}

$sample = $null; $roundtrip = $null
try {
  $leaked = @(Get-ImageHubRandomPassword ([ref]$sample))
  Assert-Selfcheck ($leaked.Count -eq 0 -and $sample.Length -eq 64) 'Password generator leaked a value or used insufficient entropy.'
  $encrypted = Protect-ImageHubSigningPassword $sample
  $leaked = @(Unprotect-ImageHubSigningPassword $encrypted ([ref]$roundtrip))
  Assert-Selfcheck ($leaked.Count -eq 0 -and $sample -ceq $roundtrip) 'DPAPI roundtrip failed or leaked plaintext into the pipeline.'
  Assert-SelfcheckThrows { Unprotect-ImageHubSigningPassword 'not-dpapi' ([ref]$roundtrip) } 'Malformed DPAPI input was accepted.'
} finally { $sample = $null; $roundtrip = $null }
Assert-SelfcheckThrows { Assert-ImageHubOrdinaryPath '\\server\share\key.p12' } 'UNC signing path was accepted.'
Assert-Selfcheck ((Get-ImageHubByteSha256 ([byte[]]@())) -ceq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') 'Empty source-state fingerprint failed.'

# Exercise the production parser with the complete serialized vault shape.
# All values are synthetic; no real metadata, password blob, or key is read.
$canonicalDate = [DateTime]::UtcNow.ToString('o')
$parserFixture = [ordered]@{
  formatVersion = 1; protection = 'Windows.CurrentUser.DPAPI'; alias = 'imagehubrelease'; keystoreName = 'release.p12'
  storePasswordDpapi = 'synthetic-encrypted-value'; keyPasswordDpapi = 'synthetic-encrypted-value'
  certificateSha256 = ('a' * 64); keystoreSha256 = ('b' * 64); createdUtc = $canonicalDate
}
$parsedFixture = ConvertFrom-ImageHubSigningMetadata ($parserFixture | ConvertTo-Json)
Assert-Selfcheck ($parsedFixture.createdUtc -is [string] -and $parsedFixture.createdUtc -ceq $canonicalDate) 'Production vault parser did not preserve the canonical ISO JSON string.'
foreach ($badDate in @(@($canonicalDate), 123, '2026-02-30T00:00:00.0000000Z', '2026-10-09T00:00:00Z')) {
  $parserFixture.createdUtc = $badDate
  Assert-SelfcheckThrows { ConvertFrom-ImageHubSigningMetadata ($parserFixture | ConvertTo-Json) } 'Production vault parser accepted an array, integer, invalid date or noncanonical date.'
}
$parserFixture.createdUtc = $canonicalDate
$parserFixture.alias = 123
Assert-SelfcheckThrows { ConvertFrom-ImageHubSigningMetadata ($parserFixture | ConvertTo-Json) } 'Production vault parser relaxed another string field.'

$scratch = Join-Path $repository ('dist/.selfcheck-' + [Guid]::NewGuid().ToString('N'))
$null = Assert-ImageHubOrdinaryPath $scratch
[void][IO.Directory]::CreateDirectory($scratch)
$source = Join-Path $scratch 'source'
[void][IO.Directory]::CreateDirectory((Join-Path $source 'data/empty'))
Write-ImageHubExclusiveBytes (Join-Path $source 'sample.bin') ([byte[]](0, 1, 2, 3, 128, 255))
Write-ReleaseText (Join-Path $source 'data/unicode.txt') "ImageHub 图像`n"
$tree = @(Get-ReleaseTree $source)
Assert-Selfcheck ($tree.Count -eq 4 -and @($tree | Where-Object { $_.path -ceq 'data/empty/' }).Count -eq 1) 'Complete file enumeration lost an empty directory.'
$copied = Copy-ReleaseFile (Join-Path $source 'sample.bin') (Join-Path $scratch 'copy.bin')
Assert-Selfcheck ($copied.bytes -eq 6 -and $copied.sha256 -ceq (Get-FileHash -LiteralPath (Join-Path $source 'sample.bin') -Algorithm SHA256).Hash.ToLowerInvariant()) 'Exclusive copy byte digest failed.'
Assert-SelfcheckThrows { Copy-ReleaseFile (Join-Path $source 'sample.bin') (Join-Path $scratch 'copy.bin') } 'Release copy overwrote an existing destination.'

# Windows input checks run before any PE inspection, ZIP creation or launch.
$windowsFixture = Join-Path $scratch 'windows-tree'
[void][IO.Directory]::CreateDirectory((Join-Path $windowsFixture 'data'))
$windowsRequired = @('imagehub.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
foreach ($name in $windowsRequired) { Write-ImageHubExclusiveBytes (Join-Path $windowsFixture $name) ([byte[]](0)) }
foreach ($missing in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  $path = Join-Path $windowsFixture $missing
  $held = Join-Path $windowsFixture ($missing + '.held')
  [IO.File]::Move($path, $held)
  try {
    $message = ''
    try { New-VerifiedWindowsZip $windowsFixture $scratch 'must-not-create.zip' $null } catch { $message = $_.Exception.Message }
    Assert-Selfcheck ($message -match 'app-local VC runtime') 'Windows packaging accepted a missing app-local VC runtime or reached a later operation.'
  } finally { [IO.File]::Move($held, $path) }
}
foreach ($extra in @('imagehost.exe', 'other.EXE')) {
  Write-ImageHubExclusiveBytes (Join-Path $windowsFixture $extra) ([byte[]](0))
  $message = ''
  try { New-VerifiedWindowsZip $windowsFixture $scratch 'must-not-create.zip' $null } catch { $message = $_.Exception.Message }
  Assert-Selfcheck ($message -match 'only the expected top-level imagehub.exe') 'Windows packaging accepted a stale/extra top-level executable or reached a later operation.'
  [IO.File]::Move((Join-Path $windowsFixture $extra), (Join-Path $windowsFixture ($extra + '.held')))
}
$workspaceStage = Join-Path $scratch 'release-stage'
[void][IO.Directory]::CreateDirectory($workspaceStage)
$firstWorkspace = New-ReleaseWorkspace $workspaceStage 'windows-release'
Write-ReleaseText (Join-Path $firstWorkspace 'retained.txt') 'SYNTHETIC_RETAINED_EVIDENCE'
$secondWorkspace = New-ReleaseWorkspace $workspaceStage 'windows-release'
$extractWorkspace = New-ReleaseWorkspace $workspaceStage 'windows-zip-check'
Assert-Selfcheck ($firstWorkspace -cne $secondWorkspace -and $secondWorkspace -cne $extractWorkspace -and
  [IO.Path]::GetDirectoryName($firstWorkspace) -ceq [IO.Path]::GetDirectoryName($workspaceStage) -and
  (Get-Content -LiteralPath (Join-Path $firstWorkspace 'retained.txt') -Raw) -ceq 'SYNTHETIC_RETAINED_EVIDENCE') 'Release workspaces collided or changed retained evidence.'
Assert-Selfcheck (-not [ImageHubReleaseWorkspace]::Create($firstWorkspace, [IntPtr]::Zero)) 'Release workspace creation adopted an existing directory.'
$private = Join-Path $scratch 'private-acl'
[void][IO.Directory]::CreateDirectory($private)
Set-ImageHubPrivateDirectoryAcl $private
Assert-ImageHubPrivateAcl $private -Directory
Write-ReleaseText (Join-Path $private 'synthetic.txt') 'No signing material.'
Assert-ImageHubPrivateAcl (Join-Path $private 'synthetic.txt')

# Reject metadata types before reaching keytool. These bytes are deliberately
# not a key, and the fixture repository never points at the real .local vault.
$fakeJava = Join-Path $scratch 'fake-java'
[void][IO.Directory]::CreateDirectory((Join-Path $fakeJava 'bin'))
Write-ImageHubExclusiveBytes (Join-Path $fakeJava 'bin/keytool.exe') ([byte[]](0))
foreach ($case in @('string-format', 'numeric-password')) {
  $fixtureRoot = Join-Path $scratch $case
  $fixtureVault = Join-Path $fixtureRoot '.local/signing/android'
  [void][IO.Directory]::CreateDirectory($fixtureVault)
  Set-ImageHubPrivateDirectoryAcl $fixtureVault
  Write-ImageHubExclusiveBytes (Join-Path $fixtureVault 'release.p12') ([byte[]](0, 1, 2))
  $metadata = [ordered]@{
    formatVersion = 1; protection = 'Windows.CurrentUser.DPAPI'; alias = 'imagehubrelease'; keystoreName = 'release.p12'
    storePasswordDpapi = 'not-dpapi'; keyPasswordDpapi = 'not-dpapi'; certificateSha256 = ('a' * 64)
    keystoreSha256 = Get-ImageHubByteSha256 ([byte[]](0, 1, 2)); createdUtc = [DateTime]::UtcNow.ToString('o')
  }
  if ($case -eq 'string-format') { $metadata.formatVersion = '1' } else { $metadata.storePasswordDpapi = 1 }
  Write-ReleaseText (Join-Path $fixtureVault 'vault.json') ($metadata | ConvertTo-Json)
  $message = ''
  try { Invoke-ImageHubAndroidSigning -RepositoryRoot $fixtureRoot -JavaHome $fakeJava -Action { throw 'Fixture must not reach signing action.' } }
  catch { $message = $_.Exception.Message }
  Assert-Selfcheck ($message -match 'metadata') 'Signing metadata type coercion was accepted or reached native keytool.'
}

# Exercise the signing Action and its exception after all five variables have
# changed. The isolated vault contains arbitrary bytes and synthetic DPAPI;
# a local identity stub prevents any certificate or native keytool operation.
$fixtureRoot = Join-Path $scratch 'environment-signing'
$fixtureVault = Join-Path $fixtureRoot '.local/signing/android'
[void][IO.Directory]::CreateDirectory($fixtureVault)
Set-ImageHubPrivateDirectoryAcl $fixtureVault
Write-ImageHubExclusiveBytes (Join-Path $fixtureVault 'release.p12') ([byte[]](0, 1, 2))
$syntheticPassword = 'C' * 64
$metadata = [ordered]@{
  formatVersion = 1; protection = 'Windows.CurrentUser.DPAPI'; alias = 'imagehubrelease'; keystoreName = 'release.p12'
  storePasswordDpapi = Protect-ImageHubSigningPassword $syntheticPassword; keyPasswordDpapi = Protect-ImageHubSigningPassword $syntheticPassword
  certificateSha256 = ('a' * 64); keystoreSha256 = Get-ImageHubByteSha256 ([byte[]](0, 1, 2)); createdUtc = [DateTime]::UtcNow.ToString('o')
}
Write-ReleaseText (Join-Path $fixtureVault 'vault.json') ($metadata | ConvertTo-Json)
Test-ImageHubEnvironmentRestore @('IMAGEHUB_ANDROID_KEYSTORE_PATH', 'IMAGEHUB_ANDROID_KEY_ALIAS', 'IMAGEHUB_ANDROID_STORE_PASSWORD', 'IMAGEHUB_ANDROID_KEY_PASSWORD', 'GRADLE_OPTS') {
  param($fail)
  function Get-ImageHubKeytoolIdentity {
    return [pscustomobject]@{ certificateSha256 = ('a' * 64); subject = 'Synthetic identity'; expiresUtc = 'Synthetic expiration' }
  }
  Invoke-ImageHubAndroidSigning -RepositoryRoot $fixtureRoot -JavaHome $fakeJava -Action {
    Assert-Selfcheck ($env:IMAGEHUB_ANDROID_KEYSTORE_PATH -ceq (Join-Path $fixtureVault 'release.p12') -and $env:IMAGEHUB_ANDROID_KEY_ALIAS -ceq 'imagehubrelease') 'Signing identity was not scoped to the operation.'
    Assert-Selfcheck ($env:IMAGEHUB_ANDROID_STORE_PASSWORD -ceq $syntheticPassword -and $env:IMAGEHUB_ANDROID_KEY_PASSWORD -ceq $syntheticPassword) 'Synthetic signing passwords were not scoped to the operation.'
    Assert-Selfcheck ($env:GRADLE_OPTS -match '-Dorg.gradle.daemon=false -Dorg.gradle.configuration-cache=false$') 'Scoped signing did not disable the Gradle daemon/cache.'
    if ($fail) { throw 'Synthetic signing Action failed.' }
  }
}
$syntheticPassword = $null

$oldSecret = Save-ImageHubProcessEnvironment @('IMAGEHUB_ANDROID_STORE_PASSWORD')
try {
  [Environment]::SetEnvironmentVariable('IMAGEHUB_ANDROID_STORE_PASSWORD', 'SYNTHETIC_SELF_CHECK_SECRET', 'Process')
  $child = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $safe = Invoke-ReleaseCommand $child @('-NoProfile', '-NonInteractive', '-Command', "[Console]::WriteLine([Environment]::GetEnvironmentVariable('IMAGEHUB_ANDROID_STORE_PASSWORD','Process')); exit 0") (Join-Path $scratch 'safe.log') -Quiet
  Assert-Selfcheck ($safe -ceq '[REDACTED]' -and (Get-Content -LiteralPath (Join-Path $scratch 'safe.log') -Raw) -notmatch 'SYNTHETIC_SELF_CHECK_SECRET') 'Build output redaction failed.'
  Assert-SelfcheckThrows { Invoke-ReleaseCommand $child @('-NoProfile', '-NonInteractive', '-Command', 'exit 12') (Join-Path $scratch 'failed.log') -Quiet } 'Failed native command was accepted.'
} finally { Restore-ImageHubProcessEnvironment $oldSecret }
$windowsVersions = [pscustomobject]@{ kernel = [pscustomobject]@{ version = '0.9.0'; revision = 5 }; platforms = [pscustomobject]@{ windows = [pscustomobject]@{ version = '1.2.3'; build = 7 } } }
Assert-SelfcheckThrows { Assert-WindowsReleaseVersion $child $windowsVersions } 'Wrong Windows executable version was accepted.'
Assert-SelfcheckThrows { [ImageHubReleaseVersionResource]::Kernel($child) } 'Missing native Windows kernel resource was accepted.'

# Use captured-shape fixture strings to check field binding. Never invoke SDK tools.
function Invoke-ReleaseCommand {
  param([string]$Command, [string[]]$Arguments, [string]$LogPath, [switch]$Quiet)
  if ($Arguments -contains 'badging') {
    return "package: name='io.imagehost.imagehost' versionCode='7' versionName='1.2.3' platformBuildVersionName='16'`nsdkVersion:'29'`nnative-code: 'arm64-v8a'"
  }
  if ($Arguments -contains 'verify') {
    return ("Verified using v2 scheme (APK Signature Scheme v2): true`nSigner #1 certificate DN: CN=ImageHub Release, O=ImageHub, C=CN`nSigner #1 certificate SHA-256 digest: " + ('a' * 64))
  }
  return "E: manifest (line=1)`n  E: application (line=2)`n    E: meta-data (line=3)`n      A: android:name(0x01010003)=`"io.imagehub.kernel.version`" (Raw: `"io.imagehub.kernel.version`")`n      A: android:value(0x01010024)=`"0.9.0+5`" (Raw: `"0.9.0+5`")`n    E: activity (line=4)`n"
}
$versions = [pscustomobject]@{ kernel = [pscustomobject]@{ version = '0.9.0'; revision = 5 }; platforms = [pscustomobject]@{ android = [pscustomobject]@{ version = '1.2.3'; build = 7 } } }
$android = Assert-AndroidRelease 'synthetic-not-an-apk' 'synthetic-not-sdk' $scratch $versions ('a' * 64)
Assert-Selfcheck ($android.kernelVersion -ceq '0.9.0+5' -and $android.verifiedV2Signature) 'Android independent platform/kernel verification fixture failed.'
Assert-SelfcheckThrows { Assert-AndroidRelease 'synthetic-not-an-apk' 'synthetic-not-sdk' $scratch $versions ('b' * 64) } 'Android wrong signing certificate was accepted.'
$versions.kernel.revision = 6
Assert-SelfcheckThrows { Assert-AndroidRelease 'synthetic-not-an-apk' 'synthetic-not-sdk' $scratch $versions ('a' * 64) } 'Android wrong kernel metadata was accepted.'
Write-Host "PASS release helper syntax, exact missing/empty/value environment restoration on success/failure (helpers, keytool, signing Action, packaging), no-password pipeline, DPAPI, path/ACL, strict vault types, complete enumeration, exclusive bytes/workspaces, Windows CRT/unique runner rejection, native failure/redaction, Windows version resource and Android metadata fixtures. Synthetic evidence retained at $scratch"
# The intentional native failure fixture sets LASTEXITCODE=12. Clear only at
# the successful end, so callers using exit $LASTEXITCODE receive success 0.
$global:LASTEXITCODE = 0
