param([string]$Serial = 'emulator-5558')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_environment.ps1')
if ($Serial -ne 'emulator-5558' -or
    (adb -s $Serial emu avd name | Select-Object -First 1) -ne 'ImageHost_API36') {
    throw 'Only this task-owned emulator may be inspected.'
}
$androidLogRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../docs/validation'))
$androidEvidence = Get-Content -LiteralPath (Join-Path $androidLogRoot 'android-file-bridge-state.json') -Raw | ConvertFrom-Json
if ($androidEvidence.phase -ne 'complete' -or
    $androidEvidence.runId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
    $androidEvidence.fixtureSha -notmatch '^[0-9a-f]{64}$' -or
    $androidEvidence.byteCount -lt 65537 -or $androidEvidence.byteCount -gt 8388608) {
    throw 'Native bridge evidence is incomplete or invalid.'
}

function Invoke-AndroidContent([string[]]$Arguments) {
    $androidProc = [Diagnostics.Process]::new()
    $androidProc.StartInfo.FileName = (Get-Command adb).Source
    $androidProc.StartInfo.UseShellExecute = $false
    $androidProc.StartInfo.RedirectStandardOutput = $true
    $androidProc.StartInfo.RedirectStandardError = $true
    foreach ($androidArg in @('-s', $Serial, 'exec-out', 'content') + $Arguments) {
        $androidProc.StartInfo.ArgumentList.Add($androidArg)
    }
    $androidBuffer = [IO.MemoryStream]::new()
    try {
        [void]$androidProc.Start()
        $androidError = $androidProc.StandardError.ReadToEndAsync()
        # exec-out preserves binary bytes. adb shell may negotiate a terminal and
        # transform line endings; PowerShell text redirection also cannot hash PNG.
        $androidChunk = [byte[]]::new(65536)
        while (($androidCount = $androidProc.StandardOutput.BaseStream.Read($androidChunk, 0, $androidChunk.Length)) -gt 0) {
            if ($androidBuffer.Length + $androidCount -gt 8388608) {
                $androidProc.Kill()
                $androidProc.WaitForExit()
                throw 'Independent test content exceeds its bound.'
            }
            $androidBuffer.Write($androidChunk, 0, $androidCount)
        }
        $androidProc.WaitForExit()
        if ($androidProc.ExitCode -ne 0 -or $androidError.GetAwaiter().GetResult().Length -ne 0) {
            throw 'Independent Android content operation did not complete.'
        }
        return ,$androidBuffer.ToArray()
    } finally {
        $androidBuffer.Dispose()
        $androidProc.Dispose()
    }
}

$androidExports = @($androidEvidence.results.exportPhotos) +
    @($androidEvidence.results.exportPhotosDuplicate) +
    @($androidEvidence.results.exportDocument) + @($androidEvidence.results.exportTree)
if ($androidExports.Count -ne 5) { throw 'Five actual saved destinations are required.' }
$androidSummary = foreach ($androidExport in $androidExports) {
    if ($androidExport.status -ne 'saved') { throw 'Unconfirmed export cannot be verified as saved.' }
    $androidUri = [uri]$androidExport.uri
    $androidUriText = $androidUri.AbsoluteUri
    if ($androidUri.Scheme -ne 'content' -or
        $androidUriText -notmatch '^content://(?:media/external_primary/images/media/[0-9]+|com\.android\.externalstorage\.documents/(?:tree/[A-Za-z0-9%._~-]+/)?document/[A-Za-z0-9%./()_~-]+)$') {
        throw 'Unexpected test-owned destination.'
    }
    # exec-out passes arguments directly. Shell quotes would become literal URI
    # bytes. Encode optional name parentheses instead of introducing shell syntax.
    $androidContentUri = $androidUriText.Replace('(', '%28').Replace(')', '%29')
    $androidMedia = $androidUri.Authority -eq 'media'
    if ($androidMedia) {
        $androidQuery = [Text.Encoding]::UTF8.GetString((Invoke-AndroidContent @('query', '--uri', $androidContentUri, '--projection', '_display_name:_size:is_pending'))).Trim()
        $androidMatch = [regex]::Match($androidQuery, '^Row:\s*0\s+_display_name=(.+),\s*_size=(\d+),\s*is_pending=(\d+)\s*$')
        if (!$androidMatch.Success -or $androidMatch.Groups[1].Value -ne $androidExport.name -or
            [long]$androidMatch.Groups[2].Value -ne $androidEvidence.byteCount -or $androidMatch.Groups[3].Value -ne '0') {
            throw 'Published name, length, or pending status differs from the native save reply.'
        }
        $androidBytes = Invoke-AndroidContent @('read', '--uri', $androidContentUri)
        $androidRoute = 'MediaStore content'
    } else {
        # The shell has no SAF grant after test-tool uninstall. Read only the
        # ordinary files in the two directories created by this owned test;
        # never grant the shell new permission, root the device, or map a cloud URI.
        if ($androidUri.AbsolutePath -notmatch '^/(?:tree/([^/]+)/)?document/([^/]+)$') {
            throw 'Invalid ordinary test document path.'
        }
        $androidEncodedTree = $Matches[1]
        $androidDocumentId = [uri]::UnescapeDataString($Matches[2])
        if ($androidDocumentId -notmatch '^primary:(Download/ImageHostBridgeFixture|Pictures/ImageHostBridgeExports)/(Bridge(?:Document|Export)(?: \([1-9][0-9]*\))?\.png)$' -or
            $Matches[2] -ne $androidExport.name) { throw 'Destination is outside the owned ordinary test folders.' }
        $androidOwnedDirectory = $Matches[1]
        if ($androidEncodedTree -and [uri]::UnescapeDataString($androidEncodedTree) -ne "primary:$androidOwnedDirectory") {
            throw 'Tree identity differs from its owned ordinary test directory.'
        }
        $androidExternalFile = '/sdcard/' + $androidDocumentId.Substring('primary:'.Length)
        $androidHostFile = Join-Path $androidLogRoot ("android-export-$([guid]::NewGuid()).png")
        if (Test-Path -LiteralPath $androidHostFile) { throw 'Independent host target already exists.' }
        adb -s $Serial pull $androidExternalFile $androidHostFile *> $null
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $androidHostFile -PathType Leaf) -or
            (Get-Item -LiteralPath $androidHostFile).Length -ne $androidEvidence.byteCount) {
            throw 'Independent ordinary exported file read did not complete.'
        }
        $androidBytes = [IO.File]::ReadAllBytes($androidHostFile)
        $androidRoute = 'Owned ordinary external file'
    }
    $androidHasher = [Security.Cryptography.SHA256]::Create()
    try { $androidSha = [Convert]::ToHexString($androidHasher.ComputeHash($androidBytes)).ToLowerInvariant() }
    finally { $androidHasher.Dispose() }
    if ($androidBytes.Length -ne $androidEvidence.byteCount -or $androidSha -ne $androidEvidence.fixtureSha) {
        throw 'Independent exported bytes differ.'
    }
    [pscustomobject]@{ uri=$androidExport.uri; name=$androidExport.name; byteCount=$androidBytes.Length; sha256=$androidSha; published=$true; route=$androidRoute }
}
$androidRows = [Text.Encoding]::UTF8.GetString((Invoke-AndroidContent @('query', '--uri', 'content://media/external_primary/images/media', '--projection', '_id:_display_name:_size:is_pending:owner_package_name')))
$androidRows | Set-Content -LiteralPath (Join-Path $androidLogRoot 'android-media-verified.log')
if ($androidRows.Contains('BridgeRejected')) { throw 'A rejected source unexpectedly inserted a media row.' }
$androidSummary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $androidLogRoot 'android-export-independent-bytes.json')
$androidSummary | Format-Table name,byteCount,sha256,published
'PASS five real native export destinations: actual names, lengths, SHA-256 and published media; no rejected photo inserted.'
