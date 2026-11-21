import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('retire', Path(__file__).with_name('retire-node-units.py'))
retire = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retire)

MANIFEST = Path(__file__).resolve().parent.parent / 'ops' / 'hetzner-bob' / 'retired.json'


def load():
    return json.loads(MANIFEST.read_text())


class ManifestTests(unittest.TestCase):
    def test_every_entry_has_issue_reason_and_restore(self):
        entries = load()['retired']
        self.assertTrue(entries)
        for e in entries:
            for key in ('id', 'issue', 'reason', 'restore'):
                self.assertTrue(e.get(key), f'{e.get("id")} missing {key}')

    def test_manifest_never_targets_protected_production_services(self):
        with self.assertRaises(ValueError):
            retire.plan({'node': 'hetzner-bob', 'retired': [
                {'id': 'x', 'issue': 'X-1', 'reason': 'r', 'restore': 'r',
                 'units': ['bob-gateway.service']}]}, stamp='t')
        retire.plan(load(), stamp='t')  # real manifest passes the guard


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.steps = retire.plan(load(), stamp='20261121T000000Z')
        self.cmds = [s['cmd'] for s in self.steps]

    def idx(self, needle):
        for i, c in enumerate(self.cmds):
            if needle in c:
                return i
        self.fail(f'no step containing {needle!r}')

    def test_backup_comes_first_and_covers_every_path(self):
        self.assertIn('tar', self.cmds[0])
        for e in load()['retired']:
            for p in retire.paths_for(e):
                self.assertIn(p, self.cmds[0])

    def test_units_are_stopped_disabled_removed_and_reset(self):
        for unit in ('omnibank-token-rotate.timer', 'omnibank-token-rotate.service',
                     'levelforge-fleet-controller.service', 'netcontrol-relay.socket'):
            self.assertLess(self.idx(f'systemctl disable --now {unit}'), self.idx(f'rm -f /etc/systemd/system/{unit}'))
        self.assertGreater(self.idx('systemctl reset-failed'), self.idx('systemctl daemon-reload'))

    def test_nginx_site_disabled_and_validated_before_reload_and_cert_delete(self):
        unlink = self.idx('rm -f /etc/nginx/sites-enabled/net.omnidat.cc')
        test = self.idx('nginx -t')
        reload_ = self.idx('systemctl reload nginx')
        delete = self.idx('certbot delete --non-interactive --cert-name net.omnidat.cc')
        self.assertLess(unlink, test)
        self.assertLess(test, reload_)
        self.assertLess(reload_, delete)

    def test_every_step_is_fail_fast(self):
        self.assertTrue(all(s.get('check', True) for s in self.steps))

    def test_already_retired_paths_are_skipped_idempotently(self):
        steps = retire.plan(load(), stamp='t', exists=lambda p: False)
        self.assertFalse(any('rm -f' in s['cmd'] or 'certbot delete' in s['cmd'] for s in steps))


if __name__ == '__main__':
    unittest.main()
