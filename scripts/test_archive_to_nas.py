import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('archive', Path(__file__).with_name('archive-to-nas.py'))
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class VerificationTests(unittest.TestCase):
    def test_archive_readback_rejects_damage_and_missing_or_duplicate_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'source'
            root.mkdir()
            (root / 'artifact').write_bytes(b'build evidence')
            (root / 'alias').symlink_to('artifact')
            manifest = Path(tmp) / 'manifest.json'
            manifest.write_text(json.dumps(archive.inventory(root)))
            for scenario in ('valid', 'corrupt', 'missing', 'duplicate'):
                target = Path(tmp) / (scenario + '.tar')
                with tarfile.open(target, 'w:gz') as tar:
                    tar.add(root / 'alias', arcname='alias')
                    if scenario != 'missing':
                        info = tar.gettarinfo(root / 'artifact', arcname='artifact')
                        payload = b'wrong evidence' if scenario == 'corrupt' else b'build evidence'
                        info.size = len(payload)
                        tar.addfile(info, io.BytesIO(payload))
                        if scenario == 'duplicate':
                            tar.addfile(info, io.BytesIO(payload))
                result = subprocess.run([sys.executable, '-c', archive.REMOTE_VERIFY, str(target), str(manifest)], capture_output=True)
                self.assertEqual(result.returncode == 0, scenario == 'valid', result.stderr)

    def test_open_file_and_lsof_failure_prevent_retirement(self):
        root = Path('/specific/inactive/source')
        for status, output in [(0, 'p42\nn/specific/inactive/source/artifact\n'), (1, '')]:
            with patch.object(archive.subprocess, 'run', return_value=subprocess.CompletedProcess([], status, output, '')):
                with self.assertRaises(RuntimeError):
                    archive.assert_inactive(root)

    def test_inventory_does_not_follow_symlinks_and_rejects_special_files(self):
        import os
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'external').symlink_to('/does/not/exist')
            self.assertEqual(archive.inventory(root)['external']['target'], '/does/not/exist')
            os.mkfifo(root / 'pipe')
            with self.assertRaises(RuntimeError):
                archive.inventory(root)


if __name__ == '__main__':
    unittest.main()
