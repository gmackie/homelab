import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('catalog', Path(__file__).with_name('catalog-nas-archives.py'))
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTests(unittest.TestCase):
    def test_only_receipted_archives_are_listed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / 'finished.tar'; archive.write_bytes(b'archive')
            (root / 'interrupted.partial').write_bytes(b'incomplete')
            receipt = {'archive': str(archive), 'source': '/old/files', 'fileBytes': 42,
                       'archiveSha256': 'a' * 64, 'verification': {'verifiedEntries': 2},
                       'retired': True, 'restore': 'restore fixture'}
            (root / 'finished.receipt.json').write_text(json.dumps(receipt))
            catalog.publish(root)
            rows = json.loads((root / 'catalog.json').read_text())['archives']
            self.assertEqual([r['archive'] for r in rows], ['finished.tar'])
            self.assertTrue(rows[0]['localSourceRetired'])
            archive.unlink()
            with self.assertRaises(ValueError): catalog.publish(root)
            # Failed refresh preserves the last complete catalog.
            self.assertEqual(json.loads((root / 'catalog.json').read_text())['archives'], rows)
