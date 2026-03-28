from __future__ import annotations

from datetime import datetime
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any
import uuid

from PySide6.QtCore import Qt, QProcess, QTimer
from PySide6.QtGui import QCloseEvent, QFont
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QSplitter,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from event_protocol import GuiEvent, parse_gui_event_line
from process_control import resume_process_tree, suspend_process_tree, terminate_process_tree
from settings_store import load_settings, save_settings
from theme import DARK_THEME_QSS, LIGHT_THEME_QSS


VALID_SOURCES = {"zip", "git", "api"}


class GoogleFontsLibraryDownloaderWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Google Fonts Library Downloader V1.3")
        self._settings = load_settings()
        self._state = "idle"
        self._theme = str(self._settings.get("theme", "light")).lower()
        self._stdout_buffer = ""
        self._stderr_buffer = ""
        self._control_file_path: Path | None = None
        self._terminal_event: dict[str, Any] | None = None
        self._cancel_requested = False
        self._last_output_folder: str = ""
        self._current_download_item: str = ""
        self._current_extract_item: str = ""
        self._current_install_item: str = ""
        self._toast_label: QLabel | None = None
        self._install_stdout_buffer = ""
        self._install_stderr_buffer = ""
        self._install_in_progress = False

        self._process = QProcess(self)
        self._process.readyReadStandardOutput.connect(self._on_stdout_ready)
        self._process.readyReadStandardError.connect(self._on_stderr_ready)
        self._process.finished.connect(self._on_process_finished)
        self._process.errorOccurred.connect(self._on_process_error)

        self._install_process = QProcess(self)
        self._install_process.readyReadStandardOutput.connect(self._on_install_stdout_ready)
        self._install_process.readyReadStandardError.connect(self._on_install_stderr_ready)
        self._install_process.finished.connect(self._on_install_process_finished)
        self._install_process.errorOccurred.connect(self._on_install_process_error)

        self._build_ui()
        self._restore_initial_state()
        self._apply_theme(self._theme)
        self._update_button_states()

    def _build_ui(self) -> None:
        root = QWidget(self)
        root.setObjectName("Root")
        self.setCentralWidget(root)

        outer = QVBoxLayout(root)
        outer.setContentsMargins(16, 16, 16, 16)
        outer.setSpacing(12)

        splitter = QSplitter(Qt.Horizontal, root)
        splitter.setChildrenCollapsible(False)

        left_panel = QFrame(splitter)
        left_panel.setObjectName("Card")
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(18, 18, 18, 18)
        left_layout.setSpacing(12)

        title = QLabel("Google Fonts Library Downloader", left_panel)
        title.setObjectName("HeaderTitle")
        subtitle = QLabel("Run, monitor, and control the full font extraction process.", left_panel)
        subtitle.setObjectName("SubTitle")
        subtitle.setWordWrap(True)

        theme_row = QHBoxLayout()
        theme_row.setSpacing(8)
        self.theme_toggle_button = QPushButton("Switch To Dark Theme", left_panel)
        self.theme_toggle_button.setObjectName("SecondaryButton")
        self.theme_toggle_button.clicked.connect(self._toggle_theme)
        theme_row.addWidget(self.theme_toggle_button)
        theme_row.addStretch(1)

        control_label = QLabel("RUN CONTROLS", left_panel)
        control_label.setObjectName("SectionTitle")
        controls_row = QHBoxLayout()
        controls_row.setSpacing(8)

        self.start_button = QPushButton("Start", left_panel)
        self.start_button.setObjectName("PrimaryButton")
        self.start_button.clicked.connect(self._start_run)

        self.pause_button = QPushButton("Pause", left_panel)
        self.pause_button.setObjectName("SecondaryButton")
        self.pause_button.clicked.connect(self._toggle_pause)

        self.stop_button = QPushButton("Stop", left_panel)
        self.stop_button.setObjectName("SecondaryButton")
        self.stop_button.clicked.connect(self._stop_gracefully)

        self.cancel_button = QPushButton("Cancel", left_panel)
        self.cancel_button.setObjectName("DangerButton")
        self.cancel_button.clicked.connect(self._cancel_immediately)

        controls_row.addWidget(self.start_button)
        controls_row.addWidget(self.pause_button)
        controls_row.addWidget(self.stop_button)
        controls_row.addWidget(self.cancel_button)

        self.status_label = QLabel("Idle", left_panel)
        self.status_label.setObjectName("SubTitle")
        self.status_label.setWordWrap(True)

        overall_label = QLabel("FULL PROCESS PROGRESS", left_panel)
        overall_label.setObjectName("SectionTitle")
        self.overall_progress_bar = QProgressBar(left_panel)
        self.overall_progress_bar.setRange(0, 100)
        self.overall_progress_bar.setValue(0)

        download_label = QLabel("CURRENT DOWNLOAD", left_panel)
        download_label.setObjectName("SectionTitle")
        self.download_progress_bar = QProgressBar(left_panel)
        self.download_progress_bar.setRange(0, 100)
        self.download_progress_bar.setValue(0)
        self.download_item_label = QLabel("No active font download.", left_panel)
        self.download_item_label.setObjectName("SubTitle")
        self.download_item_label.setWordWrap(True)

        extract_label = QLabel("ZIP EXTRACTION", left_panel)
        extract_label.setObjectName("SectionTitle")
        self.extract_progress_bar = QProgressBar(left_panel)
        self.extract_progress_bar.setRange(0, 100)
        self.extract_progress_bar.setValue(0)
        self.extract_item_label = QLabel("ZIP extraction has not started.", left_panel)
        self.extract_item_label.setObjectName("SubTitle")
        self.extract_item_label.setWordWrap(True)

        install_progress_label = QLabel("FONT INSTALLATION", left_panel)
        install_progress_label.setObjectName("SectionTitle")
        self.install_progress_bar = QProgressBar(left_panel)
        self.install_progress_bar.setRange(0, 100)
        self.install_progress_bar.setValue(0)
        self.install_item_label = QLabel("Font installation has not started.", left_panel)
        self.install_item_label.setObjectName("SubTitle")
        self.install_item_label.setWordWrap(True)

        self.install_fonts_button = QPushButton("Install All Fonts", left_panel)
        self.install_fonts_button.setObjectName("SecondaryButton")
        self.install_fonts_button.clicked.connect(self._install_all_fonts)
        self.install_fonts_button.setEnabled(False)

        self.advanced_toggle = QToolButton(left_panel)
        self.advanced_toggle.setText("Advanced Settings")
        self.advanced_toggle.setCheckable(True)
        self.advanced_toggle.setChecked(False)
        self.advanced_toggle.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.advanced_toggle.setArrowType(Qt.RightArrow)
        self.advanced_toggle.toggled.connect(self._toggle_advanced_panel)

        self.advanced_panel = QFrame(left_panel)
        self.advanced_panel.setObjectName("Card")
        self.advanced_panel.setVisible(False)
        advanced_layout = QVBoxLayout(self.advanced_panel)
        advanced_layout.setContentsMargins(12, 12, 12, 12)
        advanced_layout.setSpacing(8)

        self.downloads_root_input = QLineEdit(self.advanced_panel)
        self.base_folder_input = QLineEdit(self.advanced_panel)
        self.source_order_input = QLineEdit(self.advanced_panel)
        self.api_key_input = QLineEdit(self.advanced_panel)
        self.api_key_input.setEchoMode(QLineEdit.Password)

        advanced_layout.addWidget(self._downloads_root_block())
        advanced_layout.addWidget(self._field_block("Base Folder Name", self.base_folder_input))
        advanced_layout.addWidget(self._field_block("Source Order (comma-separated)", self.source_order_input))
        advanced_layout.addWidget(self._field_block("Google Fonts API Key", self.api_key_input))

        hint = QLabel("Source order accepts any mix of: zip, git, api", self.advanced_panel)
        hint.setObjectName("SubTitle")
        advanced_layout.addWidget(hint)

        left_layout.addWidget(title)
        left_layout.addWidget(subtitle)
        left_layout.addLayout(theme_row)
        left_layout.addWidget(control_label)
        left_layout.addLayout(controls_row)
        left_layout.addWidget(self.status_label)
        left_layout.addWidget(overall_label)
        left_layout.addWidget(self.overall_progress_bar)
        left_layout.addWidget(download_label)
        left_layout.addWidget(self.download_progress_bar)
        left_layout.addWidget(self.download_item_label)
        left_layout.addWidget(extract_label)
        left_layout.addWidget(self.extract_progress_bar)
        left_layout.addWidget(self.extract_item_label)
        left_layout.addWidget(install_progress_label)
        left_layout.addWidget(self.install_progress_bar)
        left_layout.addWidget(self.install_item_label)
        left_layout.addWidget(self.install_fonts_button)
        left_layout.addWidget(self.advanced_toggle)
        left_layout.addWidget(self.advanced_panel)
        left_layout.addStretch(1)

        right_panel = QFrame(splitter)
        right_panel.setObjectName("Card")
        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(18, 18, 18, 18)
        right_layout.setSpacing(10)

        log_header = QLabel("Live Activity Log", right_panel)
        log_header.setObjectName("HeaderTitle")
        log_subtitle = QLabel("Real-time feed of what has been done and what is running now.", right_panel)
        log_subtitle.setObjectName("SubTitle")
        log_subtitle.setWordWrap(True)

        self.log_output = QPlainTextEdit(right_panel)
        self.log_output.setReadOnly(True)
        self.log_output.setLineWrapMode(QPlainTextEdit.NoWrap)

        clear_button = QPushButton("Clear Logs", right_panel)
        clear_button.setObjectName("SecondaryButton")
        clear_button.clicked.connect(self.log_output.clear)

        right_layout.addWidget(log_header)
        right_layout.addWidget(log_subtitle)
        right_layout.addWidget(self.log_output, stretch=1)
        right_layout.addWidget(clear_button)

        splitter.addWidget(left_panel)
        splitter.addWidget(right_panel)
        splitter.setStretchFactor(0, 5)
        splitter.setStretchFactor(1, 6)
        splitter.setSizes([520, 700])
        outer.addWidget(splitter)
        self._set_extract_progress_visible(False)
        self._set_install_progress_visible(False)

    def _field_block(self, label_text: str, field: QLineEdit) -> QWidget:
        block = QWidget(self)
        layout = QVBoxLayout(block)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)
        label = QLabel(label_text, block)
        label.setObjectName("SectionTitle")
        layout.addWidget(label)
        layout.addWidget(field)
        return block

    def _downloads_root_block(self) -> QWidget:
        block = QWidget(self)
        layout = QVBoxLayout(block)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)
        label = QLabel("Downloads Root", block)
        label.setObjectName("SectionTitle")
        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)
        browse_button = QPushButton("Browse", block)
        browse_button.setObjectName("SecondaryButton")
        browse_button.clicked.connect(self._browse_download_root)
        row.addWidget(self.downloads_root_input, stretch=1)
        row.addWidget(browse_button)
        layout.addWidget(label)
        layout.addLayout(row)
        return block

    def _restore_initial_state(self) -> None:
        self.resize(
            int(self._settings.get("window_width", 1220)),
            int(self._settings.get("window_height", 760)),
        )
        self.downloads_root_input.setText(str(self._settings.get("downloads_root", "")))
        self.base_folder_input.setText(str(self._settings.get("base_folder_name", "Google Fonts 2026")))
        self.source_order_input.setText(str(self._settings.get("source_order", "zip,git,api")))
        self.api_key_input.setText(str(self._settings.get("api_key", "")))
        self._append_log("UI ready. Configure settings and press Start.", "info")

    def _toggle_advanced_panel(self, visible: bool) -> None:
        self.advanced_toggle.setArrowType(Qt.DownArrow if visible else Qt.RightArrow)
        self.advanced_panel.setVisible(visible)

    def _toggle_theme(self) -> None:
        if self._theme == "dark":
            self._apply_theme("light")
        else:
            self._apply_theme("dark")
        self._persist_settings()

    def _apply_theme(self, theme_name: str) -> None:
        self._theme = "dark" if theme_name == "dark" else "light"
        if self._theme == "dark":
            self.setStyleSheet(DARK_THEME_QSS)
            self.theme_toggle_button.setText("Switch To Light Theme")
        else:
            self.setStyleSheet(LIGHT_THEME_QSS)
            self.theme_toggle_button.setText("Switch To Dark Theme")

    def _browse_download_root(self) -> None:
        current_value = self.downloads_root_input.text().strip()
        start_dir = current_value if current_value and Path(current_value).exists() else str(Path.home())
        selected = QFileDialog.getExistingDirectory(
            self,
            "Select Download Root",
            start_dir,
        )
        if selected:
            self.downloads_root_input.setText(selected)
            self._persist_settings()

    def _resource_path(self, relative: Path) -> Path:
        if getattr(sys, "frozen", False):
            base_dir = Path(getattr(sys, "_MEIPASS"))
        else:
            base_dir = Path(__file__).resolve().parent
        return base_dir / relative

    def _project_root(self) -> Path:
        return Path(__file__).resolve().parent.parent

    def _runtime_base_dir(self) -> Path:
        return Path(tempfile.gettempdir()) / "GoogleFontsLibraryDownloader"

    def _calculate_sha256(self, path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as file_stream:
            for chunk in iter(lambda: file_stream.read(8192), b""):
                digest.update(chunk)
        return digest.hexdigest()

    def _ensure_runtime_worker_copy(self) -> Path:
        bundled_worker = self._resource_path(Path("runtime") / "Google-Fonts-Library-Downloader.worker.ps1")
        if not bundled_worker.exists():
            raise FileNotFoundError(f"Bundled worker script is missing: {bundled_worker}")

        runtime_dir = self._runtime_base_dir() / "runtime"
        runtime_dir.mkdir(parents=True, exist_ok=True)
        runtime_worker = runtime_dir / "Google-Fonts-Library-Downloader.worker.ps1"
        hash_marker = runtime_dir / "worker.hash"
        source_hash = self._calculate_sha256(bundled_worker)

        stored_hash = hash_marker.read_text(encoding="utf-8").strip() if hash_marker.exists() else ""
        if (not runtime_worker.exists()) or (stored_hash != source_hash):
            shutil.copy2(bundled_worker, runtime_worker)
            hash_marker.write_text(source_hash, encoding="utf-8")

        return runtime_worker

    def _clear_runtime_cache(self) -> None:
        runtime_base = self._runtime_base_dir()
        if runtime_base.exists():
            try:
                shutil.rmtree(runtime_base)
                self._append_log("Runtime cache cleared for fresh process start.", "info")
            except OSError as exc:
                self._append_log(f"Could not fully clear runtime cache: {exc}", "warning")

    def _parse_source_order(self) -> list[str]:
        raw_value = self.source_order_input.text().strip()
        if not raw_value:
            return ["zip", "git", "api"]

        discovered: list[str] = []
        seen: set[str] = set()
        parts = [part.strip().lower() for part in raw_value.replace(";", ",").split(",")]
        for part in parts:
            if not part:
                continue
            if part not in VALID_SOURCES:
                self._append_log(f"Ignoring unsupported source '{part}'.", "warning")
                continue
            if part in seen:
                continue
            seen.add(part)
            discovered.append(part)

        return discovered or ["zip", "git", "api"]

    def _persist_settings(self) -> None:
        payload = {
            "downloads_root": self.downloads_root_input.text().strip(),
            "base_folder_name": self.base_folder_input.text().strip() or "Google Fonts 2026",
            "api_key": self.api_key_input.text().strip(),
            "source_order": self.source_order_input.text().strip() or "zip,git,api",
            "theme": self._theme,
            "window_width": self.width(),
            "window_height": self.height(),
        }
        save_settings(payload)

    def _append_log(self, message: str, level: str = "info") -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        level_label = level.upper()
        self.log_output.appendPlainText(f"[{timestamp}] [{level_label}] {message}")
        self.log_output.verticalScrollBar().setValue(self.log_output.verticalScrollBar().maximum())

    def _format_bytes(self, value: int) -> str:
        size = float(max(0, value))
        units = ["B", "KB", "MB", "GB", "TB"]
        unit_index = 0
        while size >= 1024 and unit_index < len(units) - 1:
            size /= 1024.0
            unit_index += 1
        return f"{size:.1f} {units[unit_index]}"

    def _set_status(self, message: str) -> None:
        self.status_label.setText(message)

    def _set_extract_progress_visible(self, visible: bool) -> None:
        self.extract_progress_bar.setVisible(visible)
        self.extract_item_label.setVisible(visible)

    def _set_install_progress_visible(self, visible: bool) -> None:
        self.install_progress_bar.setVisible(visible)
        self.install_item_label.setVisible(visible)

    def _show_toast(self, message: str, duration_ms: int = 4500) -> None:
        if self._toast_label is not None:
            self._toast_label.hide()
            self._toast_label.deleteLater()
            self._toast_label = None

        toast = QLabel(message, self)
        toast.setObjectName("Toast")
        toast.setAlignment(Qt.AlignCenter)
        toast.setWordWrap(True)
        toast.setMargin(10)
        toast.setMinimumWidth(360)
        toast.setMaximumWidth(max(360, int(self.width() * 0.55)))
        toast.adjustSize()
        x = max(18, self.width() - toast.width() - 22)
        y = max(18, self.height() - toast.height() - 22)
        toast.move(x, y)
        toast.show()
        toast.raise_()
        self._toast_label = toast
        QTimer.singleShot(duration_ms, toast.hide)

    def _start_run(self) -> None:
        if self._state != "idle":
            return

        self._clear_runtime_cache()
        self._persist_settings()
        self._terminal_event = None
        self._cancel_requested = False
        self._stdout_buffer = ""
        self._stderr_buffer = ""
        self.overall_progress_bar.setValue(0)
        self.download_progress_bar.setRange(0, 100)
        self.download_progress_bar.setValue(0)
        self.download_item_label.setText("No active font download.")
        self._current_download_item = ""
        self.extract_progress_bar.setValue(0)
        self.extract_item_label.setText("ZIP extraction has not started.")
        self._current_extract_item = ""
        self._set_extract_progress_visible(False)
        self.install_progress_bar.setValue(0)
        self.install_item_label.setText("Font installation has not started.")
        self._current_install_item = ""
        self._set_install_progress_visible(False)
        self._last_output_folder = ""
        self.install_fonts_button.setEnabled(False)

        try:
            worker_script = self._ensure_runtime_worker_copy()
        except Exception as exc:  # noqa: BLE001
            self._append_log(f"Cannot prepare worker script: {exc}", "error")
            self._set_status("Worker script preparation failed.")
            return

        control_dir = Path(tempfile.gettempdir()) / "GoogleFontsLibraryDownloader" / "control"
        control_dir.mkdir(parents=True, exist_ok=True)
        self._control_file_path = control_dir / f"stop-{uuid.uuid4().hex}.signal"
        if self._control_file_path.exists():
            self._control_file_path.unlink(missing_ok=True)

        downloads_root = self.downloads_root_input.text().strip() or str(Path.home() / "Downloads")
        base_folder_name = self.base_folder_input.text().strip() or "Google Fonts 2026"
        api_key = self.api_key_input.text().strip()
        source_order = self._parse_source_order()

        args: list[str] = [
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(worker_script),
            "-DownloadsRoot",
            downloads_root,
            "-BaseFolderName",
            base_folder_name,
            "-SourceOrder",
            *source_order,
            "-ControlFilePath",
            str(self._control_file_path),
            "-EmitGuiEvents",
        ]

        if api_key:
            args.extend(["-ApiKey", api_key])

        self._append_log("Starting worker process.", "info")
        self._append_log(f"Source order: {', '.join(source_order)}", "info")
        self._process.start("powershell.exe", args)
        if not self._process.waitForStarted(6000):
            self._append_log("Failed to start PowerShell worker process.", "error")
            self._set_status("Failed to start worker.")
            return

        self._state = "running"
        self._set_status("Running")
        self._update_button_states()

    def _toggle_pause(self) -> None:
        if self._state not in {"running", "paused"}:
            return
        pid = int(self._process.processId())
        if pid <= 0:
            return

        try:
            if self._state == "running":
                result = suspend_process_tree(pid)
                self._append_log(
                    f"Paused process tree (succeeded: {result.succeeded}/{result.attempted}).",
                    "info",
                )
                self._state = "paused"
                self._set_status("Paused")
            else:
                result = resume_process_tree(pid)
                self._append_log(
                    f"Resumed process tree (succeeded: {result.succeeded}/{result.attempted}).",
                    "info",
                )
                self._state = "running"
                self._set_status("Running")
        except Exception as exc:  # noqa: BLE001
            self._append_log(f"Pause/resume failed: {exc}", "error")

        self._update_button_states()

    def _stop_gracefully(self) -> None:
        if self._state not in {"running", "paused"}:
            return
        if self._control_file_path is None:
            return

        if self._state == "paused":
            self._toggle_pause()

        self._control_file_path.write_text("stop", encoding="utf-8")
        self._state = "stopping"
        self._set_status("Stopping gracefully")
        self._append_log("Stop requested. Waiting for safe shutdown point.", "warning")
        self._update_button_states()

    def _cancel_immediately(self) -> None:
        if self._state not in {"running", "paused", "stopping"}:
            return

        self._cancel_requested = True
        pid = int(self._process.processId())
        if pid > 0:
            try:
                result = terminate_process_tree(pid)
                self._append_log(
                    f"Cancel requested. Terminated process tree (succeeded: {result.succeeded}/{result.attempted}).",
                    "warning",
                )
            except Exception as exc:  # noqa: BLE001
                self._append_log(f"Process-tree termination issue: {exc}", "warning")

        self._process.kill()
        self._set_status("Canceling")
        self._state = "stopping"
        self._update_button_states()

    def _on_stdout_ready(self) -> None:
        raw = self._decode_process_bytes(bytes(self._process.readAllStandardOutput()))
        self._stdout_buffer += raw
        self._stdout_buffer = self._consume_text_buffer(self._stdout_buffer, is_error=False)

    def _on_stderr_ready(self) -> None:
        raw = self._decode_process_bytes(bytes(self._process.readAllStandardError()))
        self._stderr_buffer += raw
        self._stderr_buffer = self._consume_text_buffer(self._stderr_buffer, is_error=True)

    def _on_install_stdout_ready(self) -> None:
        raw = self._decode_process_bytes(bytes(self._install_process.readAllStandardOutput()))
        self._install_stdout_buffer += raw
        self._install_stdout_buffer = self._consume_install_buffer(self._install_stdout_buffer, is_error=False)

    def _on_install_stderr_ready(self) -> None:
        raw = self._decode_process_bytes(bytes(self._install_process.readAllStandardError()))
        self._install_stderr_buffer += raw
        self._install_stderr_buffer = self._consume_install_buffer(self._install_stderr_buffer, is_error=True)

    def _decode_process_bytes(self, payload: bytes) -> str:
        if not payload:
            return ""
        # PowerShell 5.1 can output UTF-16LE to redirected streams.
        if b"\x00" in payload:
            try:
                return payload.decode("utf-16-le", errors="replace")
            except UnicodeDecodeError:
                pass
        return payload.decode("utf-8", errors="replace")

    def _consume_text_buffer(self, buffer: str, is_error: bool) -> str:
        normalized = buffer.replace("\r\n", "\n").replace("\r", "\n")
        parts = normalized.split("\n")
        completed = parts[:-1]
        remainder = parts[-1] if parts else ""
        for line in completed:
            self._handle_output_line(line, is_error=is_error)
        return remainder

    def _consume_install_buffer(self, buffer: str, is_error: bool) -> str:
        normalized = buffer.replace("\r\n", "\n").replace("\r", "\n")
        parts = normalized.split("\n")
        completed = parts[:-1]
        remainder = parts[-1] if parts else ""
        for line in completed:
            self._handle_install_output_line(line, is_error=is_error)
        return remainder

    def _handle_output_line(self, raw_line: str, is_error: bool) -> None:
        line = raw_line.strip()
        if not line:
            return

        gui_event = parse_gui_event_line(line)
        if gui_event is not None:
            self._handle_gui_event(gui_event)
            return

        self._append_log(line, "error" if is_error else "info")

    def _handle_install_output_line(self, raw_line: str, is_error: bool) -> None:
        line = raw_line.strip()
        if not line:
            return

        gui_event = parse_gui_event_line(line)
        if gui_event is not None:
            self._handle_gui_event(gui_event)
            return

        prefix = "[INSTALL] "
        self._append_log(prefix + line, "error" if is_error else "info")

    def _handle_gui_event(self, event: GuiEvent) -> None:
        payload = event.payload
        if event.name == "status":
            message = str(payload.get("message", "")).strip()
            level = str(payload.get("level", "info")).strip().lower()
            if message:
                self._append_log(message, level if level else "info")
                self._set_status(message)
            return

        if event.name == "task_progress":
            message = str(payload.get("message", ""))
            source = str(payload.get("source", "task"))
            if message:
                self._set_status(f"[{source}] {message}")
            return

        if event.name == "overall_progress":
            percent = int(float(payload.get("percent", 0)))
            self.overall_progress_bar.setValue(max(0, min(100, percent)))
            return

        if event.name == "download_progress":
            percent_raw = float(payload.get("percent", -1))
            item = str(payload.get("item", "")).strip()
            bytes_read = int(float(payload.get("bytesRead", 0)))
            total_bytes = int(float(payload.get("totalBytes", 0)))
            indeterminate = bool(payload.get("indeterminate", False)) or percent_raw < 0

            if indeterminate:
                self.download_progress_bar.setRange(0, 0)
            else:
                self.download_progress_bar.setRange(0, 100)
                self.download_progress_bar.setValue(max(0, min(100, int(percent_raw))))
            if item:
                self._current_download_item = item

            if self._current_download_item:
                if indeterminate:
                    progress_text = f"{self._current_download_item} ({self._format_bytes(bytes_read)})"
                elif total_bytes > 0:
                    progress_text = f"{self._current_download_item} ({self._format_bytes(bytes_read)} / {self._format_bytes(total_bytes)})"
                else:
                    progress_text = f"{self._current_download_item} ({self._format_bytes(bytes_read)})"
                self.download_item_label.setText(progress_text)
            return

        if event.name == "extract_progress":
            percent = int(float(payload.get("percent", 0)))
            item = str(payload.get("item", "")).strip()
            entries_processed = int(float(payload.get("entriesProcessed", 0)))
            total_entries = int(float(payload.get("totalEntries", 0)))

            self._set_extract_progress_visible(True)
            self.extract_progress_bar.setValue(max(0, min(100, percent)))
            if item:
                self._current_extract_item = item

            if total_entries > 0:
                self.extract_item_label.setText(
                    f"{self._current_extract_item} ({entries_processed} / {total_entries})"
                )
            elif self._current_extract_item:
                self.extract_item_label.setText(self._current_extract_item)
            return

        if event.name == "install_progress":
            percent = int(float(payload.get("percent", 0)))
            font_name = str(payload.get("font", "")).strip()
            current = int(float(payload.get("current", 0)))
            total = int(float(payload.get("total", 0)))

            self._set_install_progress_visible(True)
            self.install_progress_bar.setValue(max(0, min(100, percent)))
            if font_name:
                self._current_install_item = font_name
            if total > 0 and self._current_install_item:
                self.install_item_label.setText(
                    f"Installing {self._current_install_item} ({current} / {total})"
                )
            elif self._current_install_item:
                self.install_item_label.setText(f"Installing {self._current_install_item}")
            return

        if event.name == "install_completed":
            message = str(payload.get("message", "Font installation complete.")).strip()
            self.install_progress_bar.setValue(100)
            self.install_item_label.setText(message)
            self._set_status(message)
            self._append_log(message, "info")
            self._show_toast(message)
            return

        if event.name == "install_failed":
            message = str(payload.get("message", "Font installation failed.")).strip()
            self.install_item_label.setText(message)
            self._append_log(message, "error")
            self._set_status(message)
            return

        if event.name in {"completed", "failed"}:
            self._terminal_event = {"type": event.name, "payload": payload}
            output_folder = str(payload.get("outputFolder", "")).strip()
            if output_folder:
                self._last_output_folder = output_folder
            if event.name == "failed":
                message = str(payload.get("message", "Execution failed."))
                self._append_log(message, "error")
                self._set_status(message)
            return

    def _on_process_error(self, process_error: QProcess.ProcessError) -> None:
        self._append_log(f"Process error: {process_error}.", "error")

    def _on_install_process_error(self, process_error: QProcess.ProcessError) -> None:
        self._append_log(f"Install process error: {process_error}.", "error")

    def _on_process_finished(self, exit_code: int, _exit_status: QProcess.ExitStatus) -> None:
        if self._stdout_buffer:
            self._handle_output_line(self._stdout_buffer, is_error=False)
            self._stdout_buffer = ""
        if self._stderr_buffer:
            self._handle_output_line(self._stderr_buffer, is_error=True)
            self._stderr_buffer = ""

        outcome = "failed"
        message = f"Run finished with exit code {exit_code}."

        if self._cancel_requested:
            outcome = "canceled"
            message = "Canceled by user."
        elif self._terminal_event is not None:
            event_type = self._terminal_event.get("type")
            payload = self._terminal_event.get("payload", {})
            if event_type == "completed":
                completed_outcome = str(payload.get("outcome", "success"))
                if completed_outcome == "stopped":
                    outcome = "stopped"
                    message = "Stopped gracefully."
                else:
                    outcome = "success"
                    message = "Completed successfully."
            elif event_type == "failed":
                outcome = "failed"
                message = str(payload.get("message", "Execution failed."))
        else:
            if exit_code == 0:
                outcome = "success"
                message = "Completed successfully."
            elif exit_code == 2:
                outcome = "stopped"
                message = "Stopped gracefully."

        if outcome == "success":
            self.overall_progress_bar.setValue(100)
            self.download_progress_bar.setRange(0, 100)
            self.download_progress_bar.setValue(100)
            if self.extract_progress_bar.isVisible():
                self.extract_progress_bar.setValue(100)
            self._append_log(message, "info")
            self.install_fonts_button.setEnabled(True)
            self._show_toast("Download and extraction are done. Fonts are ready to be installed.")
            if self._last_output_folder:
                answer = QMessageBox.question(
                    self,
                    "Install Fonts",
                    "Fonts downloaded. Do you want to run Install All Fonts now?",
                    QMessageBox.Yes | QMessageBox.No,
                    QMessageBox.Yes,
                )
                if answer == QMessageBox.Yes:
                    self._install_all_fonts()
        elif outcome == "stopped":
            self._append_log(message, "warning")
            self.overall_progress_bar.setValue(0)
            self.download_progress_bar.setRange(0, 100)
            self.download_progress_bar.setValue(0)
            self.download_item_label.setText("No active font download.")
            self.extract_progress_bar.setValue(0)
            self.extract_item_label.setText("ZIP extraction has not started.")
            self._set_extract_progress_visible(False)
        elif outcome == "canceled":
            self._append_log(message, "warning")
            self.overall_progress_bar.setValue(0)
            self.download_progress_bar.setRange(0, 100)
            self.download_progress_bar.setValue(0)
            self.download_item_label.setText("No active font download.")
            self.extract_progress_bar.setValue(0)
            self.extract_item_label.setText("ZIP extraction has not started.")
            self._set_extract_progress_visible(False)
        else:
            self._append_log(message, "error")
            self.overall_progress_bar.setValue(0)
            self.download_progress_bar.setRange(0, 100)
            self.download_progress_bar.setValue(0)
            self.download_item_label.setText("No active font download.")
            self.extract_progress_bar.setValue(0)
            self.extract_item_label.setText("ZIP extraction has not started.")
            self._set_extract_progress_visible(False)

        self._set_status(message)
        self._cleanup_control_file()
        self._state = "idle"
        self._cancel_requested = False
        self._terminal_event = None
        self._update_button_states()

    def _on_install_process_finished(self, exit_code: int, _exit_status: QProcess.ExitStatus) -> None:
        if self._install_stdout_buffer:
            self._handle_install_output_line(self._install_stdout_buffer, is_error=False)
            self._install_stdout_buffer = ""
        if self._install_stderr_buffer:
            self._handle_install_output_line(self._install_stderr_buffer, is_error=True)
            self._install_stderr_buffer = ""

        if exit_code == 0:
            self.install_progress_bar.setValue(100)
            if not self.install_item_label.text().strip():
                self.install_item_label.setText("Font installation complete.")
            self._append_log("Font installation process completed.", "info")
        else:
            if self.install_progress_bar.value() >= 100:
                self.install_progress_bar.setValue(99)
            self._append_log(f"Font installation process finished with exit code {exit_code}.", "error")
            if self.install_item_label.text() == "Font installation has not started.":
                self.install_item_label.setText("Font installation failed.")

        self._install_in_progress = False
        self.install_fonts_button.setEnabled(bool(self._last_output_folder))
        self._update_button_states()

    def _install_all_fonts(self) -> None:
        if not self._last_output_folder:
            self._append_log("No completed output folder found yet.", "warning")
            return
        if self._state != "idle":
            self._append_log("Wait for the current run to finish before installing fonts.", "warning")
            return
        if self._install_in_progress:
            self._append_log("Font installation is already running.", "warning")
            return

        helper_script = Path(self._last_output_folder) / "Install-All-Fonts.ps1"
        if not helper_script.exists():
            self._append_log(f"Installer helper not found: {helper_script}", "error")
            return

        self._install_in_progress = True
        self.install_fonts_button.setEnabled(False)
        self.install_progress_bar.setValue(0)
        self.install_item_label.setText("Preparing font installation...")
        self._current_install_item = ""
        self._set_install_progress_visible(True)
        self._set_status("Installing fonts")
        self._append_log("Starting Install-All-Fonts with live progress.", "info")
        self._install_stdout_buffer = ""
        self._install_stderr_buffer = ""
        self._install_process.start(
            "powershell.exe",
            [
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(helper_script),
                "-EmitGuiEvents",
            ],
        )
        if not self._install_process.waitForStarted(5000):
            self._install_in_progress = False
            self.install_fonts_button.setEnabled(True)
            self._append_log("Failed to start Install-All-Fonts process.", "error")
            self._set_status("Install helper failed to start.")
        self._update_button_states()

    def _cleanup_control_file(self) -> None:
        if self._control_file_path and self._control_file_path.exists():
            self._control_file_path.unlink(missing_ok=True)
        self._control_file_path = None

    def _update_button_states(self) -> None:
        is_idle = self._state == "idle"
        is_running = self._state == "running"
        is_paused = self._state == "paused"
        is_stopping = self._state == "stopping"
        is_installing = self._install_in_progress

        self.start_button.setEnabled(is_idle and not is_installing)
        self.pause_button.setEnabled(is_running or is_paused)
        self.stop_button.setEnabled(is_running or is_paused)
        self.cancel_button.setEnabled(is_running or is_paused or is_stopping)
        self.install_fonts_button.setEnabled(is_idle and (not is_installing) and bool(self._last_output_folder))
        self.pause_button.setText("Resume" if is_paused else "Pause")

    def closeEvent(self, event: QCloseEvent) -> None:  # noqa: N802
        if self._state in {"running", "paused", "stopping"}:
            answer = QMessageBox.question(
                self,
                "Process Is Running",
                "A run is still active. Cancel it and close the app?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer != QMessageBox.Yes:
                event.ignore()
                return
            self._cancel_immediately()
        elif self._install_in_progress:
            answer = QMessageBox.question(
                self,
                "Installation In Progress",
                "Font installation is running. Stop installation and close the app?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer != QMessageBox.Yes:
                event.ignore()
                return
            self._install_process.kill()
            self._install_in_progress = False

        self._persist_settings()
        super().closeEvent(event)


def main() -> int:
    app = QApplication(sys.argv)
    app.setFont(QFont("Bahnschrift", 10))
    window = GoogleFontsLibraryDownloaderWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
