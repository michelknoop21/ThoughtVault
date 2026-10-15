import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("worker", Path(__file__).parents[1] / "faster-whisper-worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerTests(unittest.TestCase):
    def test_offline_cpu_inference_finishes_before_persisting_result(self):
        model = Mock()
        model.transcribe.return_value = (iter([
            SimpleNamespace(text=" Alex plant maandag.", end=5),
            SimpleNamespace(text=" De test is afgerond.", end=10),
        ]), SimpleNamespace(duration=10))
        constructor = Mock(return_value=model)
        with tempfile.TemporaryDirectory() as tmp, patch.dict("sys.modules", {"faster_whisper": SimpleNamespace(WhisperModel=constructor)}):
            output = Path(tmp) / "result.txt"
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                worker.transcribe("model-dir", "audio.wav", output, "Alex")
            constructor.assert_called_once_with("model-dir", device="cpu", compute_type="int8", cpu_threads=4, local_files_only=True)
            self.assertEqual(output.read_text(), "Alex plant maandag. De test is afgerond.")
            progress = [json.loads(line)["progress"] for line in stdout.getvalue().splitlines()]
            self.assertEqual(progress[-1], 100)
            self.assertNotIn("Alex", stdout.getvalue())
            self.assertEqual(model.transcribe.call_args.kwargs["language"], "nl")
            self.assertEqual(model.transcribe.call_args.kwargs["initial_prompt"], "Alex")

    def test_inference_error_does_not_publish_partial_output(self):
        def segments():
            yield SimpleNamespace(text="Partial", end=1)
            raise RuntimeError("inference failed")
        model = Mock()
        model.transcribe.return_value = (segments(), SimpleNamespace(duration=10))
        with tempfile.TemporaryDirectory() as tmp, patch.dict("sys.modules", {"faster_whisper": SimpleNamespace(WhisperModel=Mock(return_value=model))}):
            output = Path(tmp) / "result.txt"
            with self.assertRaisesRegex(RuntimeError, "inference failed"), contextlib.redirect_stdout(io.StringIO()):
                worker.transcribe("model", "audio", output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
