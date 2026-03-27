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
    [bool]$AutoInstallFonts = $true,
    [ValidateSet("currentuser", "allusers")]
    [string]$InstallScope = "currentuser"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ConfirmPreference = "None"

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("[INFO] {0}" -f $Message)
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
    try {
        Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 20 | Out-Null
        return $true
    }
    catch {
        try {
            Invoke-WebRequest -Uri "https://github.com" -Method Get -TimeoutSec 20 | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
}

function Copy-TtfFilesPreservingStructure {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
    $ttfFiles = Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter "*.ttf"
    if (-not $ttfFiles) {
        return 0
    }

    $copied = 0
    foreach ($file in $ttfFiles) {
        $relativePath = $file.FullName.Substring($resolvedSourceRoot.Length).TrimStart("\")
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $targetPath = Join-Path $DestinationRoot $relativePath
        $targetDir = Split-Path -Path $targetPath -Parent
        Ensure-Directory -Path $targetDir
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
        $copied++
    }

    return $copied
}

function Invoke-ZipSource {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string]$ArchiveUrl
    )

    $zipPath = Join-Path $TempRoot "google-fonts-main.zip"
    $extractPath = Join-Path $TempRoot "zip-extract"
    Ensure-Directory -Path $extractPath

    Write-Info -Message "Downloading ZIP snapshot from $ArchiveUrl"
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $zipPath -MaximumRedirection 10 -TimeoutSec 240
    Write-Info -Message "Extracting ZIP snapshot"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $repoRoot = Get-ChildItem -LiteralPath $extractPath -Directory | Select-Object -First 1
    if (-not $repoRoot) {
        throw "ZIP snapshot extracted, but no repository root directory was found."
    }

    $copied = Copy-TtfFilesPreservingStructure -SourceRoot $repoRoot.FullName -DestinationRoot $OutputFolder
    if ($copied -le 0) {
        throw "ZIP source returned zero TTF files."
    }

    return $copied
}

function Invoke-GitSource {
    param(
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string]$RepositoryUrl
    )

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

    $copied = Copy-TtfFilesPreservingStructure -SourceRoot $clonePath -DestinationRoot $OutputFolder
    if ($copied -le 0) {
        throw "Git source returned zero TTF files."
    }

    return $copied
}

function Invoke-ApiSource {
    param(
        [Parameter(Mandatory = $true)][string]$OutputFolder,
        [Parameter(Mandatory = $true)][string]$MetadataBaseUrl,
        [Parameter(Mandatory = $false)][string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw "API source requested but no API key provided. Use -ApiKey or set GOOGLE_FONTS_API_KEY."
    }

    $metadataUri = "{0}?key={1}" -f $MetadataBaseUrl, [Uri]::EscapeDataString($Key)
    Write-Info -Message "Requesting Google Fonts metadata from Developer API"
    $response = Invoke-RestMethod -Uri $metadataUri -Method Get -TimeoutSec 120
    if (-not $response.items) {
        throw "Developer API response did not contain font families."
    }

    $downloaded = 0
    foreach ($family in $response.items) {
        if (-not $family.files) {
            continue
        }

        $familyName = Convert-ToSafePathSegment -Name ([string]$family.family)
        $familyFolder = Join-Path $OutputFolder $familyName
        Ensure-Directory -Path $familyFolder

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

            $targetPath = Join-Path $familyFolder ("{0}.ttf" -f $variantName)
            $suffix = 2
            while (Test-Path -LiteralPath $targetPath) {
                $targetPath = Join-Path $familyFolder ("{0}-{1}.ttf" -f $variantName, $suffix)
                $suffix++
            }

            Invoke-WebRequest -Uri $fontUrl -OutFile $targetPath -TimeoutSec 120
            $downloaded++
        }
    }

    if ($downloaded -le 0) {
        throw "API source returned zero downloadable TTF files."
    }

    return $downloaded
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-TtfFontsNonInteractive {
    param(
        [Parameter(Mandatory = $true)][string]$FontsRoot,
        [Parameter(Mandatory = $true)][ValidateSet("currentuser", "allusers")][string]$Scope
    )

    $fontFiles = @(Get-ChildItem -LiteralPath $FontsRoot -Recurse -File -Filter "*.ttf")
    if ($fontFiles.Count -eq 0) {
        throw "No .ttf files found for installation under $FontsRoot"
    }

    $normalizedScope = $Scope.ToLowerInvariant()
    if ($normalizedScope -eq "allusers") {
        if (-not (Test-IsAdministrator)) {
            throw "InstallScope 'allusers' requires an elevated PowerShell session."
        }
        $fontsDir = Join-Path $env:WINDIR "Fonts"
        $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    }
    else {
        $fontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
        $registryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    }

    Ensure-Directory -Path $fontsDir
    if (-not (Test-Path -LiteralPath $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }

    if (-not ("FontApi" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FontApi {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string lpFileName);

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
"@
    }

    $succeeded = 0
    $failed = 0
    $newCopies = 0
    $skippedExisting = 0

    foreach ($font in $fontFiles) {
        try {
            $targetFileName = $font.Name
            $targetPath = Join-Path $fontsDir $targetFileName
            if (Test-Path -LiteralPath $targetPath) {
                $skippedExisting++
            }
            else {
                Copy-Item -LiteralPath $font.FullName -Destination $targetPath -Force
                $newCopies++
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
            [void][FontApi]::AddFontResource($targetPath)
            $succeeded++
            Write-Info -Message ("Installed font {0} ({1}/{2})" -f $font.Name, $succeeded + $failed, $fontFiles.Count)
        }
        catch {
            $failed++
            Write-Warning ("Failed to install {0}: {1}" -f $font.FullName, $_.Exception.Message)
        }
    }

    $broadcastResult = [UIntPtr]::Zero
    [void][FontApi]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$broadcastResult)

    return [pscustomobject]@{
        total           = $fontFiles.Count
        succeeded       = $succeeded
        failed          = $failed
        newCopies       = $newCopies
        skippedExisting = $skippedExisting
        scope           = $normalizedScope
    }
}

function Write-InstallerHelper {
    param([Parameter(Mandatory = $true)][string]$OutputFolder)

    $helperPath = Join-Path $OutputFolder "Install-All-Fonts.ps1"
    $helperContent = @'
[CmdletBinding()]
param(
    [string]$FontsRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Error "Run this script in an elevated PowerShell session (Run as Administrator) to install for all users."
    exit 1
}

$fontFiles = Get-ChildItem -LiteralPath $FontsRoot -Recurse -File -Filter "*.ttf"
if (-not $fontFiles) {
    Write-Host "No .ttf files found under $FontsRoot"
    exit 0
}

$windowsFontsDir = Join-Path $env:WINDIR "Fonts"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

if (-not ("FontApi" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FontApi {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string lpFileName);

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
"@
}

$succeeded = 0
$failed = 0
$newCopies = 0
$skippedExisting = 0

foreach ($font in $fontFiles) {
    try {
        $targetFileName = $font.Name
        $targetPath = Join-Path $windowsFontsDir $targetFileName
        if (Test-Path -LiteralPath $targetPath) {
            $skippedExisting++
        }
        else {
            Copy-Item -LiteralPath $font.FullName -Destination $targetPath -Force
            $newCopies++
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
        [void][FontApi]::AddFontResource($targetPath)
        $succeeded++
    }
    catch {
        $failed++
        Write-Warning ("Failed to install {0}: {1}" -f $font.FullName, $_.Exception.Message)
    }
}

$broadcastResult = [UIntPtr]::Zero
[void][FontApi]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 0, 1000, [ref]$broadcastResult)

Write-Host ("Completed all-users font install. Total={0}; Succeeded={1}; Failed={2}; NewCopies={3}; SkippedExisting={4}" -f $fontFiles.Count, $succeeded, $failed, $newCopies, $skippedExisting)

if ($failed -gt 0) {
    exit 1
}
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
        generatedAt       = (Get-Date).ToString("o")
        outputFolder      = $OutputFolder
        sourceAttemptOrder = $AttemptOrder
        sourceUsed        = $SourceUsed
        fontCount         = $FontCount
        durationSeconds   = [Math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
        failures          = $Failures
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

try {
    $githubReachable = Test-GitHubConnectivity
    if ($githubReachable) {
        Write-Info -Message "GitHub connectivity check passed."
    }
    else {
        Write-Warning "GitHub connectivity check failed. ZIP or git sources may fail; API fallback may still work."
    }

    Ensure-Directory -Path $DownloadsRoot
    $baseOutputRoot = Join-Path $DownloadsRoot $BaseFolderName
    Ensure-Directory -Path $baseOutputRoot

    $outputFolder = Get-UniqueDatedOutputFolder -RootPath $baseOutputRoot -Format $DateFormat
    Write-Info -Message ("Output folder: {0}" -f $outputFolder)

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("google-fonts-" + [Guid]::NewGuid().ToString("N"))
    Ensure-Directory -Path $tempRoot

    foreach ($source in $normalizedSourceOrder) {
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
                break
            }

            throw ("Source '{0}' completed but returned zero TTF files." -f $source)
        }
        catch {
            $message = $_.Exception.Message
            Add-Failure -Source $source -Message $message -Failures $failures
            Write-Warning ("Source '{0}' failed: {1}" -f $source, $message)
        }
    }

    if (-not $usedSource) {
        throw "All download sources failed. See download-summary.json for details."
    }

    $installerHelperPath = Write-InstallerHelper -OutputFolder $outputFolder
    Write-Info -Message ("Generated installer helper: {0}" -f $installerHelperPath)

    $summaryPath = Write-SummaryFile -OutputFolder $outputFolder -AttemptOrder $normalizedSourceOrder.ToArray() -SourceUsed $usedSource -FontCount $fontCount -Failures $failures.ToArray() -StartTime $scriptStart
    Write-Info -Message ("Wrote summary file: {0}" -f $summaryPath)

    if ($AutoInstallFonts) {
        Write-Info -Message ("Starting non-interactive font installation (scope: {0})." -f $InstallScope)
        $installResult = Install-TtfFontsNonInteractive -FontsRoot $outputFolder -Scope $InstallScope
        Write-Info -Message (
            "Font installation completed. Total={0}; Succeeded={1}; Failed={2}; NewCopies={3}; SkippedExisting={4}" -f
            $installResult.total, $installResult.succeeded, $installResult.failed, $installResult.newCopies, $installResult.skippedExisting
        )
        if ($installResult.failed -gt 0) {
            throw ("Font installation failed for {0} files." -f $installResult.failed)
        }
    }

    Write-Host ""
    Write-Host ("Completed. Output='{0}' Source='{1}' TTF_Count={2}" -f $outputFolder, $usedSource, $fontCount)
}
catch {
    $topLevelMessage = $_.Exception.Message
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
