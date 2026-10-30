#!/usr/bin/env python3
"""Bounded Windows test runner. Never use this to launch the real project.

python tools/safe_run.py --project . --timeout 30 --output-dir .safe-runs/run-1
    --expect-png .safe-runs/run-1/shot.png -- Godot_console.exe ...

The isolation marker and disabled engine file logging are mandatory, including
for fake workers. The output budget is enforced before writes; watched artifact
limits are polling tripwires, not filesystem quotas. No automatic retries.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import threading
import time
import zlib


MARKER = ".safe-run-isolated.json"
FATAL_SIGNATURES = (
    b"0x887a0005", b"0x887a0006", b"device_hung", b"device_removed",
    b"invalid vertex array", b"invalid index array", b"buffer_create",
    b"script error:", b"parse error:", b"shader compilation failed",
)


def within(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def resolve_inside(raw: str, project: Path) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = project / path
    path = path.resolve()
    if not within(path, project):
        raise ValueError(f"Path is outside isolated project: {path}")
    return path


def check_isolation(project: Path) -> None:
    marker = json.loads((project / MARKER).read_text(encoding="utf-8-sig"))
    if marker.get("kind") != "tetris-isolated-test":
        raise ValueError("Missing explicit isolated-test marker")
    if Path(marker["project_root"]).resolve() != project:
        raise ValueError("Isolation marker belongs to a different directory")
    source = Path(marker["source_root"]).resolve()
    if within(project, source) or within(source, project):
        raise ValueError("Refusing the source project or a directory containing it")
    settings: dict[str, str] = {}
    section = ""
    for raw in (project / "project.godot").read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif "=" in line and not line.startswith(";"):
            key, value = line.split("=", 1)
            settings[f"{section}/{key.strip()}"] = value.strip()
    base = "debug/file_logging/enable_file_logging"
    for key in (base, base + ".pc"):
        if settings.get(key) != "false":
            raise ValueError(f"Isolated project must explicitly set {key}=false")
    if any(value != "false" for key, value in settings.items()
           if key.startswith(base + ".")):
        raise ValueError("A feature override re-enables engine file logging")


def prepare_command(command: list[str], project: Path) -> list[str]:
    if not command:
        raise ValueError("Missing command after --")
    if any(arg == "--log-file" or arg.startswith("--log-file=") for arg in command):
        raise ValueError("--log-file overrides disabled logging and is forbidden")
    result = list(command)
    if "godot" in Path(result[0]).name.lower():
        # Only inspect engine arguments, before Godot's user-argument delimiter.
        engine_end = result.index("--") if "--" in result else len(result)
        paths = [i for i, arg in enumerate(result[:engine_end]) if arg == "--path"]
        if len(paths) > 1 or any(arg.startswith("--path=") for arg in result[:engine_end]):
            raise ValueError("Use at most one explicit --path argument")
        if paths:
            index = paths[0]
            if index + 1 >= engine_end:
                raise ValueError("Missing --path value")
            if resolve_inside(result[index + 1], project) != project:
                raise ValueError("Godot --path must be the isolated project root")
            result[index + 1] = str(project)
        else:
            result[1:1] = ["--path", str(project)]
    return result


class SECURITY_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("nLength", wintypes.DWORD), ("lpSecurityDescriptor", wintypes.LPVOID),
                ("bInheritHandle", wintypes.BOOL)]


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("lpReserved", wintypes.LPWSTR),
                ("lpDesktop", wintypes.LPWSTR), ("lpTitle", wintypes.LPWSTR),
                ("dwX", wintypes.DWORD), ("dwY", wintypes.DWORD),
                ("dwXSize", wintypes.DWORD), ("dwYSize", wintypes.DWORD),
                ("dwXCountChars", wintypes.DWORD), ("dwYCountChars", wintypes.DWORD),
                ("dwFillAttribute", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                ("wShowWindow", wintypes.WORD), ("cbReserved2", wintypes.WORD),
                ("lpReserved2", ctypes.POINTER(ctypes.c_byte)),
                ("hStdInput", wintypes.HANDLE), ("hStdOutput", wintypes.HANDLE),
                ("hStdError", wintypes.HANDLE)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", wintypes.HANDLE), ("hThread", wintypes.HANDLE),
                ("dwProcessId", wintypes.DWORD), ("dwThreadId", wintypes.DWORD)]


class BASIC_LIMIT(ctypes.Structure):
    _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64),
                ("PerJobUserTimeLimit", ctypes.c_int64), ("LimitFlags", wintypes.DWORD),
                ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD),
                ("SchedulingClass", wintypes.DWORD)]


class IO_COUNTERS(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
        "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]


class EXTENDED_LIMIT(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", BASIC_LIMIT), ("IoInfo", IO_COUNTERS),
                ("ProcessMemoryLimit", ctypes.c_size_t), ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t)]


class BASIC_ACCOUNTING(ctypes.Structure):
    _fields_ = [("TotalUserTime", ctypes.c_int64), ("TotalKernelTime", ctypes.c_int64),
                ("ThisPeriodTotalUserTime", ctypes.c_int64), ("ThisPeriodTotalKernelTime", ctypes.c_int64),
                ("TotalPageFaultCount", wintypes.DWORD), ("TotalProcesses", wintypes.DWORD),
                ("ActiveProcesses", wintypes.DWORD), ("TotalTerminatedProcesses", wintypes.DWORD)]


class WindowsJob:
    """Create suspended, assign to job, then resume: descendants cannot escape a race."""
    def __init__(self, command: list[str], cwd: Path, env: dict[str, str]):
        if os.name != "nt":
            raise RuntimeError("This runner requires Windows Job Objects")
        import msvcrt
        self.k = ctypes.WinDLL("kernel32", use_last_error=True)
        signatures = {
            "CreateJobObjectW": ([wintypes.LPVOID, wintypes.LPCWSTR], wintypes.HANDLE),
            "SetInformationJobObject": ([wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD], wintypes.BOOL),
            "QueryInformationJobObject": ([wintypes.HANDLE, ctypes.c_int, wintypes.LPVOID, wintypes.DWORD, wintypes.LPVOID], wintypes.BOOL),
            "AssignProcessToJobObject": ([wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            "TerminateJobObject": ([wintypes.HANDLE, wintypes.UINT], wintypes.BOOL),
            "TerminateProcess": ([wintypes.HANDLE, wintypes.UINT], wintypes.BOOL),
            "CloseHandle": ([wintypes.HANDLE], wintypes.BOOL),
            "CreatePipe": ([ctypes.POINTER(wintypes.HANDLE), ctypes.POINTER(wintypes.HANDLE), ctypes.POINTER(SECURITY_ATTRIBUTES), wintypes.DWORD], wintypes.BOOL),
            "SetHandleInformation": ([wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD], wintypes.BOOL),
            "CreateProcessW": ([wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.LPVOID, wintypes.LPVOID, wintypes.BOOL, wintypes.DWORD, wintypes.LPVOID, wintypes.LPCWSTR, ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION)], wintypes.BOOL),
            "ResumeThread": ([wintypes.HANDLE], wintypes.DWORD),
            "WaitForSingleObject": ([wintypes.HANDLE, wintypes.DWORD], wintypes.DWORD),
            "GetExitCodeProcess": ([wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)], wintypes.BOOL),
        }
        for name, (args, result) in signatures.items():
            fn = getattr(self.k, name)
            fn.argtypes, fn.restype = args, result
        self.job = self.k.CreateJobObjectW(None, None)
        self.process = None
        self.streams = []
        self.pid = None
        handles: list[int] = []
        info = PROCESS_INFORMATION()
        try:
            self.require(self.job)
            limits = EXTENDED_LIMIT()
            limits.BasicLimitInformation.LimitFlags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            self.require(self.k.SetInformationJobObject(self.job, 9, ctypes.byref(limits), ctypes.sizeof(limits)))
            sa = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), None, True)
            pairs = []
            for _ in range(3):
                read, write = wintypes.HANDLE(), wintypes.HANDLE()
                self.require(self.k.CreatePipe(ctypes.byref(read), ctypes.byref(write), ctypes.byref(sa), 0))
                handles.extend([read.value, write.value])
                pairs.append((read.value, write.value))
            # Parent read ends and stdin writer must not be inherited.
            for handle in (pairs[0][0], pairs[1][0], pairs[2][1]):
                self.require(self.k.SetHandleInformation(handle, 1, 0))
            startup = STARTUPINFOW()
            startup.cb = ctypes.sizeof(startup)
            startup.dwFlags = 0x100 | 0x1  # STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW
            startup.wShowWindow = 0
            startup.hStdInput = pairs[2][0]
            startup.hStdOutput = pairs[0][1]
            startup.hStdError = pairs[1][1]
            environment = ctypes.create_unicode_buffer("\0".join(f"{key}={value}" for key, value in sorted(env.items(), key=lambda item: item[0].upper())) + "\0\0")
            cmdline = ctypes.create_unicode_buffer(subprocess.list2cmdline(command))
            self.require(self.k.CreateProcessW(None, cmdline, None, None, True,
                0x08000000 | 0x4 | 0x400, environment, str(cwd), ctypes.byref(startup), ctypes.byref(info)))
            self.process, self.pid = info.hProcess, info.dwProcessId
            self.require(self.k.AssignProcessToJobObject(self.job, self.process))
            # Close parent's writers and stdin pipe: workers receive stdin EOF.
            for handle in (pairs[0][1], pairs[1][1], pairs[2][0], pairs[2][1]):
                self.k.CloseHandle(handle)
                handles.remove(handle)
            for handle in (pairs[0][0], pairs[1][0]):
                fd = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
                handles.remove(handle)
                self.streams.append(os.fdopen(fd, "rb", buffering=0))
            if self.k.ResumeThread(info.hThread) == 0xFFFFFFFF:
                raise ctypes.WinError(ctypes.get_last_error())
        except BaseException:
            if self.process:
                self.k.TerminateProcess(self.process, 1)
            self.close()
            raise
        finally:
            if info.hThread:
                self.k.CloseHandle(info.hThread)
            for handle in handles:
                self.k.CloseHandle(handle)

    @staticmethod
    def require(value):
        if not value:
            raise ctypes.WinError(ctypes.get_last_error())
        return value

    def poll(self) -> int | None:
        if self.k.WaitForSingleObject(self.process, 0) == 0x102:
            return None
        code = wintypes.DWORD()
        self.require(self.k.GetExitCodeProcess(self.process, ctypes.byref(code)))
        return code.value

    def stop_tree(self) -> int:
        self.require(self.k.TerminateJobObject(self.job, 1))
        deadline = time.monotonic() + 5.0
        while True:
            account = BASIC_ACCOUNTING()
            self.require(self.k.QueryInformationJobObject(self.job, 1, ctypes.byref(account), ctypes.sizeof(account), None))
            if account.ActiveProcesses == 0 or time.monotonic() >= deadline:
                return account.ActiveProcesses
            time.sleep(0.01)

    def close(self):
        if self.job:
            self.k.CloseHandle(self.job)
            self.job = None
        if self.process:
            self.k.CloseHandle(self.process)
            self.process = None
        for stream in self.streams:
            stream.close()


class Capture:
    def __init__(self, directory: Path, limit: int):
        self.limit = limit
        self.saved = 0
        self.received = 0
        self.reason = ""
        self.tail = b""
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.file = (directory / "process-output.log").open("xb")

    def read(self, stream) -> None:
        rolling = b""
        try:
            while chunk := stream.read(4096):
                with self.lock:
                    self.received += len(chunk)
                    available = self.limit - self.saved
                    written = self.file.write(chunk[:available])
                    self.saved += written
                    self.tail = (self.tail + chunk)[-4096:]
                    check = (rolling + chunk).lower()
                    rolling = check[-256:]
                    signature = next((item for item in FATAL_SIGNATURES if item in check), None)
                    if signature and not self.reason:
                        self.reason = "fatal_output:" + signature.decode("ascii")
                    if self.received >= self.limit and not self.reason:
                        self.reason = "output_budget"
                    if self.reason:
                        self.stop.set()
        except (OSError, ValueError) as error:
            with self.lock:
                if not self.reason:
                    self.reason = "capture_error:" + str(error)
                self.stop.set()


def validate_png(path: Path, max_bytes: int) -> None:
    """Check complete chunks, CRCs and non-interlaced pixel stream, no third-party libs."""
    if not path.is_file() or not 0 < path.stat().st_size <= max_bytes:
        raise ValueError(f"PNG missing, empty or over budget: {path}")
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    position, dimensions, compressed, ended = 8, None, bytearray(), False
    row_bytes, color, palette = 0, -1, False
    while position + 12 <= len(data):
        size = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        end = position + 12 + size
        if end > len(data):
            raise ValueError("Truncated PNG chunk")
        body = data[position + 8:position + 8 + size]
        crc = struct.unpack_from(">I", data, position + 8 + size)[0]
        if zlib.crc32(kind + body) & 0xFFFFFFFF != crc:
            raise ValueError("PNG checksum mismatch")
        if kind == b"IHDR":
            if dimensions is not None or size != 13 or position != 8:
                raise ValueError("Invalid PNG header")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color)
            depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
            if not channels or depth not in depths[color] or not 0 < width <= 8192 or not 0 < height <= 8192 or compression or filtering or interlace:
                raise ValueError("Unsupported or oversized screenshot PNG")
            row_bytes = (width * channels * depth + 7) // 8
            dimensions = height * (row_bytes + 1)
            if dimensions > 128 * 1024 * 1024:
                raise ValueError("PNG decoded image over budget")
        elif kind == b"PLTE":
            if not 0 < size <= 768 or size % 3:
                raise ValueError("Invalid PNG palette")
            palette = True
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            ended = size == 0 and end == len(data)
            break
        position = end
    if not dimensions or not ended or not compressed or (color == 3 and not palette):
        raise ValueError("Incomplete PNG")
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(compressed, dimensions + 1)
    if len(pixels) != dimensions or not decoder.eof or decoder.unused_data:
        raise ValueError("Invalid PNG pixel stream")
    if any(pixels[offset] > 4 for offset in range(0, len(pixels), row_bytes + 1)):
        raise ValueError("Invalid PNG row filter")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--max-output-bytes", type=int, default=8 * 1024 * 1024)
    parser.add_argument("--max-file-bytes", type=int, default=64 * 1024 * 1024)
    parser.add_argument("--watch-file", action="append", default=[])
    parser.add_argument("--expect-png", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        if not 0 < args.timeout <= 3600 or not 0 < args.max_output_bytes <= 64 * 1024 * 1024 or args.max_file_bytes <= 0:
            raise ValueError("Invalid time or output budget")
        project = Path(args.project).resolve(strict=True)
        check_isolation(project)
        command = prepare_command(args.command[1:] if args.command[:1] == ["--"] else args.command, project)
        output = resolve_inside(args.output_dir, project)
        if output == project or output.exists():
            raise ValueError("Output directory must be new for this run")
        expected = [resolve_inside(path, project) for path in args.expect_png]
        watched = [resolve_inside(path, project) for path in args.watch_file] + expected
        if any(path.exists() for path in expected):
            raise ValueError("Expected screenshots must not exist before launch")
        output.mkdir(parents=True)
        environment = dict(os.environ)
        for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP"):
            location = output / "environment" / key.lower()
            location.mkdir(parents=True, exist_ok=True)
            environment[key] = str(location)
        environment["TETRIS_SAFE_RUN"] = "1"
        environment["TETRIS_RUN_DIR"] = str(output)
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({"ok": False, "reason": "preflight", "detail": str(error)}))
        return 2

    capture = Capture(output, args.max_output_bytes)
    job = None
    readers: list[threading.Thread] = []
    reason, child_code, remaining = "", None, None
    start = time.monotonic()
    try:
        job = WindowsJob(command, project, environment)
        for stream in job.streams:
            reader = threading.Thread(target=capture.read, args=(stream,), daemon=True)
            readers.append(reader)
            reader.start()
        while True:
            if capture.stop.is_set():
                reason = capture.reason
                break
            child_code = job.poll()
            if child_code is not None:
                reason = "success" if child_code == 0 else "child_exit"
                break
            if time.monotonic() - start >= args.timeout:
                reason = "timeout"
                break
            if any(path.exists() and path.stat().st_size > args.max_file_bytes for path in watched):
                reason = "artifact_budget"
                break
            capture.stop.wait(0.02)
    except KeyboardInterrupt:
        reason = "cancelled"
    except (OSError, ValueError, RuntimeError) as error:
        reason = "runner_error:" + str(error)
    finally:
        if job is not None:
            try:
                remaining = job.stop_tree()  # Also kill grandchildren after a successful parent exit.
            except OSError as error:
                reason = "cleanup_error:" + str(error)
            for reader in readers:
                reader.join(timeout=2.0)
            if remaining != 0 or any(reader.is_alive() for reader in readers):
                reason = "cleanup_incomplete"
            job.close()
        capture.file.close()
    if capture.reason and reason in ("success", "child_exit"):
        reason = capture.reason
    if reason == "success":
        try:
            if any(path.exists() and path.stat().st_size > args.max_file_bytes for path in watched):
                raise ValueError("Watched output exceeded its budget before process exit")
            for path in expected:
                validate_png(path, args.max_file_bytes)
        except (OSError, ValueError, zlib.error) as error:
            reason = "invalid_screenshot:" + str(error)
    result = {"ok": reason == "success", "reason": reason, "child_exit_code": child_code,
              "pid": job.pid if job else None, "remaining_job_processes": remaining,
              "elapsed_seconds": round(time.monotonic() - start, 3),
              "output_bytes_saved": capture.saved, "output_bytes_received": capture.received,
              "output_limit": args.max_output_bytes, "output_dir": str(output)}
    (output / "run.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
    if reason == "success":
        return 0
    return 124 if reason == "timeout" else 1


if __name__ == "__main__":
    raise SystemExit(main())
