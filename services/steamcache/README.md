# Steam Cache

This directory contains a current `LanCache` deployment for Steam and other game CDNs using the upstream `lancachenet/monolithic` and `lancachenet/lancache-dns` containers.

## Recommended host

Use `storedge.local` (`192.168.0.181`) unless `newnas.local` (`192.168.0.190`) has meaningfully better free space or faster storage.

Reasoning:

- Both hosts answer on SSH and SMB.
- `storedge.local` identifies itself as Debian 12 over SSH, which is the lower-risk target for a Docker-based deployment.
- `newnas.local` is also usable, but nothing from the current machine shows it is the better cache box.

## Important network note

The host being named `storedge.local` or `newnas.local` does not make Steam use the cache.

Steam caching works when LAN clients use the cache host for DNS, or when your existing DNS server is explicitly loaded with the LanCache domain overrides. The easiest setup is:

- Run `lancache-dns` on the cache host
- Set your router DHCP DNS server to the cache host IP
- Set `UPSTREAM_DNS` in `.env` to your existing resolver, currently `192.168.0.248`

`.local` hostnames are still fine for admin access if your clients support mDNS/Bonjour, but they are not the caching mechanism.

## Files

- `docker-compose.yml`: cache + DNS stack
- `.env.example`: env template prefilled for `storedge.local`

## Deploy on the target host

1. Install Docker Engine and Docker Compose plugin.
2. Copy this directory to the target host.
3. Copy `.env.example` to `.env`.
4. If you choose `newnas.local`, change both `LANCACHE_IP` and `DNS_BIND_IP` to `192.168.0.190`.
5. Set `CACHE_ROOT` to a large local path on the target host.
6. Start the stack:

```bash
docker compose up -d
```

## Verify

After changing DHCP DNS to the cache host IP, test from a client:

```bash
nslookup steam.cache.lancache.net
nslookup lancache.steamcontent.com
```

Both should return the cache host IP, either `192.168.0.181` or `192.168.0.190`.

Then download a Steam title twice. The first pass warms the cache. The second pass should come from LAN speed.

## If you want to keep Pi-hole as the client DNS

That is still possible, but it is a different setup:

- Pi-hole must serve the LanCache override domains itself, not just forward random lookups upstream.
- The official project points to the `cache-domains` generators for that path.

This directory is set up for the simpler and more reliable "cache box is the DNS server for clients" model.
