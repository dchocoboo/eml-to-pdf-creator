from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "Scripts" / "process_mailkit_queue.py"
SPEC = importlib.util.spec_from_file_location("process_mailkit_queue", SCRIPT_PATH)
assert SPEC and SPEC.loader
processor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(processor)


class ProcessMailkitQueueTests(unittest.TestCase):
    def test_failure_stays_queued_and_later_email_is_processed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            queue = root / "Incoming"
            output = root / "output"
            queue.mkdir()
            failed = queue / "failed.eml"
            succeeded = queue / "succeeded.eml"
            failed.write_text("failed", encoding="utf-8")
            succeeded.write_text("succeeded", encoding="utf-8")
            (failed.with_suffix(".json")).write_text('{"subject": "Failed"}', encoding="utf-8")
            (succeeded.with_suffix(".json")).write_text('{"subject": "Succeeded"}', encoding="utf-8")

            def convert(source: str, destination: str) -> None:
                if Path(source).name == "failed.eml":
                    raise RuntimeError("bad email")

            with (
                patch.object(processor, "QUEUE_DIR", queue),
                patch.object(processor, "CURRENT_QUEUE_DIRS", (queue,)),
                patch.object(processor, "output_directory", return_value=output),
                patch.object(processor, "convert_eml", side_effect=convert),
                patch.object(processor, "create_apple_notes", return_value=False),
                patch.object(processor, "notify_processed") as notify,
            ):
                self.assertEqual(processor.process_queue(), 1)

            self.assertTrue(failed.exists())
            self.assertTrue(failed.with_suffix(".json").exists())
            self.assertFalse(succeeded.exists())
            self.assertFalse(succeeded.with_suffix(".json").exists())
            notify.assert_called_once_with(["Succeeded"])


if __name__ == "__main__":
    unittest.main()
