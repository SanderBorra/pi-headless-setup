# Raspberry Pi Headless Setup

Automatische headless setup voor Raspberry Pi via cloud-init.

## Ondersteunde Hardware

| Model | Arch | WiFi | Getest |
|-------|------|------|--------|
| Pi Zero 2W | arm64 | Ingebouwd | Ja |
| Pi 1B Rev 2 | armhf | USB adapter | Ja |
| Pi 3/4/5 | arm64 | Ingebouwd | Verwacht OK |

## Scripts

### pi-preboot.sh

Flash SD-kaart met cloud-init configuratie.

```bash
# Pi Zero 2W (64-bit, default)
sudo ./pi-preboot.sh --hostname Zero2W --user sander --password Amber_Jade \
  --wifi-ssid NetwerkTali --wifi-pass Hetwachtwoordvan2020

# Oude Pi (32-bit)
sudo ./pi-preboot.sh --hostname rp-black --user sander --password Amber_Jade \
  --wifi-ssid NetwerkTali --wifi-pass Hetwachtwoordvan2020 --arch armhf
```

**Parameters:**

| Parameter | Verplicht | Beschrijving |
|-----------|-----------|--------------|
| --hostname | Ja | Hostname voor de Pi |
| --user | Ja | Gebruikersnaam |
| --password | Ja | Wachtwoord |
| --wifi-ssid | Ja | WiFi netwerk naam |
| --wifi-pass | Ja | WiFi wachtwoord |
| --arch | Nee | arm64 (default) of armhf (32-bit) |
| --device | Nee | SD-kaart device (default: interactief) |

### pi-connect.sh

Test SSH en installeer public key.

```bash
./pi-connect.sh --host Zero2W.local --user sander
./pi-connect.sh --host 192.168.1.188 --user sander
```

## Hoe Het Werkt

### Cloud-init Bestanden (boot partitie)

1. **meta-data** - Instance identificatie (unieke ID per flash)
2. **user-data** - User account + hostname
3. **network-config** - WiFi (Netplan formaat, DHCP)
4. **ssh** - Leeg bestand, activeert SSH

### Kritieke Fix: Race Condition

Cloud-init start voordat `/boot/firmware` gemount is. Fix in rootfs:

```
# /lib/systemd/system/cloud-init-main.service
RequiresMountsFor=/var/lib/cloud /boot/firmware
```

Zie: https://github.com/canonical/cloud-init/issues/6614

### Cloud-init State Reset

Bij elke flash worden deze directories geleegd:
- `/var/lib/cloud/instances/*`
- `/var/lib/cloud/instance` (symlink)
- `/var/lib/cloud/data/*`
- `/var/lib/cloud/sem/*`

## Workflow

```
1. sudo ./pi-preboot.sh --hostname <naam> --user <user> --password <pass> \
     --wifi-ssid <ssid> --wifi-pass <pass> [--arch armhf]

2. SD-kaart in Pi, boot (wacht ~90 sec voor cloud-init)

3. ./pi-connect.sh --host <naam>.local --user <user>

4. ssh <user>@<naam>.local
```

## Image Cache

Images worden gecached in: `~/.cache/raspberry-pi-images/`

## Actieve Pi's

| Hostname | Model | IP (DHCP) | Software |
|----------|-------|-----------|----------|
| rp-black | Pi 1B Rev 2 | 192.168.1.188 | - |
| Zero2W | Pi Zero 2W | 192.168.1.72 | sqlite3, RustPi |
| Zero2Wa | Pi Zero 2W | 192.168.1.174 | sqlite3, RustPi |

## Cross-compilatie (Rust)

Voor aarch64 (Pi Zero 2W):

```bash
cd ~/Projects/RustPi
cargo build --release --target aarch64-unknown-linux-gnu
scp target/aarch64-unknown-linux-gnu/release/RustPi sander@Zero2W.local:~/
```

Vereist: `sudo apt install gcc-aarch64-linux-gnu`

## Wat NIET Te Doen

| Actie | Waarom Niet |
|-------|-------------|
| wpa_supplicant.conf in /etc/ | NetworkManager negeert dit |
| /etc/network/interfaces | Wordt niet gebruikt |
| NetworkManager .nmconnection | Timing issues bij boot |
| systemd-networkd configureren | Conflicteert met NetworkManager |
