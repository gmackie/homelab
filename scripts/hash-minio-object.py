#!/usr/bin/env python3
"""Restricted SSH helper: read own-prefix snapshot through local S3 and return SHA256."""
import importlib.util
import json
from pathlib import Path
import sys

request = json.loads(sys.stdin.read(4097))
key = request['key']
if not isinstance(key, str) or not key.startswith('hetzner-master/') or '..' in key.split('/'):
    raise RuntimeError('only hetzner-master snapshot objects can be verified')
values = {}
for line in Path('/etc/forgegraph/homelab-storage-minio.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        name, value = line.split('=', 1)
        values[name] = value.strip().strip('"').strip("'")
spec = importlib.util.spec_from_file_location('retention', Path(__file__).with_name('retain-local-snapshots.py'))
retention = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retention)
print(retention.remote_digest({'s3_endpoint': '127.0.0.1:9010', 's3_bucket': 'forgegraph-artifacts',
                               's3_access_key': values['MINIO_ROOT_USER'], 's3_secret_key': values['MINIO_ROOT_PASSWORD']}, key))
