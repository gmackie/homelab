#!/bin/bash
# LAB-1: snapshot the NAS artifact store and replicate to the second NAS.
# Dedicated SSH key is restricted by storedge to write-only rsync in one directory.
set -euo pipefail
exec 9>/run/fleet-storage-backup.lock
flock -n 9 || exit 0
stamp="fleet-storage-$(date -u +%Y%m%dT%H%M%SZ)"
ssh_command='ssh -c aes128-gcm@openssh.com -i /root/.ssh/LAB-1-storedge -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15'
zfs snapshot "tank/apps/minio@$stamp"
snapshot="/tank/apps/minio/.zfs/snapshot/$stamp/"
rsync -aH --numeric-ids --delete-delay --checksum -e "$ssh_command" "$snapshot" mackieg@100.113.97.115:minio/
# Archives are immutable after rename; incomplete transfers are excluded.
rsync -aH --numeric-ids --checksum --exclude='*.partial' -e "$ssh_command" /tank/archive/fleet-storage/ mackieg@100.113.97.115:archives/
# Keep the seven latest successful-run snapshots. Failed backups never prune snapshots.
mapfile -t snapshots < <(zfs list -H -t snapshot -o name -s creation -r tank/apps/minio | grep '^tank/apps/minio@fleet-storage-')
count=${#snapshots[@]}
if (( count > 7 )); then
  for ((i=0; i<count-7; i++)); do zfs destroy "${snapshots[$i]}"; done
fi
echo "$(date -u +%FT%TZ) verified checksum replication to storedge completed for $stamp"
