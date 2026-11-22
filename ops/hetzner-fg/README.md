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

`nix.mount` requires `mnt-docker.mount`. Every Nix consumer requires `nix.mount`:
the drop-ins above, plus systemd's implicit dependency for units whose `ExecStart`
is under `/nix/store` (such as `forgegraph.service`). If the volume does not mount,
those units refuse to start instead of running on an empty store. The directory
under the mount on `/` is empty and `chattr +i`, so nothing can write a new store
onto root while it is unmounted.

Stopping `nix.mount` stops all of its dependents (agent, nix-serve, promtail,
forgegraph). Start them again afterwards.

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
