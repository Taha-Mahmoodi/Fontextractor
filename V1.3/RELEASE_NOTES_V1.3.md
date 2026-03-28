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
- Network/TLS startup hardening for older Windows/PowerShell environments (improves startup on other laptops).
- One-line CLI execution command documented for running from anywhere (no local script path required).
- ZIP extraction stability fix: extract stage now targets `.ttf` entries and safely skips bad non-font ZIP entries.
- Download bar accuracy fix: when server size is unknown, GUI now shows indeterminate progress instead of jumping to ~95%.
- Install helper stability fix: robust Local AppData path resolution added to prevent empty-path failures on some Windows environments.

## Changed

- Project structure simplified to latest version only.
- Removed older version folders and retained only `V1.3`.
