# V1.3 Release Notes

## Added

- ZIP extraction progress bar in GUI (shown only during extraction).
- Live extraction progress events from worker script (`extract_progress`).
- Completion toast after download/extraction: "Download and extraction are done. Fonts are ready to be installed."
- Font installation progress bar in GUI with current font name.
- Live install events from `Install-All-Fonts.ps1`:
  - `install_progress`
  - `install_completed`
  - `install_failed`
- Non-GUI CLI now supports unattended full run with auto-install defaults:
  - `-AutoInstallFonts` (default: `true`)
  - `-InstallScope` (`currentuser` or `allusers`)

## Changed

- Project structure simplified to latest version only.
- Removed older version folders and retained only `V1.3`.
