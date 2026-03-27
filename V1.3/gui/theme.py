from __future__ import annotations


LIGHT_THEME_QSS = """
QMainWindow, QWidget#Root {
    background: #e9edf4;
    color: #1f2b3a;
    font-family: "Bahnschrift", "Segoe UI", sans-serif;
    font-size: 13px;
}
QFrame#Card {
    background: #e9edf4;
    border: 1px solid #d9e0ea;
    border-radius: 18px;
}
QLabel#HeaderTitle {
    font-size: 24px;
    font-weight: 700;
    color: #17243a;
}
QLabel#SubTitle {
    color: #58657a;
    font-size: 12px;
}
QLabel#SectionTitle {
    font-size: 12px;
    font-weight: 600;
    color: #4a5872;
    letter-spacing: 0.7px;
}
QLineEdit, QPlainTextEdit, QComboBox, QToolButton, QPushButton {
    background: #edf1f7;
    border: 1px solid #d3dbe7;
    border-radius: 14px;
    padding: 8px 12px;
    color: #1f2b3a;
}
QLineEdit:focus, QComboBox:focus {
    border: 1px solid #77b6ff;
    background: #f4f7fb;
}
QPlainTextEdit {
    border-radius: 16px;
    padding: 10px;
    selection-background-color: #b7d8ff;
}
QPushButton {
    min-height: 34px;
    font-weight: 600;
}
QPushButton:hover {
    border-color: #9ec8ff;
}
QPushButton:pressed {
    background: #dde7f3;
}
QPushButton#PrimaryButton {
    color: #f5fbff;
    border: 1px solid #3f90ef;
    background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #46d7ff, stop:0.55 #3a9cff, stop:1 #6f6cff);
}
QPushButton#PrimaryButton:disabled {
    background: #bcc7d6;
    color: #f2f4f8;
    border-color: #bec8d5;
}
QPushButton#SecondaryButton {
    color: #233246;
}
QPushButton#DangerButton {
    background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #ff7f7f, stop:1 #ff6161);
    color: #ffffff;
    border: 1px solid #de5252;
}
QProgressBar {
    border: 1px solid #cfd8e4;
    background: #edf1f7;
    border-radius: 12px;
    text-align: center;
    color: #2d3b51;
    min-height: 18px;
}
QProgressBar::chunk {
    border-radius: 10px;
    background: qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #7de4ff, stop:0.5 #48acff, stop:1 #6d77ff);
}
QSplitter::handle {
    background: #d8e0eb;
    width: 3px;
}
QCheckBox {
    spacing: 8px;
}
QLabel#Toast {
    background: rgba(236, 246, 255, 0.95);
    border: 1px solid #9ec8ff;
    border-radius: 12px;
    color: #173253;
    font-size: 12px;
    font-weight: 600;
}
"""


DARK_THEME_QSS = """
QMainWindow, QWidget#Root {
    background: #0d1426;
    color: #d5e8ff;
    font-family: "Bahnschrift", "Segoe UI", sans-serif;
    font-size: 13px;
}
QFrame#Card {
    background: rgba(22, 34, 58, 0.9);
    border: 1px solid rgba(91, 149, 245, 0.35);
    border-radius: 18px;
}
QLabel#HeaderTitle {
    font-size: 24px;
    font-weight: 700;
    color: #d9e7ff;
}
QLabel#SubTitle {
    color: #94a9c8;
    font-size: 12px;
}
QLabel#SectionTitle {
    font-size: 12px;
    font-weight: 600;
    color: #a8bfe5;
    letter-spacing: 0.8px;
}
QLineEdit, QPlainTextEdit, QComboBox, QToolButton, QPushButton {
    background: rgba(14, 24, 44, 0.88);
    border: 1px solid rgba(93, 135, 211, 0.38);
    border-radius: 14px;
    padding: 8px 12px;
    color: #d7e8ff;
}
QLineEdit:focus, QComboBox:focus {
    border: 1px solid #62d6ff;
    background: rgba(17, 33, 58, 0.9);
}
QPlainTextEdit {
    border-radius: 16px;
    padding: 10px;
    selection-background-color: #245fa4;
}
QPushButton {
    min-height: 34px;
    font-weight: 600;
}
QPushButton:hover {
    border-color: #62d6ff;
}
QPushButton:pressed {
    background: rgba(19, 36, 65, 0.95);
}
QPushButton#PrimaryButton {
    border: 1px solid #51cdff;
    color: #e8f8ff;
    background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #1de4ff, stop:0.5 #2f7bff, stop:1 #9266ff);
}
QPushButton#PrimaryButton:disabled {
    border-color: #375274;
    color: #7f9bc0;
    background: #1a2945;
}
QPushButton#SecondaryButton {
    border: 1px solid rgba(148, 180, 236, 0.4);
    color: #d4e6ff;
}
QPushButton#DangerButton {
    background: qlineargradient(x1:0,y1:0,x2:1,y2:1, stop:0 #ff6f91, stop:1 #ff5252);
    border: 1px solid #ff657f;
    color: #ffffff;
}
QProgressBar {
    border: 1px solid rgba(95, 140, 219, 0.42);
    background: rgba(12, 23, 43, 0.8);
    border-radius: 12px;
    text-align: center;
    color: #c8dcff;
    min-height: 18px;
}
QProgressBar::chunk {
    border-radius: 10px;
    background: qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #2bf4ff, stop:0.52 #3aa1ff, stop:1 #8f65ff);
}
QSplitter::handle {
    background: rgba(85, 130, 205, 0.45);
    width: 3px;
}
QCheckBox {
    spacing: 8px;
}
QLabel#Toast {
    background: rgba(15, 31, 55, 0.96);
    border: 1px solid rgba(104, 196, 255, 0.7);
    border-radius: 12px;
    color: #d8ecff;
    font-size: 12px;
    font-weight: 600;
}
"""
