[CmdletBinding()]
param(
    [string]$ProductVersion = "0.0.1",
    [string]$Manufacturer = "FontExtractor",
    [string]$UpgradeCode = "B85B42A5-2F4B-43A3-99F9-6DA32C7CF001"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distExe = Join-Path $scriptDir "dist\FontExtractorGUI.exe"
if (-not (Test-Path -LiteralPath $distExe)) {
    throw "EXE not found at $distExe. Run build_exe.ps1 first."
}

function Get-WixCliPath {
    $cmd = Get-Command wix.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidate = "C:\Program Files\WiX Toolset v6.0\bin\wix.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw "WiX CLI not found. Install WiXToolset.WiXCLI."
}

$wixExe = Get-WixCliPath
$installerDir = Join-Path $scriptDir "installer"
New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

$wxsPath = Join-Path $installerDir "FontExtractorGUI.wxs"
$msiPath = Join-Path $scriptDir "dist\FontExtractorGUI-$ProductVersion.msi"

$wxs = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="FontExtractor GUI"
           Manufacturer="$Manufacturer"
           Version="$ProductVersion"
           UpgradeCode="$UpgradeCode"
           Scope="perMachine">
    <MajorUpgrade DowngradeErrorMessage="A newer version of FontExtractor GUI is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="FontExtractor GUI" />
    </StandardDirectory>

    <StandardDirectory Id="ProgramMenuFolder">
      <Directory Id="ApplicationProgramsFolder" Name="FontExtractor GUI" />
    </StandardDirectory>

    <Component Id="MainExecutableComponent" Directory="INSTALLFOLDER" Guid="*">
      <File Id="MainExecutableFile" Source="$distExe" KeyPath="yes" />
    </Component>

    <Component Id="StartMenuShortcutComponent" Directory="ApplicationProgramsFolder" Guid="*">
      <Shortcut Id="ApplicationStartMenuShortcut"
                Name="FontExtractor GUI"
                Description="FontExtractor GUI"
                Target="[INSTALLFOLDER]FontExtractorGUI.exe"
                WorkingDirectory="INSTALLFOLDER" />
      <RemoveFolder Id="RemoveAppProgramMenuDir" On="uninstall" />
      <RegistryValue Root="HKLM" Key="Software\$Manufacturer\FontExtractorGUI" Name="installed" Type="integer" Value="1" KeyPath="yes" />
    </Component>

    <Feature Id="MainFeature" Title="FontExtractor GUI" Level="1">
      <ComponentRef Id="MainExecutableComponent" />
      <ComponentRef Id="StartMenuShortcutComponent" />
    </Feature>
  </Package>
</Wix>
"@

Set-Content -LiteralPath $wxsPath -Value $wxs -Encoding UTF8
& $wixExe build $wxsPath -arch x64 -o $msiPath

Write-Host ("MSI build completed: {0}" -f $msiPath)
