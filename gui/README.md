# Google Fonts Library Downloader NeoGlass GUI

This folder contains a PySide6 desktop GUI wrapper for the PowerShell Google Fonts Library Downloader.

## Run From Source

1. Create and activate a virtual environment.
2. Install dependencies:

```powershell
python -m pip install -r requirements.txt
```

3. Launch:

```powershell
python app.py
```

## Build Single-File EXE

```powershell
.\build_exe.ps1 -PythonExe "$env:LocalAppData\Programs\Python\Python312\python.exe"
```

Output:

`dist\GoogleFontsLibraryDownloaderGUI.exe`

## Behavior

- Uses `gui/runtime/Google-Fonts-Library-Downloader.worker.ps1` for execution (the original root script is untouched).
- Emits and parses structured GUI events using `__FX_GUI_EVENT__` JSON lines.
- Supports `Pause`/`Resume` (process suspend), `Stop` (graceful stop file), and `Cancel` (immediate terminate).

