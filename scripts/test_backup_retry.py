"""Exercise the backup shell with isolated filesystems and fake remote commands."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class BackupRetryTests(unittest.TestCase):
    def test_failed_copy_reuses_snapshot_until_every_copy_succeeds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = root / 'state'
            state.mkdir()
            commands = root / 'bin'
            commands.mkdir()
            fake = commands / 'fake'
            fake.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
root=Path(os.environ['FIXTURE_ROOT'])
name=Path(sys.argv[0]).name
args=sys.argv[1:]
with (root/'calls').open('a') as f: f.write(json.dumps([name]+args)+'\\n')
if name=='zfs':
 if args[0]=='snapshot': (root/'snapshot').write_text(args[1])
 elif args[0]=='list':
  if not (root/'snapshot').exists(): sys.exit(1)
  print((root/'snapshot').read_text())
elif name=='rsync':
 if os.environ.get('FAIL_COPY','') in ('all',args[-1].split(':')[-1]): sys.exit(255)
elif name=='docker': print('sha256:'+'a'*64)
''')
            fake.chmod(0o755)
            for name in ['zfs', 'rsync', 'docker', 'flock']:
                (commands / name).symlink_to(fake)
            config = root / 'config'
            config.mkdir()
            (config / 'homelab-storage-minio.env').write_text('fixture')
            (config / 'forgegraph-minio.service').write_text('fixture')
            bundle = state / 'service-config'
            bundle.mkdir()
            (bundle / ('minio-' + 'a' * 64 + '.tar.gz')).write_bytes(b'fixture')
            source = Path(__file__).resolve().parents[1] / 'ops/fleet-storage/backup-to-storedge.sh'
            script = root / 'backup.sh'
            script.write_text(source.read_text()
                              .replace('/run/fleet-storage-backup.lock', str(root / 'lock'))
                              .replace('/var/lib/fleet-storage', str(state))
                              .replace('/etc/forgegraph/homelab-storage-minio.env', str(config / 'homelab-storage-minio.env'))
                              .replace('/etc/systemd/system/forgegraph-minio.service', str(config / 'forgegraph-minio.service')))
            env = dict(os.environ, FIXTURE_ROOT=str(root), PATH=str(commands) + os.pathsep + os.environ['PATH'])
            pending = state / 'pending-minio-snapshot'

            def run(fail):
                return subprocess.run(['bash', str(script)], env=dict(env, FAIL_COPY=fail), capture_output=True, text=True)

            self.assertNotEqual(run('all').returncode, 0)
            stamp = pending.read_text()
            self.assertNotEqual(run('service-config/').returncode, 0)
            self.assertEqual(pending.read_text(), stamp)
            self.assertEqual(run('').returncode, 0)
            self.assertFalse(pending.exists())
            calls = [json.loads(line) for line in (root / 'calls').read_text().splitlines()]
            self.assertEqual(sum(c[:2] == ['zfs', 'snapshot'] for c in calls), 1)
            self.assertFalse(any(c[:2] == ['zfs', 'destroy'] for c in calls))
            # A corrupt state marker cannot trigger a new snapshot or transfer.
            pending.write_text('unexpected-snapshot\n')
            before = (root / 'calls').read_text()
            self.assertNotEqual(run('').returncode, 0)
            self.assertEqual((root / 'calls').read_text(), before + '["flock", "-n", "9"]\n')


if __name__ == '__main__':
    unittest.main()
