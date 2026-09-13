#!/usr/bin/env python3
"""Command-line and stdio MCP automation for pdfmail."""

from __future__ import annotations

import argparse
import fcntl
import json
import plistlib
import re
import shutil
import subprocess
import sys
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

EXTENSION_LIBRARY_DIR = (
    Path.home()
    / "Library"
    / "Containers"
    / "com.local.pdfmail.extension"
    / "Data"
    / "Library"
)
PDFMAIL_DIR = EXTENSION_LIBRARY_DIR / "Application Support" / "pdfmail"
QUEUE_DIR = PDFMAIL_DIR / "Incoming"
SETTINGS_PLIST = EXTENSION_LIBRARY_DIR / "Preferences" / "com.local.pdfmail.settings.plist"
SETTINGS_JSON = PDFMAIL_DIR / "config.json"
PROCESSOR_LOCK = PDFMAIL_DIR / "processor.lock"
DEFAULT_OUTPUT_DIR = Path.home() / "Documents" / "pdfmail PDFs"
DEFAULT_SETTINGS: dict[str, Any] = {
    "keywords": [
        "receipt",
        "invoice",
        "order",
        "purchase",
        "payment",
        "booking",
        "reservation",
        "charged",
    ],
    "notesFolder": "Purchases",
    "createAppleNotes": False,
    "markColor": "green",
    "outputDirectory": str(DEFAULT_OUTPUT_DIR),
}
SUPPORTED_PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")


def read_settings() -> dict[str, Any]:
    loaded: dict[str, Any] = {}
    if SETTINGS_PLIST.exists():
        with SETTINGS_PLIST.open("rb") as file:
            loaded = plistlib.load(file)
    elif SETTINGS_JSON.exists():
        with SETTINGS_JSON.open("r", encoding="utf-8") as file:
            loaded = json.load(file)

    settings = {**DEFAULT_SETTINGS, **loaded}
    settings["outputDirectory"] = str(
        Path(str(settings.get("outputDirectory") or DEFAULT_OUTPUT_DIR)).expanduser()
    )
    settings["createAppleNotes"] = settings.get("createAppleNotes") is True
    return settings


def processor_script() -> Path:
    script_dir = Path(__file__).resolve().parent
    candidates = (
        script_dir / "process_mailkit_queue.py",
        Path(__file__).resolve().parents[2] / "mailkit" / "Scripts" / "process_mailkit_queue.py",
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("The pdfmail queue processor script could not be found.")


def processor_python() -> Path:
    candidates = (
        Path("/opt/homebrew/opt/python@3.14/bin/python3.14"),
        Path("/opt/homebrew/bin/python3"),
        Path(sys.executable),
        Path("/usr/local/bin/python3"),
        Path("/usr/bin/python3"),
    )
    for candidate in candidates:
        if candidate.is_file() and candidate.stat().st_mode & 0o111:
            return candidate
    raise FileNotFoundError("A Python 3 executable could not be found.")


def processor_is_running() -> bool:
    PDFMAIL_DIR.mkdir(parents=True, exist_ok=True)
    with PROCESSOR_LOCK.open("a+", encoding="utf-8") as lock_file:
        acquired = False
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            acquired = True
        except BlockingIOError:
            return True
        finally:
            if acquired:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    return False


def queue_files() -> list[Path]:
    return sorted(QUEUE_DIR.glob("*.eml")) if QUEUE_DIR.exists() else []


def status() -> dict[str, Any]:
    pending = queue_files()
    return {
        "processorRunning": processor_is_running(),
        "queuedCount": len(pending),
        "queuedFiles": [str(path) for path in pending],
        "outputDirectory": read_settings()["outputDirectory"],
    }


def safe_stem(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]+", "-", value).strip("-")
    return (cleaned or "email")[:80]


def enqueue(paths: list[str]) -> list[dict[str, Any]]:
    if not paths:
        raise ValueError("Provide at least one .eml path.")

    resolved: list[Path] = []
    errors: list[str] = []
    for raw_path in paths:
        path = Path(raw_path).expanduser().resolve()
        if path.suffix.lower() != ".eml":
            errors.append(f"Not an .eml file: {path}")
        elif not path.is_file():
            errors.append(f"File does not exist: {path}")
        else:
            resolved.append(path)
    if errors:
        raise ValueError("; ".join(errors))

    QUEUE_DIR.mkdir(parents=True, exist_ok=True)
    output_dir = Path(read_settings()["outputDirectory"])
    queued: list[dict[str, Any]] = []
    for source in resolved:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        destination_stem = f"{stamp}-{safe_stem(source.stem)}-{uuid.uuid4().hex[:8]}"
        eml_path = QUEUE_DIR / f"{destination_stem}.eml"
        temporary_eml = QUEUE_DIR / f"{destination_stem}.eml.tmp"
        metadata_path = QUEUE_DIR / f"{destination_stem}.json"
        temporary_metadata = QUEUE_DIR / f"{destination_stem}.json.tmp"
        metadata = {
            "subject": source.stem,
            "from": "Automation",
            "dateReceived": None,
            "messageID": None,
            "emlFile": eml_path.name,
        }
        try:
            shutil.copy2(source, temporary_eml)
            temporary_metadata.write_text(
                json.dumps(metadata, indent=2, sort_keys=True),
                encoding="utf-8",
            )
            temporary_metadata.replace(metadata_path)
            temporary_eml.replace(eml_path)
        except Exception:
            temporary_eml.unlink(missing_ok=True)
            temporary_metadata.unlink(missing_ok=True)
            metadata_path.unlink(missing_ok=True)
            raise
        queued.append(
            {
                "source": str(source),
                "queuedPath": str(eml_path),
                "expectedPDF": str(output_dir / f"{destination_stem}.pdf"),
            }
        )
    return queued


def process_current_queue() -> dict[str, Any]:
    result = subprocess.run(
        [str(processor_python()), str(processor_script())],
        capture_output=True,
        text=True,
        check=False,
    )
    response = {
        "exitCode": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        "status": status(),
    }
    if result.returncode != 0:
        raise RuntimeError(json.dumps(response, sort_keys=True))
    return response


def convert(paths: list[str]) -> dict[str, Any]:
    queued = enqueue(paths)
    processing = process_current_queue()
    for item in queued:
        item["created"] = Path(item["expectedPDF"]).exists()
    return {"queued": queued, "processing": processing}


TOOLS = [
    {
        "name": "convert_eml",
        "description": "Convert one or more local .eml files with pdfmail's saved output and Apple Notes settings.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "paths": {
                    "type": "array",
                    "items": {"type": "string"},
                    "minItems": 1,
                    "description": "Absolute or home-relative paths to local .eml files.",
                }
            },
            "required": ["paths"],
            "additionalProperties": False,
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False},
    },
    {
        "name": "get_status",
        "description": "Read pdfmail's current queue and processor status.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "get_settings",
        "description": "Read pdfmail's effective conversion settings.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "process_queue",
        "description": "Process only pdfmail's current queue; the historical legacy queue is never included.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False},
    },
]


def tool_result(value: Any, *, is_error: bool = False) -> dict[str, Any]:
    return {
        "content": [{"type": "text", "text": json.dumps(value, indent=2, sort_keys=True)}],
        "isError": is_error,
    }


def call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "convert_eml":
        paths = arguments.get("paths")
        if not isinstance(paths, list) or not all(isinstance(path, str) for path in paths):
            raise ValueError("paths must be an array of strings.")
        return tool_result(convert(paths))
    if name == "get_status":
        return tool_result(status())
    if name == "get_settings":
        return tool_result(read_settings())
    if name == "process_queue":
        return tool_result(process_current_queue())
    raise ValueError(f"Unknown tool: {name}")


def handle_mcp_message(message: dict[str, Any]) -> dict[str, Any] | None:
    request_id = message.get("id")
    method = message.get("method")
    if request_id is None:
        return None

    try:
        if method == "initialize":
            requested = str(message.get("params", {}).get("protocolVersion", ""))
            protocol_version = (
                requested if requested in SUPPORTED_PROTOCOL_VERSIONS else SUPPORTED_PROTOCOL_VERSIONS[0]
            )
            result = {
                "protocolVersion": protocol_version,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "pdfmail", "version": "1.0.0"},
                "instructions": "Convert local .eml files using pdfmail's saved settings. Only the current pdfmail queue is processed.",
            }
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            params = message.get("params") or {}
            try:
                result = call_tool(str(params.get("name", "")), params.get("arguments") or {})
            except Exception as error:
                result = tool_result({"error": str(error)}, is_error=True)
        else:
            return {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            }
        return {"jsonrpc": "2.0", "id": request_id, "result": result}
    except Exception as error:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32603, "message": str(error)},
        }


def run_mcp_server() -> int:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
            response = handle_mcp_message(message)
        except Exception as error:
            response = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": f"Parse error: {error}"},
            }
        if response is not None:
            print(json.dumps(response, separators=(",", ":")), flush=True)
    return 0


def print_json(value: Any) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description="Automate pdfmail or run its MCP server.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status", help="Show the current queue and processor status.")
    subparsers.add_parser("settings", help="Show effective pdfmail settings.")
    convert_parser = subparsers.add_parser("convert", help="Convert local .eml files now.")
    convert_parser.add_argument("paths", nargs="+")
    subparsers.add_parser("process-queue", help="Process the current pdfmail queue.")
    subparsers.add_parser("mcp", help="Run the local stdio MCP server.")
    arguments = parser.parse_args()

    try:
        if arguments.command == "status":
            print_json(status())
        elif arguments.command == "settings":
            print_json(read_settings())
        elif arguments.command == "convert":
            print_json(convert(arguments.paths))
        elif arguments.command == "process-queue":
            print_json(process_current_queue())
        elif arguments.command == "mcp":
            return run_mcp_server()
    except Exception as error:
        print_json({"error": str(error)})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
