param([string]$Serial = 'emulator-5558')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_environment.ps1')
if ($Serial -ne 'emulator-5558') { throw 'Only the dedicated ImageHost emulator is allowed.' }
$androidAvd = (adb -s $Serial emu avd name) -join "`n"
if ($androidAvd -notmatch '^ImageHost_API36\r?\n') { throw 'Unexpected emulator ownership.' }
$androidRepository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$androidLogRoot = Join-Path $androidRepository 'docs/validation'
$androidFixture = Join-Path $androidLogRoot 'android-bridge-fixture.png'
$androidDeadline = [DateTime]::UtcNow.AddMinutes(12)
$androidPreviousPhase = ''
$androidPrepared = $false
$androidSteps = 0

function Read-BridgeState {
    try {
        $androidJson = (adb -s $Serial shell run-as io.imagehost.imagehost cat files/android_bridge_state.json 2>$null) -join ''
        if (!$androidJson) { return $null }
        return $androidJson | ConvertFrom-Json
    } catch { return $null }
}

function Read-Selector {
    adb -s $Serial shell uiautomator dump /data/local/tmp/ImageHostBridgeUi.xml *> $null
    if ($LASTEXITCODE -ne 0) { return $null }
    try {
        return [xml]((adb -s $Serial shell cat /data/local/tmp/ImageHostBridgeUi.xml) -join '')
    } catch { return $null }
}

function Find-Label($ui, [string]$label, [bool]$directoryOnly = $false) {
    $androidNodes = if ($directoryOnly) {
        $ui.SelectNodes('//node[@resource-id="com.google.android.documentsui:id/dir_list"]//node')
    } else { $ui.SelectNodes('//node') }
    return $androidNodes | Where-Object { $_.text -eq $label -and $_.enabled -eq 'true' } | Select-Object -Last 1
}

function Tap-Observed($node) {
    if (!$node -or $node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw 'No observed selector control.'
    }
    $androidX = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    $androidY = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    if ($androidX -lt 0 -or $androidX -ge 1080 -or $androidY -lt 0 -or $androidY -ge 2400) {
        throw 'Selector bounds outside the observed emulator display.'
    }
    adb -s $Serial shell input tap $androidX $androidY
}

while ([DateTime]::UtcNow -lt $androidDeadline) {
    $androidState = Read-BridgeState
    if (!$androidState) { Start-Sleep -Milliseconds 250; continue }
    if ($androidState.phase -ne $androidPreviousPhase) {
        Write-Output "Native phase: $($androidState.phase)"
        $androidPreviousPhase = $androidState.phase
        $androidSteps = 0
    }
    if ($androidState.phase -eq 'complete') {
        if ($androidState.runId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
            throw 'Invalid native evidence run identity.'
        }
        $androidState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $androidLogRoot 'android-file-bridge-state.json')
        adb -s $Serial shell run-as io.imagehost.imagehost touch "files/android_bridge_ack-$($androidState.runId)"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot acknowledge preserved native evidence.' }
        Write-Output 'Native selector driver completed; verify the Flutter test result separately.'
        exit 0
    }
    if (!$androidPrepared) {
        if ($androidState.fixtureSha -notmatch '^[0-9a-f]{64}$' -or
            $androidState.byteCount -lt 65537 -or $androidState.byteCount -gt 8388608 -or
            !(Test-Path -LiteralPath $androidFixture -PathType Leaf) -or
            (Get-Item -LiteralPath $androidFixture).Length -ne $androidState.byteCount -or
            (Get-FileHash -LiteralPath $androidFixture -Algorithm SHA256).Hash.ToLowerInvariant() -ne $androidState.fixtureSha) {
            throw 'The test-owned host fixture does not match the native evidence.'
        }
        adb -s $Serial shell mkdir -p /sdcard/Download/ImageHostBridgeFixture /sdcard/Pictures/ImageHostBridgeExports
        adb -s $Serial push $androidFixture /sdcard/Download/ImageHostBridgeFixture/BridgeFixture.png *> $null
        adb -s $Serial shell content query --uri content://media/external_primary/images/media --projection _id:_display_name:_size:is_pending:owner_package_name |
            Set-Content -LiteralPath (Join-Path $androidLogRoot 'android-media-before-bridge.log')
        $androidPrepared = $true
    }
    if ($androidState.phase -in @('exportPhotos', 'sourceFdRegression')) {
        Start-Sleep -Milliseconds 250
        continue
    }
    if ($androidState.phase -notin @('importFile', 'importPhoto', 'cancelledImport', 'exportDocument', 'exportTree')) {
        throw 'Unknown native test phase.'
    }
    $androidUi = Read-Selector
    if (!$androidUi) { Start-Sleep -Milliseconds 250; continue }
    $androidCheck = Read-BridgeState
    if (!$androidCheck -or $androidCheck.phase -ne $androidState.phase) { continue }
    $androidPackages = $androidUi.SelectNodes('//node') | ForEach-Object { $_.package } | Select-Object -Unique
    $androidPermission = $androidState.phase -eq 'exportTree' -and
        ($androidUi.SelectNodes('//node') | Where-Object {
            $_.text -in @('Allow imagehost to access files in ImageHostBridgeExports?',
                'Allow imagehost to access files in ImageHostBridgeFixture?')
        })
    if ('com.google.android.documentsui' -notin $androidPackages -and !$androidPermission) {
        Start-Sleep -Milliseconds 250
        continue
    }
    $androidSteps++
    if ($androidSteps -gt 24) { throw 'Selector made no bounded progress.' }
    switch ($androidState.phase) {
        { $_ -in @('importFile', 'importPhoto') } {
            # Repeated verification leaves confirmed user files in this owned
            # directory. A grid can expose only a fixture thumbnail/preview while
            # its selectable label is below the system navigation area.
            $androidListView = $androidUi.SelectNodes('//node') |
                Where-Object { $_.'content-desc' -eq 'List view' -and $_.enabled -eq 'true' } |
                Select-Object -First 1
            if ($androidListView) { Tap-Observed $androidListView; continue }
            $androidFile = Find-Label $androidUi 'BridgeFixture.png' $true
            if (!$androidFile) {
                $androidFile = $androidUi.SelectNodes('//node') |
                    Where-Object { $_.'content-desc' -like 'BridgeFixture.png,*' -and $_.enabled -eq 'true' } |
                    Select-Object -First 1
            }
            $androidFolder = Find-Label $androidUi 'ImageHostBridgeFixture' $true
            $androidDownload = Find-Label $androidUi 'Download' $true
            $androidDevice = Find-Label $androidUi 'sdk_gphone64_x86_64'
            if ($androidFile) { Tap-Observed $androidFile }
            elseif ($androidFolder) { Tap-Observed $androidFolder }
            elseif ($androidDownload) { Tap-Observed $androidDownload }
            elseif ($androidDevice -and !$androidDevice.bounds.StartsWith('[0,262]')) { Tap-Observed $androidDevice }
            else {
                $androidRoots = $androidUi.SelectNodes('//node') |
                    Where-Object { $_.'content-desc' -eq 'Show roots' } | Select-Object -First 1
                if ($androidRoots) { Tap-Observed $androidRoots }
                else { throw 'Test source is unavailable in the observed selector.' }
            }
        }
        'cancelledImport' { adb -s $Serial shell input keyevent 4 }
        'exportDocument' {
            $androidSave = Find-Label $androidUi 'SAVE'
            if (!$androidSave) { throw 'No observed create-document save control.' }
            Tap-Observed $androidSave
        }
        'exportTree' {
            $androidAllow = Find-Label $androidUi 'ALLOW'
            $androidFolder = Find-Label $androidUi 'ImageHostBridgeExports' $true
            $androidPictures = Find-Label $androidUi 'Pictures' $true
            $androidTitle = $androidUi.SelectNodes('//node') | Where-Object {
                $_.text -in @('ImageHostBridgeExports', 'ImageHostBridgeFixture')
            } | Select-Object -First 1
            $androidUse = Find-Label $androidUi 'USE THIS FOLDER'
            $androidDevice = Find-Label $androidUi 'sdk_gphone64_x86_64'
            if ($androidAllow) { Tap-Observed $androidAllow }
            elseif ($androidFolder) { Tap-Observed $androidFolder }
            elseif ($androidPictures) { Tap-Observed $androidPictures }
            elseif ($androidTitle -and $androidUse) { Tap-Observed $androidUse }
            elseif ($androidDevice) { Tap-Observed $androidDevice }
            else {
                $androidRoots = $androidUi.SelectNodes('//node') |
                    Where-Object { $_.'content-desc' -eq 'Show roots' } | Select-Object -First 1
                if ($androidRoots) { Tap-Observed $androidRoots }
                else { throw 'The confirmed test directory is unavailable in the observed selector.' }
            }
        }
    }
}
throw 'Native selector driver timed out; no test success is inferred.'
