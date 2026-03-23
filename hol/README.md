# HOL FRR lab

This directory contains the lab automation: `setup.sh`, `cleanup.sh`, `config.txt`, and optional `install.sh`.

## Use cases

### 1. Temporary setup

Use this when you only need the lab for a session and will tear it down yourself (or do not want anything to run automatically after reboot).

1. Edit `config.txt` (host interface, `mode`, `numPods`, LAN settings).
2. Run **`./setup.sh`** (requires Docker and `sudo` for networking).
3. Run **`./cleanup.sh`** when you are done.

You do **not** need `install.sh`. Nothing is registered with systemd; a reboot leaves Docker state as-is until you clean up or run setup again.

### 2. Permanent setup

Use this when the lab should be recreated automatically after every reboot (same `config.txt` on disk).

1. Edit `config.txt` as needed.
2. Run **`sudo ./install.sh`** once from this directory.

That installs a systemd unit (`hol-lab.service`) that, on boot (and when started manually), runs `cleanup.sh` if lab containers already exist, then runs `setup.sh`. See `install.sh` for `--no-start` and `uninstall`.

**Note:** `install.sh` does not change `setup.sh` or `cleanup.sh`; you can still run those scripts by hand without using `install.sh`.

---

## DHCP

Values below come from `setup.sh` (generated `dhcpd.conf` and container addressing). The **DHCP server address** used inside each pod is:

| Role | Address |
|------|---------|
| DHCP server (on `eth2` in the `dhcpd` container) | **172.16.253.2/24** |

**Declared / service subnets (scopes)** in `dhcpd.conf`:

| Subnet | Netmask | Notes |
|--------|---------|--------|
| 172.16.253.0 | 255.255.255.0 | Declared empty (topology / no leases here) |
| 192.168.18.0 | 255.255.255.0 | One fixed lease: **192.168.18.11**; gateway **192.168.18.1**; DNS **8.8.8.8**; domain `selab.net` |
| 192.168.19.0 | 255.255.255.0 | Range **192.168.19.11–192.168.19.254**; gateway **192.168.19.1** |
| 192.168.20.0 | 255.255.255.0 | Range **192.168.20.11–192.168.20.254**; gateway **192.168.20.1** |

Default/max lease times are **600s / 7200s** where ranges are defined.

---

## RADIUS

Values below come from the generated `clients.conf` and `authorize` files created by `setup.sh`. The **RADIUS server** address inside each pod is:

| Role | Address |
|------|---------|
| RADIUS (`radiusd` on `eth3`) | **172.16.254.2/24** |

**Shared secret** (all `clients.conf` entries in the stock lab):

| Client block | Network / IP | Secret |
|--------------|----------------|--------|
| `hol1` | 172.16.0.0/16 | **nile123** |
| `hol2` | 192.168.0.0/16 | **nile123** |
| `hol3` | 10.0.0.0/8 | **nile123** |

**Users** (in `authorize`; used as inner credentials for EAP methods such as **PEAP** when the stock FreeRADIUS `default` / inner-tunnel chain is used):

The lab also returns the **Nile** vendor-specific attribute **`netseg`** (see `dictionary.nile`, attribute `netseg`) where noted below.

| Username | Password | Nile VSA `netseg` |
|----------|----------|-------------------|
| `bob` | `hello` | *(none)* |
| `employee` | `nilesecure` | **Employee** |
| `contractor` | `nilesecure` | **Contractor** |

These are lab defaults. Change them in the generated files (or in `setup.sh` if you regenerate from source) before any real deployment.

---

## FRR (NSB uplink)

Per-pod WAN addresses are computed in `setup.sh`; **NSB uplink** addressing is driven by `config.txt`:

| Setting | Meaning | Default in `config.txt` (example) |
|---------|---------|-----------------------------------|
| `router_ip` | FRR `eth1` (router) address | **172.16.0.1/30** |
| `nsb_uplink_ip` | OSPF `network … area 0` (NSB uplink prefix) | **172.16.0.0/30** |

Pick **`router_ip`** and **`nsb_uplink_ip`** so they **do not overlap** any subnet defined for **DHCP**, **RADIUS**, or **FRR** in this lab (including Docker **`wan_net`**, **172.16.253.0/24**, the DHCP scope subnets listed in the DHCP section, **172.16.254.0/24**, or any other NSB/FRR uplink you use). **`router_ip`** must be a host address inside **`nsb_uplink_ip`**.

Adjust both in `config.txt` before running `setup.sh` if you need a different uplink.

---

## Files

| File | Purpose |
|------|---------|
| `config.txt` | Shared settings for `setup.sh` and `cleanup.sh` |
| `setup.sh` | Build images, create networks, start pods |
| `cleanup.sh` | Remove containers, bridges, VLANs, generated configs |
| `install.sh` | Optional systemd install for persistent lab |
