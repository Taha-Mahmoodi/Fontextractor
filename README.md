# FontExtractor (Open Source)

FontExtractor downloads Google Fonts (`.ttf`) into a dated output folder and optionally helps install them on Windows.

This repository includes:
- A **PowerShell CLI script** for direct/automation use.
- A **desktop GUI app** (PySide6) for non-technical users.

## Project Status

- Latest app snapshot: **`V1.1`**
- Legacy snapshots kept for history:
  - `gui/`
  - `V000.2/`
  - `V1/`

If you are starting fresh, use **`V1.1`**.

## Features

- Multi-source fallback for fonts:
  - GitHub ZIP snapshot
  - Git clone
  - Google Fonts API
- Dated output folders (`yyyy-MM-dd`, with suffix if needed)
- Download summary JSON output
- Optional helper script to install all downloaded fonts
- GUI controls:
  - Start / Pause / Stop / Cancel
  - Full process progress
  - Current download progress with downloaded amount
  - Live activity log
  - Theme toggle (light/dark)
  - Folder picker for download destination

## Requirements

### For CLI
- Windows PowerShell 5.1+
- Internet connection
- Optional:
  - `git` (for git source)
  - Google Fonts API key (for API source)

### For GUI (run from source)
- Python 3.12+
- `pip`

## How To Run (Without GUI / CLI)

Main script:
- [`Download-GoogleFonts.ps1`](./Download-GoogleFonts.ps1)

Example (defaults):

```powershell
powershell -ExecutionPolicy Bypass -File .\Download-GoogleFonts.ps1
```

Example (custom output root + source order):

```powershell
powershell -ExecutionPolicy Bypass -File .\Download-GoogleFonts.ps1 `
  -DownloadsRoot "D:\Fonts" `
  -BaseFolderName "Google Fonts 2026" `
  -SourceOrder zip,git,api
```

Example (API fallback with key):

```powershell
$env:GOOGLE_FONTS_API_KEY = "YOUR_KEY"
powershell -ExecutionPolicy Bypass -File .\Download-GoogleFonts.ps1 -SourceOrder api
```

### Common CLI Parameters

- `-DownloadsRoot` path where output folders are created
- `-BaseFolderName` parent folder name under `DownloadsRoot`
- `-SourceOrder` one or more of: `zip`, `git`, `api`
- `-ApiKey` Google Fonts API key
- `-DateFormat` output folder date format

## How To Run (GUI)

Use the latest version in:
- `V1\gui`

### Use prebuilt binaries (no Python required)

Prebuilt artifacts are included in this repository under:
- `V1.1/FontExtractorGUI.exe`
- `V1.1/FontExtractorGUI-1.1.0.msi`

For end users, these are self-contained:
- No Python installation required
- No manual dependency installation required

### Run GUI from source

```powershell
cd .\V1\gui
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\requirements.txt
.\.venv\Scripts\python.exe .\app.py
```

### Build GUI EXE

```powershell
cd .\V1\gui
.\build_exe.ps1 -PythonExe "$env:LocalAppData\Programs\Python\Python312\python.exe"
```

Output:
- `V1\gui\dist\FontExtractorGUI.exe`

### Build MSI installer

```powershell
cd .\V1\gui
.\build_msi.ps1 -ProductVersion "1.1.0"
```

Output:
- `V1\gui\dist\FontExtractorGUI-1.1.0.msi`

## GUI Usage Notes

- `Pause` suspends process tree.
- `Stop` requests graceful stop.
- `Cancel` terminates immediately.
- `Install All Fonts` triggers elevated install helper after fonts are downloaded.
- Runtime cache is automatically cleared when starting a new process.

## SmartScreen / Publisher Warning

If Windows shows **"Unknown publisher"** (SmartScreen), it means the app is not signed with a trusted code-signing certificate.

This repo now includes a GitHub Actions release pipeline:
- Workflow: `.github/workflows/release-windows.yml`
- Trigger: push tag `v*` (or run manually)
- Output: EXE + MSI release assets
- Optional signing: set repository secrets:
  - `WINDOWS_CERT_PFX_BASE64` (Base64 of your `.pfx`)
  - `WINDOWS_CERT_PASSWORD`

Notes:
- Without these secrets, releases are built but **unsigned**.
- To reduce/avoid SmartScreen warnings in production, use a trusted code-signing certificate (EV certificate is best for faster reputation).

## Output Files

Each run writes:
- Downloaded fonts in a dated folder
- `download-summary.json`
- `Install-All-Fonts.ps1` helper script

## Troubleshooting

- If API source fails:
  - verify key and quota
- If git source fails:
  - ensure `git` is installed and in `PATH`
- If GUI fails to launch:
  - run from source and inspect terminal output
- If installer helper fails:
  - run as Administrator

## Version Control / Release Flow

Recommended:
1. Create feature branch.
2. Commit with clear message.
3. Tag releases (for example `v1.1.0`).
4. Publish EXE/MSI from release tags.

## License

This project is licensed under the **MIT License**. See [LICENSE](./LICENSE).
