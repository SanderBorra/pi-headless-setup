#!/bin/bash

# Re-exec with sudo if not root
if [[ $EUID -ne 0 && "$1" != "--help" && "$1" != "-h" ]]; then
    exec sudo "$0" "$@"
fi

# Minimal Raspberry Pi Pre-boot Configuration
# Only: SSH + WiFi (DHCP) + User

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

show_help() {
    cat << EOF
Minimal Raspberry Pi Pre-boot Setup (cloud-init)

Usage: sudo $0 --hostname <name> --user <user> --password <pass> \\
              --wifi-ssid <ssid> --wifi-pass <pass> [--arch arm64|armhf]

Required:
  --hostname    Pi hostname
  --user        Username
  --password    Password
  --wifi-ssid   WiFi network name
  --wifi-pass   WiFi password

Optional:
  --arch        arm64 (default) or armhf (32-bit for old Pi)

Configures via cloud-init (boot partition only):
  - meta-data   : instance identification
  - user-data   : user account + hostname
  - network-config : WiFi (DHCP, Netplan format)
  - ssh         : enable SSH daemon

Examples:
  # Pi Zero 2W (64-bit)
  sudo $0 --hostname pi-zero --user sander --password secret \\
          --wifi-ssid MyNetwork --wifi-pass mypass

  # Pi 1B Rev 2 (32-bit)
  sudo $0 --hostname rp-black --user sander --password secret \\
          --wifi-ssid MyNetwork --wifi-pass mypass --arch armhf
EOF
}

# Validate minimal args
validate_minimal_args() {
    [[ -z "$PI_HOSTNAME" ]] && log_error "Missing --hostname"
    [[ -z "$PI_USER" ]] && log_error "Missing --user"
    [[ -z "$PI_PASSWORD" ]] && log_error "Missing --password"
    [[ -z "$WIFI_SSID" ]] && log_error "Missing --wifi-ssid"
    [[ -z "$WIFI_PASS" ]] && log_error "Missing --wifi-pass"
}

# Find latest image
find_latest_image() {
    [[ -z "$PI_ARCH" ]] && PI_ARCH="arm64"

    if [[ "$PI_ARCH" == "armhf" ]]; then
        IMAGE_BASE_URL="$IMAGE_URL_ARMHF"
        ARCH_PATTERN="raspios_lite_armhf"
        log_step "Finding latest 32-bit (armhf) image..."
    else
        IMAGE_BASE_URL="$IMAGE_URL_ARM64"
        ARCH_PATTERN="raspios_lite_arm64"
        log_step "Finding latest 64-bit (arm64) image..."
    fi

    LATEST_DIR=$(curl -s "$IMAGE_BASE_URL" | \
        grep -oE "href=\"${ARCH_PATTERN}-[0-9]{4}-[0-9]{2}-[0-9]{2}/\"" | \
        sed 's/href="//g;s/"//g' | sort -r | head -1)

    [[ -z "$LATEST_DIR" ]] && log_error "Could not find latest image"

    log_info "Latest: $LATEST_DIR"

    IMAGE_FILE=$(curl -s "${IMAGE_BASE_URL}${LATEST_DIR}" | \
        grep -oE 'href="[^"]+\.img\.xz"' | \
        sed 's/href="//g;s/"//g' | head -1)

    [[ -z "$IMAGE_FILE" ]] && log_error "Could not find image file"

    IMAGE_URL="${IMAGE_BASE_URL}${LATEST_DIR}${IMAGE_FILE}"
    IMAGE_NAME="${IMAGE_FILE%.xz}"
    IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"

    log_info "Image: $IMAGE_FILE"
}

# Download image
download_image() {
    mkdir -p "$IMAGE_DIR"

    if [[ -f "$IMAGE_PATH" ]]; then
        log_info "Image cached: $IMAGE_PATH"
        return 0
    fi

    log_step "Downloading image..."
    local IMAGE_XZ="$IMAGE_DIR/$IMAGE_FILE"

    if [[ ! -f "$IMAGE_XZ" ]]; then
        wget --progress=bar:force -O "$IMAGE_XZ" "$IMAGE_URL" || \
            curl -L --progress-bar -o "$IMAGE_XZ" "$IMAGE_URL"
    fi

    log_info "Extracting..."
    xz -dk "$IMAGE_XZ"
    log_info "Ready: $IMAGE_PATH"
}

# Write image
write_image() {
    log_step "Writing to $DEVICE..."

    echo ""
    lsblk "$DEVICE"
    echo ""
    echo -e "${RED}ALL DATA ON $DEVICE WILL BE ERASED!${NC}"
    read -p "Continue? (yes/no): " CONFIRM || true
    [[ "$CONFIRM" != "yes" ]] && log_error "Aborted"

    umount "${DEVICE}"* 2>/dev/null || true
    sleep 1

    log_info "Writing..."
    dd if="$IMAGE_PATH" of="$DEVICE" bs=4M status=progress conv=fsync

    sync
    partprobe "$DEVICE" 2>/dev/null || true
    sleep 3
    log_info "Done"
}

# Mount partitions
mount_partitions() {
    log_step "Mounting..."

    PART_PREFIX=$(get_part_prefix "$DEVICE")
    BOOTFS="/tmp/pi-bootfs-$$"
    ROOTFS="/tmp/pi-rootfs-$$"
    mkdir -p "$BOOTFS" "$ROOTFS"

    sleep 2
    mount "${PART_PREFIX}1" "$BOOTFS" || log_error "Failed to mount boot"
    mount "${PART_PREFIX}2" "$ROOTFS" || log_error "Failed to mount root"

    log_info "Mounted: $BOOTFS, $ROOTFS"
}

# CLOUD-INIT ONLY configuration
# All config via boot partition files - no rootfs modifications!
configure_minimal() {
    log_step "Configuring via cloud-init..."

    # 1. Enable SSH
    log_info "Enabling SSH..."
    touch "$BOOTFS/ssh"

    # 2. meta-data - instance identification
    log_info "Creating meta-data..."
    INSTANCE_ID="${PI_HOSTNAME}-$(date +%s)"
    cat > "$BOOTFS/meta-data" << EOF
instance_id: ${INSTANCE_ID}
dsmode: local
EOF

    # 3. user-data - user and hostname setup
    log_info "Creating user-data for user '$PI_USER'..."
    PASS_HASH=$(openssl passwd -6 "$PI_PASSWORD")

    cat > "$BOOTFS/user-data" << EOF
#cloud-config

hostname: ${PI_HOSTNAME}

users:
  - name: ${PI_USER}
    passwd: ${PASS_HASH}
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [adm, dialout, cdrom, sudo, audio, video, plugdev, games, users, input, netdev, gpio, i2c, spi]

ssh_pwauth: true
EOF

    # 4. network-config - WiFi via Netplan format (cloud-init)
    log_info "Creating network-config for WiFi..."
    cat > "$BOOTFS/network-config" << EOF
network:
  version: 2
  wifis:
    renderer: NetworkManager
    wlan0:
      dhcp4: true
      regulatory-domain: "NL"
      access-points:
        "${WIFI_SSID}":
          password: "${WIFI_PASS}"
      optional: true
EOF

    # 5. Fix cloud-init race condition (boot partition not mounted yet)
    # See: https://github.com/canonical/cloud-init/issues/6614
    log_info "Fixing cloud-init boot timing..."
    local SERVICE_FILE="$ROOTFS/lib/systemd/system/cloud-init-main.service"
    if [[ -f "$SERVICE_FILE" ]]; then
        if ! grep -q "/boot/firmware" "$SERVICE_FILE"; then
            sed -i 's|RequiresMountsFor=/var/lib/cloud|RequiresMountsFor=/var/lib/cloud /boot/firmware|' "$SERVICE_FILE"
            log_info "Fixed: RequiresMountsFor now includes /boot/firmware"
        else
            log_info "Already fixed: /boot/firmware in RequiresMountsFor"
        fi
    else
        log_warn "cloud-init-main.service not found"
    fi

    # 6. Reset cloud-init state (critical for re-run!)
    log_info "Resetting cloud-init state..."
    rm -rf "$ROOTFS/var/lib/cloud/instances"/*
    rm -rf "$ROOTFS/var/lib/cloud/instance"
    rm -rf "$ROOTFS/var/lib/cloud/data"/*
    rm -rf "$ROOTFS/var/lib/cloud/sem"/*

    log_info "Configuration complete"
}

# Cleanup
cleanup() {
    log_step "Finishing..."
    sync
    umount "$BOOTFS" 2>/dev/null || true
    umount "$ROOTFS" 2>/dev/null || true
    rmdir "$BOOTFS" "$ROOTFS" 2>/dev/null || true
    log_info "Unmounted"
}

# Main
main() {
    for arg in "$@"; do
        [[ "$arg" == "-h" || "$arg" == "--help" ]] && { show_help; exit 0; }
    done

    echo "========================================"
    echo "Minimal Raspberry Pi Pre-boot Setup"
    echo "========================================"
    echo ""

    parse_args "$@"
    validate_minimal_args

    log_info "Hostname: $PI_HOSTNAME"
    log_info "User: $PI_USER"
    log_info "Arch: ${PI_ARCH:-arm64}"
    log_info "WiFi: $WIFI_SSID (DHCP)"
    log_info "Method: cloud-init (network-config)"
    echo ""

    find_latest_image
    download_image
    select_device
    write_image
    mount_partitions
    configure_minimal
    cleanup

    echo ""
    echo "========================================"
    echo -e "${GREEN}Done!${NC}"
    echo "========================================"
    echo ""
    echo "Boot the Pi and wait ~90 seconds (cloud-init needs time)."
    echo ""
    echo "Find IP:  ./pi-connect.sh --scan --user ${PI_USER}"
    echo "Or:       nmap -sn 192.168.1.0/24 | grep -i raspberry"
    echo ""
    echo "Connect:  ssh ${PI_USER}@<ip>"
    echo "Password: ${PI_PASSWORD}"
    echo ""
}

main "$@"
