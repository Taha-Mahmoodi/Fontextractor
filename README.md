# Google Fonts Library Downloader (Open Source)

Google Fonts Library Downloader downloads Google Fonts (`.ttf`) into a dated output folder, with both CLI and GUI workflows.

## Current Version

- Latest and only maintained snapshot: `V1.3`

## What Was Added In V1.3

- GUI: new `ZIP EXTRACTION` progress bar that appears during archive extraction.
- GUI: completion toast after download/extraction: "Download and extraction are done. Fonts are ready to be installed."
- GUI: new `FONT INSTALLATION` progress bar with current font name while installing.
- GUI: installer now emits structured install progress events for live UI updates.
- CLI: non-GUI script now supports unattended runs end-to-end, including optional non-interactive font installation.
- Repository cleanup: older version folders removed; only `V1.3` remains.

## Features

- Multi-source fallback for downloads: `zip`, `git`, `api`
- Dated output folders (`yyyy-MM-dd`, with suffix if needed)
- Download summary JSON output
- Auto-generated `Install-All-Fonts.ps1`
- GUI controls: Start / Pause / Stop / Cancel + live logs + progress bars + theme toggle

## Requirements

### CLI

- Windows PowerShell 5.1+
- Internet connection
- Optional: `git` in PATH
- Optional (for API source): Google Fonts API key

### GUI (from source)

- Python 3.12+
- `pip`

## CLI Usage (Non-GUI)

Main script:
- [`Google-Fonts-Library-Downloader.ps1`](./Google-Fonts-Library-Downloader.ps1)

Default unattended run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Google-Fonts-Library-Downloader.ps1
```

Run with explicit options:

```powershell
powershell -ExecutionPolicy Bypass -File .\Google-Fonts-Library-Downloader.ps1 `
  -DownloadsRoot "D:\Fonts" `
  -BaseFolderName "Google Fonts 2026" `
  -SourceOrder zip,git,api `
  -AutoInstallFonts $true `
  -InstallScope currentuser
```

### CLI Parameters

- `-DownloadsRoot`: output root path
- `-BaseFolderName`: parent folder under root
- `-SourceOrder`: any mix/order of `zip`, `git`, `api`
- `-ApiKey`: Google Fonts API key
- `-DateFormat`: output date format
- `-AutoInstallFonts`: automatically install fonts after download (default: `true`)
- `-InstallScope`: `currentuser` (default) or `allusers` (requires elevated terminal)

## GUI Usage

Use GUI source in:
- `V1.3\gui`

Run from source:

```powershell
cd .\V1.3\gui
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\requirements.txt
.\.venv\Scripts\python.exe .\app.py
```

Build EXE:

```powershell
cd .\V1.3\gui
.\build_exe.ps1 -PythonExe "$env:LocalAppData\Programs\Python\Python312\python.exe"
```

Build MSI:

```powershell
cd .\V1.3\gui
.\build_msi.ps1 -ProductVersion "1.3.0"
```

## GitHub Release Pipeline

- Workflow: `.github/workflows/release-windows.yml`
- Builds EXE and MSI from `V1.3/gui`
- Optional code signing with secrets:
  - `WINDOWS_CERT_PFX_BASE64`
  - `WINDOWS_CERT_PASSWORD`

## License

MIT. See [LICENSE](./LICENSE).
