"""LAB-1: per-platform capacity floors match the documented policy."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
OPS = SCRIPTS.parent / 'ops' / 'fleet-storage'


def planned_mac_agents():
    with tempfile.TemporaryDirectory() as home:
        out = subprocess.run(
            [sys.executable, str(SCRIPTS / 'install-macos-storage-controls.py'), '/', '/Volumes/dev'],
            capture_output=True, text=True, check=True, env={**os.environ, 'HOME': home}).stdout
    agents = {}
    for line in out.splitlines():
        label, rest = line.split(' ', 1)
        agents[label] = ast.literal_eval(rest.rsplit(' apply=', 1)[0])
    return agents


class MacFloorTests(unittest.TestCase):
    def test_mac_telemetry_uses_documented_40_gib_floor_only(self):
        # APFS reports container-wide usage, so the Linux 85% rule would demand
        # ~139 GiB free on a 926 GiB laptop container. Macs warn on the floor.
        argv = planned_mac_agents()['com.forgegraph.preflight-disk-sweep']
        self.assertIn('--min-free-gib', argv)
        self.assertEqual(argv[argv.index('--min-free-gib') + 1], '40')
        self.assertIn('--max-used-percent', argv)
        self.assertEqual(argv[argv.index('--max-used-percent') + 1], '100')
        self.assertEqual(argv[-2:], ['/', '/Volumes/dev'])


class NixGcCadenceTests(unittest.TestCase):
    def test_hetzner_fg_collects_daily(self):
        # hetzner-fg builds the ForgeGraph registry with --no-link several times
        # a day; each build leaves GiBs of dead paths on its 75 GiB root.
        conf = (OPS / 'hetzner-fg-nix-gc.conf').read_text()
        self.assertIn('OnCalendar=\n', conf)
        self.assertIn('OnCalendar=*-*-* 06:15:00 UTC', conf)

    def test_gc_never_deletes_generations(self):
        unit = (OPS / 'fleet-nix-gc.service').read_text()
        self.assertIn('nix-store --gc', unit)
        self.assertNotIn('--delete', unit)
        self.assertNotIn('-d', unit.split('ExecStart=', 1)[1].split())


if __name__ == '__main__':
    unittest.main()
