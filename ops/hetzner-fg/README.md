# hetzner-fg: Nix store on the /mnt/docker volume (FORGE-205)

hetzner-fg's 75 GiB root disk also carries Forgejo (`/var/lib/gitea`), PostgreSQL,
`/var/lib/forgegraph` and containerd, about 52 GiB of non-Nix data. Each ForgeGraph
registry build and nixci `nix flake check` left about 7 GB of dead store paths, so
`/` kept falling below the 15 GiB `fleet-storage-pressure` floor however often GC ran.

Since 2026-11-22 `/nix` is a bind mount of `/mnt/docker/nix` (sdb, Hetzner volume
`HC_Volume_104330084`), and root went from about 7–15 GiB free to 22 GiB. The
install is Determinate Nix with no `nix-daemon`: root and the ForgeGraph agent use
the store directly. Build directories were already on the volume
(`build-dir = /mnt/HC_Volume_104330084/nix-build`).

| File | Installed as |
| --- | --- |
| `nix.mount` | `/etc/systemd/system/nix.mount`, enabled (`local-fs.target.wants`) |
| `requires-nix.conf` | `/etc/systemd/system/forgegraph-agent.service.d/requires-nix.conf` |
| | `/etc/systemd/system/nix-serve.service.d/requires-nix.conf` |
| | `/etc/systemd/system/promtail.service.d/requires-nix.conf` |
| | `/etc/systemd/system/fleet-nix-gc.service.d/requires-nix.conf` |
| `nix.custom.conf` | `/etc/nix/nix.custom.conf` (0644, included by Determinate's `nix.conf`) |
| `retired.json` | applied with `scripts/retire-node-units.py` (see below) |

`nix.mount` requires `mnt-docker.mount`. Every Nix consumer requires `nix.mount`:
the drop-ins above, plus systemd's implicit dependency for units whose `ExecStart`
is under `/nix/store`. If the volume does not mount,
those units refuse to start instead of running on an empty store. The directory
under the mount on `/` is empty and `chattr +i`, so nothing can write a new store
onto root while it is unmounted.

Stopping `nix.mount` stops all of its dependents (agent, nix-serve, promtail).
Start them again afterwards.

## Automatic GC headroom (LAB-15)

With the store on sdb, Nix's own GC thresholds have to protect the volume's 85%
line. They used to be sized for root (`min-free` 8 GiB, `max-free` 20 GiB), so
the volume could reach about 95% before Nix collected anything.

| | Bytes | Notes |
| --- | --- | --- |
| Usable (df used + avail) | 201,077,346,304 (187.3 GiB) | ext4 reserves the rest of the 196.3 GiB filesystem |
| 85% line (df Use%) | 28.1 GiB free | `fleet-storage-pressure` (shutil) trips later, at ~20.4 GiB free |
| `min-free` | 34359738368 (32 GiB) | line + about half a registry build of dead paths (~7 GiB) |
| `max-free` | 51539607552 (48 GiB) | a pass frees up to two builds' worth, then stops |

During a build Nix checks free space every `min-free-check-interval` (5 s). Below
`min-free` it collects dead paths until `max-free` is free or nothing dead is
left. It does not collect again in that process until free space drops another
3%. The daily `fleet-nix-gc` collects everything dead regardless. If live data
alone takes the volume past 85% (`/mnt/docker/.pnpm-store` is ~38 GiB), GC cannot
help; prune that instead.

Install (the file holds no secrets; Determinate's own `nix.conf` must not be
edited). There is no `nix-daemon`, so every new `nix` process reads the file and
no reload is needed. Install between jobs anyway, so a running build doesn't mix
the old and new limits:

```bash
# no nix/nix-store process and no forgegraph-ci-*.scope running
install -m 644 -o root -g root nix.custom.conf /etc/nix/nix.custom.conf
PATH=/root/.nix-profile/bin:$PATH nix config show | grep -E '^(min|max)-free ='
systemctl is-active nix-serve promtail forgegraph-agent   # all active
```

## Retired units (`retired.json`)

`forgegraph.service` was the self-hosted ForgeGraph server from before the
Cloudflare Worker. It and its env files (which held a dead git.gmac.io token) were
retired in LAB-15:

```bash
python3 scripts/retire-node-units.py ops/hetzner-fg/retired.json           # dry run
python3 scripts/retire-node-units.py ops/hetzner-fg/retired.json --apply   # root, on hetzner-fg
```

Everything is backed up to `/root/retired-node-units/<stamp>.tar.gz` (mode 600)
first. `files` entries may not be under `/var/lib`, `/nix`, `/srv`, `/home` or
`/mnt`, so the tool cannot remove Forgejo, Postgres or Gitea data.

## Moving the store (what was done)

1. Wait until no `nix`/`nix-store` process and no `forgegraph-ci-*.scope` is
   running, then stop `forgegraph-agent` and the `forgegraph-store-prune`,
   `fleet-nix-gc` and `disk-guard` timers.
2. `rsync -aHAXS --numeric-ids /nix/ /mnt/docker/nix/` twice (the second with
   `--delete`), then check the entry counts match.
3. Install the units, `systemctl daemon-reload`, `systemctl enable --now nix.mount`.
4. With `PATH=/root/.nix-profile/bin:$PATH`, run
   `nix-store --verify --check-contents` and `nix eval --expr '1 + 1'`. Systemd
   units have no Nix profile on `PATH`, so set it explicitly.
5. Start the agent and timers. Check one nixci job and one registry deploy succeed.
6. `mount --bind / /run/rootfs` (non-recursive) exposes the old copy. Check it is on
   the root device (`stat -c %d`), empty it with `find -xdev -mindepth 1 -delete`,
   then `chattr +i` the directory.

Before the move, `--check-contents` already reported three paths as modified on
the root copy, with identical hashes after the move: `nodejs-slim-24.14.1` (a
`pnpm` symlink added 2026-06-27), its `-npm` output and the root `profile`. Do not
`--repair` them without finding what depends on the injected `pnpm`.

The daily `fleet-nix-gc` (`../fleet-storage/hetzner-fg-nix-gc.conf`) still applies:
`nix-store --gc` acts on `/nix` wherever it is mounted, and the volume also holds
Docker.

## Rollback

Stop the dependents, then `systemctl disable --now nix.mount`. `chattr -i /nix`,
`rsync -aHAXS --numeric-ids /mnt/docker/nix/ /nix/`, remove the drop-ins,
`systemctl daemon-reload`, and start the services. Root needs about 9 GiB free.
