# Google Fonts Library Downloader GUI (V1.3)

PySide6 desktop wrapper for the downloader worker script.

## Run From Source

```powershell
python -m pip install -r requirements.txt
python app.py
```

## Build EXE

```powershell
.\build_exe.ps1 -PythonExe "$env:LocalAppData\Programs\Python\Python312\python.exe"
```

Output: `dist\GoogleFontsLibraryDownloaderGUI.exe`

## Behavior

- Uses `runtime/Google-Fonts-Library-Downloader.worker.ps1` (runtime copy model).
- Parses `__FX_GUI_EVENT__` JSON lines from worker/helper scripts.
- Supports `Pause` / `Resume`, `Stop`, `Cancel`.
- Shows:
  - full-process progress
  - current download progress
  - ZIP extraction progress (visible during extraction)
  - font installation progress with current font name
- Shows toast after download/extraction completes.
