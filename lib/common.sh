#!/bin/bash
# Common functions for Raspberry Pi setup scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

# Parse command line arguments
# Usage: parse_args "$@"
# Sets global variables: PI_TYPE, HOSTNAME, USER, PASSWORD, WIFI_SSID, WIFI_PASS, LAN_IP, WIFI_IP, DEVICE, SKIP_WRITE
parse_args() {
    PI_TYPE=""
    PI_HOSTNAME=""
    PI_USER=""
    PI_PASSWORD=""
    WIFI_SSID=""
    WIFI_PASS=""
    LAN_IP=""
    WIFI_IP=""
    DEVICE=""
    SKIP_WRITE=false
    PI_HOST=""
    PI_ARCH=""
    PI_SCAN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)      PI_TYPE="$2"; shift 2 ;;
            --hostname)  PI_HOSTNAME="$2"; shift 2 ;;
            --user)      PI_USER="$2"; shift 2 ;;
            --password)  PI_PASSWORD="$2"; shift 2 ;;
            --wifi-ssid) WIFI_SSID="$2"; shift 2 ;;
            --wifi-pass) WIFI_PASS="$2"; shift 2 ;;
            --lan-ip)    LAN_IP="$2"; shift 2 ;;
            --wifi-ip)   WIFI_IP="$2"; shift 2 ;;
            --device)    DEVICE="$2"; shift 2 ;;
            --skip-write) SKIP_WRITE=true; shift ;;
            --host)      PI_HOST="$2"; shift 2 ;;
            --arch)      PI_ARCH="$2"; shift 2 ;;
            --scan)      PI_SCAN=true; shift ;;
            -h|--help)   show_help; exit 0 ;;
            *)           log_error "Unknown option: $1" ;;
        esac
    done
}

# Validate required parameters for preboot
validate_preboot_args() {
    [[ -z "$PI_TYPE" ]] && log_error "Missing --type (lan or zero)"
    [[ "$PI_TYPE" != "lan" && "$PI_TYPE" != "zero" ]] && log_error "--type must be 'lan' or 'zero'"
    [[ -z "$PI_HOSTNAME" ]] && log_error "Missing --hostname"
    [[ -z "$PI_USER" ]] && log_error "Missing --user"
    [[ -z "$PI_PASSWORD" ]] && log_error "Missing --password"
    [[ -z "$WIFI_SSID" ]] && log_error "Missing --wifi-ssid"
    [[ -z "$WIFI_PASS" ]] && log_error "Missing --wifi-pass"
}

# Validate device is safe (SD card only, not system drive)
validate_device() {
    local dev="$1"
    local dev_name=$(basename "$dev")

    # Block system drives
    local ROOT_DEV=$(findmnt -n -o SOURCE / | sed 's/\[.*\]//' | grep -oE '([a-z]+|nvme[0-9]+n[0-9]+)')
    [[ "$dev_name" == "$ROOT_DEV"* ]] && log_error "SAFETY: $dev is your system drive!"
    [[ "$dev_name" == nvme* ]] && log_error "SAFETY: NVMe devices not allowed"

    [[ ! -b "$dev" ]] && log_error "Device $dev does not exist"

    # Check removable or mmcblk
    if [[ "$dev_name" != mmcblk* ]]; then
        local tran=$(lsblk -d -n -o TRAN "$dev" 2>/dev/null)
        local rm=$(lsblk -d -n -o RM "$dev" 2>/dev/null)
        [[ "$tran" != "usb" ]] && log_error "SAFETY: $dev is not USB (transport: $tran)"
        [[ "$rm" != "1" ]] && log_warn "Device $dev is not marked removable"
    fi

    log_info "Device $dev validated"
}

# Select SD card device interactively
select_device() {
    if [[ -n "$DEVICE" ]]; then
        validate_device "$DEVICE"
        return
    fi

    echo ""
    echo "Available SD card devices:"
    echo "=========================="
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM | grep -E "NAME|usb|mmcblk" | grep -v "nvme"
    echo ""

    read -p "Enter device (e.g., sdb, mmcblk0): " DEV_INPUT || true
    [[ -z "$DEV_INPUT" ]] && log_error "No device specified"

    if [[ "$DEV_INPUT" == /dev/* ]]; then
        DEVICE="$DEV_INPUT"
    else
        DEVICE="/dev/$DEV_INPUT"
    fi

    validate_device "$DEVICE"
}

# Get partition prefix (handles mmcblk vs sd naming)
get_part_prefix() {
    local dev="$1"
    if [[ "$dev" == *"mmcblk"* || "$dev" == *"nvme"* ]]; then
        echo "${dev}p"
    else
        echo "${dev}"
    fi
}

# Image cache directory
IMAGE_DIR="$HOME/.cache/raspberry-pi-images"

# Image URLs per architecture
IMAGE_URL_ARM64="https://downloads.raspberrypi.com/raspios_lite_arm64/images/"
IMAGE_URL_ARMHF="https://downloads.raspberrypi.com/raspios_lite_armhf/images/"
