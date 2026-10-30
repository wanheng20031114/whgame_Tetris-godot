"""Finite fake-worker integration tests; never launches Godot or binds a port."""
import ctypes
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

RUNNER = Path(__file__).with_name("safe_run.py")


@unittest.skipUnless(os.name == "nt", "Windows Job Object tests")
class SafeRunTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="safe-run-test-", dir=RUNNER.parent)
        self.root = Path(self.temp.name).resolve()
        (self.root / "project.godot").write_text(
            '[debug]\nfile_logging/enable_file_logging=false\nfile_logging/enable_file_logging.pc=false\n', encoding="utf-8")
        (self.root / ".safe-run-isolated.json").write_text(json.dumps({
            "kind": "tetris-isolated-test", "project_root": str(self.root),
            "source_root": "C:/Users/wh/Documents/godot/whgame_Tetris-godot"}), encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def run_worker(self, code, extra=(), timeout=2, worker_args=()):
        output = self.root / "run"
        command = [sys.executable, str(RUNNER), "--project", str(self.root),
                   "--output-dir", str(output), "--timeout", str(timeout), *extra,
                   "--", sys.executable, "-u", "-c", code, *worker_args]
        result = subprocess.run(command, capture_output=True, text=True, timeout=12)
        self.assertTrue(result.stdout.strip(), result.stderr)
        return result, json.loads(result.stdout.strip()), output

    def test_success(self):
        result, data, output = self.run_worker("print('worker complete')")
        self.assertEqual(result.returncode, 0, data)
        self.assertEqual(data["remaining_job_processes"], 0)
        self.assertIn(b"worker complete", (output / "process-output.log").read_bytes())

    def test_nonzero_exit(self):
        result, data, _ = self.run_worker("import sys; sys.exit(7)")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(data["child_exit_code"], 7)

    def test_timeout(self):
        result, data, _ = self.run_worker("import time; time.sleep(30)", timeout=0.3)
        self.assertEqual(result.returncode, 124, data)
        self.assertEqual(data["remaining_job_processes"], 0)
        self.assertLess(data["elapsed_seconds"], 7)

    def test_output_budget_both_streams(self):
        result, data, output = self.run_worker(
            "import os; [(os.write(1,b'x'*4096),os.write(2,b'y'*4096)) for _ in range(1000)]",
            extra=("--max-output-bytes", "8192"))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(data["reason"], "output_budget")
        self.assertEqual((output / "process-output.log").stat().st_size, 8192)
        self.assertEqual(data["remaining_job_processes"], 0)

    def test_split_device_failure(self):
        result, data, _ = self.run_worker(
            "import os,time; os.write(2,b'GPU 0x887a'); time.sleep(.1); os.write(2,b'0005'); time.sleep(30)")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(data["reason"], "fatal_output:0x887a0005")

    def test_parent_success_still_kills_grandchild(self):
        child_file = self.root / "child.pid"
        code = ("import subprocess,sys,pathlib; "
                "p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
                f"pathlib.Path({str(child_file)!r}).write_text(str(p.pid))")
        result, data, _ = self.run_worker(code)
        self.assertEqual(result.returncode, 0, data)
        self.assertEqual(data["remaining_job_processes"], 0)
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x100000, False, int(child_file.read_text()))
        if handle:
            try:
                self.assertEqual(kernel.WaitForSingleObject(handle, 0), 0)
            finally:
                kernel.CloseHandle(handle)

    def test_real_or_copied_marker_refused(self):
        marker = self.root / ".safe-run-isolated.json"
        config = json.loads(marker.read_text())
        config["project_root"] = config["source_root"]
        marker.write_text(json.dumps(config), encoding="utf-8")
        result, data, _ = self.run_worker("raise RuntimeError('must not start')")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(data["reason"], "preflight")

    def test_logging_must_be_disabled(self):
        (self.root / "project.godot").write_text('[debug]\nfile_logging/enable_file_logging=false\n')
        result, data, _ = self.run_worker("raise RuntimeError('must not start')")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(data["reason"], "preflight")

    def test_log_file_override_refused(self):
        result, data, _ = self.run_worker("pass", worker_args=("--log-file", "unused"))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(data["reason"], "preflight")

    def test_missing_png_fails(self):
        result, data, _ = self.run_worker("pass", extra=("--expect-png", str(self.root / "run" / "shot.png")))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(data["reason"].startswith("invalid_screenshot:"))

    def test_valid_png(self):
        png = self.root / "run" / "shot.png"
        code = (
            "import struct,zlib,pathlib\n"
            "def chunk(kind,body):\n"
            " return struct.pack('>I',len(body))+kind+body+struct.pack('>I',zlib.crc32(kind+body)&0xffffffff)\n"
            "data=b'\\x89PNG\\r\\n\\x1a\\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b'\\x00\\xff\\x00\\x00\\xff'))+chunk(b'IEND',b'')\n"
            f"pathlib.Path({str(png)!r}).write_bytes(data)\n")
        result, data, _ = self.run_worker(code, extra=("--expect-png", str(png)))
        self.assertEqual(result.returncode, 0, data)

    def test_invalid_png(self):
        png = self.root / "run" / "shot.png"
        result, data, _ = self.run_worker(
            f"import pathlib; pathlib.Path({str(png)!r}).write_bytes(b'not a PNG')",
            extra=("--expect-png", str(png)))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(data["reason"].startswith("invalid_screenshot:"))

    def test_quick_artifact_overflow_still_fails(self):
        artifact = self.root / "run" / "analysis.json"
        result, data, _ = self.run_worker(
            f"import pathlib; pathlib.Path({str(artifact)!r}).write_bytes(b'x'*1024)",
            extra=("--watch-file", str(artifact), "--max-file-bytes", "512"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(data["ok"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SafeRunTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "tests_run": result.testsRun, "successful": result.wasSuccessful(),
            "failures": [{"test": str(test), "traceback": trace} for test, trace in result.failures],
            "errors": [{"test": str(test), "traceback": trace} for test, trace in result.errors],
            "skipped": [{"test": str(test), "reason": reason} for test, reason in result.skipped],
            "scope": "Finite Python fake workers only; no Godot process and no network listener",
            "tree_assertion": "Successful parent exit with live grandchild ends with zero Job Object processes",
            "output_assertion": "Combined stdout/stderr file capped at exactly 8192 bytes in flood test",
        }, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)
