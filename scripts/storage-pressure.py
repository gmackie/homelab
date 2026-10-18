#!/usr/bin/env python3
"""Read-only capacity telemetry; warn before build hosts hit their admission floor."""
import argparse
import json
from pathlib import Path
import shutil
import socket
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('paths', nargs='+')
parser.add_argument('--min-free-gib', type=float, default=40)
parser.add_argument('--max-used-percent', type=float, default=85)
args = parser.parse_args()
failed = False
for name in args.paths:
    path = Path(name)
    if not path.exists():
        print(json.dumps({'host': socket.gethostname(), 'path': name, 'status': 'missing', 'time': time.time()}))
        failed = True
        continue
    total, used, free = shutil.disk_usage(path)
    pressure = free < args.min_free_gib * 1024**3 or used / total * 100 > args.max_used_percent
    failed |= pressure
    print(json.dumps({'host': socket.gethostname(), 'path': name, 'freeGiB': round(free / 1024**3, 1),
                      'usedPercent': round(used / total * 100, 1), 'status': 'pressure' if pressure else 'ok',
                      'time': time.time()}))
raise SystemExit(1 if failed else 0)
