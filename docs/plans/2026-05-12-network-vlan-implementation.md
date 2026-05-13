# Network VLAN Redesign -- Implementation Plan

Reference: [Network VLAN Redesign Design](2026-05-12-network-vlan-redesign.md)

---

## Phase 0: Project Setup

### 0.1 Create directory structure

```
networking/
  config/
    home-vlans.yaml
    firewall-rules.yaml
    wifi-ssids.yaml
    port-profiles.yaml
    device-assignments.yaml
  scripts/
    setup-unifi.py
    setup-glinet-van.sh
    setup-glinet-travel.sh
    update-pihole-dns.sh
    update-tailscale.sh
  .env.example
  .gitignore
  requirements.txt
```

### 0.2 Generate UDM Pro API key

Manual step in UniFi controller UI:
1. Open web UI at `https://192.168.0.1`
2. Settings > System > API > Create API Key
3. Save to `networking/.env` (gitignored)

### 0.3 Write YAML config files

Define all VLANs, firewall rules, SSIDs, port profiles, and device assignments as declarative YAML. These are the source of truth.

**Files**: `networking/config/*.yaml`

### 0.4 Write the UniFi setup script

Python script that:
1. Reads YAML config files
2. Authenticates to UDM Pro via API key
3. For each resource type: fetches existing, diffs against desired, creates/updates as needed
4. Dry-run mode by default, `--apply` to push changes

Dependencies: `httpx` (or `requests`), `pyyaml`

**Files**: `networking/scripts/setup-unifi.py`, `networking/requirements.txt`

---

## Phase 1: Write YAML Config

### 1.1 VLAN definitions (`home-vlans.yaml`)

```yaml
site: default
dns_server: 10.1.1.50

vlans:
  management:
    vlan_id: 1
    subnet: 10.1.1.0/24
    gateway: 10.1.1.1
    dhcp:
      enabled: true
      start: 10.1.1.100
      stop: 10.1.1.199
    purpose: management

  trusted:
    vlan_id: 10
    subnet: 10.1.10.0/24
    gateway: 10.1.10.1
    dhcp:
      enabled: true
      start: 10.1.10.100
      stop: 10.1.10.199

  iot:
    vlan_id: 20
    subnet: 10.1.20.0/24
    gateway: 10.1.20.1
    dhcp:
      enabled: true
      start: 10.1.20.100
      stop: 10.1.20.199

  lab:
    vlan_id: 30
    subnet: 10.1.30.0/24
    gateway: 10.1.30.1
    dhcp:
      enabled: true
      start: 10.1.30.100
      stop: 10.1.30.199

  media:
    vlan_id: 40
    subnet: 10.1.40.0/24
    gateway: 10.1.40.1
    dhcp:
      enabled: true
      start: 10.1.40.100
      stop: 10.1.40.199

  cameras:
    vlan_id: 50
    subnet: 10.1.50.0/24
    gateway: 10.1.50.1
    dhcp:
      enabled: true
      start: 10.1.50.100
      stop: 10.1.50.199

  guest:
    vlan_id: 99
    subnet: 10.1.99.0/24
    gateway: 10.1.99.1
    dhcp:
      enabled: true
      start: 10.1.99.100
      stop: 10.1.99.249
```

### 1.2 Firewall rules (`firewall-rules.yaml`)

```yaml
rules:
  # DNS for all VLANs
  - name: Allow all to Pi-hole DNS
    action: accept
    ruleset: LAN_IN
    index: 1000
    protocol: all
    dst_address: 10.1.1.50
    dst_port: 53

  # Trusted -> other VLANs
  - name: Allow Trusted to IoT
    action: accept
    ruleset: LAN_IN
    index: 2000
    protocol: all
    src_network: trusted
    dst_network: iot

  - name: Allow Trusted to Lab
    action: accept
    ruleset: LAN_IN
    index: 2001
    protocol: all
    src_network: trusted
    dst_network: lab

  - name: Allow Trusted to Media
    action: accept
    ruleset: LAN_IN
    index: 2002
    protocol: all
    src_network: trusted
    dst_network: media

  - name: Allow Trusted to Mgmt
    action: accept
    ruleset: LAN_IN
    index: 2003
    protocol: tcp
    src_network: trusted
    dst_network: management
    dst_port: 22,443

  # Cross-VLAN service access
  - name: Allow IoT to Lab (HA)
    action: accept
    ruleset: LAN_IN
    index: 2010
    protocol: tcp
    src_network: iot
    dst_network: lab
    dst_port: 443,8123,445

  - name: Allow Media to Lab (Jellyfin)
    action: accept
    ruleset: LAN_IN
    index: 2011
    protocol: tcp
    src_network: media
    dst_network: lab
    dst_port: 8096

  - name: Allow Cameras to Lab (NVR)
    action: accept
    ruleset: LAN_IN
    index: 2012
    protocol: tcp
    src_network: cameras
    dst_network: lab
    dst_port: 554,8554

  # Block inter-VLAN (catch-all)
  - name: Block all inter-VLAN
    action: drop
    ruleset: LAN_IN
    index: 9000
    protocol: all
    src_network: any
    dst_network: any

  # WAN rules
  - name: Block Cameras internet
    action: drop
    ruleset: WAN_OUT
    index: 1000
    protocol: all
    src_network: cameras

  - name: Allow IoT NTP only
    action: accept
    ruleset: WAN_OUT
    index: 1001
    protocol: udp
    src_network: iot
    dst_port: 123

  - name: Block IoT internet
    action: drop
    ruleset: WAN_OUT
    index: 1002
    protocol: all
    src_network: iot

  - name: Guest web only
    action: accept
    ruleset: WAN_OUT
    index: 1010
    protocol: tcp
    src_network: guest
    dst_port: 80,443

  # Guest isolation
  - name: Block Guest to RFC1918
    action: drop
    ruleset: LAN_IN
    index: 1500
    protocol: all
    src_network: guest
    dst_address: 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

### 1.3 Wi-Fi SSIDs (`wifi-ssids.yaml`)

```yaml
ssids:
  - name: MackieNet
    vlan: trusted
    security: wpa2_wpa3
    band: both
    passphrase_env: WIFI_TRUSTED_PASS

  - name: TBD_IOT_NAME
    vlan: iot
    security: wpa2
    band: 2g_only
    passphrase_env: WIFI_IOT_PASS

  - name: TBD_MEDIA_NAME
    vlan: media
    security: wpa2_wpa3
    band: 5g_preferred
    passphrase_env: WIFI_MEDIA_PASS

  - name: TBD_GUEST_NAME
    vlan: guest
    security: wpa2
    band: both
    passphrase_env: WIFI_GUEST_PASS
```

### 1.4 Port profiles (`port-profiles.yaml`)

```yaml
profiles:
  mgmt-access:
    native_vlan: management
    tagged_vlans: []

  trusted-access:
    native_vlan: trusted
    tagged_vlans: []

  iot-access:
    native_vlan: iot
    tagged_vlans: []

  lab-access:
    native_vlan: lab
    tagged_vlans: []

  media-access:
    native_vlan: media
    tagged_vlans: []

  camera-access:
    native_vlan: cameras
    tagged_vlans: []

  ap-trunk:
    native_vlan: management
    tagged_vlans: [trusted, iot, media, guest]

  switch-trunk:
    native_vlan: management
    tagged_vlans: [trusted, iot, lab]

  uplink-trunk:
    native_vlan: management
    tagged_vlans: [trusted, iot, lab, media, cameras, guest]
```

### 1.5 Device assignments (`device-assignments.yaml`)

```yaml
# USW Pro 24 PoE
usw_pro_24:
  port_1:  { device: "UDM Pro LAN", profile: uplink-trunk }
  port_2:  { device: "US 8 60W uplink", profile: switch-trunk }
  port_3:  { device: "UAP-AC-Pro #1", profile: ap-trunk }
  port_4:  { device: "UAP-AC-Pro #2", profile: ap-trunk }
  port_5:  { device: "UAP-AC-Pro #3", profile: ap-trunk }
  port_6:  { device: "UAP-AC-Pro #4", profile: ap-trunk }
  port_7:  { device: "UAP-AC-Pro #5", profile: ap-trunk }
  port_8:  { device: "UAP-AC-Pro #6", profile: ap-trunk }
  port_9:  { device: "UAP-AC-Pro #7", profile: ap-trunk }
  port_10: { device: "UAP-AC-Pro #8", profile: ap-trunk }
  port_11: { device: "UAP-AC-Pro #9", profile: ap-trunk }
  port_12: { device: "labnuc", profile: lab-access }
  port_13: { device: "nuckvm", profile: lab-access }
  port_14: { device: "storedge (Synology)", profile: lab-access }
  port_15: { device: "storedge (Turing Pi)", profile: lab-access }
  port_16: { device: "newnas NIC 1", profile: lab-access }
  port_17: { device: "newnas NIC 2", profile: lab-access }
  port_18: { device: "Xbox", profile: media-access }

# US 8 60W
us_8_60w:
  port_1: { device: "USW Pro 24 uplink", profile: switch-trunk }
  port_2: { device: "Brother Printer", profile: trusted-access }
  port_3: { device: "Pi-hole RPi", profile: mgmt-access }
  port_4: { device: "Framework-13", profile: trusted-access }
  port_5: { device: "Home Assistant", profile: iot-access }
  port_6: { device: "vanas", profile: lab-access }
  port_7: { device: "SLZB-06M", profile: mgmt-access }

# Static IP assignments
static_ips:
  management:
    - { ip: 10.1.1.10, mac: TBD, name: "UAP-AC-Pro #1" }
    # ... APs 10.1.1.10-.18
    - { ip: 10.1.1.50, mac: TBD, name: "Pi-hole" }
    - { ip: 10.1.1.51, mac: TBD, name: "SLZB-06M" }
  trusted:
    - { ip: 10.1.10.2, mac: TBD, name: "Framework-13" }
    - { ip: 10.1.10.50, mac: TBD, name: "Brother Printer" }
    - { ip: 10.1.10.51, mac: TBD, name: "Bambu Lab X1C" }
  iot:
    - { ip: 10.1.20.2, mac: TBD, name: "Home Assistant" }
    - { ip: 10.1.20.3, mac: TBD, name: "Hue Bridge" }
  lab:
    - { ip: 10.1.30.2, mac: TBD, name: "labnuc" }
    - { ip: 10.1.30.3, mac: TBD, name: "nuckvm" }
    - { ip: 10.1.30.10, mac: TBD, name: "storedge (Synology)" }
    - { ip: 10.1.30.11, mac: TBD, name: "storedge (Turing Pi)" }
    - { ip: 10.1.30.12, mac: TBD, name: "newnas" }
    - { ip: 10.1.30.13, mac: TBD, name: "vanas" }
  media:
    - { ip: 10.1.40.2, mac: TBD, name: "Xbox" }
```

---

## Phase 2: Write the UniFi Setup Script

### 2.1 Core script (`setup-unifi.py`)

Python script with these capabilities:
- Load YAML config files
- Authenticate to UDM Pro via API key (from `.env`)
- **Dry-run by default** -- prints what it would do
- `--apply` flag to push changes
- For each resource type:
  - Fetch existing from API
  - Compare against desired config
  - Create missing, update changed, report drift

Operations in order:
1. Create VLAN networks
2. Create port profiles
3. Create firewall rules (ordered by index)
4. Create/update Wi-Fi SSIDs
5. Enable mDNS reflector
6. Report summary

### 2.2 Dependencies

```
# requirements.txt
httpx>=0.27
pyyaml>=6.0
python-dotenv>=1.0
```

**Files**: `networking/scripts/setup-unifi.py`, `networking/requirements.txt`

---

## Phase 3: Run Setup Script (creates VLANs, does NOT move devices)

### 3.1 Dry run

```bash
cd networking
python scripts/setup-unifi.py --dry-run
```

Review output. Verify all 7 VLANs, firewall rules, SSIDs, and port profiles look correct.

### 3.2 Apply

```bash
python scripts/setup-unifi.py --apply
```

This creates all VLANs, firewall rules, SSIDs, and port profiles on the UDM Pro. The old Default network continues to work -- nothing breaks yet.

### 3.3 Verify in UniFi controller

Open the UniFi UI and confirm:
- All 7 VLANs appear under Networks
- Firewall rules are listed under Security
- New SSIDs are broadcasting
- Port profiles are available
- mDNS reflector is enabled

---

## Phase 4: Update Pi-hole DNS

### 4.1 Write DNS update script

```bash
#!/bin/bash
# networking/scripts/update-pihole-dns.sh
PIHOLE_HOST="pi@192.168.0.248"  # Use old IP until migrated

ssh $PIHOLE_HOST 'cat > /etc/pihole/custom.list << EOF
10.1.1.1 gateway.homelab.local
10.1.1.50 pihole.homelab.local
10.1.10.2 framework.homelab.local
10.1.20.2 homeassistant.homelab.local
10.1.30.2 labnuc.homelab.local
10.1.30.3 nuckvm.homelab.local
10.1.30.10 storedge.homelab.local
10.1.30.12 newnas.homelab.local
10.1.30.13 vanas.homelab.local
10.1.40.2 xbox.homelab.local
EOF
pihole restartdns'
```

Run this alongside the old records initially -- both old and new IPs resolve during transition.

**Files**: `networking/scripts/update-pihole-dns.sh`

---

## Phase 5: Migrate Devices (by VLAN, in order)

### 5.1 Lab (VLAN 30) -- first, most critical

1. In UniFi UI or via script: assign port profiles on USW Pro 24
   - Port 12 (labnuc) -> `lab-access`
   - Port 13 (nuckvm) -> `lab-access`
   - Port 14-17 (storedge, newnas) -> `lab-access`
   - US 8 Port 6 (vanas) -> `lab-access`
2. SSH into each server, update static IPs to `10.1.30.x`
3. Update labnuc Tailscale: `tailscale up --advertise-routes=10.1.0.0/16 --accept-routes`
4. Update Hetzner VPS Tailscale ACLs
5. Test: SSH to each server, verify internet, verify Tailscale mesh
6. Update K3s manifests in this repo with new IPs

### 5.2 Management (VLAN 1) -- Pi-hole and infra

1. US 8 Port 3 (Pi-hole) -> `mgmt-access`
2. US 8 Port 7 (SLZB-06M) -> `mgmt-access`
3. Update Pi-hole static IP to `10.1.1.50`
4. Verify all VLANs have `10.1.1.50` as DHCP DNS server
5. Test: DNS resolution from each VLAN

### 5.3 IoT (VLAN 20)

1. US 8 Port 5 (Home Assistant) -> `iot-access`
2. Hue Bridge -> `iot-access` or IoT SSID
3. Move Wi-Fi IoT devices to IoT SSID: Reolink, Elgato x2, ESP32, TP-Link, Peloton
4. Update Home Assistant integrations with new device IPs
5. Test: HA dashboard, Hue control from phone, automations

### 5.4 Trusted (VLAN 10)

1. MackieNet SSID already tagged to VLAN 10 from Phase 3
2. US 8 Port 2 (printer) -> `trusted-access`
3. US 8 Port 4 (Framework-13) -> `trusted-access`
4. Bambu Lab X1C stays on MackieNet (now VLAN 10)
5. Phones/laptops auto-reconnect, get `10.1.10.x` via DHCP
6. Test: printing, Bambu slicer, internet, cross-VLAN to IoT/Lab

### 5.5 Media (VLAN 40)

1. USW Pro 24 Port 18 (Xbox) -> `media-access`
2. Connect TV, Chromecast, Quest to Media SSID
3. Test: Xbox Live, Chromecast casting, Jellyfin streaming

### 5.6 Guest (VLAN 99)

1. New SSID already broadcasting from Phase 3
2. Test: connect a device, verify internet, verify NO access to internal VLANs

---

## Phase 6: GL.iNET Router Setup

### 6.1 Write van router setup script

Full UCI script that configures VLANs (10, 20, 50, 99), firewall zones, SSIDs, and DHCP. Run over SSH.

**Files**: `networking/scripts/setup-glinet-van.sh`

### 6.2 Write travel router setup script

Simpler script: VLANs (10, 99) only. Reconfigures from `192.168.8.x` to `10.3.x.x`.

**Files**: `networking/scripts/setup-glinet-travel.sh`

### 6.3 Configure Tailscale on both routers

```bash
# Van
ssh root@<van-router> 'tailscale up --advertise-routes=10.2.0.0/16 --accept-routes'

# Travel
ssh root@<travel-router> 'tailscale up --advertise-routes=10.3.0.0/16 --accept-routes'
```

### 6.4 Update Tailscale ACLs

In Tailscale admin console, allow:
- All subnet routers advertise their `/16` ranges
- Hetzner VPS can reach `10.1.30.0/24` (Lab)
- Personal devices can access all sites

**Files**: `networking/scripts/update-tailscale.sh`

---

## Phase 7: Update Homelab Configs

### 7.1 Update K3s manifests

Grep all YAML in this repo for `192.168` and update to `10.1.x.x`:
- `networking/internal-dns.yaml`
- `networking/advanced-networking.yaml`
- `networking/cilium-ebpf.yaml`

### 7.2 Update Home Assistant

Re-point integrations to new device IPs.

### 7.3 Update CLAUDE.md

Reflect new network architecture.

---

## Phase 8: Cleanup

### 8.1 Delete old Default network

Once all devices confirmed on new VLANs:
1. Remove the Default network from UniFi controller
2. Verify no devices still on `192.168.0.x`

### 8.2 Remove old DNS entries

Remove `192.168.x` records from Pi-hole.

### 8.3 Final verification

- All devices reachable on correct VLANs
- Inter-VLAN firewall rules working (test blocked + allowed flows)
- Tailscale mesh healthy across all sites
- mDNS discovery working (Chromecast, Hue, AirPlay)
- Guest network fully isolated
- IoT cannot reach internet (except NTP)

---

## Execution Order Summary

| Phase | What | Downtime | Rollback |
|-------|------|----------|----------|
| 0 | Project setup | None | Delete files |
| 1 | Write YAML configs | None | Git revert |
| 2 | Write Python script | None | Git revert |
| 3 | Run script (creates VLANs) | None (parallel networks) | Re-run with delete flag or remove via UI |
| 4 | Update Pi-hole | Brief DNS blip | Revert custom.list |
| 5.1 | Migrate Lab | Server reconnects (~1min) | Change port profile back |
| 5.2 | Migrate Management | Brief infra blip | Revert port profiles |
| 5.3 | Migrate IoT | Devices re-associate | Move back to old SSID |
| 5.4 | Migrate Trusted | Auto DHCP renewal | Re-tag MackieNet |
| 5.5 | Migrate Media | Devices re-associate | Revert port/SSID |
| 5.6 | Activate Guest | None | Disable SSID |
| 6 | GL.iNET routers | Router restart (~2min) | Restore backup config |
| 7 | Update configs | None | Git revert |
| 8 | Cleanup | None | -- |

Total estimated migration window: ~2-3 hours with testing.
