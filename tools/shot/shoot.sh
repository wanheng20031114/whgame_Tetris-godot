#!/bin/sh
# 用法: sh tools/shot/shoot.sh <scene名> <dark|light> [call_spec] [后缀]
set -eu
[ "$#" -ge 2 ] || { echo 'Usage: shoot.sh <scene> <dark|light> [call_spec] [suffix]' >&2; exit 2; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
G=${GODOT_BIN:-"C:/Program Files/Godot/Godot_console.exe"}
PY=${PYTHON_BIN:-python}
RUN="$ROOT/.safe-runs/shot-$(date +%Y%m%d-%H%M%S)-$$"
PNG="$RUN/$1${4:-}_$2.png"
exec "$PY" "$ROOT/tools/safe_run.py" --project "$ROOT" --timeout 30 --output-dir "$RUN" --expect-png "$PNG" -- "$G" --resolution 1280x720 -s res://tools/shot/shot.gd -- "res://scenes/ui/$1.tscn" "$2" "$PNG" 150 "${3:-}"
