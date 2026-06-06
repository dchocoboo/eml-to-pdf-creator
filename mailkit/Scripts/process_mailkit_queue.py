#!/usr/bin/env python3
"""Convert MailKit queued EML files to PDFs and Apple Notes."""

from __future__ import annotations

import html
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MAILTONOTES_DIR = (
    Path.home()
    / "Library"
    / "Containers"
    / "com.local.mailtonotes.extension"
    / "Data"
    / "Library"
    / "Application Support"
    / "MailToNotes"
)
QUEUE_DIR = MAILTONOTES_DIR / "Incoming"
OUTPUT_DIR = REPO_ROOT / "output"
SETTINGS_JSON = MAILTONOTES_DIR / "config.json"
DEFAULT_NOTES_FOLDER = "Purchases"

sys.path.insert(0, str(REPO_ROOT))
from eml_to_image import convert_eml  # noqa: E402


def main() -> int:
    QUEUE_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    eml_files = sorted(QUEUE_DIR.glob("*.eml"))
    if not eml_files:
        print(f"No queued .eml files found in {QUEUE_DIR}")
        return 0

    for eml_path in eml_files:
        metadata = read_metadata(eml_path)
        pdf_path = OUTPUT_DIR / f"{eml_path.stem}.pdf"
        print(f"Processing {eml_path.name}")

        convert_eml(str(eml_path), str(OUTPUT_DIR))
        create_note(metadata, pdf_path)

        metadata_path = eml_path.with_suffix(".json")
        if metadata_path.exists():
            metadata_path.unlink()
        eml_path.unlink()

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
    if not SETTINGS_JSON.exists():
        return DEFAULT_NOTES_FOLDER

    with SETTINGS_JSON.open("r", encoding="utf-8") as file:
        value = json.load(file).get("notesFolder", "").strip()
        return value or DEFAULT_NOTES_FOLDER


if __name__ == "__main__":
    raise SystemExit(main())
