#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config_dir="$repo_root/ops/arr-tv-movies-recovery"

exports_file="$config_dir/newnas.exports"
fstab_entry="$config_dir/labnuc-fstab.entry"
service_dropin="$config_dir/media-storage.conf"
jellyfin_dropin="$config_dir/jellyfin-tv-movies.conf"

grep -Fqx '/tank/media/library 100.64.115.45(rw,sync,no_subtree_check,root_squash,crossmnt)' "$exports_file"
grep -Fq '100.123.166.5:/tank/media/library /mnt/nas/homelab nfs4' "$fstab_entry"
grep -Fq 'nofail,_netdev,x-systemd.automount' "$fstab_entry"
if grep -Fq '192.168.0.250' "$fstab_entry"; then
    echo 'obsolete NAS address remains in the replacement mount entry' >&2
    exit 1
fi
grep -Fqx 'RequiresMountsFor=/mnt/nas/homelab' "$service_dropin"
grep -Fq -- '-v /mnt/nas/homelab/movies:/media/movies:ro' "$jellyfin_dropin"
grep -Fq -- '-v /mnt/nas/homelab/tv:/media/tv:ro' "$jellyfin_dropin"
if grep -Eq '/mnt/nas/homelab/(media|media-general)' "$jellyfin_dropin"; then
    echo 'out-of-scope Jellyfin media mounts remain in the TV/movie override' >&2
    exit 1
fi
