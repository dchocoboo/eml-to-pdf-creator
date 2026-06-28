#!/usr/bin/env python3
"""Convert MailKit queued EML files to PDFs."""

from __future__ import annotations

import html
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = Path(__file__).resolve().parents[2]
EXTENSION_LIBRARY_DIR = (
    Path.home()
    / "Library"
    / "Containers"
    / "com.local.pdfmail.extension"
    / "Data"
    / "Library"
)
LEGACY_EXTENSION_LIBRARY_DIR = (
    Path.home()
    / "Library"
    / "Containers"
    / "com.local.mailtonotes.extension"
    / "Data"
    / "Library"
)
PDFMAIL_DIR = (
    EXTENSION_LIBRARY_DIR
    / "Application Support"
    / "pdfmail"
)
LEGACY_MAILTONOTES_DIR = (
    LEGACY_EXTENSION_LIBRARY_DIR
    / "Application Support"
    / "MailToNotes"
)
QUEUE_DIR = PDFMAIL_DIR / "Incoming"
DEFAULT_OUTPUT_DIR = Path.home() / "Documents" / "pdfmail PDFs"
SETTINGS_JSON = PDFMAIL_DIR / "config.json"
LEGACY_SETTINGS_JSON = LEGACY_MAILTONOTES_DIR / "config.json"
SETTINGS_PLIST = (
    EXTENSION_LIBRARY_DIR
    / "Preferences"
    / "com.local.pdfmail.settings.plist"
)
LEGACY_SETTINGS_PLIST = (
    LEGACY_EXTENSION_LIBRARY_DIR
    / "Preferences"
    / "com.local.mailtonotes.settings.plist"
)
DEFAULT_NOTES_FOLDER = "Purchases"
DEFAULT_CREATE_APPLE_NOTES = False
ATTACH_PDF_TO_NOTE = False
USE_SHORTCUTS_FOR_NOTES = True
NOTES_SHORTCUTS = ("pdfmail Create Note", "MailToNotes Create Note")

sys.path.insert(0, str(next(
    path for path in [REPO_ROOT, SCRIPT_DIR, SCRIPT_DIR.parent]
    if (path / "eml_to_image.py").exists()
)))
from eml_to_image import convert_eml  # noqa: E402


def main() -> int:
    output_dir = output_directory()
    QUEUE_DIR.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    eml_files = sorted(QUEUE_DIR.glob("*.eml"))
    if not eml_files:
        print(f"No queued .eml files found in {QUEUE_DIR}")
        return 0

    processed_subjects: list[str] = []

    for eml_path in eml_files:
        metadata = read_metadata(eml_path)
        pdf_path = output_dir / f"{eml_path.stem}.pdf"
        print(f"Processing {eml_path.name}")

        convert_eml(str(eml_path), str(output_dir))
        if create_apple_notes():
            try:
                create_note(metadata, pdf_path)
            except Exception as error:
                print(f"Warning: PDF was created but Apple Notes update failed: {error}")
        else:
            print("Apple Notes creation is currently disabled; PDF only.")

        processed_subjects.append(metadata.get("subject") or eml_path.stem)

        metadata_path = eml_path.with_suffix(".json")
        if metadata_path.exists():
            metadata_path.unlink()
        if eml_path.exists():
            eml_path.unlink()

    notify_processed(processed_subjects)
    return 0


def read_metadata(eml_path: Path) -> dict[str, str]:
    metadata_path = eml_path.with_suffix(".json")
    if not metadata_path.exists():
        return {
            "subject": eml_path.stem,
            "from": "Unknown",
        }

    with metadata_path.open("r", encoding="utf-8") as file:
        return json.load(file)


def create_note(metadata: dict[str, str], pdf_path: Path) -> None:
    subject = metadata.get("subject") or pdf_path.stem
    note_title = f"Purchase - {subject}"

    shortcut_name = available_notes_shortcut()
    if USE_SHORTCUTS_FOR_NOTES and shortcut_name:
        create_note_with_shortcut(pdf_path, note_title, shortcut_name)
        return

    sender = metadata.get("from") or "Unknown"
    body = (
        "<html><body>"
        f"<p><b>Subject:</b> {html.escape(subject)}</p>"
        f"<p><b>From:</b> {html.escape(sender)}</p>"
        "</body></html>"
    )

    script = """
on run argv
    set notesFolderName to item 1 of argv
    set noteTitle to item 2 of argv
    set noteBody to item 3 of argv
    set pdfPath to item 4 of argv
    set attachPdfToNote to item 5 of argv

    tell application "Notes"
        if not (exists folder notesFolderName of default account) then
            make new folder at default account with properties {name:notesFolderName}
        end if

        set targetFolder to folder notesFolderName of default account
        set newNote to make new note at targetFolder with properties {name:noteTitle, body:noteBody}

        if attachPdfToNote is "true" then
            try
                set pdfAlias to POSIX file pdfPath as alias
                make new attachment at end of attachments of newNote with data pdfAlias
            end try
        end if
    end tell
end run
"""

    subprocess.run(
        [
            "osascript",
            "-e",
            script,
            notes_folder(),
            note_title,
            body,
            str(pdf_path),
            str(ATTACH_PDF_TO_NOTE).lower(),
        ],
        check=True,
    )


def create_note_with_shortcut(pdf_path: Path, note_title: str, shortcut_name: str) -> None:
    shortcut_pdf_path = copy_pdf_for_shortcut(pdf_path, note_title)
    subprocess.run(
        [
            "shortcuts",
            "run",
            shortcut_name,
            "--input-path",
            str(shortcut_pdf_path),
        ],
        check=True,
    )


def copy_pdf_for_shortcut(pdf_path: Path, note_title: str) -> Path:
    safe_stem = re.sub(r'[:/\\*?"<>|\r\n\t]', "-", note_title)
    safe_stem = re.sub(r"\s+", " ", safe_stem).strip() or pdf_path.stem
    safe_stem = safe_stem[:160]
    shortcut_dir = Path(tempfile.mkdtemp(prefix="pdfmail-shortcut-"))
    shortcut_pdf_path = shortcut_dir / f"{safe_stem}.pdf"
    shutil.copy2(pdf_path, shortcut_pdf_path)
    return shortcut_pdf_path


def available_notes_shortcut() -> str | None:
    try:
        result = subprocess.run(
            ["shortcuts", "list"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None

    shortcuts = {line.strip() for line in result.stdout.splitlines()}
    return next((name for name in NOTES_SHORTCUTS if name in shortcuts), None)


def notes_folder() -> str:
    value = str(read_settings().get("notesFolder", "")).strip()
    return value or DEFAULT_NOTES_FOLDER


def create_apple_notes() -> bool:
    value = read_settings().get("createAppleNotes", DEFAULT_CREATE_APPLE_NOTES)
    return value is True


def output_directory() -> Path:
    value = str(read_settings().get("outputDirectory", "")).strip()
    return Path(value).expanduser() if value else DEFAULT_OUTPUT_DIR


def read_settings() -> dict[str, object]:
    for settings_plist in (SETTINGS_PLIST, LEGACY_SETTINGS_PLIST):
        if settings_plist.exists():
            with settings_plist.open("rb") as file:
                return plistlib.load(file)

    for settings_json in (SETTINGS_JSON, LEGACY_SETTINGS_JSON):
        if settings_json.exists():
            with settings_json.open("r", encoding="utf-8") as file:
                return json.load(file)

    return {}


def notify_processed(subjects: list[str]) -> None:
    if not subjects:
        return

    if len(subjects) == 1:
        title = "Email processed"
        message = truncate(subjects[0])
    else:
        title = f"{len(subjects)} emails processed"
        message = "Created PDFs."

    script = """
on run argv
    set notificationTitle to item 1 of argv
    set notificationMessage to item 2 of argv

    display notification notificationMessage with title notificationTitle subtitle "pdfmail"
end run
"""

    subprocess.run(["osascript", "-e", script, title, message], check=False)


def truncate(value: str, limit: int = 80) -> str:
    value = " ".join(value.split())
    if len(value) <= limit:
        return value

    return f"{value[:limit - 1]}..."


if __name__ == "__main__":
    raise SystemExit(main())
