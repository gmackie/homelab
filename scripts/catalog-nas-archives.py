#!/usr/bin/env python3
"""Index completed NAS archive receipts; partial transfers never enter the catalog."""
import argparse
import datetime
import json
from pathlib import Path
import re


def collect(root):
    root = root.resolve()
    entries = []
    for path in sorted(root.rglob('*.receipt.json')):
        receipt = json.loads(path.read_text())
        archive = Path(receipt['archive'])
        # A receipt can describe only a real completed archive beside itself.
        if archive.is_symlink() or not archive.is_file() or archive.suffix != '.tar':
            raise ValueError('missing or invalid completed archive: ' + str(archive))
        relative = archive.resolve().relative_to(root)
        if archive.resolve().parent != path.resolve().parent:
            raise ValueError('archive is not beside its receipt: ' + str(path))
        if not re.fullmatch('[0-9a-f]{64}', receipt['archiveSha256']):
            raise ValueError('invalid archive digest: ' + str(path))
        entries.append({'archive': str(relative), 'source': receipt['source'],
                        'sourceBytes': receipt['fileBytes'], 'archiveBytes': archive.stat().st_size,
                        'sha256': receipt['archiveSha256'],
                        'verifiedEntries': receipt['verification']['verifiedEntries'],
                        'localSourceRetired': receipt['retired'],
                        'restore': receipt['restore']})
    return entries


def publish(root):
    entries = collect(root)
    catalog = {'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'archives': entries}
    lines = ['# Fleet archive on newnas', '',
             'Browse from Finder: `smb://newnas.local/fleet-archive` or '
             '`smb://10.1.0.76/fleet-archive`, using the existing mackieg NAS account.', '',
             'This share is read-only. Only completed archives with verification receipts '
             'appear here. The catalog reads receipts; it does not rehash every archive.', '',
             'Restore into an empty local directory. Check the archive SHA256 first, then '
             'use the receipt restore command. On Linux use `tar -xzpf` for gzip archives. '
             'Keep active workspaces and databases on local disks.', '',
             'Storedge replication is separate: a completed archive on newnas does not '
             'prove a secondary backup exists.', '']
    for item in entries:
        lines.extend(['## ' + item['archive'], '',
                      '- Original: `' + item['source'] + '`',
                      '- Original bytes: ' + str(item['sourceBytes']),
                      '- Verified entries: ' + str(item['verifiedEntries']),
                      '- SHA256: `' + item['sha256'] + '`',
                      '- Local source retired: ' + str(item['localSourceRetired']),
                      '', '```sh', item['restore'], '```', ''])
    for name, content in [('catalog.json', json.dumps(catalog, indent=2) + '\n'),
                          ('README.md', '\n'.join(lines))]:
        temporary = root / (name + '.partial')
        temporary.write_text(content)
        temporary.chmod(0o600)
        temporary.replace(root / name)
    print(json.dumps({'completedArchives': len(entries),
                      'sourceBytes': sum(x['sourceBytes'] for x in entries)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    publish(parser.parse_args().root)
