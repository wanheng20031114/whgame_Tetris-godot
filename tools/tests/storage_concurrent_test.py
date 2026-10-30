import json
import os
from pathlib import Path
import subprocess
import sys

project = Path.cwd()
command = [sys.argv[1], '--headless', '--path', str(project), '--script', 'res://tools/tests/storage_concurrent_worker.gd']
workers = [subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) for _ in range(2)]
for worker in workers:
    output, _ = worker.communicate(timeout=15)
    print(output.decode('utf-8', errors='replace'))
    assert worker.returncode == 0
directory = Path(os.environ['TETRIS_RUN_DIR']) / 'concurrent-data'
total = sum(path.stat().st_size for path in directory.rglob('*') if path.is_file())
assert 1000 <= total <= 20000, total
assert not (directory / '.budget-write-lock').exists()
print(json.dumps({'ok': True, 'test': 'concurrent storage writers', 'total_bytes': total, 'limit': 20000}))
