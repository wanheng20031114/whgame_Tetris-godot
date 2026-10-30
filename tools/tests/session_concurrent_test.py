import json
import os
from pathlib import Path
import subprocess
import sys

project = Path.cwd()
command = [sys.argv[1], '--headless', '--path', str(project), '--script', 'res://tools/tests/session_concurrent_worker.gd']
workers = [subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) for _ in range(2)]
for worker in workers:
    output, _ = worker.communicate(timeout=15)
    print(output.decode('utf-8', errors='replace'))
    assert worker.returncode == 0
directory = Path(os.environ['TETRIS_RUN_DIR'])/'concurrent-sessions'
total = sum(p.stat().st_size for p in directory.rglob('*') if p.is_file())
session_bytes = sum(p.stat().st_size for p in (directory/'sessions').glob('session_shared.json*') if p.is_file())
assert session_bytes == 6000, session_bytes
assert total <= 20000, total
assert not (directory/'.budget-write-lock').exists()
print(json.dumps({'ok': True, 'session_bytes': session_bytes, 'session_limit': 6000, 'total_bytes': total, 'total_limit': 20000}))
