"""FORGE-205: hetzner-fg's Nix store is bind-mounted from the /mnt/docker volume."""
import configparser
from pathlib import Path
import unittest

OPS = Path(__file__).resolve().parent.parent / 'ops' / 'hetzner-fg'


def unit(name):
    parser = configparser.ConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    parser.read(OPS / name)
    return parser


class NixMountTests(unittest.TestCase):
    def test_bind_mounts_volume_copy_onto_nix(self):
        mount = unit('nix.mount')['Mount']
        self.assertEqual(mount['What'], '/mnt/docker/nix')
        # systemd requires a mount unit's name to match its Where= path.
        self.assertEqual(mount['Where'], '/nix')
        self.assertEqual(mount['Options'], 'bind')

    def test_waits_for_the_volume_and_starts_at_boot(self):
        u = unit('nix.mount')
        self.assertEqual(u['Unit']['RequiresMountsFor'], '/mnt/docker')
        self.assertEqual(u['Install']['WantedBy'], 'local-fs.target')

    def test_nix_consumers_require_the_mounted_store(self):
        # Without this, a failed mount would let the agent or nix-serve start
        # against the empty root directory instead of refusing to start.
        self.assertEqual(unit('requires-nix.conf')['Unit']['RequiresMountsFor'], '/nix/store')
        readme = (OPS / 'README.md').read_text()
        for service in ('forgegraph-agent', 'nix-serve', 'promtail', 'fleet-nix-gc'):
            self.assertIn(f'{service}.service.d/requires-nix.conf', readme)


if __name__ == '__main__':
    unittest.main()
