"""LAB-15: Nix auto-GC keeps hetzner-fg's /mnt/docker volume (which holds /nix) under 85%."""
from pathlib import Path
import unittest

OPS = Path(__file__).resolve().parent.parent / 'ops' / 'hetzner-fg'
GiB = 1024 ** 3

# sdb (Hetzner volume HC_Volume_104330084) on 2026-11-22: `df -B1 /mnt/docker`
# used + available = 166097457152 + 34979889152. ext4 reserves the rest of the
# 210779168768-byte filesystem for root, so df's Use% is used / (used + avail).
USABLE = 201_077_346_304
PRESSURE_PERCENT = 85            # fleet-storage-pressure / df alert line
REGISTRY_BUILD_DEAD = 7 * GiB    # dead paths one registry/nixci build leaves
# Measured 2026-11-23 01:43-01:53Z (nix flake check, min-free 32 GiB): free
# space fell 4.4 GB below where it started while auto-GC held gc.lock, because
# build directories (build-dir on the same volume) are not collectable.
OBSERVED_BUILD_DIP = 4_427_816_960


def nix_conf():
    settings = {}
    for line in (OPS / 'nix.custom.conf').read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if line:
            key, value = (part.strip() for part in line.split('=', 1))
            settings[key] = value
    return settings


class NixAutoGcTests(unittest.TestCase):
    def setUp(self):
        self.conf = nix_conf()
        self.min_free = int(self.conf['min-free'])
        self.max_free = int(self.conf['max-free'])
        self.pressure_free = USABLE * (100 - PRESSURE_PERCENT) / 100  # ~28.1 GiB

    def test_auto_gc_starts_before_the_85_percent_line(self):
        # Nix checks free space every min-free-check-interval (5 s) while it
        # builds, so a margin of half a build's output is enough to collect
        # before the alert line rather than at the old 8 GiB.
        self.assertGreaterEqual(self.min_free, self.pressure_free + REGISTRY_BUILD_DEAD / 2)
        # A build that starts just above min-free must not dip past the line.
        self.assertGreaterEqual(self.min_free, self.pressure_free + 2 * OBSERVED_BUILD_DIP)
        self.assertEqual(self.min_free % GiB, 0)

    def test_one_auto_gc_frees_at_least_two_builds_of_garbage(self):
        # max-free is where GC stops; leaving room for two builds avoids a GC
        # pass on every build.
        self.assertGreaterEqual(self.max_free - self.min_free, 2 * REGISTRY_BUILD_DEAD)
        self.assertEqual(self.max_free % GiB, 0)
        self.assertLess(self.max_free, USABLE / 2)

    def test_keeps_existing_settings_and_no_credentials(self):
        self.assertEqual(self.conf['build-dir'], '/mnt/HC_Volume_104330084/nix-build')
        self.assertEqual(self.conf['sandbox-dev-shm-size'], '40G')
        text = (OPS / 'nix.custom.conf').read_text()
        self.assertNotIn('access-tokens', text)
        self.assertNotIn('netrc', text)

    def test_readme_documents_install_path(self):
        self.assertIn('/etc/nix/nix.custom.conf', (OPS / 'README.md').read_text())


if __name__ == '__main__':
    unittest.main()
