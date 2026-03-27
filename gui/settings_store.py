from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


DEFAULT_SETTINGS: dict[str, Any] = {
    "downloads_root": str(Path.home() / "Downloads"),
    "base_folder_name": "Google Fonts 2026",
    "api_key": "",
    "source_order": "zip,git,api",
    "theme": "light",
    "window_width": 1220,
    "window_height": 760,
}


def get_settings_path() -> Path:
    appdata = os.environ.get("APPDATA")
    base_dir = Path(appdata) if appdata else (Path.home() / ".google-fonts-library-downloader-gui")
    settings_dir = base_dir / "GoogleFontsLibraryDownloaderGUI"
    settings_dir.mkdir(parents=True, exist_ok=True)
    return settings_dir / "settings.json"


def load_settings() -> dict[str, Any]:
    settings = dict(DEFAULT_SETTINGS)
    settings_path = get_settings_path()
    if not settings_path.exists():
        return settings

    try:
        raw_data = json.loads(settings_path.read_text(encoding="utf-8"))
        if isinstance(raw_data, dict):
            for key, value in raw_data.items():
                if key in settings:
                    settings[key] = value
    except (json.JSONDecodeError, OSError):
        return settings

    return settings


def save_settings(data: dict[str, Any]) -> None:
    settings = dict(DEFAULT_SETTINGS)
    settings.update(data)
    settings_path = get_settings_path()
    settings_path.write_text(json.dumps(settings, indent=2), encoding="utf-8")

