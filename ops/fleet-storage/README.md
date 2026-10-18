# LAB-1 fleet build storage

Local disks are working space. NAS holds retained artifacts and historical output.
Active checkouts, SQLite/Postgres databases, Unity projects, and node_modules stay
local; do not replace them with network symlinks. One pnpm store per local volume
allows hardlinks/clones without adding network latency to builds.

## Deployed controls

- Preflight runner PR 19 checks both workspace and home filesystems before every
  job claim. preflight-app PR 58 provisions a 25 GiB admission floor; both Macs
  persist that floor. No automatic cache deletion in the admission check.
- ForgeGraph PR 877 accounts for hidden CI/worktree paths and external CI root
  symlinks. Generic reaping protects all managed CI/worktrees, even with `--all`.
- `storage-pressure.py` records free GiB and utilization hourly, before the 25 GiB
  floor. Linux uses a systemd timer; Macs replace the legacy age-based sweep
  LaunchAgent with read-only telemetry. Pressure returns failure for monitoring.
- `journald-storage.conf` limits Linux journals to 512 MiB/14 days and reserves
  2 GiB. Application-specific databases and Docker volumes are never pruned.

## Archive and restore

`scripts/archive-to-nas.py SOURCE --destination
/tank/archive/fleet-storage/DATE/HOST/NAME --receipts RECEIPTS` inspects by default.
Add `--apply` to stream over SSH, `--compress` for dependency caches, and explicitly
add `--retire` only for a known inactive directory. It hashes every file, verifies
remote archive SHA256 and every file/symlink/mode, then rechecks the source and
open handles before retirement. Source changes or verification errors retain it.
Receipts include the restore command and also live beside the archive on newnas.
A `.partial` is an interrupted transfer, never proof of an archive. Remove only
that exact partial after a replacement archive has verified successfully.

The guard is an inactivity check, not a lock against another process starting.
Use it only for historical trees whose owners have stopped writing. Do not use
for live databases, running builds, or active workspaces. Keep source quiescent
through verification and retirement. Linux/macOS permissions can hide processes;
use an account able to see the relevant owners' handles.

To restore, create an empty local target then run the receipt's SSH/tar command.
Compressed archives autodetect with BSD tar; GNU tar requires `-xzpf` for gzip.
Do not extract over a live workspace. Preserve the manifest and receipt with data.

## MinIO on newnas

Data: ZFS `tank/apps/minio`, mount `/tank/apps/minio`. MinIO image is pinned to
the exact image exported from labnuc, same RELEASE.2025-09-07T16-13-09Z binary.
Root-only credentials are `/etc/forgegraph/homelab-storage-minio.env`, never in Git.
`forgegraph-minio.service` runs on newnas. Labnuc retains TCP ports 9010 and 9011
through socket-proxyd to newnas, preserving consumers' existing endpoints.

Cutover: live rsync, stop source, final rsync, checksum dry-run with no differences,
start destination, authenticated bucket/object comparison and PUT/GET/DELETE via
labnuc endpoint. Preserve the stopped source until validation passes. Roll back
by stopping proxy sockets/services, stopping NAS MinIO, final reverse sync if any
new writes occurred, restoring the original labnuc service and enabling it. Never
start both services against independent writable copies.

## Second NAS and retention

`backup-to-storedge.sh` snapshots MinIO, copies the snapshot with rsync checksums
to storedge `/mnt/core/srv/backups/fleet-storage/minio`, and copies completed
archives to `.../archives`. SSH uses a dedicated root key on newnas; storedge
restricts it to write-only rsync in this backup directory, from newnas's tailnet
address. Preserve SSH_ORIGINAL_COMMAND through sudo for rrsync validation.

The daily timer runs 04:15 UTC plus up to 15 minutes jitter. Retain the seven
latest MinIO snapshots after successful replication; failed replication does not
prune snapshots. Snapshots are crash-consistent, not an application transaction
backup. Storedge's MinIO copy mirrors deletions; completed archive files are
immutable and copied without deletion. This is recovery redundancy within the
same site, not an off-site backup. Monitor the timer result and NAS capacity.

A backup failure must be resolved rather than treating a local copy as disposable.
No automatic build-product retention is enabled until owners choose that policy.

## Local database snapshot retention

`fleet-snapshot-retention.timer` runs daily at 08:15 UTC (up to 15 minutes jitter),
after the agent's 03:00 UTC database dumps. It keeps the newest dated dump per
database locally. An older local dump is removed only after an authenticated
full-object S3 GET and a matching SHA256 of the local file, with no open handles
or changes during verification. Pre-restore snapshots, unknown filenames and
symlinks are excluded. Default script invocation is inspect-only. Missing S3
configuration, failed download or mismatched content fails closed. Receipts live
in `/var/lib/forgegraph/storage-receipts`. NAS daily/weekly/monthly history is
unchanged. This timer is installed on hetzner-master, the host with the large
local database dumps; it never touches PostgreSQL data directories.
