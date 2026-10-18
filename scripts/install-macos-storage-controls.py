#!/usr/bin/env python3
"""Install read-only hourly capacity telemetry and optional unreferenced Nix GC.

Defaults to inspection. Replaces the legacy age-based Preflight sweep agent,
preserving its original plist. Never deletes profile generations or workspaces.
"""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('paths', nargs='+')
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
home = Path.home()
lib = home / '.local/lib/fleet-storage'
logs = home / 'Library/Logs'
agents = home / 'Library/LaunchAgents'
items = [{'Label': 'com.forgegraph.preflight-disk-sweep',
          'ProgramArguments': ['/usr/bin/python3', str(lib / 'storage-pressure.py')] + args.paths,
          'RunAtLoad': True, 'StartInterval': 3600,
          'StandardOutPath': str(logs / 'fleet-storage-pressure.log'),
          'StandardErrorPath': str(logs / 'fleet-storage-pressure.log')}]
nix = Path('/nix/var/nix/profiles/default/bin/nix-store')
if nix.exists():
    items.append({'Label': 'com.forgegraph.nix-gc', 'ProgramArguments': [str(nix), '--gc'],
                  'StartCalendarInterval': {'Weekday': 0, 'Hour': 6, 'Minute': 15},
                  'StandardOutPath': str(logs / 'fleet-nix-gc.log'),
                  'StandardErrorPath': str(logs / 'fleet-nix-gc.log'), 'LowPriorityIO': True, 'Nice': 10})
for item in items:
    print(item['Label'], item['ProgramArguments'], 'apply=' + str(args.apply))
if args.apply:
    for directory in [lib, logs, agents]:
        directory.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).with_name('storage-pressure.py')
    if source.resolve() != (lib / 'storage-pressure.py').resolve():
        shutil.copy2(source, lib / 'storage-pressure.py')
    for item in items:
        path = agents / (item['Label'] + '.plist')
        backup = path.with_suffix('.plist.before-LAB-1')
        if path.exists() and not backup.exists():
            shutil.copy2(path, backup)
        subprocess.run(['launchctl', 'bootout', 'gui/' + str(os.getuid()), str(path)], capture_output=True)
        path.write_bytes(plistlib.dumps(item))
        subprocess.run(['launchctl', 'bootstrap', 'gui/' + str(os.getuid()), str(path)], check=True)
