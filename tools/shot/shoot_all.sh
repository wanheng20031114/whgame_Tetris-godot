#!/bin/sh
# 用法: sh tools/shot/shoot_all.sh <outdir> [mode...]
set -eu
[ "$#" -ge 1 ] || { echo 'Usage: shoot_all.sh <isolated output directory> [mode...]' >&2; exit 2; }
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT=$1
shift
case "$OUT" in
  /*|[A-Za-z]:*) ;;
  *) OUT="$ROOT/$OUT" ;;
esac
MODES=${*:-dark light}
G=${GODOT_BIN:-"C:/Program Files/Godot/Godot_console.exe"}
PY=${PYTHON_BIN:-python}
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
for m in $MODES; do
for s in login_screen main_lobby guide_system replay_system player_stats_screen multiplayer_setup multiplayer_lobby main; do
  RUN="$OUT/${s}_${m}_$STAMP"
  PNG="$RUN/${s}_$m.png"
  "$PY" "$ROOT/tools/safe_run.py" --project "$ROOT" --timeout 30 --output-dir "$RUN" --expect-png "$PNG" -- "$G" --resolution 1280x720 -s res://tools/shot/shot.gd -- "res://scenes/ui/$s.tscn" "$m" "$PNG" 150
done; done
