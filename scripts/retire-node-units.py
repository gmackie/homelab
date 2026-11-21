#!/usr/bin/env python3
"""Retire obsolete node-local units, nginx sites and LE lineages from a manifest.

Dry-run by default (prints the plan). On the node, as root:
    python3 retire-node-units.py ops/hetzner-bob/retired.json --apply
Everything is backed up to /root/retired-node-units/<stamp>.tar.gz (mode 600)
before anything is removed; every step is fail-fast.
"""
import argparse
import datetime as dt
import json
import os
import shlex
import subprocess
import sys

BACKUP_DIR = '/root/retired-node-units'


def paths_for(entry):
    paths = [f'/etc/systemd/system/{u}' for u in entry.get('units', [])]
    for site in entry.get('nginx_sites', []):
        paths += [f'/etc/nginx/sites-enabled/{site}', f'/etc/nginx/sites-available/{site}']
    for cert in entry.get('certs', []):
        paths += [f'/etc/letsencrypt/live/{cert}', f'/etc/letsencrypt/archive/{cert}',
                  f'/etc/letsencrypt/renewal/{cert}.conf']
    return paths


def _guard(manifest):
    protected = set(manifest.get('protected', [])) | {'bob-gateway', 'ooda-runner', 'bob-web'}
    for entry in manifest['retired']:
        for unit in entry.get('units', []):
            base = unit.rsplit('.', 1)[0]
            if unit in protected or base in protected or any(p in unit for p in ('gateway', 'ooda-runner')):
                raise ValueError(f'{entry["id"]}: refusing to retire protected unit {unit}')


def plan(manifest, stamp, exists=lambda p: True):
    _guard(manifest)
    entries = manifest['retired']
    present = [p for e in entries for p in paths_for(e) if exists(p)]
    steps = []
    if present:
        archive = f'{BACKUP_DIR}/{stamp}.tar.gz'
        steps.append({'cmd': f'install -d -m 700 {BACKUP_DIR} && tar -czf {archive} '
                             + ' '.join(shlex.quote(p) for p in present) + f' && chmod 600 {archive}'})
    units = [u for e in entries for u in e.get('units', []) if exists(f'/etc/systemd/system/{u}')]
    for u in units:
        steps.append({'cmd': f'systemctl disable --now {u}'})
    for u in units:
        steps.append({'cmd': f'rm -f /etc/systemd/system/{u}'})
    steps.append({'cmd': 'systemctl daemon-reload'})
    reset = [u for e in entries for u in e.get('units', [])]
    if reset:
        steps.append({'cmd': 'systemctl reset-failed ' + ' '.join(reset) + ' 2>/dev/null || true'})
    sites = [s for e in entries for s in e.get('nginx_sites', [])]
    touched_nginx = False
    for s in sites:
        for p in (f'/etc/nginx/sites-enabled/{s}', f'/etc/nginx/sites-available/{s}'):
            if exists(p):
                steps.append({'cmd': f'rm -f {p}'})
                touched_nginx = True
    if touched_nginx:
        steps.append({'cmd': 'nginx -t'})
        steps.append({'cmd': 'systemctl reload nginx'})
    for e in entries:
        for c in e.get('certs', []):
            if exists(f'/etc/letsencrypt/renewal/{c}.conf'):
                steps.append({'cmd': f'certbot delete --non-interactive --cert-name {c}'})
    return steps


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('manifest')
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args(argv)
    manifest = json.load(open(args.manifest))
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    steps = plan(manifest, stamp, exists=os.path.lexists)
    for s in steps:
        print(('+ ' if args.apply else 'would run: ') + s['cmd'], flush=True)
        if args.apply:
            subprocess.run(s['cmd'], shell=True, check=True)
    if args.apply:
        print(f'retired {[e["id"] for e in manifest["retired"]]}; backup in {BACKUP_DIR}/{stamp}.tar.gz')
    return 0


if __name__ == '__main__':
    sys.exit(main())
