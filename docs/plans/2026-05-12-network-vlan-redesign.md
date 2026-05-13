# Network VLAN Redesign

Complete network infrastructure redesign migrating from a flat `192.168.0.0/24` to a segmented `10.x.x.x` addressing scheme with VLAN isolation, multi-site connectivity, and future-proofed address space.

## Current State

- Flat `192.168.0.0/24` network, no VLANs (all "Default")
- 32 client devices on a single subnet
- Ubiquiti Dream Machine Pro as router/controller
- USW Pro 24 PoE main switch + US 8 60W secondary switch
- 9x UAP-AC-Pro broadcasting single SSID "mackieNet"
- GL.iNET travel router on `192.168.8.0/24` (trip use)
- Tailscale mesh: labnuc + Hetzner VPS

## Design Goals

- VLAN segmentation by trust level and function
- IoT isolation (no internet except NTP/updates)
- Camera network with no internet access (future)
- Guest network with internet-only access
- Multi-site connectivity: home, van (Starlink), travel router
- Reserved address space for corporate and startup networks
- Tailscale mesh connecting all sites
- Automated deployment via APIs and scripts

---

## Address Architecture

### Scheme: `10.<site>.<vlan>.<host>`

Each site gets a `/16`. Each VLAN within a site gets a `/24`. VLAN ID matches the third octet for readability.

### Site Allocations

| Site ID | Range | Description | Tailscale Subnet Router |
|---------|-------|-------------|------------------------|
| `10.1.x.x/16` | Home | UDM Pro, main network | labnuc |
| `10.2.x.x/16` | Van | GL.iNET + Starlink | GL.iNET van router |
| `10.3.x.x/16` | Travel | GL.iNET trip router | GL.iNET trip router |
| `10.4-9.x.x` | *Reserved* | Future personal sites | -- |
| `10.10.x.x/16` | Corporate | Reserved for corp network | -- |
| `10.11.x.x/16` | Startup 1 | Reserved | -- |
| `10.12.x.x/16` | Startup 2 | Reserved | -- |
| `10.13.x.x/16` | Startup 3 | Reserved | -- |
| `10.14-99.x.x` | *Unallocated* | Future growth | -- |
| `100.x.x.x` | Tailscale | Overlay mesh (automatic) | All nodes |

---

## Site 1: Home (`10.1.x.x`)

### VLAN Definitions

| VLAN ID | Subnet | Purpose | Gateway | Static Range | DHCP Range |
|---------|--------|---------|---------|-------------|------------|
| 1 | `10.1.1.0/24` | Management | `.1` | `.2-.99` | `.100-.199` |
| 10 | `10.1.10.0/24` | Trusted LAN | `.1` | `.2-.99` | `.100-.199` |
| 20 | `10.1.20.0/24` | IoT | `.1` | `.2-.99` | `.100-.199` |
| 30 | `10.1.30.0/24` | Lab / Servers | `.1` | `.2-.99` | `.100-.199` |
| 40 | `10.1.40.0/24` | Media / Entertainment | `.1` | `.2-.99` | `.100-.199` |
| 50 | `10.1.50.0/24` | Security Cameras | `.1` | `.2-.99` | `.100-.199` |
| 99 | `10.1.99.0/24` | Guest | `.1` | -- | `.100-.249` |

### Device Assignments

#### VLAN 1 -- Management

| Device | Old IP | New IP | Connection | Notes |
|--------|--------|--------|------------|-------|
| UDM Pro | 192.168.0.1 | `10.1.1.1` | Gateway | Router + controller |
| USW Pro 24 PoE | 192.168.0.3 | `10.1.1.2` | Wired | Main switch |
| US 8 60W | -- | `10.1.1.3` | Wired | Secondary switch |
| UAP-AC-Pro x9 | DHCP | `10.1.1.10-.18` | PoE | AP static block |
| Pi-hole RPi | 192.168.0.248 | `10.1.1.50` | US 8 Port 3 | DNS for all VLANs |
| SLZB-06M | 192.168.0.254 | `10.1.1.51` | US 8 Port 7 | Zigbee coordinator |

#### VLAN 10 -- Trusted LAN

| Device | Old IP | New IP | Connection | Notes |
|--------|--------|--------|------------|-------|
| iPhone 15 Pro | 192.168.0.178 | DHCP | Wi-Fi (MackieNet) | |
| iPhone-gm | 192.168.0.61 | DHCP | Wi-Fi (MackieNet) | |
| Apple Laptop | 192.168.0.131 | DHCP | Wi-Fi | |
| Framework-13 | 192.168.0.188 | `10.1.10.2` | US 8 Port 4 | Workstation |
| Brother Printer | 192.168.0.99 | `10.1.10.50` | US 8 Port 2 | Static for discovery |
| Bambu Lab X1C | 192.168.0.116 | `10.1.10.51` | Wi-Fi (MackieNet) | Static for slicer |

#### VLAN 20 -- IoT

| Device | Old IP | New IP | Connection | Notes |
|--------|--------|--------|------------|-------|
| Home Assistant | 192.168.0.97 | `10.1.20.2` | US 8 Port 5 | Needs Lab access |
| Hue Bridge | 192.168.0.117 | `10.1.20.3` | Wired | Static for HA |
| Reolink TrackMix | 192.168.0.120 | DHCP | Wi-Fi | |
| Elgato Key Light x2 | 192.168.0.158/.160 | DHCP | Wi-Fi | |
| ESP32-B56C48 | 192.168.0.59 | DHCP | Wi-Fi | |
| TP-Link EP25 | 192.168.0.113 | DHCP | Wi-Fi | Smart plug |
| Peloton | 192.168.0.16 | DHCP | Wi-Fi | |

#### VLAN 30 -- Lab / Servers

| Device | Old IP | New IP | Connection | Notes |
|--------|--------|--------|------------|-------|
| labnuc (Beelink) | 192.168.0.204 | `10.1.30.2` | USW Pro 24 | K3s, Tailscale subnet router |
| nuckvm (Lenovo) | 192.168.0.119 | `10.1.30.3` | USW Pro 24 | VM host |
| storedge (Synology) | 192.168.0.250 | `10.1.30.10` | USW Pro 24 | NAS |
| storedge (Turing Pi) | 192.168.0.250 | `10.1.30.11` | USW Pro 24 | Compute board |
| newnas (Ugreen) | 192.168.0.189/.190 | `10.1.30.12` | USW Pro 24 | Dual-NIC NAS |
| vanas (Domoticz) | 192.168.0.23 | `10.1.30.13` | US 8 Port 6 | |

#### VLAN 40 -- Media / Entertainment

| Device | Old IP | New IP | Connection | Notes |
|--------|--------|--------|------------|-------|
| Xbox | 192.168.0.9 | `10.1.40.2` | USW Pro 24 | Static for port forwarding |
| TCL Smart TV | 192.168.0.41 | DHCP | Wi-Fi | |
| Chromecast | 192.168.0.232 | DHCP | Wi-Fi | |
| Oculus Quest 3 | 192.168.0.192 | DHCP | Wi-Fi | |

#### VLAN 50 -- Security Cameras

Empty -- reserved for future cameras. No internet access.

#### VLAN 99 -- Guest

No static devices. DHCP only, internet-only access. Separate SSID.

---

## Wi-Fi SSIDs

| SSID | VLAN | Band | Purpose |
|------|------|------|---------|
| MackieNet | 10 (Trusted) | 2.4 + 5 GHz | Personal devices |
| *(TBD -- IoT)* | 20 (IoT) | 2.4 GHz only | IoT devices |
| *(TBD -- Media)* | 40 (Media) | 5 GHz preferred | TV, Chromecast, Quest |
| *(TBD -- Guest)* | 99 (Guest) | 2.4 + 5 GHz | Visitors |

Cameras (VLAN 50) get their own SSID when Wi-Fi cameras are added, or use PoE.

---

## Firewall Rules

Default policy: **DENY all inter-VLAN traffic.** Whitelist specific flows.

### Allowed Flows

| # | Source | Destination | Ports/Protocol | Purpose |
|---|--------|-------------|---------------|---------|
| 1 | All VLANs | `10.1.1.50` | UDP/TCP 53 | DNS via Pi-hole |
| 2 | Trusted (10) | IoT (20) | All | Phone -> Hue, Elgato, HA |
| 3 | Trusted (10) | Lab (30) | All | Laptop -> servers, NAS, SSH |
| 4 | Trusted (10) | Media (40) | All | Phone -> Chromecast casting |
| 5 | Trusted (10) | Mgmt (1) | TCP 443, 22 | Admin access |
| 6 | IoT (20) | Lab (30) | TCP 443, 8123, SMB | HA -> NAS, API calls |
| 7 | Media (40) | Lab (30) | TCP 8096 | Xbox/TV -> Jellyfin |
| 8 | Cameras (50) | Lab (30) | TCP 554, 8554 | Future: NVR RTSP |
| 9 | Lab (30) | Internet | All | Updates, Tailscale |
| 10 | Trusted (10) | Internet | All | Normal browsing |
| 11 | Media (40) | Internet | All | Xbox Live, streaming |
| 12 | Guest (99) | Internet | TCP 80, 443 | Web only |

### Blocked (explicit)

| Source | Destination | Why |
|--------|-------------|-----|
| Guest (99) | All RFC1918 | Complete isolation |
| Cameras (50) | Internet | Prevent phone-home |
| IoT (20) | Internet | Block except NTP (UDP 123) + update domains |
| Any | Trusted (10) | No unsolicited inbound to personal devices |

### mDNS / Discovery

Enable UDM Pro mDNS reflector (Settings -> Services -> MDNS) for VLANs 10, 20, 40 to allow Chromecast, Hue, and AirPlay discovery across Trusted, IoT, and Media.

---

## Physical Switch Configuration

### USW Pro 24 PoE

| Port | Device | Mode | Native VLAN | Tagged VLANs |
|------|--------|------|-------------|-------------|
| 1 | UDM Pro (LAN) | Trunk | 1 (Mgmt) | 10,20,30,40,50,99 |
| 2 | US 8 60W uplink | Trunk | 1 (Mgmt) | 10,20,30 |
| 3-11 | UAP-AC-Pro x9 | Trunk | 1 (Mgmt) | 10,20,40,99 |
| 12 | labnuc | Access | 30 (Lab) | -- |
| 13 | nuckvm | Access | 30 (Lab) | -- |
| 14 | storedge (Synology) | Access | 30 (Lab) | -- |
| 15 | storedge (Turing Pi) | Access | 30 (Lab) | -- |
| 16 | newnas NIC 1 | Access | 30 (Lab) | -- |
| 17 | newnas NIC 2 | Access | 30 (Lab) | -- |
| 18 | Xbox | Access | 40 (Media) | -- |
| 19-24 | *Available* | -- | -- | -- |

### US 8 60W

| Port | Device | Mode | Native VLAN | Tagged VLANs |
|------|--------|------|-------------|-------------|
| 1 | USW Pro 24 uplink | Trunk | 1 (Mgmt) | 10,20,30 |
| 2 | Brother Printer | Access | 10 (Trusted) | -- |
| 3 | Pi-hole RPi | Access | 1 (Mgmt) | -- |
| 4 | Framework-13 | Access | 10 (Trusted) | -- |
| 5 | Home Assistant | Access | 20 (IoT) | -- |
| 6 | vanas | Access | 30 (Lab) | -- |
| 7 | SLZB-06M | Access | 1 (Mgmt) | -- |
| 8 | *Available* | -- | -- | -- |

### UDM Pro Ports

| Port | Connection |
|------|-----------|
| WAN 1 | ISP modem |
| WAN 2 | *Available* (failover) |
| LAN 1 | USW Pro 24 Port 1 (trunk, all VLANs) |
| LAN 2 | *Available* |

---

## Site 2: Van (`10.2.x.x`)

Permanent GL.iNET router with Starlink WAN. Tailscale subnet router advertising `10.2.0.0/16`.

### Van VLANs

| VLAN ID | Subnet | Purpose |
|---------|--------|---------|
| 1 | `10.2.1.0/24` | Management |
| 10 | `10.2.10.0/24` | Trusted LAN |
| 20 | `10.2.20.0/24` | IoT |
| 50 | `10.2.50.0/24` | Cameras |
| 99 | `10.2.99.0/24` | Guest (passengers) |

### Van SSIDs

| SSID | VLAN | Purpose |
|------|------|---------|
| MackieNet | 10 | Personal devices (same SSID for roaming) |
| *(TBD -- IoT)* | 20 | Van IoT devices |
| *(TBD -- Guest)* | 99 | Passengers |

### Van WAN

Starlink -> GL.iNET WAN port. Starlink uses CGNAT; Tailscale NAT traversal handles connectivity.

---

## Site 3: Travel Router (`10.3.x.x`)

Portable GL.iNET (currently at `192.168.8.1`). Connects upstream to hotel Wi-Fi (repeater) or ethernet. Tailscale subnet router advertising `10.3.0.0/16`.

### Travel VLANs

| VLAN ID | Subnet | Purpose |
|---------|--------|---------|
| 1 | `10.3.1.0/24` | Management |
| 10 | `10.3.10.0/24` | Trusted LAN |
| 99 | `10.3.99.0/24` | Guest (travel companions) |

### Travel SSID

| SSID | VLAN | Purpose |
|------|------|---------|
| MackieNet | 10 | Personal devices (auto-connect) |
| *(TBD -- Guest)* | 99 | Travel companions |

---

## Tailscale Mesh

All sites connected via Tailscale with subnet routing.

```
                    +---------------+
                    |   Tailscale   |
                    |  Coord Svc    |
                    +-------+-------+
           +----------------+----------------+
           |                |                |
    +------+------+  +------+------+  +------+------+
    |  Home       |  |  Van        |  |  Travel     |
    |  labnuc     |  |  GL.iNET    |  |  GL.iNET    |
    |  10.1.0.0/16|  |  10.2.0.0/16|  |  10.3.0.0/16|
    +------+------+  +------+------+  +------+------+
           |                |                |
    +------+------+         |         +------+------+
    |  Hetzner    |   +-----+-----+   |  Phone/     |
    |  VPS        |   | Starlink  |   |  Laptop     |
    |  (direct)   |   | CGNAT     |   |  (direct)   |
    +-------------+   +-----------+   +-------------+
```

### Tailscale Configuration

Each subnet router runs:

```bash
# Home (labnuc)
tailscale up --advertise-routes=10.1.0.0/16 --accept-routes

# Van (GL.iNET)
tailscale up --advertise-routes=10.2.0.0/16 --accept-routes

# Travel (GL.iNET)
tailscale up --advertise-routes=10.3.0.0/16 --accept-routes
```

Tailscale ACLs should allow:
- All sites can reach each other's advertised subnets
- Hetzner VPS can reach Lab (VLAN 30) subnets
- Personal devices (with Tailscale client) can reach all sites directly

---

## Migration Plan

### Phase 1: Prepare (no downtime)

1. Create all VLAN networks in UniFi controller
2. Configure DHCP ranges on each VLAN
3. Create Wi-Fi SSIDs tagged to VLANs
4. Create all firewall rules
5. Enable mDNS reflector for VLANs 10, 20, 40
6. Update Pi-hole with new `10.1.x.x` DNS records (keep old records)
7. Keep existing Default network running

### Phase 2: Move infrastructure

1. Assign switch port profiles (trunk/access) in UniFi controller
2. Pi-hole gets static `10.1.1.50`, set as DNS for all VLANs
3. SLZB-06M to VLAN 1

### Phase 3: Move devices by VLAN (in order)

1. **Lab (30)** -- labnuc, nuckvm, storedge, newnas, vanas. Update static IPs. Update Tailscale `--advertise-routes=10.1.0.0/16`.
2. **IoT (20)** -- Home Assistant, Hue Bridge, Reolink, ESP32, Elgato, Peloton. Re-point HA integrations.
3. **Trusted (10)** -- Re-tag MackieNet to VLAN 10. Move Framework-13, printer, Bambu Lab.
4. **Media (40)** -- Xbox, TV, Chromecast, Quest to new SSID/ports.
5. **Cameras (50)** -- Empty, ready for future.
6. **Guest (99)** -- New SSID, no migration.

### Phase 4: Cleanup

1. Delete old Default network (`192.168.0.0/24`)
2. Remove old DNS entries from Pi-hole
3. Update hardcoded IPs in Home Assistant, K3s manifests, scripts

### Phase 5: Remote sites

1. Van GL.iNET -- VLANs, SSIDs, Tailscale
2. Travel GL.iNET -- Reconfigure from `192.168.8.x` to `10.3.x.x`
3. Update Tailscale ACLs for cross-site routing

### Risk Mitigation

- Keep a fallback device on old `192.168.0.x` until Phase 4
- UDM Pro accessible at both old and new IPs during transition
- Schedule for a weekend when IoT downtime is acceptable

---

## Automation Strategy

### UniFi (UDM Pro, switches, APs)

**Primary tool: Python script + YAML config** pushing to the UniFi REST API.

Network config is defined in YAML files (readable, diffable, version-controlled). A Python script reads the YAML and pushes it to the UDM Pro via REST API. No state files, no external providers — just data and a script.

**Authentication**: UniFi OS 4.x / Network 8.6+ supports **API keys** (Settings > System > API). No session management needed.

**Key API endpoints**:

| Operation | Method | Endpoint |
|-----------|--------|----------|
| List/create networks | GET/POST | `/proxy/network/api/s/{site}/rest/networkconf` |
| List/create firewall rules | GET/POST | `/proxy/network/api/s/{site}/rest/firewallrule` |
| List/create port profiles | GET/POST | `/proxy/network/api/s/{site}/rest/portconf` |
| List/create WLANs | GET/POST | `/proxy/network/api/s/{site}/rest/wlanconf` |
| Set device port overrides | PUT | `/proxy/network/api/s/{site}/rest/device/{id}` |
| mDNS reflector | PUT | `/proxy/network/api/s/{site}/rest/setting/connectivity` |
| Traffic rules (Network 8.x) | GET/POST | `/proxy/network/v2/api/site/{site}/trafficrules` |

The script is idempotent: it checks if a resource exists before creating, and updates if config has changed.

**CLI (SSH)**: Available on UDM Pro for debugging (`ip`, `iptables`, `bridge`), but changes are overwritten by the controller. Not useful for configuration.

### GL.iNET Travel Routers (Van + Trip)

**Primary tool: UCI over SSH** (shell scripts).

GL.iNET runs OpenWrt underneath. VLANs and firewall are configured at the OpenWrt/UCI layer. The GL.iNET JSON-RPC API is useful for Tailscale and Wi-Fi toggling but not for VLAN setup.

**Tailscale**: Native in GL.iNET firmware 4.x. Enable subnet routing from the GUI or via SSH:
```bash
tailscale up --advertise-routes=10.2.0.0/16 --accept-routes
```

### File Layout

```
networking/
  config/
    home-vlans.yaml         # VLAN definitions (subnets, DHCP, DNS)
    firewall-rules.yaml     # Inter-VLAN firewall rules
    wifi-ssids.yaml         # SSID-to-VLAN bindings
    port-profiles.yaml      # Switch port profile definitions
    device-assignments.yaml # Device-to-VLAN/port mapping
  scripts/
    setup-unifi.py          # Reads YAML, pushes to UniFi REST API
    setup-glinet-van.sh     # UCI script for van router
    setup-glinet-travel.sh  # UCI script for travel router
    update-pihole-dns.sh    # Pi-hole DNS records
    update-tailscale.sh     # Tailscale subnet router config
```
