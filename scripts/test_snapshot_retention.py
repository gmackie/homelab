import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('retention', Path(__file__).with_name('retain-local-snapshots.py'))
retention = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retention)


class RetentionTests(unittest.TestCase):
    def test_keeps_latest_and_never_selects_pre_restore_or_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); directory = root / 'db'; directory.mkdir()
            for name in ['db-2026-10-17.sql.gz', 'db-2026-10-18.sql.gz', 'db-pre-restore-123.sql.gz']:
                (directory / name).write_bytes(b'dump')
            (directory / 'db-2026-10-16.sql.gz').symlink_to('/missing')
            self.assertEqual([p.name for p in retention.candidates(root)], ['db-2026-10-17.sql.gz'])

    def test_remote_hash_mismatch_or_open_handle_preserves_local_dump(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'db.sql.gz'; path.write_bytes(b'dump')
            with self.assertRaises(RuntimeError):
                retention.retire(path, 'wrong', Path(tmp) / 'receipts')
            self.assertTrue(path.exists())
            import hashlib
            value = hashlib.sha256(b'dump').hexdigest()
            result = subprocess.CompletedProcess([], 0, 'p42\nn' + str(path) + '\n', '')
            with patch.object(retention.subprocess, 'run', return_value=result):
                with self.assertRaises(RuntimeError):
                    retention.retire(path, value, Path(tmp) / 'receipts')
            self.assertTrue(path.exists())

    def test_verified_retirement_records_sha_and_preserves_newest_dump(self):
        with tempfile.TemporaryDirectory() as tmp:
            import hashlib,json
            path = Path(tmp) / 'old.sql.gz'; path.write_bytes(b'dump')
            value = hashlib.sha256(b'dump').hexdigest()
            result = subprocess.CompletedProcess([], 0, 'p42\nn/elsewhere\n', '')
            receipts = Path(tmp) / 'receipts'
            with patch.object(retention.subprocess, 'run', return_value=result):
                retention.retire(path, value, receipts)
            self.assertFalse(path.exists())
            self.assertEqual(json.loads((receipts / 'old.sql.gz.json').read_text())['sha256'], value)

    def test_invalid_trusted_verifier_response_retains_snapshot(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); directory = root / 'db'; directory.mkdir()
            for date in ['2026-10-17', '2026-10-18']:
                (directory / ('db-' + date + '.sql.gz')).write_bytes(b'dump')
            config = root / 'config.json'
            config.write_text(json.dumps({'node_name': 'fixture', 'snapshot': {'s3_endpoint': 'fixture'}}))
            argv = ['retain', '--root', str(root), '--config', str(config), '--apply',
                    '--ssh-verifier', 'fixture', '--ssh-key', str(root / 'key')]
            with patch.object(sys, 'argv', argv):
                with patch.object(retention.subprocess, 'check_output', return_value='not a digest'):
                    with self.assertRaises(RuntimeError):
                        retention.main()
            self.assertTrue((directory / 'db-2026-10-17.sql.gz').exists())


if __name__ == '__main__':
    unittest.main()
