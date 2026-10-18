#!/usr/bin/env python3
"""Keep newest daily dump locally; retire older copies only after S3 SHA256 readback.

Default is inspection. Never removes NAS objects, pre-restore dumps or live DBs.
"""
import argparse
import datetime
import hashlib
import hmac
import json
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request


def sha256(stream):
    h = hashlib.sha256()
    for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
        h.update(chunk)
    return h.hexdigest()


def candidates(root):
    result = []
    for directory in sorted(root.iterdir()):
        if directory.is_symlink() or not directory.is_dir():
            continue
        files = sorted(p for p in directory.iterdir() if not p.is_symlink() and p.is_file()
                       and re.fullmatch(re.escape(directory.name) + r'-\d{4}-\d{2}-\d{2}\.sql\.gz', p.name))
        result.extend(files[:-1])
    return result


def remote_digest(config, key):
    endpoint = config['s3_endpoint']
    scheme = 'https' if config.get('s3_use_ssl') else 'http'
    path = '/' + urllib.parse.quote(config['s3_bucket'] + '/' + key, safe='/')
    now = datetime.datetime.now(datetime.timezone.utc)
    stamp = now.strftime('%Y%m%dT%H%M%SZ')
    day = stamp[:8]
    empty = hashlib.sha256(b'').hexdigest()
    headers = {'host': endpoint, 'x-amz-content-sha256': empty, 'x-amz-date': stamp}
    signed = ';'.join(sorted(headers))
    canonical = 'GET\n' + path + '\n\n' + ''.join(k + ':' + headers[k] + '\n' for k in sorted(headers)) + '\n' + signed + '\n' + empty
    scope = day + '/us-east-1/s3/aws4_request'
    message = 'AWS4-HMAC-SHA256\n' + stamp + '\n' + scope + '\n' + hashlib.sha256(canonical.encode()).hexdigest()
    keybytes = ('AWS4' + config['s3_secret_key']).encode()
    for part in [day, 'us-east-1', 's3', 'aws4_request']:
        keybytes = hmac.new(keybytes, part.encode(), hashlib.sha256).digest()
    signature = hmac.new(keybytes, message.encode(), hashlib.sha256).hexdigest()
    headers['Authorization'] = 'AWS4-HMAC-SHA256 Credential=' + config['s3_access_key'] + '/' + scope + ', SignedHeaders=' + signed + ', Signature=' + signature
    with urllib.request.urlopen(urllib.request.Request(scheme + '://' + endpoint + path, headers=headers), timeout=120) as response:
        return sha256(response)


def retire(path, expected, receipt_dir):
    original = path.stat()
    with path.open('rb') as f:
        if sha256(f) != expected:
            raise RuntimeError('local/remote SHA256 mismatch: ' + str(path))
    handles = subprocess.run(['lsof', '-nP', '-Fpn'], capture_output=True, text=True)
    if handles.returncode != 0 or any(line == 'n' + str(path) for line in handles.stdout.splitlines()):
        raise RuntimeError('cannot establish inactivity: ' + str(path))
    latest = path.stat()
    if (latest.st_dev, latest.st_ino, latest.st_size, latest.st_mtime_ns) != (original.st_dev, original.st_ino, original.st_size, original.st_mtime_ns):
        raise RuntimeError('snapshot changed during verification: ' + str(path))
    receipt_dir.mkdir(parents=True, exist_ok=True)
    receipt = receipt_dir / (path.name + '.json')
    receipt.write_text(json.dumps({'source': str(path), 'sha256': expected, 'bytes': latest.st_size,
                                  'retired': False, 'verifiedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()}))
    path.unlink()
    data = json.loads(receipt.read_text()); data['retired'] = True
    receipt.write_text(json.dumps(data) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('/var/lib/forgegraph/snapshots'))
    parser.add_argument('--config', type=Path, default=Path('/etc/forgegraph/agent.json'))
    parser.add_argument('--receipts', type=Path, default=Path('/var/lib/forgegraph/storage-receipts'))
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--ssh-verifier', help='trusted NAS host with the restricted hash-minio-object helper')
    parser.add_argument('--ssh-key', type=Path, help='dedicated SSH verifier key')
    args = parser.parse_args()
    if not args.root.exists():
        return
    config = json.loads(args.config.read_text())
    if not config.get('snapshot', {}).get('s3_endpoint'):
        raise RuntimeError('NAS snapshot destination is not configured; local dumps retained')
    for path in candidates(args.root):
        key = config['node_name'] + '/' + path.parent.name + '/' + path.name
        print(json.dumps({'candidate': str(path), 'object': key, 'apply': args.apply}), flush=True)
        if args.apply:
            if args.ssh_verifier:
                if not args.ssh_key:
                    raise RuntimeError('--ssh-key is required with --ssh-verifier')
                expected = subprocess.check_output([
                    'ssh', '-i', str(args.ssh_key), '-o', 'BatchMode=yes',
                    '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=15',
                    args.ssh_verifier,
                ], input=json.dumps({'key': key}), text=True, timeout=1800).strip()
                if not re.fullmatch('[0-9a-f]{64}', expected):
                    raise RuntimeError('invalid digest from trusted verifier')
            else:
                expected = remote_digest(config['snapshot'], key)
            retire(path, expected, args.receipts)
            print(json.dumps({'retired': str(path), 'sha256': expected}), flush=True)


if __name__ == '__main__':
    main()
