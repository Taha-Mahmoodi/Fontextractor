[CmdletBinding()]
param(
    [string]$DownloadsRoot = (Join-Path $env:USERPROFILE "Downloads"),
    [string]$BaseFolderName = "Google Fonts 2026",
    [string]$ApiKey = $env:GOOGLE_FONTS_API_KEY,
    [ValidateSet("zip", "git", "api")]
    [string[]]$SourceOrder = @("zip", "git", "api"),
    [string]$DateFormat = "yyyy-MM-dd",
    [string]$ZipUrl = "https://github.com/google/fonts/archive/refs/heads/main.zip",
    [string]$GitRepoUrl = "https://github.com/google/fonts.git",
    [string]$ApiMetadataUrl = "https://www.googleapis.com/webfonts/v1/webfonts",
    [string]$ControlFilePath = "",
    [switch]$EmitGuiEvents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:GuiEventPrefix = "__FX_GUI_EVENT__"
$script:LastOverallPercent = 0.0
$script:SourceAttemptIndex = 0
$script:SourceAttemptCount = 1

function Enable-NetworkTls {
    try {
        $protocol = [System.Net.SecurityProtocolType]::Tls12
        if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains "Tls13") {
            $protocol = $protocol -bor [System.Net.SecurityProtocolType]::Tls13
        }
        [System.Net.ServicePointManager]::SecurityProtocol = $protocol
    }
    catch {
        # Best effort only.
    }
}

function Convert-ToClampedPercent {
    param([Parameter(Mandatory = $true)][double]$Value)

    if ($Value -lt 0) {
        return 0.0
    }

    if ($Value -gt 100) {
        return 100.0
    }

    return [Math]::Round($Value, 2)
}

function Write-GuiEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $false)][hashtable]$Data = @{}
    )

    if (-not $EmitGuiEvents) {
        return
    }

    $payload = @{
        timestamp = (Get-Date).ToString("o")
        event     = $Event
    }

    foreach ($entry in $Data.GetEnumerator()) {
        $payload[$entry.Key] = $entry.Value
    }

    $json = $payload | ConvertTo-Json -Compress -Depth 8
    [Console]::Out.WriteLine($script:GuiEventPrefix + $json)
}

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][ValidateSet("debug", "info", "warning", "error")][string]$Level = "info",
        [Parameter(Mandatory = $false)][string]$Source = "script"
    )

    Write-GuiEvent -Event "status" -Data @{
        level   = $Level
        source  = $Source
        message = $Message
    }
}

function Write-TaskProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][double]$Percent,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $clamped = Convert-ToClampedPercent -Value $Percent
    Write-GuiEvent -Event "task_progress" -Data @{
        source  = $Source
        percent = $clamped
        message = $Message
    }
}

function Write-OverallProgress {
    param(
        [Parameter(Mandatory = $true)][double]$Percent,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Source = "script",
        [Parameter(Mandatory = $false)][switch]$AllowDecrease
    )

    $clamped = Convert-ToClampedPercent -Value $Percent
    if (-not $AllowDecrease -and $clamped -lt $script:LastOverallPercent) {
        $clamped = $script:LastOverallPercent
    }

    $script:LastOverallPercent = $clamped
    Write-GuiEvent -Event "overall_progress" -Data @{
        source  = $Source
        percent = $clamped
        message = $Message
    }
}

function Update-SourceOverallProgress {
    param(
        [Parameter(Mandatory = $true)][double]$TaskPercent,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $slotSize = 100.0 / [Math]::Max(1, [double]$script:SourceAttemptCount)
    $slotStart = $slotSize * [double]$script:SourceAttemptIndex
    $slotRelative = $slotSize * ((Convert-ToClampedPercent -Value $TaskPercent) / 100.0)
    $sourcePhasePercent = $slotStart + $slotRelative
    $overallPercent = 10.0 + (75.0 * ($sourcePhasePercent / 100.0))
    Write-OverallProgress -Percent $overallPercent -Message $Message -Source $Source
}

function Set-FinalPhaseProgress {
    param(
        [Parameter(Mandatory = $true)][double]$FinalPhasePercent,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Source = "script"
    )

    $finalClamped = Convert-ToClampedPercent -Value $FinalPhasePercent
    $overallPercent = 85.0 + (15.0 * ($finalClamped / 100.0))
    Write-OverallProgress -Percent $overallPercent -Message $Message -Source $Source
}

function Test-StopRequested {
    if ([string]::IsNullOrWhiteSpace($ControlFilePath)) {
        return $false
    }

    return (Test-Path -LiteralPath $ControlFilePath)
}

function Throw-IfStopRequested {
    if (Test-StopRequested) {
        throw [System.OperationCanceledException]::new("Stop requested by GUI.")
    }
}

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("[INFO] {0}" -f $Message)
    Write-Status -Message $Message -Level "info"
}

function Add-Failure {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.IList]$Failures
    )

    $Failures.Add(
        [pscustomobject]@{
            source  = $Source
            message = $Message
        }
    ) | Out-Null
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Convert-ToSafePathSegment {
    param([Parameter(Mandatory = $true)][string]$Name)

    $safe = $Name -replace '[<>:"/\\|?*]', "_"
    $safe = $safe.Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "Unknown"
    }

    return $safe
}

function Get-UniqueDatedOutputFolder {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$Format
    )

    $baseName = Get-Date -Format $Format
    $candidate = Join-Path $RootPath $baseName
    if (-not (Test-Path -LiteralPath $candidate)) {
        New-Item -Path $candidate -ItemType Directory -Force | Out-Null
        return $candidate
    }

    $suffix = 2
    while ($true) {
        $candidateWithSuffix = Join-Path $RootPath ("{0}-{1}" -f $baseName, $suffix)
        if (-not (Test-Path -LiteralPath $candidateWithSuffix)) {
            New-Item -Path $candidateWithSuffix -ItemType Directory -Force | Out-Null
            return $candidateWithSuffix
        }

        $suffix++
    }
}

function Test-GitHubConnectivity {
    Throw-IfStopRequested
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $client.BeginConnect("github.com", 443, $null, $null)
        $connected = $asyncResult.AsyncWaitHandle.WaitOne(5000, $false)
        if (-not $connected) {
            $client.Close()
            return $false
        }
        $client.EndConnect($asyncResult)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Copy-TtfFilesPreservingStructure {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $false)][string]$ProgressSource = "source",
        [Parameter(Mandatory = $false)][double]$TaskStartPercent = 0,
        [Parameter(Mandatory = $false)][double]$TaskEndPercent = 100,
        [Parameter(Mandatory = $false)][switch]$UpdateOverallProgress
    )

    Throw-IfStopRequested
    $resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
    $ttfFiles = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter "*.ttf")
    if ($ttfFiles.Count -eq 0) {
        return 0
    }

    $copied = 0
    foreach ($file in $ttfFiles) {
        Throw-IfStopRequested
        $relativePath = $file.FullName.Substring($resolvedSourceRoot.Length).TrimStart("\")
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $targetPath = Join-Path $DestinationRoot $relativePath
        $targetDir = Split-Path -Path $targetPath -Parent
        Ensure-Directory -Path $targetDir
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
        $copied++

        $progressRatio = $copied / [double]$ttfFiles.Count
        $taskPercent = $TaskStartPercent + (($TaskEndPercent - $TaskStartPercent) * $progressRatio)
        $progressMessage = "Copied $copied / $($ttfFiles.Count) TTF files."
        Write-TaskProgress -Source $ProgressSource -Percent $taskPercent -Message $progressMessage
        if ($UpdateOverallProgress) {
            Update-SourceOverallProgress -TaskPercent $taskPercent -Source $ProgressSource -Message $progressMessage
        }
    }

    return $copied
}

function Download-FileWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [Parameter(Mandatory = $true)][string]$SourceName,
        [Parameter(Mandatory = $true)][string]$ItemName,
        [Parameter(Mandatory = $false)][int]$TimeoutSeconds = 120
    )

    Throw-IfStopRequested

    $headContentLength = [int64]-1
    try {
        $headRequest = [System.Net.HttpWebRequest]::Create($Uri)
        $headRequest.Method = "HEAD"
        $headRequest.Timeout = $TimeoutSeconds * 1000
        $headRequest.ReadWriteTimeout = $TimeoutSeconds * 1000
        $headResponse = $headRequest.GetResponse()
        try {
            $headContentLength = [int64]$headResponse.ContentLength
        }
        finally {
            if ($null -ne $headResponse) {
                $headResponse.Dispose()
            }
        }
    }
    catch {
        $headContentLength = [int64]-1
    }

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = "GET"
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = $TimeoutSeconds * 1000
    $response = $request.GetResponse()

    $receivedBytes = [int64]0
    $totalBytes = [int64]-1
    try {
        $totalBytes = [int64]$response.ContentLength
        if ($totalBytes -le 0 -and $headContentLength -gt 0) {
            $totalBytes = $headContentLength
        }

        $buffer = New-Object byte[] 65536
        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

        try {
            $initialIndeterminate = $totalBytes -le 0
            Write-GuiEvent -Event "download_progress" -Data @{
                source     = $SourceName
                item       = $ItemName
                bytesRead  = 0
                totalBytes = if ($totalBytes -gt 0) { $totalBytes } else { 0 }
                percent    = if ($initialIndeterminate) { -1 } else { 0 }
                indeterminate = $initialIndeterminate
            }

            while ($true) {
                Throw-IfStopRequested
                $bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -le 0) {
                    break
                }

                $outputStream.Write($buffer, 0, $bytesRead)
                $receivedBytes += $bytesRead

                if ($totalBytes -gt 0) {
                    $downloadPercent = Convert-ToClampedPercent -Value ((100.0 * $receivedBytes) / $totalBytes)
                    $isIndeterminate = $false
                }
                else {
                    # Unknown size: keep an indeterminate bar and only show byte count.
                    $downloadPercent = -1
                    $isIndeterminate = $true
                }

                Write-GuiEvent -Event "download_progress" -Data @{
                    source     = $SourceName
                    item       = $ItemName
                    bytesRead  = $receivedBytes
                    totalBytes = if ($totalBytes -gt 0) { $totalBytes } else { 0 }
                    percent    = $downloadPercent
                    indeterminate = $isIndeterminate
                }
            }
        }
        finally {
            if ($null -ne $inputStream) {
                $inputStream.Dispose()
            }
            if ($null -ne $outputStream) {
                $outputStream.Dispose()
            }
        }
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
    }

    $finalTotalBytes = if ($totalBytes -gt 0) { $totalBytes } elseif ($receivedBytes -gt 0) { $receivedBytes } else { 0 }
    Write-GuiEvent -Event "download_progress" -Data @{
        source     = $SourceName
        item       = $ItemName
        bytesRead  = if ($receivedBytes -gt 0) { $receivedBytes } else { 0 }
        totalBytes = $finalTotalBytes
        percent    = 100
        indeterminate = $false
    }
}

function Expand-ZipArchiveWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $false)][string]$SourceName = "zip",
        [Parameter(Mandatory = $false)][double]$TaskStartPercent = 35,
        [Parameter(Mandatory = $false)][double]$TaskEndPercent = 55
    )

    Throw-IfStopRequested
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $fileEntries = @(
            $archive.Entries | Where-Object {
                (-not [string]::IsNullOrWhiteSpace($_.Name)) -and
                $_.Name.EndsWith(".ttf", [System.StringComparison]::OrdinalIgnoreCase)
            }
        )
        $entryTotal = [Math]::Max(1, $fileEntries.Count)
        $processed = 0
        $skipped = 0

        Write-GuiEvent -Event "extract_progress" -Data @{
            source           = $SourceName
            item             = "Preparing ZIP extraction"
            entriesProcessed = 0
            totalEntries     = $fileEntries.Count
            percent          = 0
        }

        foreach ($entry in $fileEntries) {
            Throw-IfStopRequested
            $entryPath = ($entry.FullName -replace "\\", "/").TrimStart("/")
            $segments = @($entryPath.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries))
            if ($segments.Count -lt 2) {
                $skipped++
                continue
            }

            $relativePath = [System.IO.Path]::Combine($segments[1..($segments.Count - 1)])
            if ([string]::IsNullOrWhiteSpace($relativePath) -or $relativePath.Contains("..")) {
                $skipped++
                continue
            }

            $targetPath = Join-Path $DestinationPath $relativePath
            $targetPath = [System.IO.Path]::GetFullPath($targetPath)
            $targetDir = Split-Path -Path $targetPath -Parent
            Ensure-Directory -Path $targetDir

            try {
                $inputStream = $entry.Open()
                $outputStream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try {
                    $inputStream.CopyTo($outputStream)
                }
                finally {
                    if ($null -ne $inputStream) { $inputStream.Dispose() }
                    if ($null -ne $outputStream) { $outputStream.Dispose() }
                }

                $processed++
            }
            catch {
                $skipped++
                Write-Status -Message ("Skipping ZIP entry '{0}': {1}" -f $entry.FullName, $_.Exception.Message) -Level "warning" -Source $SourceName
                continue
            }

            $extractPercent = Convert-ToClampedPercent -Value ((100.0 * $processed) / [double]$entryTotal)
            $taskPercent = $TaskStartPercent + (($TaskEndPercent - $TaskStartPercent) * ($extractPercent / 100.0))
            $entryLabel = $relativePath

            Write-GuiEvent -Event "extract_progress" -Data @{
                source           = $SourceName
                item             = $entryLabel
                entriesProcessed = $processed
                totalEntries     = $fileEntries.Count
                percent          = $extractPercent
            }
            $extractMessage = "Extracting ZIP: $processed / $($fileEntries.Count) files"
            Write-TaskProgress -Source $SourceName -Percent $taskPercent -Message $extractMessage
            Update-SourceOverallProgress -TaskPercent $taskPercent -Source $SourceName -Message $extractMessage
        }

        Write-GuiEvent -Event "extract_progress" -Data @{
            source           = $SourceName
            item             = "ZIP extraction complete"
            entriesProcessed = $processed
            totalEntries     = $fileEntries.Count
            percent          = 100
        }

        if ($processed -le 0) {
            throw "ZIP extraction produced zero TTF files."
        }

        if ($skipped -gt 0) {
            Write-Status -Message ("ZIP extraction completed with $skipped skipped entries.") -Level "warning" -Source $SourceName
        }

        return $processed
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Invoke-ZipSource {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string]$ArchiveUrl
    )

    $sourceName = "zip"
    $zipPath = Join-Path $TempRoot "google-fonts-main.zip"
    $extractPath = Join-Path $TempRoot "zip-extract"
    Ensure-Directory -Path $extractPath

    Write-TaskProgress -Source $sourceName -Percent 0 -Message "Preparing ZIP download."
    Update-SourceOverallProgress -TaskPercent 0 -Source $sourceName -Message "Preparing ZIP download."
    Throw-IfStopRequested

    Write-Info -Message "Downloading ZIP snapshot from $ArchiveUrl"
    Download-FileWithProgress -Uri $ArchiveUrl -OutFile $zipPath -SourceName $sourceName -ItemName "ZIP snapshot (google/fonts main.zip)" -TimeoutSeconds 240
    Write-TaskProgress -Source $sourceName -Percent 35 -Message "ZIP download complete."
    Update-SourceOverallProgress -TaskPercent 35 -Source $sourceName -Message "ZIP download complete."
    Throw-IfStopRequested

    Write-Info -Message "Extracting ZIP snapshot"
    $extracted = Expand-ZipArchiveWithProgress -ZipPath $zipPath -DestinationPath $extractPath -SourceName $sourceName -TaskStartPercent 35 -TaskEndPercent 85
    Write-TaskProgress -Source $sourceName -Percent 90 -Message "Copying extracted TTF files."
    Update-SourceOverallProgress -TaskPercent 90 -Source $sourceName -Message "Copying extracted TTF files."
    Throw-IfStopRequested

    $copied = Copy-TtfFilesPreservingStructure -SourceRoot $extractPath -DestinationRoot $OutputFolder -ProgressSource $sourceName -TaskStartPercent 90 -TaskEndPercent 100 -UpdateOverallProgress
    if ($copied -le 0) {
        throw "ZIP source returned zero TTF files."
    }

    Write-TaskProgress -Source $sourceName -Percent 100 -Message ("ZIP source finished with $copied TTF files.")
    Update-SourceOverallProgress -TaskPercent 100 -Source $sourceName -Message "ZIP source finished."
    return $copied
}

function Invoke-GitSource {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string]$RepositoryUrl
    )

    $sourceName = "git"
    Write-TaskProgress -Source $sourceName -Percent 0 -Message "Preparing git clone."
    Update-SourceOverallProgress -TaskPercent 0 -Source $sourceName -Message "Preparing git clone."
    Throw-IfStopRequested

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        throw "git was not found in PATH. Install git or remove 'git' from -SourceOrder."
    }

    $clonePath = Join-Path $TempRoot "google-fonts-git"
    Write-Info -Message "Cloning repository from $RepositoryUrl"
    & git clone --depth 1 $RepositoryUrl $clonePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw ("git clone failed with exit code {0}." -f $LASTEXITCODE)
    }

    Write-TaskProgress -Source $sourceName -Percent 45 -Message "Git clone complete."
    Update-SourceOverallProgress -TaskPercent 45 -Source $sourceName -Message "Git clone complete."
    Throw-IfStopRequested

    $copied = Copy-TtfFilesPreservingStructure -SourceRoot $clonePath -DestinationRoot $OutputFolder -ProgressSource $sourceName -TaskStartPercent 45 -TaskEndPercent 100 -UpdateOverallProgress
    if ($copied -le 0) {
        throw "Git source returned zero TTF files."
    }

    Write-TaskProgress -Source $sourceName -Percent 100 -Message "Git source finished."
    Update-SourceOverallProgress -TaskPercent 100 -Source $sourceName -Message "Git source finished."
    return $copied
}

function Invoke-ApiSource {
    param(
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string]$MetadataBaseUrl,
        [Parameter(Mandatory = $false)][string]$Key
    )

    $sourceName = "api"
    Write-TaskProgress -Source $sourceName -Percent 0 -Message "Preparing API download."
    Update-SourceOverallProgress -TaskPercent 0 -Source $sourceName -Message "Preparing API download."
    Throw-IfStopRequested

    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw "API source requested but no API key provided. Use -ApiKey or set GOOGLE_FONTS_API_KEY."
    }

    $metadataUri = "{0}?key={1}" -f $MetadataBaseUrl, [Uri]::EscapeDataString($Key)
    Write-Info -Message "Requesting Google Fonts metadata from Developer API"
    $response = Invoke-RestMethod -Uri $metadataUri -Method Get -TimeoutSec 120
    if (-not $response.items) {
        throw "Developer API response did not contain font families."
    }

    Write-TaskProgress -Source $sourceName -Percent 20 -Message "Metadata loaded."
    Update-SourceOverallProgress -TaskPercent 20 -Source $sourceName -Message "Metadata loaded."
    Throw-IfStopRequested

    $downloadQueue = New-Object "System.Collections.Generic.List[object]"
    foreach ($family in $response.items) {
        if (-not $family.files) {
            continue
        }

        $familyName = Convert-ToSafePathSegment -Name ([string]$family.family)
        foreach ($variant in $family.files.PSObject.Properties) {
            $variantName = Convert-ToSafePathSegment -Name ([string]$variant.Name)
            $fontUrl = [string]$variant.Value
            if ([string]::IsNullOrWhiteSpace($fontUrl)) {
                continue
            }

            if ($fontUrl.StartsWith("http://")) {
                $fontUrl = "https://{0}" -f $fontUrl.Substring(7)
            }

            if ($fontUrl -notmatch "\.ttf($|\?)") {
                continue
            }

            $downloadQueue.Add(
                [pscustomobject]@{
                    familyName  = $familyName
                    variantName = $variantName
                    fontUrl     = $fontUrl
                }
            ) | Out-Null
        }
    }

    if ($downloadQueue.Count -eq 0) {
        throw "API source returned zero downloadable TTF files."
    }

    $downloaded = 0
    foreach ($entry in $downloadQueue) {
        Throw-IfStopRequested
        $familyFolder = Join-Path $OutputFolder $entry.familyName
        Ensure-Directory -Path $familyFolder

        $targetPath = Join-Path $familyFolder ("{0}.ttf" -f $entry.variantName)
        $suffix = 2
        while (Test-Path -LiteralPath $targetPath) {
            $targetPath = Join-Path $familyFolder ("{0}-{1}.ttf" -f $entry.variantName, $suffix)
            $suffix++
        }

        $fontItemName = "{0} / {1}" -f $entry.familyName, $entry.variantName
        Download-FileWithProgress -Uri $entry.fontUrl -OutFile $targetPath -SourceName $sourceName -ItemName $fontItemName -TimeoutSeconds 120
        $downloaded++

        $ratio = $downloaded / [double]$downloadQueue.Count
        $taskPercent = 20 + (80 * $ratio)
        $message = "Downloaded $downloaded / $($downloadQueue.Count) TTF files from API."
        Write-TaskProgress -Source $sourceName -Percent $taskPercent -Message $message
        Update-SourceOverallProgress -TaskPercent $taskPercent -Source $sourceName -Message $message
    }

    if ($downloaded -le 0) {
        throw "API source returned zero downloadable TTF files."
    }

    Write-TaskProgress -Source $sourceName -Percent 100 -Message "API source finished."
    Update-SourceOverallProgress -TaskPercent 100 -Source $sourceName -Message "API source finished."
    return $downloaded
}

function Write-InstallerHelper {
    param([Parameter(Mandatory = $true)][string]$OutputFolder)

    Throw-IfStopRequested
    $helperPath = Join-Path $OutputFolder "Install-All-Fonts.ps1"
$helperContent = @'
[CmdletBinding()]
param(
    [string]$FontsRoot = $PSScriptRoot,
    [switch]$EmitGuiEvents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$GuiEventPrefix = "__FX_GUI_EVENT__"

function Write-GuiInstallEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $false)][hashtable]$Data = @{}
    )

    if (-not $EmitGuiEvents) {
        return
    }

    $payload = @{
        timestamp = (Get-Date).ToString("o")
        event     = $Event
    }

    foreach ($entry in $Data.GetEnumerator()) {
        $payload[$entry.Key] = $entry.Value
    }

    $json = $payload | ConvertTo-Json -Compress -Depth 6
    [Console]::Out.WriteLine($GuiEventPrefix + $json)
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-ResolvedLocalAppData {
    $path = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($path) -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $path = Join-Path $env:USERPROFILE "AppData\Local"
    }
    return $path
}

if ([string]::IsNullOrWhiteSpace($FontsRoot)) {
    $FontsRoot = $PSScriptRoot
}

if (-not (Test-Path -LiteralPath $FontsRoot)) {
    $message = "Fonts root not found: $FontsRoot"
    Write-GuiInstallEvent -Event "install_failed" -Data @{ message = $message }
    Write-Error $message
    exit 1
}

$fontFiles = @(Get-ChildItem -LiteralPath $FontsRoot -Recurse -File -Filter "*.ttf" | Sort-Object FullName)
if (-not $fontFiles) {
    $message = "No .ttf files found under $FontsRoot"
    Write-GuiInstallEvent -Event "install_failed" -Data @{ message = $message }
    Write-Error $message
    exit 1
}

$localAppData = Get-ResolvedLocalAppData
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $message = "Could not resolve Local AppData folder for current user."
    Write-GuiInstallEvent -Event "install_failed" -Data @{ message = $message }
    Write-Error $message
    exit 1
}

$windowsFontsDir = Join-Path $localAppData "Microsoft\Windows\Fonts"
$registryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
Ensure-Directory -Path $windowsFontsDir
if (-not (Test-Path -LiteralPath $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

if (-not ("Win32.FontApi" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FontApi {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string lpszFilename);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        IntPtr lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult
    );
}
"@ -Namespace Win32
}

$succeeded = 0
$failed = 0
$total = $fontFiles.Count
$processed = 0

Write-GuiInstallEvent -Event "install_progress" -Data @{
    percent = 0
    current = 0
    total   = $total
    font    = ""
}

foreach ($font in $fontFiles) {
    $processed++
    $fontName = $font.Name
    try {
        $targetFileName = $font.Name
        $targetPath = Join-Path $windowsFontsDir $targetFileName
        if (-not (Test-Path -LiteralPath $targetPath)) {
            Copy-Item -LiteralPath $font.FullName -Destination $targetPath -Force
        }

        $registryBase = "{0} (TrueType)" -f $font.BaseName
        $registryName = $registryBase
        $counter = 2
        while ($true) {
            $existing = Get-ItemProperty -Path $registryPath -Name $registryName -ErrorAction SilentlyContinue
            if (-not $existing) {
                break
            }

            $existingValue = $existing.$registryName
            if ($existingValue -eq $targetFileName) {
                break
            }

            $registryName = "{0} ({1})" -f $registryBase, $counter
            $counter++
        }

        New-ItemProperty -Path $registryPath -Name $registryName -Value $targetFileName -PropertyType String -Force | Out-Null
        [void][Win32.FontApi]::AddFontResource($targetPath)
        $succeeded++
    }
    catch {
        $failed++
        Write-Warning ("Failed to install {0}: {1}" -f $fontName, $_.Exception.Message)
    }

    $percent = [Math]::Round((100.0 * $processed) / [double]$total, 2)
    Write-GuiInstallEvent -Event "install_progress" -Data @{
        percent = $percent
        current = $processed
        total   = $total
        font    = $fontName
    }
}

$broadcastResult = [UIntPtr]::Zero
[void][Win32.FontApi]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$broadcastResult)

if ($failed -gt 0) {
    $message = "Font installation completed with errors. Installed $succeeded of $total fonts."
    Write-GuiInstallEvent -Event "install_failed" -Data @{
        message   = $message
        installed = $succeeded
        total     = $total
        failed    = $failed
    }
    Write-Error $message
    exit 1
}

$message = "Font installation completed."
Write-GuiInstallEvent -Event "install_completed" -Data @{
    message   = $message
    installed = $succeeded
    total     = $total
}
Write-Host ("Font installation completed. Total={0}; Installed={1}; Failed={2}" -f $total, $succeeded, $failed)
'@

    Set-Content -LiteralPath $helperPath -Value $helperContent -Encoding UTF8
    return $helperPath
}

function Write-SummaryFile {
    param(
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string[]]$AttemptOrder,
        [Parameter(Mandatory = $false)][string]$SourceUsed,
        [Parameter(Mandatory = $true)][int]$FontCount,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Failures,
        [Parameter(Mandatory = $true)][datetime]$StartTime
    )

    $summaryPath = Join-Path $OutputFolder "download-summary.json"
    $summary = [pscustomobject]@{
        generatedAt        = (Get-Date).ToString("o")
        outputFolder       = $OutputFolder
        sourceAttemptOrder = $AttemptOrder
        sourceUsed         = $SourceUsed
        fontCount          = $FontCount
        durationSeconds    = [Math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
        failures           = $Failures
    }

    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    return $summaryPath
}

$scriptStart = Get-Date
$failures = New-Object "System.Collections.Generic.List[object]"
$usedSource = $null
$fontCount = 0
$outputFolder = $null
$installerHelperPath = $null
$summaryPath = $null
$tempRoot = $null

$normalizedSourceOrder = New-Object "System.Collections.Generic.List[string]"
$seenSources = @{}
foreach ($source in $SourceOrder) {
    $normalized = $source.ToLowerInvariant()
    if (-not $seenSources.ContainsKey($normalized)) {
        $seenSources[$normalized] = $true
        $normalizedSourceOrder.Add($normalized) | Out-Null
    }
}

if ($normalizedSourceOrder.Count -eq 0) {
    $normalizedSourceOrder.Add("zip") | Out-Null
    $normalizedSourceOrder.Add("git") | Out-Null
    $normalizedSourceOrder.Add("api") | Out-Null
}

$script:SourceAttemptCount = [Math]::Max(1, $normalizedSourceOrder.Count)
Write-TaskProgress -Source "script" -Percent 0 -Message "Preparing run."
Write-OverallProgress -Percent 0 -Message "Starting." -Source "script" -AllowDecrease
Write-Status -Message "Worker initialized." -Level "info" -Source "script"
Enable-NetworkTls

try {
    Throw-IfStopRequested
    Write-Info -Message "Checking connectivity..."
    Write-OverallProgress -Percent 2 -Message "Checking connectivity." -Source "script"
    $githubReachable = Test-GitHubConnectivity
    if ($githubReachable) {
        Write-Info -Message "GitHub connectivity check passed."
    }
    else {
        $warnMessage = "GitHub connectivity check failed. ZIP or git sources may fail; API fallback may still work."
        Write-Warning $warnMessage
        Write-Status -Message $warnMessage -Level "warning" -Source "script"
    }

    Throw-IfStopRequested
    Ensure-Directory -Path $DownloadsRoot
    $baseOutputRoot = Join-Path $DownloadsRoot $BaseFolderName
    Ensure-Directory -Path $baseOutputRoot
    Write-OverallProgress -Percent 7 -Message "Output root prepared." -Source "script"

    $outputFolder = Get-UniqueDatedOutputFolder -RootPath $baseOutputRoot -Format $DateFormat
    Write-Info -Message ("Output folder: {0}" -f $outputFolder)

    Throw-IfStopRequested
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("google-fonts-" + [Guid]::NewGuid().ToString("N"))
    Ensure-Directory -Path $tempRoot
    Write-OverallProgress -Percent 10 -Message "Initialization complete." -Source "script"

    for ($i = 0; $i -lt $normalizedSourceOrder.Count; $i++) {
        Throw-IfStopRequested
        $source = $normalizedSourceOrder[$i]
        $script:SourceAttemptIndex = $i
        Write-Status -Message ("Trying source '{0}'." -f $source) -Level "info" -Source $source
        try {
            $downloadedCount = 0
            switch ($source) {
                "zip" {
                    $downloadedCount = Invoke-ZipSource -TempRoot $tempRoot -OutputFolder $outputFolder -ArchiveUrl $ZipUrl
                    break
                }
                "git" {
                    $downloadedCount = Invoke-GitSource -TempRoot $tempRoot -OutputFolder $outputFolder -RepositoryUrl $GitRepoUrl
                    break
                }
                "api" {
                    $downloadedCount = Invoke-ApiSource -OutputFolder $outputFolder -MetadataBaseUrl $ApiMetadataUrl -Key $ApiKey
                    break
                }
                default {
                    throw ("Unsupported source: {0}" -f $source)
                }
            }

            if ($downloadedCount -gt 0) {
                $usedSource = $source
                $fontCount = $downloadedCount
                Write-Info -Message ("Source '{0}' succeeded with {1} TTF files." -f $source, $downloadedCount)
                Write-OverallProgress -Percent 85 -Message "Source phase complete." -Source $source
                break
            }

            throw ("Source '{0}' completed but returned zero TTF files." -f $source)
        }
        catch {
            $message = $_.Exception.Message
            Add-Failure -Source $source -Message $message -Failures $failures
            Write-Warning ("Source '{0}' failed: {1}" -f $source, $message)
            Write-Status -Message ("Source '{0}' failed: {1}" -f $source, $message) -Level "warning" -Source $source
            Write-TaskProgress -Source $source -Percent 100 -Message "Source failed. Moving to next source."
            Update-SourceOverallProgress -TaskPercent 100 -Source $source -Message "Source failed. Moving to next source."
        }
    }

    if (-not $usedSource) {
        throw "All download sources failed. See download-summary.json for details."
    }

    Throw-IfStopRequested
    Set-FinalPhaseProgress -FinalPhasePercent 20 -Message "Generating installer helper." -Source "script"
    $installerHelperPath = Write-InstallerHelper -OutputFolder $outputFolder
    Write-Info -Message ("Generated installer helper: {0}" -f $installerHelperPath)

    Throw-IfStopRequested
    Set-FinalPhaseProgress -FinalPhasePercent 65 -Message "Writing summary." -Source "script"
    $summaryPath = Write-SummaryFile -OutputFolder $outputFolder -AttemptOrder $normalizedSourceOrder.ToArray() -SourceUsed $usedSource -FontCount $fontCount -Failures $failures.ToArray() -StartTime $scriptStart
    Write-Info -Message ("Wrote summary file: {0}" -f $summaryPath)

    Set-FinalPhaseProgress -FinalPhasePercent 100 -Message "Completed successfully." -Source "script"
    Write-Host ""
    Write-Host ("Completed. Output='{0}' Source='{1}' TTF_Count={2}" -f $outputFolder, $usedSource, $fontCount)
    Write-GuiEvent -Event "completed" -Data @{
        outcome    = "success"
        outputFolder = $outputFolder
        sourceUsed = $usedSource
        fontCount  = $fontCount
        summaryPath = $summaryPath
    }
    exit 0
}
catch {
    $topLevelException = $_.Exception
    $topLevelMessage = if ($topLevelException) { $topLevelException.Message } else { "Unknown error." }
    $isStopRequestedException = $false
    if ($topLevelException -is [System.OperationCanceledException]) {
        $isStopRequestedException = $true
    }

    if ($isStopRequestedException) {
        Write-Warning "Graceful stop requested by GUI."
        Write-Status -Message "Graceful stop requested by GUI." -Level "warning" -Source "script"

        if (-not [string]::IsNullOrWhiteSpace($outputFolder)) {
            try {
                $summaryPath = Write-SummaryFile -OutputFolder $outputFolder -AttemptOrder $normalizedSourceOrder.ToArray() -SourceUsed $usedSource -FontCount $fontCount -Failures $failures.ToArray() -StartTime $scriptStart
                Write-Warning ("Stopped. Partial summary written to: {0}" -f $summaryPath)
            }
            catch {
                Write-Warning ("Stop requested, and summary writing failed: {0}" -f $_.Exception.Message)
            }
        }

        Set-FinalPhaseProgress -FinalPhasePercent 100 -Message "Stopped by user." -Source "script"
        Write-GuiEvent -Event "completed" -Data @{
            outcome     = "stopped"
            message     = "Stopped by user."
            outputFolder = $outputFolder
            sourceUsed  = $usedSource
            fontCount   = $fontCount
            summaryPath = $summaryPath
        }
        Write-Host "Stopped by user request."
        exit 2
    }

    if (-not [string]::IsNullOrWhiteSpace($topLevelMessage)) {
        Add-Failure -Source "script" -Message $topLevelMessage -Failures $failures
    }

    if (-not [string]::IsNullOrWhiteSpace($outputFolder)) {
        try {
            $summaryPath = Write-SummaryFile -OutputFolder $outputFolder -AttemptOrder $normalizedSourceOrder.ToArray() -SourceUsed $usedSource -FontCount $fontCount -Failures $failures.ToArray() -StartTime $scriptStart
            Write-Warning ("Execution failed. Summary written to: {0}" -f $summaryPath)
        }
        catch {
            Write-Warning ("Execution failed, and summary writing also failed: {0}" -f $_.Exception.Message)
        }
    }

    Write-GuiEvent -Event "failed" -Data @{
        message      = $topLevelMessage
        outputFolder = $outputFolder
        sourceUsed   = $usedSource
        fontCount    = $fontCount
        summaryPath  = $summaryPath
        failures     = $failures.ToArray()
    }
    Write-Status -Message $topLevelMessage -Level "error" -Source "script"
    Write-Error $topLevelMessage
    exit 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and (Test-Path -LiteralPath $tempRoot)) {
        try {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning ("Temporary folder cleanup failed: {0}" -f $_.Exception.Message)
        }
    }
}
