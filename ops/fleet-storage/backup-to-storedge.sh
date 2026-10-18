#!/bin/bash
# LAB-1: snapshot the NAS artifact store and replicate to the second NAS.
# Dedicated SSH key is restricted by storedge to write-only rsync in one directory.
set -euo pipefail
exec 9>/run/fleet-storage-backup.lock
flock -n 9 || exit 0
ssh_command='ssh -c aes128-gcm@openssh.com -i /root/.ssh/LAB-1-storedge -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3'
state_dir=/var/lib/fleet-storage
install -d -m 700 "$state_dir"
pending="$state_dir/pending-minio-snapshot"
if [ -f "$pending" ]; then
  stamp=$(cat "$pending")
  # Never silently replace a missing frozen source with changing live data.
  [[ "$stamp" =~ ^fleet-storage-[0-9]{8}T[0-9]{6}Z$ ]] || { echo 'Invalid pending backup snapshot' >&2; exit 1; }
  zfs list -H -o name "tank/apps/minio@$stamp" >/dev/null
else
  stamp="fleet-storage-$(date -u +%Y%m%dT%H%M%SZ)"
  zfs snapshot "tank/apps/minio@$stamp"
  (umask 077; printf '%s\n' "$stamp" > "$pending.partial")
  mv "$pending.partial" "$pending"
fi
snapshot="/tank/apps/minio/.zfs/snapshot/$stamp/"
rsync -aH --numeric-ids --timeout=120 --delete-delay --checksum -e "$ssh_command" "$snapshot" mackieg@100.113.97.115:minio/
# Archives are immutable after rename; incomplete transfers are excluded.
rsync -aH --numeric-ids --timeout=120 --checksum --exclude='*.partial' -e "$ssh_command" /tank/archive/fleet-storage/ mackieg@100.113.97.115:archives/
# Keep service credentials root-only, alongside the exact pinned container image.
config_dir=/var/lib/fleet-storage/service-config
install -d -m 700 "$config_dir"
install -m 600 /etc/forgegraph/homelab-storage-minio.env "$config_dir/"
install -m 600 /etc/systemd/system/forgegraph-minio.service "$config_dir/"
image=$(docker inspect --format '{{.Image}}' forgegraph-minio)
[[ "$image" =~ ^sha256:[0-9a-f]{64}$ ]]
image_file="$config_dir/minio-${image#sha256:}.tar.gz"
if [ ! -f "$image_file" ]; then
  (umask 077; docker save "$image" | gzip -1 > "$image_file.partial")
  mv "$image_file.partial" "$image_file"
fi
rsync -aH --numeric-ids --timeout=120 --checksum --exclude='*.partial' -e "$ssh_command" "$config_dir/" mackieg@100.113.97.115:service-config/
# Keep the seven latest successful-run snapshots. Failed backups never prune snapshots.
snapshots=()
while IFS= read -r name; do snapshots+=("$name"); done < <(zfs list -H -t snapshot -o name -s creation -r tank/apps/minio | grep '^tank/apps/minio@fleet-storage-')
count=${#snapshots[@]}
if (( count > 7 )); then
  for ((i=0; i<count-7; i++)); do zfs destroy "${snapshots[$i]}"; done
fi
rm "$pending"
echo "$(date -u +%FT%TZ) verified checksum replication to storedge completed for $stamp"
