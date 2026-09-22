from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "Scripts" / "pdfmail_automation.py"
SPEC = importlib.util.spec_from_file_location("pdfmail_automation", SCRIPT_PATH)
assert SPEC and SPEC.loader
automation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(automation)


class PdfmailAutomationTests(unittest.TestCase):
    def test_initialize_and_tool_listing(self) -> None:
        initialize = automation.handle_mcp_message(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {"protocolVersion": "2025-11-25"},
            }
        )
        self.assertEqual(initialize["result"]["protocolVersion"], "2025-11-25")

        tools = automation.handle_mcp_message(
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
        )
        self.assertEqual(
            [tool["name"] for tool in tools["result"]["tools"]],
            ["convert_eml", "get_status", "get_settings", "process_queue", "clear_queue"],
        )

    def test_enqueue_uses_only_current_queue_and_writes_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "Order confirmation.eml"
            source.write_text("Subject: Test\n\nBody", encoding="utf-8")
            queue = root / "current" / "Incoming"
            output = root / "output"

            with (
                patch.object(automation, "QUEUE_DIR", queue),
                patch.object(
                    automation,
                    "read_settings",
                    return_value={"outputDirectory": str(output)},
                ),
            ):
                result = automation.enqueue([str(source)])

            self.assertEqual(len(result), 1)
            queued_path = Path(result[0]["queuedPath"])
            self.assertEqual(queued_path.parent, queue)
            self.assertTrue(queued_path.exists())
            metadata = json.loads(queued_path.with_suffix(".json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["subject"], "Order confirmation")
            self.assertEqual(metadata["from"], "Automation")
            self.assertEqual(Path(result[0]["expectedPDF"]).parent, output)
            self.assertEqual(list(queue.glob("*.tmp")), [])

    def test_convert_tool_rejects_non_array_paths(self) -> None:
        response = automation.handle_mcp_message(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "convert_eml", "arguments": {"paths": "mail.eml"}},
            }
        )
        self.assertTrue(response["result"]["isError"])

    def test_clear_queue_removes_only_supported_current_queue_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            queue = root / "current" / "Incoming"
            queue.mkdir(parents=True)
            lock = root / "current" / "processor.lock"
            legacy = root / "legacy" / "Incoming"
            legacy.mkdir(parents=True)
            for name in ("one.eml", "one.json", "orphan.json", "writing.eml.tmp", "writing.json.tmp"):
                (queue / name).write_text("x", encoding="utf-8")
            (legacy / "keep.eml").write_text("x", encoding="utf-8")

            with patch.object(automation, "QUEUE_DIR", queue), patch.object(automation, "PDFMAIL_DIR", lock.parent), patch.object(automation, "PROCESSOR_LOCK", lock):
                result = automation.clear_current_queue()

            self.assertEqual(result["clearedPendingEmails"], 1)
            self.assertEqual(result["clearedStaleArtifacts"], 4)
            self.assertEqual(list(queue.iterdir()), [])
            self.assertTrue((legacy / "keep.eml").exists())

    def test_clear_queue_refuses_when_processor_lock_is_held(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            queue = root / "Incoming"
            queue.mkdir()
            queued = queue / "keep.eml"
            queued.write_text("x", encoding="utf-8")
            lock = root / "processor.lock"
            with (
                patch.object(automation, "QUEUE_DIR", queue),
                patch.object(automation, "PDFMAIL_DIR", root),
                patch.object(automation, "PROCESSOR_LOCK", lock),
                patch.object(automation.fcntl, "flock", side_effect=BlockingIOError),
                self.assertRaisesRegex(RuntimeError, "processor is running"),
            ):
                automation.clear_current_queue()
            self.assertTrue(queued.exists())

    def test_clear_queue_mcp_metadata_is_destructive(self) -> None:
        clear_tool = next(tool for tool in automation.TOOLS if tool["name"] == "clear_queue")
        self.assertTrue(clear_tool["annotations"]["destructiveHint"])
        self.assertFalse(clear_tool["annotations"]["readOnlyHint"])


if __name__ == "__main__":
    unittest.main()
