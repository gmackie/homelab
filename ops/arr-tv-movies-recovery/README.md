# TV and movie storage recovery

This directory records the host-level configuration used to restore the
TV/movie media path between `newnas` and `labnuc`.

- `newnas.exports` restricts the NFS export to labnuc's reserved LAN address
  and keeps root squashing enabled.
- `labnuc-fstab.entry` mounts the export through a systemd automount so boot is
  not blocked when the NAS is unavailable.
- `forgegraph-media-storage-online.service` and
  `forgegraph-wait-media-storage` wait for the LAN DNS name and the actual
  newnas NFS mount to become ready after boot.
- `media-storage.conf` makes storage-backed services depend on that readiness
  gate, so a one-time early mount failure does not leave them inactive.
- `jellyfin-tv-movies.conf` removes the obsolete music/general bind mounts and
  exposes only the read-only movie and TV libraries requested for this phase.
- `forgegraph-tailscale-local-routing.service` prevents Homebase's advertised
  `10.1.0.0/16` route from overriding labnuc's directly connected
  `10.1.0.0/23` LAN.
- `pihole-dns-hosts.json` is the authoritative set of local media names served
  by Pi-hole, including `newnas.homelab.lan` at its reserved primary LAN
  address, `10.1.0.75`.
- `caddy-media.conf` provides the matching HTTP virtual hosts and keeps the
  application ports off user-facing URLs.
- `Caddyfile.labnuc` makes port 80 Caddy's local HTTP listener while preserving
  the existing labnuc administration route and imported site directory.
- `forgegraph-speedtest.service` keeps Speedtest Tracker on a loopback-only
  bridge port so its bundled nginx cannot take Caddy's ports 80 and 443.

Install the export fragment under `/etc/exports.d/` on newnas and the fstab
entry in `/etc/fstab` on labnuc. Install `forgegraph-wait-media-storage` as
`/usr/local/libexec/forgegraph-wait-media-storage`, install the readiness unit
under `/etc/systemd/system/`, and install the service fragments as systemd
drop-ins. Run `exportfs -ra`, `systemctl daemon-reload`, `systemctl enable
forgegraph-media-storage-online.service`, and `findmnt --verify` before starting
the media services.

Provider and indexer credentials do not belong in this repository. Configure
them directly in SABnzbd and Prowlarr using the local service interfaces or a
secret-management path.

SABnzbd treats the Tailscale CGNAT range as external unless it is listed under
the advanced `local_ranges` setting. Keep general internet exposure disabled
and use `10.0.0.0/8, 100.64.0.0/10` for the homelab LAN and tailnet. Its host
whitelist should contain `labnuc`, `100.64.115.45`, and
`sabnzbd.homelab.lan`.

The NewNAS primary NIC (`6c:1f:f7:40:40:c8`) is reserved as `10.1.0.75` on
the Default UniFi DHCP scope. Keep its second NIC (`6c:1f:f7:40:40:c9`)
reserved as `10.1.0.76`; do not attach either reservation to the Trusted
`10.1.10.0/24` scope. Allow TCP/2049 from labnuc's reserved `10.1.1.188`
address in NewNAS UFW. The media mount must resolve `newnas.homelab.lan` to
`10.1.0.75` and use that LAN path, not the NewNAS Tailscale address.

## Local and tailnet DNS

Pi-hole's embedded web server must not occupy ports 80 or 443 because Caddy
owns port 80 for the `*.homelab.lan` virtual hosts. Configure Pi-hole v6 from
inside the container, using the JSON file in this directory as the value of
`dns.hosts`:

```bash
pihole-FTL --config dns.hosts '<contents of pihole-dns-hosts.json>'
pihole-FTL --config dns.listeningMode ALL
pihole-FTL --config webserver.port '8081,[::]:8081'
```

Install `caddy-media.conf` as `/etc/caddy/conf.d/media.conf`, validate the full
configuration with `caddy validate --config /etc/caddy/Caddyfile`, and reload
Caddy only after Pi-hole has released ports 80 and 443.

Install and enable `forgegraph-tailscale-local-routing.service` on labnuc.
This host is physically attached to the homelab LAN and must not accept
Homebase's overlapping subnet route.

The UniFi DHCP server should advertise only `10.1.1.188` as DNS on the Default,
Trusted, IoT, Lab, Media, Cameras, and Guest networks. Do not retain the stale
`192.168.0.248`, Google DNS, or per-VLAN gateway fallback entries because they
allow clients to bypass Pi-hole.

On a UniFi OS gateway, apply that desired state through the Network service
configuration interface and verify the generated dnsmasq fragments under
`/run/dnsmasq.dhcp.conf.d/`. Back up the controller database and the live
service configuration before changing them.

In the Tailscale DNS configuration, use `100.64.115.45` as the restricted
nameserver for `homelab.lan`, replacing any stale resolver for that suffix.
Keep MagicDNS enabled; a global DNS override is not required for this private
suffix.
