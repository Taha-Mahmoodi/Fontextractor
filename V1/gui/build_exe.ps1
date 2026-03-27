[CmdletBinding()]
param(
    [string]$PythonExe = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvDir = Join-Path $scriptDir ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host "Creating virtual environment..."
    & $PythonExe -m venv $venvDir
}

Write-Host "Installing dependencies..."
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $scriptDir "requirements.txt")

Push-Location $scriptDir
try {
    if (Test-Path -LiteralPath ".\build") {
        Remove-Item -LiteralPath ".\build" -Recurse -Force
    }
    if (Test-Path -LiteralPath ".\dist") {
        Remove-Item -LiteralPath ".\dist" -Recurse -Force
    }

    $workerData = "{0};runtime" -f (Join-Path $scriptDir "runtime\Download-GoogleFonts.worker.ps1")
    Write-Host "Building one-file executable..."
    & $venvPython -m PyInstaller `
        --noconfirm `
        --clean `
        --onefile `
        --windowed `
        --name "FontExtractorGUI" `
        --add-data $workerData `
        "app.py"
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host ("Build completed: {0}" -f (Join-Path $scriptDir "dist\FontExtractorGUI.exe"))
