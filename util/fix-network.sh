#!/bin/bash
# Fix network configuration on mounted SD card

ROOTFS="${1:-/media/sander/rootfs}"

if [[ ! -d "$ROOTFS/etc/NetworkManager" ]]; then
    echo "Error: $ROOTFS/etc/NetworkManager not found"
    echo "Usage: sudo $0 [rootfs_path]"
    exit 1
fi

echo "Fixing network configuration on $ROOTFS..."

# Fix Wired connection with interface-name
cat > "$ROOTFS/etc/NetworkManager/system-connections/Wired.nmconnection" << 'EOF'
[connection]
id=Wired
type=ethernet
interface-name=eth0
autoconnect=true

[ethernet]

[ipv4]
method=auto

[ipv6]
method=disabled
EOF
chmod 600 "$ROOTFS/etc/NetworkManager/system-connections/Wired.nmconnection"
echo "- Wired.nmconnection: eth0 met DHCP"

# Fix WiFi connection with interface-name
cat > "$ROOTFS/etc/NetworkManager/system-connections/NetwerkTali.nmconnection" << 'EOF'
[connection]
id=NetwerkTali
type=wifi
interface-name=wlan0
autoconnect=true

[wifi]
ssid=NetwerkTali
mode=infrastructure

[wifi-security]
key-mgmt=wpa-psk
psk=Hetwachtwoordvan2020

[ipv4]
method=auto

[ipv6]
method=disabled
EOF
chmod 600 "$ROOTFS/etc/NetworkManager/system-connections/NetwerkTali.nmconnection"
echo "- NetwerkTali.nmconnection: wlan0 met DHCP"

# Disable conflicting services
rm -f "$ROOTFS/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" 2>/dev/null
rm -f "$ROOTFS/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service" 2>/dev/null
echo "- Conflicterende services disabled"

# Keep wifi-start for rfkill only
cat > "$ROOTFS/usr/local/bin/wifi-start.sh" << 'EOF'
#!/bin/bash
sleep 2
rfkill unblock wifi 2>/dev/null || true
ip link set wlan0 up 2>/dev/null || true
EOF
chmod +x "$ROOTFS/usr/local/bin/wifi-start.sh"
echo "- wifi-start.sh vereenvoudigd (alleen rfkill)"

echo ""
echo "Done! Unmount SD card en start Pi:"
echo "  sync && sudo umount /media/sander/bootfs /media/sander/rootfs"
