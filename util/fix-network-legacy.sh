#!/bin/bash
# Fix network using legacy /etc/network/interfaces method

ROOTFS="${1:-/media/sander/rootfs}"

if [[ ! -d "$ROOTFS/etc" ]]; then
    echo "Error: $ROOTFS/etc not found"
    exit 1
fi

echo "Switching to legacy /etc/network/interfaces method..."

# Disable NetworkManager and systemd-networkd
rm -f "$ROOTFS/etc/systemd/system/multi-user.target.wants/NetworkManager.service" 2>/dev/null
rm -f "$ROOTFS/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" 2>/dev/null
rm -f "$ROOTFS/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service" 2>/dev/null
echo "- NetworkManager en systemd-networkd disabled"

# Enable networking service
ln -sf /lib/systemd/system/networking.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/networking.service" 2>/dev/null

# Configure /etc/network/interfaces
cat > "$ROOTFS/etc/network/interfaces" << 'EOF'
# Loopback
auto lo
iface lo inet loopback

# Ethernet - DHCP
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# WiFi
auto wlan0
allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF
echo "- /etc/network/interfaces geconfigureerd"

# Configure wpa_supplicant
cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" << 'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=NL

network={
    ssid="NetwerkTali"
    psk="Hetwachtwoordvan2020"
    key_mgmt=WPA-PSK
}
EOF
chmod 600 "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"
echo "- wpa_supplicant.conf geconfigureerd"

# Simple wifi-start for rfkill
cat > "$ROOTFS/usr/local/bin/wifi-start.sh" << 'EOF'
#!/bin/bash
sleep 2
rfkill unblock wifi 2>/dev/null || true
ip link set wlan0 up 2>/dev/null || true
ifup wlan0 2>/dev/null || true
EOF
chmod +x "$ROOTFS/usr/local/bin/wifi-start.sh"
echo "- wifi-start.sh updated"

echo ""
echo "Done! Legacy networking configured."
echo "Unmount: sync && sudo umount /media/sander/bootfs /media/sander/rootfs"
