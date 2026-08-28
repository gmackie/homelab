# TV and movie storage recovery

This directory records the host-level configuration used to restore the
TV/movie media path between `newnas` and `labnuc`.

- `newnas.exports` restricts the NFS export to labnuc's Tailscale address and
  keeps root squashing enabled.
- `labnuc-fstab.entry` mounts the export through a systemd automount so boot is
  not blocked when the NAS is unavailable.
- `media-storage.conf` makes storage-backed services depend on the actual
  `/mnt/nas/homelab` mount.
- `jellyfin-tv-movies.conf` removes the obsolete music/general bind mounts and
  exposes only the read-only movie and TV libraries requested for this phase.

Install the export fragment under `/etc/exports.d/` on newnas, the fstab entry
in `/etc/fstab` on labnuc, and the service fragments as systemd drop-ins. Run
`exportfs -ra`, `systemctl daemon-reload`, and `findmnt --verify` before starting
the media services.

Provider and indexer credentials do not belong in this repository. Configure
them directly in SABnzbd and Prowlarr using the local service interfaces or a
secret-management path.

SABnzbd treats the Tailscale CGNAT range as external unless it is listed under
the advanced `local_ranges` setting. Keep general internet exposure disabled
and use `10.0.0.0/8, 100.64.0.0/10` for the homelab LAN and tailnet. Its host
whitelist should contain `labnuc`, `100.64.115.45`, and
`sabnzbd.homelab.lan`.
