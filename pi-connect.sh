#!/bin/bash
set -e

# Raspberry Pi Connection & SSH Key Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

show_help() {
    cat << EOF
Raspberry Pi Connection & SSH Key Setup

Usage: $0 --host <hostname|ip> --user <user>

Required:
  --host        Hostname or IP to connect to
  --user        Username for SSH

Examples:
  $0 --host rp-black.local --user <user>
  $0 --host 192.168.1.188 --user <user>
EOF
}

main() {
    parse_args "$@"

    [[ -z "$PI_HOST" ]] && log_error "Missing --host"
    [[ -z "$PI_USER" ]] && log_error "Missing --user"

    echo "Testing SSH to ${PI_USER}@${PI_HOST}..."

    # Test SSH connection (timeout 5 seconds)
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${PI_USER}@${PI_HOST}" exit 2>/dev/null; then
        log_ok "SSH works (key already installed)"
        echo ""
        echo "Connect with: ssh ${PI_USER}@${PI_HOST}"
        exit 0
    fi

    # SSH failed - try to connect and setup key
    log_info "SSH key not installed, setting up..."

    # Clean old known_hosts entries
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$PI_HOST" 2>/dev/null || true

    # Find public key
    PUBKEY=""
    for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
        [[ -f "$key" ]] && PUBKEY="$key" && break
    done

    [[ -z "$PUBKEY" ]] && log_error "No SSH public key found. Generate with: ssh-keygen -t ed25519"

    log_info "Copying $PUBKEY..."

    # Copy key (will prompt for password)
    if ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$PUBKEY" "${PI_USER}@${PI_HOST}"; then
        log_ok "SSH key installed"
        echo ""
        echo "Connect with: ssh ${PI_USER}@${PI_HOST}"
        exit 0
    else
        log_error "Failed to copy SSH key"
    fi
}

main "$@"
