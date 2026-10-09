param(
  [Parameter(Mandatory)][ValidateSet('windows', 'android')][string]$Platform,
  [string]$FlutterSdk = 'C:\Users\PAN\development\flutter',
  [string]$JavaHome = '',
  [string]$AndroidSdk = '',
  [switch]$InitializeAndroidSigning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Platform = $Platform.ToLowerInvariant()
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$application = Join-Path $repository 'app'
. (Join-Path $PSScriptRoot 'android_signing.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-ReleaseText {
  param([string]$Path, [string]$Text)
  Write-ImageHubExclusiveBytes $Path ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Invoke-ReleaseCommand {
  param([string]$Command, [string[]]$Arguments, [string]$LogPath, [switch]$Quiet)
  $null = Assert-ImageHubOrdinaryPath $Command -MustExist
  $output = New-Object 'Collections.Generic.List[string]'
  $log = [IO.StreamWriter]::new([IO.FileStream]::new($LogPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read), [Text.UTF8Encoding]::new($false))
  try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & $Command @Arguments 2>&1 | ForEach-Object {
        $line = [string]$_
        foreach ($name in @('IMAGEHUB_ANDROID_STORE_PASSWORD', 'IMAGEHUB_ANDROID_KEY_PASSWORD')) {
          $secret = [Environment]::GetEnvironmentVariable($name, 'Process')
          if ($secret) { $line = $line.Replace($secret, '[REDACTED]') }
        }
        $log.WriteLine($line); $log.Flush()
        $output.Add($line)
        if (-not $Quiet) { Write-Host $line }
      }
      $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw "Release command failed (exit $code). The incomplete stage and safe log were retained." }
    return ($output -join "`n")
  } finally { $log.Dispose() }
}

function Get-ReleaseSource {
  $commit = @(& git -C $repository rev-parse HEAD 2>$null) -join ''
  if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'Cannot establish the release source Git identity.' }
  $status = @(& git -C $repository status --porcelain=v1 --untracked-files=all 2>$null)
  if ($LASTEXITCODE -ne 0) { throw 'Cannot establish the release source worktree state.' }
  $diff = @(& git -C $repository diff HEAD --binary --no-ext-diff 2>$null) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw 'Cannot establish the release source diff fingerprint.' }
  $sourceFiles = @(& git -C $repository -c core.quotepath=false ls-files --cached --others --exclude-standard 2>$null | Sort-Object -Unique)
  if ($LASTEXITCODE -ne 0) { throw 'Cannot establish the release source file list.' }
  $sourceRecords = New-Object 'Collections.Generic.List[string]'
  foreach ($relative in $sourceFiles) {
    if ($relative -match '(^/|:|\\|(^|/)\.\.?(/|$)|[\r\n])' -or $relative.StartsWith('"')) { throw 'Source contains a path that cannot be safely fingerprinted.' }
    $path = Assert-ImageHubOrdinaryPath (Join-Path $repository $relative)
    if (-not (Test-Path -LiteralPath $path)) { $sourceRecords.Add("missing`t$relative"); continue }
    if ((Get-Item -LiteralPath $path -Force).PSIsContainer) { throw 'Git source contains an unsupported directory entry.' }
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { $sourceRecords.Add("$relative`t$($stream.Length)`t$(Get-ImageHubStreamSha256 $stream)") }
    finally { $stream.Dispose() }
  }
  return [ordered]@{
    commit = $commit; dirty = ($status.Count -gt 0); status = $status
    statusSha256 = Get-ImageHubByteSha256 ([Text.Encoding]::UTF8.GetBytes(($status -join "`n")))
    trackedDiffSha256 = Get-ImageHubByteSha256 ([Text.Encoding]::UTF8.GetBytes($diff))
    sourceFileCount = $sourceFiles.Count
    sourceFilesSha256 = Get-ImageHubByteSha256 ([Text.Encoding]::UTF8.GetBytes(($sourceRecords -join "`n")))
    interpretation = 'The commit identifies the base. A dirty worktree is not claimed to be that committed tree.'
  }
}

function Get-ReleaseTree {
  param([string]$Directory)
  $root = Assert-ImageHubOrdinaryPath $Directory -MustExist
  $pending = New-Object 'Collections.Generic.Queue[string]'
  $items = New-Object 'Collections.Generic.List[object]'
  $pending.Enqueue($root)
  while ($pending.Count -gt 0) {
    $current = $pending.Dequeue()
    foreach ($item in @(Get-ChildItem -LiteralPath $current -Force | Sort-Object Name)) {
      $null = Assert-ImageHubOrdinaryPath $item.FullName -MustExist
      $relative = $item.FullName.Substring($root.TrimEnd('\').Length + 1).Replace('\', '/')
      if ($relative -match '(^/|:|\\|(^|/)\.\.?(/|$))') { throw 'Unsafe release entry path.' }
      if ($item.PSIsContainer) {
        $items.Add([pscustomobject]@{ path = $relative + '/'; directory = $true; source = $item.FullName })
        $pending.Enqueue($item.FullName)
      } else {
        $items.Add([pscustomobject]@{ path = $relative; directory = $false; source = $item.FullName })
      }
    }
  }
  return @($items | Sort-Object path)
}

function Copy-ReleaseFile {
  param([string]$Source, [string]$Destination)
  $null = Assert-ImageHubOrdinaryPath $Source -MustExist
  $null = Assert-ImageHubOrdinaryPath $Destination
  $input = [IO.FileStream]::new($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $output = $null
  try {
    $output = [IO.FileStream]::new($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $input.CopyTo($output, 65536); $output.Flush($true); $output.Dispose(); $output = $null
    $input.Position = 0
    $sourceHash = Get-ImageHubStreamSha256 $input
    $copiedHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($copiedHash -cne $sourceHash -or (Get-Item -LiteralPath $Destination).Length -ne $input.Length) {
      throw 'Copied release file does not match its closed source bytes.'
    }
    return [pscustomobject]@{ sha256 = $copiedHash; bytes = $input.Length }
  } finally { if ($null -ne $output) { $output.Dispose() }; $input.Dispose() }
}

function Assert-WindowsReleaseVersion {
  param([string]$Executable, $Versions)
  if (-not ('ImageHubReleaseVersionResource' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ImageHubReleaseVersionResource {
  [DllImport("version.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetFileVersionInfoSizeW(string path, out uint unused);
  [DllImport("version.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool GetFileVersionInfoW(string path, uint unused, uint count, byte[] data);
  [DllImport("version.dll", CharSet=CharSet.Unicode)] static extern bool VerQueryValueW(byte[] data, string subblock, out IntPtr value, out uint length);
  public static string Kernel(string path) {
    uint unused; uint size = GetFileVersionInfoSizeW(path, out unused);
    if (size == 0 || size > 1048576) throw new InvalidOperationException("Missing version resource.");
    byte[] data = new byte[size];
    if (!GetFileVersionInfoW(path, 0, size, data)) throw new InvalidOperationException("Unreadable version resource.");
    var pin = GCHandle.Alloc(data, GCHandleType.Pinned);
    try {
      IntPtr value; uint length;
      if (!VerQueryValueW(data, "\\StringFileInfo\\040904e4\\ImageHubKernelVersion", out value, out length) || length < 2 || length > 256)
        throw new InvalidOperationException("Missing kernel identity.");
      return Marshal.PtrToStringUni(value, (int)length - 1);
    } finally { pin.Free(); }
  }
}
'@
  }
  $expected = $Versions.platforms.windows
  $identity = "$($expected.version)+$($expected.build)"
  $kernel = "$($Versions.kernel.version)+$($Versions.kernel.revision)"
  $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($Executable)
  $parts = $expected.version.Split('.')
  if ($version.FileVersion -cne $identity -or $version.ProductVersion -cne $identity -or $version.IsDebug -or
      $version.FileMajorPart -ne [int]$parts[0] -or $version.FileMinorPart -ne [int]$parts[1] -or
      $version.FileBuildPart -ne [int]$parts[2] -or $version.FilePrivatePart -ne $expected.build -or
      [ImageHubReleaseVersionResource]::Kernel($Executable) -cne $kernel) { throw 'Windows PE platform or kernel identity differs from versions.json.' }
  $stream = [IO.File]::OpenRead($Executable)
  $reader = [IO.BinaryReader]::new($stream)
  try {
    if ($reader.ReadUInt16() -ne 0x5a4d -or $stream.Length -lt 64) { throw 'Invalid Windows executable.' }
    $stream.Position = 0x3c; $offset = $reader.ReadUInt32()
    if ($offset -gt $stream.Length - 6) { throw 'Invalid PE header position.' }
    $stream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Windows release executable is not x64.' }
  } finally { $reader.Dispose(); $stream.Dispose() }
  return [ordered]@{ platformVersion = $identity; kernelVersion = $kernel; machine = 'x64'; debug = $false }
}

function New-ReleaseWorkspace {
  param([string]$Stage, [ValidateSet('windows-release', 'windows-zip-check')][string]$Purpose)
  $stagePath = Assert-ImageHubOrdinaryPath $Stage -MustExist
  if (-not (Get-Item -LiteralPath $stagePath).PSIsContainer) { throw 'Release stage must be a directory.' }
  $workspace = Join-Path ([IO.Path]::GetDirectoryName($stagePath)) ([IO.Path]::GetFileName($stagePath) + '-' + $Purpose + '-' + [Guid]::NewGuid().ToString('N'))
  $null = Assert-ImageHubOrdinaryPath $workspace
  if ($null -eq ('ImageHubReleaseWorkspace' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ImageHubReleaseWorkspace {
  [DllImport("kernel32.dll", EntryPoint = "CreateDirectoryW", CharSet = CharSet.Unicode, SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool Create(string path, IntPtr securityAttributes);
}
'@
  }
  # CreateDirectoryW fails for an existing path instead of adopting its files.
  # Keep each failed workspace as evidence; subsequent attempts get new names.
  if (-not [ImageHubReleaseWorkspace]::Create($workspace, [IntPtr]::Zero)) { throw 'Could not exclusively create a new release workspace; existing evidence was retained.' }
  $null = Assert-ImageHubOrdinaryPath $workspace -MustExist
  return $workspace
}

function New-VerifiedWindowsZip {
  param([string]$ReleaseDirectory, [string]$Stage, [string]$ArtifactName, $Versions)
  $tree = @(Get-ReleaseTree $ReleaseDirectory)
  $executables = @($tree | Where-Object { -not $_.directory -and $_.path -notmatch '/' -and $_.path -match '(?i)\.exe$' })
  if ($executables.Count -ne 1 -or $executables[0].path -cne 'imagehub.exe') { throw 'Windows Release must contain only the expected top-level imagehub.exe.' }
  foreach ($required in @('flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (@($tree | Where-Object { -not $_.directory -and $_.path -ceq $required }).Count -ne 1) { throw 'Windows Flutter Release directory is incomplete, including its app-local VC runtime.' }
  }
  if (@($tree | Where-Object { $_.directory -and $_.path -ceq 'data/' }).Count -ne 1) { throw 'Windows Flutter Release directory is incomplete.' }
  $copyRoot = New-ReleaseWorkspace $Stage 'windows-release'
  $records = New-Object 'Collections.Generic.List[object]'
  foreach ($entry in $tree) {
    $destination = Join-Path $copyRoot $entry.path.Replace('/', '\')
    if ($entry.directory) {
      [void][IO.Directory]::CreateDirectory($destination)
      $records.Add([pscustomobject]@{ path = $entry.path; directory = $true; bytes = 0; sha256 = $null })
    } else {
      [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
      $copied = Copy-ReleaseFile $entry.source $destination
      $records.Add([pscustomobject]@{ path = $entry.path; directory = $false; bytes = $copied.bytes; sha256 = $copied.sha256 })
    }
  }
  $native = Assert-WindowsReleaseVersion (Join-Path $copyRoot 'imagehub.exe') $Versions
  $zipPath = Join-Path $Stage $ArtifactName
  $zipStream = [IO.FileStream]::new($zipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  $zip = $null
  try {
    $zip = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($record in $records) {
      $entry = $zip.CreateEntry($record.path, [IO.Compression.CompressionLevel]::Optimal)
      if (-not $record.directory) {
        $input = [IO.File]::OpenRead((Join-Path $copyRoot $record.path.Replace('/', '\')))
        $output = $entry.Open()
        try { $input.CopyTo($output, 65536) } finally { $output.Dispose(); $input.Dispose() }
      }
    }
    $zip.Dispose(); $zip = $null; $zipStream.Flush($true)
  } finally { if ($null -ne $zip) { $zip.Dispose() }; $zipStream.Dispose() }
  $extractRoot = New-ReleaseWorkspace $Stage 'windows-zip-check'
  $verify = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    if ($verify.Entries.Count -ne $records.Count) { throw 'Windows ZIP entry count differs from the complete Release directory.' }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $map = @{}
    foreach ($record in $records) { $map[$record.path] = $record }
    foreach ($entry in $verify.Entries) {
      if (-not $seen.Add($entry.FullName) -or -not $map.ContainsKey($entry.FullName)) { throw 'Windows ZIP has a duplicate or unexpected entry.' }
      $record = $map[$entry.FullName]
      if ($entry.FullName -cne $record.path -or $entry.Length -ne $record.bytes) { throw 'Windows ZIP entry identity or length mismatch.' }
      $destination = Join-Path $extractRoot $record.path.Replace('/', '\')
      if ($record.directory) { [void][IO.Directory]::CreateDirectory($destination); continue }
      [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
      $input = $entry.Open()
      try { $actualHash = Get-ImageHubStreamSha256 $input } finally { $input.Dispose() }
      if ($actualHash -cne $record.sha256) { throw 'Windows ZIP entry byte digest mismatch.' }
      $input = $entry.Open()
      $output = [IO.FileStream]::new($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try { $input.CopyTo($output, 65536); $output.Flush($true) } finally { $output.Dispose(); $input.Dispose() }
      if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256) { throw 'Extracted Windows ZIP bytes differ.' }
    }
  } finally { $verify.Dispose() }
  $null = Assert-WindowsReleaseVersion (Join-Path $extractRoot 'imagehub.exe') $Versions
  $smoke = & (Join-Path $PSScriptRoot 'verify_release_smoke.ps1') -Executable (Join-Path $extractRoot 'imagehub.exe')
  Write-ReleaseText (Join-Path $Stage 'windows-smoke.log') (($smoke -join "`n") + "`n")
  return [ordered]@{ native = $native; files = $records.ToArray(); verifiedCompleteZip = $true; extractedRunnerNormalExit = $true }
}

function Assert-AndroidRelease {
  param([string]$Apk, [string]$BuildTools, [string]$Stage, $Versions, [string]$CertificateSha256)
  $badging = Invoke-ReleaseCommand (Join-Path $BuildTools 'aapt.exe') @('dump', 'badging', $Apk) (Join-Path $Stage 'android-badging.log') -Quiet
  $package = [regex]::Match($badging, "(?m)^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
  $expected = $Versions.platforms.android
  if (-not $package.Success -or $package.Groups[1].Value -cne 'io.imagehost.imagehost' -or
      $package.Groups[2].Value -cne [string]$expected.build -or $package.Groups[3].Value -cne $expected.version -or
      $badging -notmatch "(?m)^sdkVersion:'29'\s*$" -or $badging -notmatch "(?m)^native-code: 'arm64-v8a'\s*$" -or
      $badging -match '(?m)^application-debuggable') { throw 'Android APK package, minimum SDK, ABI, version, or release mode differs from the required identity.' }
  $signature = Invoke-ReleaseCommand (Join-Path $BuildTools 'apksigner.bat') @('verify', '--verbose', '--print-certs', $Apk) (Join-Path $Stage 'android-signature.log') -Quiet
  $digest = [regex]::Matches($signature, '(?m)^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})\s*$')
  if ($digest.Count -ne 1 -or $digest[0].Groups[1].Value.ToLowerInvariant() -cne $CertificateSha256 -or
      $signature -match '(?i)CN=Android Debug' -or $signature -notmatch '(?m)^Verified using v2 scheme .*: true\s*$') {
    throw 'Android APK does not have the verified dedicated release certificate and v2 signature.'
  }
  $xml = Invoke-ReleaseCommand (Join-Path $BuildTools 'aapt.exe') @('dump', 'xmltree', $Apk, 'AndroidManifest.xml') (Join-Path $Stage 'android-manifest.log') -Quiet
  $kernel = "$($Versions.kernel.version)+$($Versions.kernel.revision)"
  # Bind name/value to one meta-data element, not a value anywhere in the manifest.
  $meta = [regex]::Matches($xml, '(?m)^([ \t]*)E: meta-data[^\r\n]*\r?\n((?:\1  A:[^\r\n]*\r?\n?)+)')
  $matched = @($meta | Where-Object {
    $_.Groups[2].Value -match 'A: android:name[^\r\n]*="io\.imagehub\.kernel\.version"' -and
    $_.Groups[2].Value -match ('A: android:value[^\r\n]*="' + [regex]::Escape($kernel) + '"')
  })
  if ($matched.Count -ne 1) { throw 'Android APK kernel metadata differs from versions.json.' }
  return [ordered]@{ applicationId = 'io.imagehost.imagehost'; minimumSdk = 29; abi = 'arm64-v8a'; platformVersion = "$($expected.version)+$($expected.build)"; kernelVersion = $kernel; certificateSha256 = $CertificateSha256; verifiedV2Signature = $true }
}

$environmentNames = @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_USER_HOME', 'ANDROID_AVD_HOME', 'GRADLE_USER_HOME', 'PATH')
$previousEnvironment = Save-ImageHubProcessEnvironment $environmentNames
$location = Get-Location
$stage = $null
$workStage = $null
try {
  $null = Assert-ImageHubOrdinaryPath $repository -MustExist
  $flutter = Assert-ImageHubOrdinaryPath (Join-Path $FlutterSdk 'bin/flutter.bat') -MustExist
  $dart = Assert-ImageHubOrdinaryPath (Join-Path $FlutterSdk 'bin/dart.bat') -MustExist
  if ($Platform -eq 'android') {
    . (Join-Path $PSScriptRoot 'android_environment.ps1')
    if ($JavaHome) { $env:JAVA_HOME = $JavaHome }
    if ($AndroidSdk) { $env:ANDROID_HOME = $AndroidSdk }
    $env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
  } elseif ($InitializeAndroidSigning) { throw '-InitializeAndroidSigning is only valid for Android packaging.' }
  $null = Assert-ImageHubOrdinaryPath (Join-Path $repository 'dist')
  $null = Assert-ImageHubOrdinaryPath (Join-Path $repository 'dist/.staging')
  [void][IO.Directory]::CreateDirectory((Join-Path $repository 'dist/.staging'))
  $workStage = Join-Path $repository ('dist/.staging/' + $Platform + '-' + [Guid]::NewGuid().ToString('N'))
  $stage = Join-Path $workStage 'release'
  $null = Assert-ImageHubOrdinaryPath $stage
  [void][IO.Directory]::CreateDirectory($stage)
  $null = Assert-ImageHubOrdinaryPath $stage -MustExist
  Set-Location -LiteralPath $application
  $null = Invoke-ReleaseCommand $dart @('tool/versioning.dart', 'check') (Join-Path $stage 'version-check.log')
  $versionsPath = Join-Path $application 'versions.json'
  $versions = Get-Content -LiteralPath $versionsPath -Raw | ConvertFrom-Json
  $versionHash = (Get-FileHash -LiteralPath $versionsPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $own = $versions.platforms.$Platform
  $identity = "$($own.version)+$($own.build)"
  $final = Join-Path $repository ("dist/$Platform/$identity")
  $null = Assert-ImageHubOrdinaryPath $final
  if (Test-Path -LiteralPath $final) { throw 'This platform/version/build already has a release directory. It cannot be overwritten or silently rebuilt under the same identity.' }
  $source = Get-ReleaseSource
  if ($Platform -eq 'windows') {
    $artifactName = "ImageHub-windows-x64-$identity.zip"
    $null = Invoke-ReleaseCommand $flutter @('build', 'windows', '--release') (Join-Path $stage 'build.log')
    $verification = New-VerifiedWindowsZip (Join-Path $application 'build/windows/x64/runner/Release') $stage $artifactName $versions
  } else {
    $artifactName = "ImageHub-android-arm64-$identity.apk"
    $buildToolsRoot = Assert-ImageHubOrdinaryPath (Join-Path $env:ANDROID_HOME 'build-tools') -MustExist
    $buildTools = @(Get-ChildItem -LiteralPath $buildToolsRoot -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [Version]$_.Name } -Descending | Select-Object -First 1)
    if ($buildTools.Count -ne 1) { throw 'Installed Android Build Tools are missing.' }
    $null = Assert-ImageHubOrdinaryPath $buildTools[0].FullName -MustExist
    $signing = Invoke-ImageHubAndroidSigning -JavaHome $env:JAVA_HOME -Initialize:$InitializeAndroidSigning -Action {
      param($publicIdentity)
      $null = Invoke-ReleaseCommand $flutter @('build', 'apk', '--release', '--target-platform', 'android-arm64', '--split-per-abi', '-P', 'force-version-code-ignoring-abi=true') (Join-Path $stage 'build.log')
      return $publicIdentity
    }
    $artifactPath = Join-Path $stage $artifactName
    $null = Copy-ReleaseFile (Join-Path $application 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk') $artifactPath
    $verification = Assert-AndroidRelease $artifactPath $buildTools[0].FullName $stage $versions $signing.certificateSha256
  }
  $after = Get-ReleaseSource
  if ($after.commit -cne $source.commit -or $after.statusSha256 -cne $source.statusSha256 -or $after.trackedDiffSha256 -cne $source.trackedDiffSha256 -or
      $after.sourceFilesSha256 -cne $source.sourceFilesSha256 -or
      (Get-FileHash -LiteralPath $versionsPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $versionHash) {
    throw 'Release source changed during packaging; the stage was retained and no successful release was published.'
  }
  $artifactPath = Join-Path $stage $artifactName
  $artifact = Get-Item -LiteralPath $artifactPath
  $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifest = [ordered]@{
    formatVersion = 1; product = 'ImageHub'; platform = $Platform; architecture = $(if ($Platform -eq 'windows') { 'x64' } else { 'arm64' })
    createdUtc = [DateTime]::UtcNow.ToString('o'); versions = $versions; versionsManifestSha256 = $versionHash
    source = $source; artifact = [ordered]@{ file = $artifactName; bytes = $artifact.Length; sha256 = $artifactHash }
    verification = $verification
    validationBoundary = 'Local release packaging and listed host checks only; no real service, physical-device PT, store publication, or certification claim.'
  }
  Write-ReleaseText (Join-Path $stage 'release.json') (($manifest | ConvertTo-Json -Depth 15) + "`n")
  $manifestHash = (Get-FileHash -LiteralPath (Join-Path $stage 'release.json') -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-ReleaseText (Join-Path $stage 'SHA256SUMS') ("$artifactHash  $artifactName`n$manifestHash  release.json`n")
  $null = Assert-ImageHubOrdinaryPath $stage -MustExist
  $null = Assert-ImageHubOrdinaryPath ([IO.Path]::GetDirectoryName($final))
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($final))
  $null = Assert-ImageHubOrdinaryPath ([IO.Path]::GetDirectoryName($final)) -MustExist
  if (Test-Path -LiteralPath $final) { throw 'A release with this identity appeared; the verified stage was retained without overwriting it.' }
  [IO.Directory]::Move($stage, $final)
  Write-Host "PASS verified local release: $final"
  [pscustomobject]@{ releaseDirectory = $final; artifact = Join-Path $final $artifactName; sha256 = $artifactHash; platformVersion = $identity }
} catch {
  if ($workStage) { Write-Warning "Packaging failed. Incomplete evidence was retained at $workStage; it is not a successful release." }
  throw
} finally {
  try { Set-Location -LiteralPath $location.Path }
  finally { Restore-ImageHubProcessEnvironment $previousEnvironment }
}
