param(
    [string]$ToolRoot = 'D:\Workspace\DevelopmentTools'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$taskToolRoot = [IO.Path]::GetFullPath($ToolRoot).TrimEnd('\')
if ($taskToolRoot -ne 'D:\Workspace\DevelopmentTools') {
    throw 'This approved installer only writes to D:\Workspace\DevelopmentTools.'
}
foreach ($directory in @($taskToolRoot, "$taskToolRoot\Downloads", "$taskToolRoot\Logs", "$taskToolRoot\AndroidUser", "$taskToolRoot\Avd", "$taskToolRoot\Gradle")) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Tool directories must not be reparse points.'
    }
}

function Get-VerifiedArchive([string]$Uri, [string]$Name, [string]$Sha256, [long]$ExpectedSize = 0) {
    $destination = Join-Path "$taskToolRoot\Downloads" $Name
    if (-not (Test-Path -LiteralPath $destination)) {
        $partial = "$destination.part"
        Write-Host "Downloading $Name"
        & curl.exe --silent --show-error --fail --location --retry 2 --connect-timeout 30 --max-time 3600 --output $partial $Uri
        if ($LASTEXITCODE -ne 0) { throw "Download failed for $Name" }
        if ($ExpectedSize -gt 0 -and (Get-Item -LiteralPath $partial).Length -ne $ExpectedSize) {
            throw "Download length mismatch for $Name"
        }
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256.ToLowerInvariant()) {
            throw "Download SHA256 mismatch for $Name"
        }
        Move-Item -LiteralPath $partial -Destination $destination
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256.ToLowerInvariant()) {
        throw "Cached SHA256 mismatch for $Name"
    }
    return $destination
}

$jdkContainer = "$taskToolRoot\Jdk21"
$javaCandidates = @(Get-ChildItem -LiteralPath $jdkContainer -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/java.exe') })
if ($javaCandidates.Count -eq 0) {
    $assets = @(Invoke-RestMethod -Uri 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse')
    if ($assets.Count -ne 1) { throw 'Expected one official Temurin Windows x64 JDK21 asset.' }
    $package = $assets[0].binary.package
    if ($package.link -notmatch '^https://github\.com/adoptium/temurin21-binaries/releases/download/') {
        throw 'Unexpected official JDK download host.'
    }
    $jdkArchive = Get-VerifiedArchive $package.link $package.name $package.checksum $package.size
    if (Test-Path -LiteralPath $jdkContainer) { throw 'An incomplete JDK directory is preserved; inspect it before retrying.' }
    Expand-Archive -LiteralPath $jdkArchive -DestinationPath $jdkContainer
    $javaCandidates = @(Get-ChildItem -LiteralPath $jdkContainer -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/java.exe') })
}
if ($javaCandidates.Count -ne 1) { throw 'Expected one installed JDK directory.' }
$env:JAVA_HOME = $javaCandidates[0].FullName
& "$env:JAVA_HOME\bin\java.exe" -version
if ($LASTEXITCODE -ne 0) { throw 'JDK verification failed.' }

$sdkRoot = "$taskToolRoot\AndroidSdk"
$manager = "$sdkRoot\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path -LiteralPath $manager)) {
    $sdkArchive = Get-VerifiedArchive 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' 'commandlinetools-win-15859902_latest.zip' '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
    $bootstrap = "$taskToolRoot\AndroidBootstrap"
    if (Test-Path -LiteralPath $bootstrap) { throw 'An incomplete bootstrap is preserved; inspect it before retrying.' }
    Expand-Archive -LiteralPath $sdkArchive -DestinationPath $bootstrap
    New-Item -ItemType Directory -Path "$sdkRoot\cmdline-tools" -Force | Out-Null
    $source = [IO.Path]::GetFullPath("$bootstrap\cmdline-tools")
    $target = [IO.Path]::GetFullPath("$sdkRoot\cmdline-tools\latest")
    if (-not $source.StartsWith("$taskToolRoot\", [StringComparison]::OrdinalIgnoreCase) -or
        -not $target.StartsWith("$taskToolRoot\", [StringComparison]::OrdinalIgnoreCase) -or
        (Test-Path -LiteralPath $target)) {
        throw 'Unsafe or existing Android command-line destination.'
    }
    Move-Item -LiteralPath $source -Destination $target
}
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_USER_HOME = "$taskToolRoot\AndroidUser"
$env:ANDROID_AVD_HOME = "$taskToolRoot\Avd"
$env:GRADLE_USER_HOME = "$taskToolRoot\Gradle"
$env:PATH = "$env:JAVA_HOME\bin;$sdkRoot\platform-tools;$env:PATH"

$packages = @('platform-tools', 'platforms;android-36', 'build-tools;36.0.0', 'ndk;28.2.13676358', 'cmake;3.22.1', 'emulator', 'system-images;android-36;google_apis;x86_64')
Write-Output 'Installing the approved Android build and emulator packages. See Logs/sdk-install.log.'
1..30 | ForEach-Object { 'y' } | & $manager "--sdk_root=$sdkRoot" --install @packages *> "$taskToolRoot\Logs\sdk-install.log"
if ($LASTEXITCODE -ne 0) { throw 'SDK package installation failed; the installation log and downloads are preserved.' }

$environment = [ordered]@{
    toolRoot = $taskToolRoot
    javaHome = $env:JAVA_HOME
    androidHome = $env:ANDROID_HOME
    androidUserHome = $env:ANDROID_USER_HOME
    androidAvdHome = $env:ANDROID_AVD_HOME
    gradleUserHome = $env:GRADLE_USER_HOME
    flutterHome = 'C:\Users\PAN\development\flutter'
    packages = $packages
}
$environment | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$taskToolRoot\android-environment.json" -Encoding utf8
& $manager "--sdk_root=$sdkRoot" --list_installed *> "$taskToolRoot\Logs\sdk-installed.log"
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify installed SDK packages.' }
Write-Output "Android tools installed and verified in $taskToolRoot. System PATH was not changed."
