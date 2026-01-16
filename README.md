# pi-headless-setup

Headless Raspberry Pi setup via cloud-init. WiFi werkt out-of-the-box.

## Gebruik

```bash
# Pi Zero 2W (64-bit)
sudo ./pi-preboot.sh --hostname Zero2W --user sander --password secret \
  --wifi-ssid MyNetwork --wifi-pass mypassword

# Oude Pi (32-bit)
sudo ./pi-preboot.sh --hostname rp-black --user sander --password secret \
  --wifi-ssid MyNetwork --wifi-pass mypassword --arch armhf
```

Na boot (~90 sec):
```bash
./pi-connect.sh --host Zero2W.local --user sander
```

## Ondersteunde Hardware

| Model | Arch | Getest |
|-------|------|--------|
| Pi Zero 2W | arm64 | ✅ |
| Pi 1B Rev 2 | armhf | ✅ |
| Pi 3/4/5 | arm64 | Verwacht OK |

## Hoe het werkt

Cloud-init bestanden in boot partitie:
- `meta-data` - Instance ID (uniek per flash)
- `user-data` - User account + hostname
- `network-config` - WiFi (Netplan formaat)
- `ssh` - Activeert SSH daemon

Inclusief fix voor [cloud-init race condition](https://github.com/canonical/cloud-init/issues/6614).

## Vereisten

- Linux host met SD-kaart lezer
- `wget` of `curl`, `xz-utils`, `openssl`
