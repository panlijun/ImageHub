param(
  [switch]$Initialize,
  [switch]$Validate,
  [Alias('JavaHome')][string]$SigningJavaHome = $env:JAVA_HOME
)

# Dot-source to load the helpers without creating a key or exposing passwords.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

function Save-ImageHubProcessEnvironment {
  param([Parameter(Mandatory)][string[]]$Names)
  # GetEnvironmentVariable collapses existing empty values to null on .NET
  # Framework. The process dictionary preserves both existence and the value.
  $environment = [Environment]::GetEnvironmentVariables('Process')
  $snapshot = @{}
  foreach ($name in $Names) {
    $snapshot[$name] = [pscustomobject]@{ Exists = $environment.Contains($name); Value = $environment[$name] }
  }
  return $snapshot
}

function Restore-ImageHubProcessEnvironment {
  param([Parameter(Mandatory)][hashtable]$Snapshot)
  foreach ($name in $Snapshot.Keys) {
    $state = $Snapshot[$name]
    if (-not $state.Exists) {
      # An ordinary PowerShell $null is converted to an empty string by this
      # overload on recent runtimes. NullString explicitly requests deletion.
      [Environment]::SetEnvironmentVariable($name, [Management.Automation.Language.NullString]::Value, 'Process')
    } elseif ($state.Value.Length -eq 0) {
      # .NET Framework deletes empty values. Preserve an existing empty value
      # with the Windows API instead, including under Windows PowerShell 5.1.
      if ($null -eq ('ImageHubProcessEnvironment' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ImageHubProcessEnvironment {
  [DllImport("kernel32.dll", EntryPoint = "SetEnvironmentVariableW", CharSet = CharSet.Unicode, SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool Set(string name, string value);
}
'@
      }
      if (-not [ImageHubProcessEnvironment]::Set($name, '')) { throw 'Could not restore an empty process environment value.' }
    } else {
      [Environment]::SetEnvironmentVariable($name, $state.Value, 'Process')
    }
  }
}

function Assert-ImageHubOrdinaryPath {
  param([Parameter(Mandatory)][string]$Path, [switch]$MustExist)
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith('\\') -or $full.StartsWith('\\?\')) {
    throw 'Signing and release paths must be ordinary local paths.'
  }
  $cursor = $full
  while ($cursor) {
    if (Test-Path -LiteralPath $cursor) {
      $item = Get-Item -LiteralPath $cursor -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'A signing or release path contains a link or reparse point.'
      }
    }
    $parent = [IO.Path]::GetDirectoryName($cursor)
    if ($parent -eq $cursor) { break }
    $cursor = $parent
  }
  if ($MustExist -and -not (Test-Path -LiteralPath $full)) {
    throw 'A required signing or release path is missing.'
  }
  return $full
}

function Set-ImageHubPrivateDirectoryAcl {
  param([Parameter(Mandatory)][string]$Path)
  $null = Assert-ImageHubOrdinaryPath -Path $Path -MustExist
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
  foreach ($sid in @($user, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
      $sid, [Security.AccessControl.FileSystemRights]::FullControl,
      ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
      [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $Path -AclObject $acl
}

function Assert-ImageHubPrivateAcl {
  param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
  $acl = Get-Acl -LiteralPath $Path
  if ($Directory -and -not $acl.AreAccessRulesProtected) { throw 'Android signing vault has unprotected inherited permissions.' }
  $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18')
  foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
    if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and $rule.IdentityReference.Value -notin $allowed) {
      throw 'Android signing material has permissions for another principal; unsafe vault access is refused.'
    }
  }
}

function Write-ImageHubExclusiveBytes {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
  $null = Assert-ImageHubOrdinaryPath -Path $Path
  $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
  finally { $stream.Dispose() }
}

function Get-ImageHubByteSha256 {
  param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
  $hash = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $hash.Dispose() }
}

function Get-ImageHubStreamSha256 {
  param([Parameter(Mandatory)][IO.Stream]$Stream)
  $hash = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hash.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
  finally { $hash.Dispose() }
}

function Get-ImageHubRandomPassword {
  param([Parameter(Mandatory)][ref]$Password)
  $bytes = New-Object byte[] 48
  $random = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $random.GetBytes($bytes); $Password.Value = [Convert]::ToBase64String($bytes) }
  finally { [Array]::Clear($bytes, 0, $bytes.Length); $random.Dispose() }
}

function Protect-ImageHubSigningPassword {
  param([Parameter(Mandatory)][string]$Password)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Password)
  $entropy = [Text.Encoding]::UTF8.GetBytes('ImageHub.android.release-signing.v1')
  try {
    return [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect(
      $bytes, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser))
  } finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Unprotect-ImageHubSigningPassword {
  param([Parameter(Mandatory)][string]$ProtectedPassword, [Parameter(Mandatory)][ref]$Password)
  $plain = $null
  try {
    $plain = [Security.Cryptography.ProtectedData]::Unprotect(
      [Convert]::FromBase64String($ProtectedPassword),
      [Text.Encoding]::UTF8.GetBytes('ImageHub.android.release-signing.v1'),
      [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $decodedPassword = [Text.Encoding]::UTF8.GetString($plain)
    if ($decodedPassword -notmatch '^[A-Za-z0-9+/]{64}$') { throw 'Invalid protected password.' }
    $Password.Value = $decodedPassword
  } catch { throw 'The Android signing password cannot be decrypted by the current Windows user.' }
  finally { if ($null -ne $plain) { [Array]::Clear($plain, 0, $plain.Length) } }
}

function Invoke-ImageHubKeytool {
  param([string]$Keytool, [string[]]$Arguments, [string]$StorePassword, [string]$KeyPassword)
  $old = Save-ImageHubProcessEnvironment @('IMAGEHUB_KEYTOOL_STORE_PASSWORD', 'IMAGEHUB_KEYTOOL_KEY_PASSWORD')
  try {
    [Environment]::SetEnvironmentVariable('IMAGEHUB_KEYTOOL_STORE_PASSWORD', $StorePassword, 'Process')
    [Environment]::SetEnvironmentVariable('IMAGEHUB_KEYTOOL_KEY_PASSWORD', $KeyPassword, 'Process')
    # Password values never appear in the command line or the output pipeline.
    # Native stderr is captured; only a fixed failure is exposed.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $result = @(& $Keytool '-J-Duser.language=en' '-J-Duser.country=US' @Arguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw 'Android release keytool operation failed; existing signing material was retained.' }
    $safeResult = ($result | ForEach-Object { [string]$_ }) -join "`n"
    foreach ($secret in @($StorePassword, $KeyPassword)) {
      if ($secret) { $safeResult = $safeResult.Replace($secret, '[REDACTED]') }
    }
    return $safeResult
  } finally {
    Restore-ImageHubProcessEnvironment $old
  }
}

function Get-ImageHubKeytoolIdentity {
  param([string]$Keytool, [string]$KeystorePath, [string]$StorePassword, [string]$KeyPassword)
  $base = @('-keystore', $KeystorePath, '-storetype', 'PKCS12', '-alias', 'imagehubrelease',
    '-storepass:env', 'IMAGEHUB_KEYTOOL_STORE_PASSWORD')
  $listing = Invoke-ImageHubKeytool $Keytool (@('-list', '-v') + $base) $StorePassword $KeyPassword
  if ($listing -notmatch 'Entry type: PrivateKeyEntry') { throw 'Android release alias is not a private key entry.' }
  $public = Invoke-ImageHubKeytool $Keytool (@('-exportcert', '-rfc') + $base) $StorePassword $KeyPassword
  $match = [regex]::Match($public, '(?s)-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----')
  if (-not $match.Success) { throw 'Android release certificate cannot be verified.' }
  $der = [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
  $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($der)
  $rsa = $null
  try {
    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
    if ($null -eq $rsa -or $rsa.KeySize -ne 4096 -or
        $certificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'ImageHub Release' -or
        $certificate.Subject -notmatch '(^|,\s*)O=ImageHub(,|$)' -or
        $certificate.Subject -notmatch '(^|,\s*)C=CN(,|$)' -or
        $certificate.NotAfter.ToUniversalTime() -le [DateTime]::UtcNow) {
      throw 'Android signing identity is not the expected valid ImageHub RSA4096 release certificate.'
    }
    return [pscustomobject]@{ certificateSha256 = Get-ImageHubByteSha256 $der; subject = $certificate.Subject; expiresUtc = $certificate.NotAfter.ToUniversalTime().ToString('o') }
  } finally { if ($null -ne $rsa) { $rsa.Dispose() }; $certificate.Dispose() }
}

function Initialize-ImageHubAndroidSigningVault {
  param([string]$RepositoryRoot, [string]$Keytool)
  $root = Assert-ImageHubOrdinaryPath $RepositoryRoot -MustExist
  $parent = Join-Path $root '.local/signing'
  $vault = Join-Path $parent 'android'
  $null = Assert-ImageHubOrdinaryPath $parent
  if (Test-Path -LiteralPath $vault) { throw 'Android signing vault already exists; initialization never overwrites an identity.' }
  [void][IO.Directory]::CreateDirectory($parent)
  $null = Assert-ImageHubOrdinaryPath $parent -MustExist
  # An earlier incomplete initialization is evidence, not permission to rotate.
  if (@(Get-ChildItem -LiteralPath $parent -Force -Filter '.android-init-*').Count -ne 0) {
    throw 'An incomplete Android signing initialization exists; retain and inspect it before continuing.'
  }
  $stage = Join-Path $parent ('.android-init-' + [Guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($stage)
  Set-ImageHubPrivateDirectoryAcl $stage
  $keyPath = Join-Path $stage 'release.p12'
  $password = $null
  Get-ImageHubRandomPassword ([ref]$password)
  try {
    $null = Invoke-ImageHubKeytool $Keytool @('-genkeypair', '-keystore', $keyPath, '-storetype', 'PKCS12',
      '-alias', 'imagehubrelease', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
      '-dname', 'CN=ImageHub Release,O=ImageHub,C=CN', '-noprompt',
      '-storepass:env', 'IMAGEHUB_KEYTOOL_STORE_PASSWORD', '-keypass:env', 'IMAGEHUB_KEYTOOL_KEY_PASSWORD') $password $password
    $null = Assert-ImageHubOrdinaryPath $keyPath -MustExist
    $identity = Get-ImageHubKeytoolIdentity $Keytool $keyPath $password $password
    $metadata = [ordered]@{
      formatVersion = 1; protection = 'Windows.CurrentUser.DPAPI'; alias = 'imagehubrelease'; keystoreName = 'release.p12'
      storePasswordDpapi = Protect-ImageHubSigningPassword $password
      keyPasswordDpapi = Protect-ImageHubSigningPassword $password
      certificateSha256 = $identity.certificateSha256
      keystoreSha256 = (Get-FileHash -LiteralPath $keyPath -Algorithm SHA256).Hash.ToLowerInvariant()
      createdUtc = [DateTime]::UtcNow.ToString('o')
    }
    Write-ImageHubExclusiveBytes (Join-Path $stage 'vault.json') ([Text.UTF8Encoding]::new($false).GetBytes(($metadata | ConvertTo-Json -Depth 4) + "`n"))
    $null = Assert-ImageHubOrdinaryPath $parent -MustExist
    if (Test-Path -LiteralPath $vault) { throw 'Another Android signing vault appeared; incomplete initialization was retained.' }
    # Same-parent move is an exclusive publication; never delete failed stages.
    [IO.Directory]::Move($stage, $vault)
  } finally { $password = $null }
}

function ConvertFrom-ImageHubSigningMetadata {
  param([Parameter(Mandatory)][string]$Json)
  try {
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
      $metadata = ConvertFrom-Json -InputObject $Json -DateKind String
    } else {
      $metadata = ConvertFrom-Json -InputObject $Json
    }
  } catch { throw 'Invalid Android signing vault metadata JSON.' }
  $expected = @('formatVersion', 'protection', 'alias', 'keystoreName', 'storePasswordDpapi', 'keyPasswordDpapi', 'certificateSha256', 'keystoreSha256', 'createdUtc')
  $actual = @($metadata.PSObject.Properties.Name)
  if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $_ -notin $expected }).Count -ne 0 -or
      [regex]::Matches($Json, '"(?:[^"\\]|\\.)*"\s*:').Count -ne $expected.Count) {
    throw 'Android signing metadata contains unexpected, missing, or duplicate fields.'
  }
  foreach ($name in $expected) {
    if ([regex]::Matches($Json, ('"' + [regex]::Escape($name) + '"\s*:')).Count -ne 1) {
      throw 'Android signing metadata contains missing or duplicate fields.'
    }
  }
  # Some PowerShell JSON decoders turn ISO strings into DateTime automatically.
  # Preserve only this field's unique canonical raw JSON string; never coerce
  # an array, number, other field, escaped date, or otherwise invalid input.
  $rawDates = [regex]::Matches($Json, '"createdUtc"\s*:\s*"(?<value>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{7}Z)"(?=\s*[,}])')
  $parsedCreatedUtc = [DateTime]::MinValue
  if ($rawDates.Count -ne 1 -or -not [DateTime]::TryParseExact($rawDates[0].Groups['value'].Value, 'o',
      [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedCreatedUtc) -or
      $parsedCreatedUtc.Kind -ne [DateTimeKind]::Utc) { throw 'Android signing metadata createdUtc must be a canonical UTC JSON string.' }
  if ($metadata.createdUtc -is [DateTime]) { $metadata.createdUtc = $rawDates[0].Groups['value'].Value }
  foreach ($name in $expected) {
    if ($name -ne 'formatVersion' -and $metadata.$name -isnot [string]) {
      throw 'Android signing metadata fields must be strings without type coercion.'
    }
  }
  if (($metadata.formatVersion -isnot [int] -and $metadata.formatVersion -isnot [long]) -or
      $metadata.formatVersion -ne 1 -or $metadata.protection -cne 'Windows.CurrentUser.DPAPI' -or
      $metadata.alias -cne 'imagehubrelease' -or $metadata.keystoreName -cne 'release.p12' -or
      $metadata.certificateSha256 -cnotmatch '^[0-9a-f]{64}$' -or $metadata.keystoreSha256 -cnotmatch '^[0-9a-f]{64}$' -or
      $metadata.createdUtc -cne $rawDates[0].Groups['value'].Value) { throw 'Invalid or future Android signing vault metadata.' }
  return $metadata
}

function Invoke-ImageHubAndroidSigning {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$JavaHome = $env:JAVA_HOME,
    [switch]$Initialize
  )
  $root = Assert-ImageHubOrdinaryPath $RepositoryRoot -MustExist
  $keytool = Assert-ImageHubOrdinaryPath (Join-Path $JavaHome 'bin/keytool.exe') -MustExist
  $vault = Join-Path $root '.local/signing/android'
  $null = Assert-ImageHubOrdinaryPath $vault
  if (-not (Test-Path -LiteralPath $vault)) {
    if (-not $Initialize) { throw 'Android release signing vault is missing. Explicit -InitializeAndroidSigning is required once.' }
    Initialize-ImageHubAndroidSigningVault $root $keytool
  } elseif ($Initialize) {
    # An explicit initialization flag is idempotent only for an intact vault.
    # Validation below still refuses partial, changed, or undecipherable data.
  }
  $null = Assert-ImageHubOrdinaryPath $vault -MustExist
  Assert-ImageHubPrivateAcl $vault -Directory
  $items = @(Get-ChildItem -LiteralPath $vault -Force)
  if ($items.Count -ne 2 -or @($items | Where-Object { $_.PSIsContainer -or $_.Name -notin @('release.p12', 'vault.json') }).Count -ne 0) {
    throw 'Android signing vault is incomplete or contains unknown items; it will not be replaced.'
  }
  $keyPath = Assert-ImageHubOrdinaryPath (Join-Path $vault 'release.p12') -MustExist
  $metadataPath = Assert-ImageHubOrdinaryPath (Join-Path $vault 'vault.json') -MustExist
  Assert-ImageHubPrivateAcl $keyPath
  Assert-ImageHubPrivateAcl $metadataPath
  $keyStream = $null; $metadataStream = $null; $reader = $null; $storePassword = $null; $keyPassword = $null
  $names = @('IMAGEHUB_ANDROID_KEYSTORE_PATH', 'IMAGEHUB_ANDROID_KEY_ALIAS', 'IMAGEHUB_ANDROID_STORE_PASSWORD', 'IMAGEHUB_ANDROID_KEY_PASSWORD', 'GRADLE_OPTS')
  $old = Save-ImageHubProcessEnvironment $names
  try {
    # Deny write/delete while keytool and the actual build use this identity.
    $keyStream = [IO.FileStream]::new($keyPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $metadataStream = [IO.FileStream]::new($metadataPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($metadataStream.Length -gt 65536 -or $keyStream.Length -lt 1 -or $keyStream.Length -gt 1048576) { throw 'Invalid Android signing vault size.' }
    $reader = [IO.StreamReader]::new($metadataStream, [Text.Encoding]::UTF8, $true, 1024, $true)
    $metadata = ConvertFrom-ImageHubSigningMetadata $reader.ReadToEnd()
    if ((Get-ImageHubStreamSha256 $keyStream) -cne $metadata.keystoreSha256) { throw 'Android release keystore bytes changed; identity replacement is forbidden.' }
    Unprotect-ImageHubSigningPassword $metadata.storePasswordDpapi ([ref]$storePassword)
    Unprotect-ImageHubSigningPassword $metadata.keyPasswordDpapi ([ref]$keyPassword)
    if ($storePassword -cne $keyPassword) { throw 'Invalid PKCS12 signing password relationship.' }
    $identity = Get-ImageHubKeytoolIdentity $keytool $keyPath $storePassword $keyPassword
    if ($identity.certificateSha256 -cne $metadata.certificateSha256) { throw 'Android release certificate identity changed.' }
    [Environment]::SetEnvironmentVariable($names[0], $keyPath, 'Process')
    [Environment]::SetEnvironmentVariable($names[1], 'imagehubrelease', 'Process')
    [Environment]::SetEnvironmentVariable($names[2], $storePassword, 'Process')
    [Environment]::SetEnvironmentVariable($names[3], $keyPassword, 'Process')
    # Do not leave a reusable Gradle daemon holding inherited signing secrets.
    [Environment]::SetEnvironmentVariable('GRADLE_OPTS', ($old['GRADLE_OPTS'].Value + ' -Dorg.gradle.daemon=false -Dorg.gradle.configuration-cache=false').Trim(), 'Process')
    & $Action ([pscustomobject]@{ keystorePath = $keyPath; alias = 'imagehubrelease'; certificateSha256 = $identity.certificateSha256; subject = $identity.subject; expiresUtc = $identity.expiresUtc })
  } finally {
    try { Restore-ImageHubProcessEnvironment $old }
    finally {
      $storePassword = $null; $keyPassword = $null
      if ($null -ne $reader) { $reader.Dispose() }
      if ($null -ne $metadataStream) { $metadataStream.Dispose() }
      if ($null -ne $keyStream) { $keyStream.Dispose() }
    }
  }
}

if ($Initialize -or $Validate) {
  Invoke-ImageHubAndroidSigning -JavaHome $SigningJavaHome -Initialize:$Initialize -Action { param($identity) $identity }
}
