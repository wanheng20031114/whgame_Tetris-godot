# Isolated screenshot and probe tools

These tools must run through `tools/safe_run.py` in an explicitly marked project
copy. The real project is not a test workspace. The runner is a Windows/Python
development tool, not a runtime dependency of exported games.

The copy needs `.safe-run-isolated.json` with `kind` equal to
`tetris-isolated-test`, `project_root` equal to its absolute directory, and
`source_root` equal to the original project's absolute directory. Its
`project.godot` must disable both `debug/file_logging/enable_file_logging` and
`debug/file_logging/enable_file_logging.pc`. Do not pass `--log-file`.

Run from the copy, using a new output directory for every run:

```powershell
python tools/safe_run.py --project . --timeout 10 --output-dir .safe-runs/handling-001 -- "C:/Program Files/Godot/Godot_console.exe" --headless -s res://tools/shot/probe_handling.gd
python tools/safe_run.py --project . --timeout 30 --output-dir .safe-runs/lobby-001 --expect-png .safe-runs/lobby-001/lobby.png -- "C:/Program Files/Godot/Godot_console.exe" --resolution 1280x720 -s res://tools/shot/shot.gd -- res://scenes/ui/main_lobby.tscn dark res://.safe-runs/lobby-001/lobby.png 150
```

The runner injects the validated `--path`, isolates APPDATA/LOCALAPPDATA/TEMP,
caps the combined output file (8 MiB by default), and fails on device-loss or
script-error signatures. Its Windows Job Object contains the process from its
first instruction; cleanup kills descendants even after the main child exits.
`run.json` records the child exit code, stop reason, byte counts and remaining
Job Object process count. A successful screenshot requires a new, complete PNG
with valid checksums and image data. GDScript also decodes the PNG after saving.

Screenshot paths are mandatory and must be inside that run's new output
directory. There is no `user://` or real AppData screenshot fallback. The
runner redirects its child's AppData environment variables into the isolated
run directory; game-owned persistent data uses the copy's `userdata` directory.

`--watch-file PATH --max-file-bytes N` provides an external artifact-size
tripwire. Polling can overshoot this size; strict write limits belong in the
producer. `--timeout` is a monotonic wall-clock deadline for test jobs only.
These tools never retry a failed run automatically.

`shoot.sh` and `shoot_all.sh` use this runner and stop the batch on its first
failure. `GODOT_BIN` and `PYTHON_BIN` select executable paths. Shell output
directories must be inside the isolated project. Theme probes use the
non-persisting `UITheme.set_mode(..., false)` option.

Finite fake-worker verification, without starting Godot:

```powershell
python tools/test_safe_run.py --report tools/shot/test-results/safe-run.json
```
