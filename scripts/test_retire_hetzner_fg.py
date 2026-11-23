"""LAB-15: retire hetzner-fg's legacy self-hosted ForgeGraph server (forgegraph.service)."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('retire', Path(__file__).with_name('retire-node-units.py'))
retire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retire)

MANIFEST = Path(__file__).resolve().parent.parent / 'ops' / 'hetzner-fg' / 'retired.json'
ENV_FILES = ['/etc/forgegraph/env/forgegraph.env', '/etc/forgegraph/env.file-',
             '/etc/forgegraph/env.file.bak-']


def load():
    return json.loads(MANIFEST.read_text())


def entry(**kw):
    return {'id': 'x', 'issue': 'X-1', 'reason': 'r', 'restore': 'r', **kw}


class HetznerFgManifestTests(unittest.TestCase):
    def setUp(self):
        self.cmds = [s['cmd'] for s in retire.plan(load(), stamp='20261123T000000Z')]

    def idx(self, needle):
        for i, c in enumerate(self.cmds):
            if needle in c:
                return i
        self.fail(f'no step containing {needle!r}')

    def test_entries_are_documented(self):
        for e in load()['retired']:
            for key in ('id', 'issue', 'reason', 'restore'):
                self.assertTrue(e.get(key), f'{e.get("id")} missing {key}')

    def test_unit_and_env_files_are_backed_up_first(self):
        self.assertIn('tar', self.cmds[0])
        for path in ['/etc/systemd/system/forgegraph.service', *ENV_FILES]:
            self.assertIn(path, self.cmds[0])

    def test_env_files_removed_only_after_the_unit_is_stopped(self):
        stop = self.idx('systemctl disable --now forgegraph.service')
        for path in ENV_FILES:
            self.assertGreater(self.idx(f'rm -f {path}'), stop)

    def test_live_hetzner_fg_services_are_protected(self):
        for unit in ('forgegraph-agent.service', 'nix-serve.service', 'promtail.service',
                     'nix.mount', 'postgresql.service', 'forgejo.service'):
            with self.assertRaises(ValueError):
                retire.plan({**load(), 'retired': [entry(units=[unit])]}, stamp='t')

    def test_files_refuse_service_data_and_the_store(self):
        for path in ('/var/lib/gitea/custom/conf/app.ini', '/var/lib/postgresql/16/main',
                     '/var/lib/forgejo/data', '/nix/store/x', 'relative/path'):
            with self.assertRaises(ValueError):
                retire.plan({**load(), 'retired': [entry(files=[path])]}, stamp='t')

    def test_already_retired_is_a_no_op(self):
        steps = retire.plan(load(), stamp='t', exists=lambda p: False)
        self.assertFalse(any('rm -f' in s['cmd'] or 'tar ' in s['cmd'] for s in steps))


if __name__ == '__main__':
    unittest.main()
