#!/usr/bin/env python3
"""Convert MailKit queued EML files to PDFs and Apple Notes."""

from __future__ import annotations

import html
import json
import plistlib
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EXTENSION_LIBRARY_DIR = (
    Path.home()
    / "Library"
    / "Containers"
    / "com.local.mailtonotes.extension"
    / "Data"
    / "Library"
)
MAILTONOTES_DIR = (
    EXTENSION_LIBRARY_DIR
    / "Application Support"
    / "MailToNotes"
)
QUEUE_DIR = MAILTONOTES_DIR / "Incoming"
DEFAULT_OUTPUT_DIR = Path.home() / "Documents" / "MailToNotes PDFs"
SETTINGS_JSON = MAILTONOTES_DIR / "config.json"
SETTINGS_PLIST = (
    EXTENSION_LIBRARY_DIR
    / "Preferences"
    / "com.local.mailtonotes.settings.plist"
)
DEFAULT_NOTES_FOLDER = "Purchases"

sys.path.insert(0, str(REPO_ROOT))
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
        create_note(metadata, pdf_path)
        processed_subjects.append(metadata.get("subject") or eml_path.stem)

        metadata_path = eml_path.with_suffix(".json")
        if metadata_path.exists():
            metadata_path.unlink()
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
    sender = metadata.get("from") or "Unknown"
    note_title = f"Purchase - {subject}"
    pdf_url = pdf_path.as_uri()
    body = (
        "<html><body>"
        f"<h1>{html.escape(subject)}</h1>"
        f"<p><strong>From:</strong> {html.escape(sender)}</p>"
        f'<p><strong>PDF:</strong> <a href="{html.escape(pdf_url)}">{html.escape(str(pdf_path))}</a></p>'
        "</body></html>"
    )

    script = """
on run argv
    set notesFolderName to item 1 of argv
    set noteTitle to item 2 of argv
    set noteBody to item 3 of argv
    set pdfPath to item 4 of argv

    tell application "Notes"
        if not (exists folder notesFolderName of default account) then
            make new folder at default account with properties {name:notesFolderName}
        end if

        set targetFolder to folder notesFolderName of default account
        set newNote to make new note at targetFolder with properties {name:noteTitle, body:noteBody}

        try
            set pdfAlias to POSIX file pdfPath as alias
            make new attachment at end of attachments of newNote with data pdfAlias
        end try
    end tell
end run
"""

    subprocess.run(
        ["osascript", "-e", script, notes_folder(), note_title, body, str(pdf_path)],
        check=True,
    )


def notes_folder() -> str:
    value = str(read_settings().get("notesFolder", "")).strip()
    return value or DEFAULT_NOTES_FOLDER


def output_directory() -> Path:
    value = str(read_settings().get("outputDirectory", "")).strip()
    return Path(value).expanduser() if value else DEFAULT_OUTPUT_DIR


def read_settings() -> dict[str, object]:
    if SETTINGS_PLIST.exists():
        with SETTINGS_PLIST.open("rb") as file:
            return plistlib.load(file)

    if SETTINGS_JSON.exists():
        with SETTINGS_JSON.open("r", encoding="utf-8") as file:
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
        message = "Created PDFs and Apple Notes."

    script = """
on run argv
    set notificationTitle to item 1 of argv
    set notificationMessage to item 2 of argv

    display notification notificationMessage with title notificationTitle subtitle "MailToNotes"
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
