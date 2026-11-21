# hetzner-bob node-local retirements

`retired.json` records the node-local systemd units, nginx sites, and Let's Encrypt
lineages on hetzner-bob that were retired on purpose. Each entry has its issue, the reason,
and how to restore it, so nobody re-installs a dead unit from an old runbook.

```bash
python3 scripts/retire-node-units.py ops/hetzner-bob/retired.json           # dry run
sudo python3 scripts/retire-node-units.py ops/hetzner-bob/retired.json --apply
```

`--apply` first writes a mode-600 tarball of every path it will touch to
`/root/retired-node-units/<stamp>.tar.gz`. It then stops, disables, and removes each unit,
runs `daemon-reload` and `reset-failed`, removes the nginx site, and runs `nginx -t` before
`reload`. It deletes certbot lineages last. Every step is fail-fast, and a second run does
nothing. The script refuses to touch bob production services (gateway, ooda-runner, web).
