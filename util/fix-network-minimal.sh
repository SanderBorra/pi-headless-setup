#!/bin/bash
# Minimal fix - replicate what worked before

ROOTFS="${1:-/media/sander/rootfs}"

if [[ ! -d "$ROOTFS/etc" ]]; then
    echo "Error: $ROOTFS/etc not found"
    exit 1
fi

echo "Applying minimal working configuration..."

# 1. Remove ALL custom NetworkManager WiFi configs (conflicted with wpa_supplicant)
rm -f "$ROOTFS/etc/NetworkManager/system-connections/NetwerkTali.nmconnection" 2>/dev/null
rm -f "$ROOTFS/etc/NetworkManager/system-connections/Wired.nmconnection" 2>/dev/null
echo "- Removed custom NetworkManager configs"

# 2. Keep NetworkManager enabled (handles eth0 automatically via DHCP)
# Already enabled by default, don't touch it

# 3. wpa_supplicant config (this worked)
mkdir -p "$ROOTFS/etc/wpa_supplicant"
cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" << 'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=NL

network={
    ssid="NetwerkTali"
    psk="Hetwachtwoordvan2020"
    key_mgmt=WPA-PSK
}
EOF
chmod 600 "$ROOTFS/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
echo "- wpa_supplicant-wlan0.conf configured"

# 4. systemd-networkd config for wlan0 static IP (this worked)
mkdir -p "$ROOTFS/etc/systemd/network"
cat > "$ROOTFS/etc/systemd/network/20-wlan0.network" << 'EOF'
[Match]
Name=wlan0

[Network]
Address=192.168.1.9/24
Gateway=192.168.1.1
DNS=192.168.1.1
DNS=8.8.8.8
EOF
echo "- systemd-networkd wlan0 config created"

# 5. Enable wpa_supplicant@wlan0 service
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sf /lib/systemd/system/wpa_supplicant@.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service" 2>/dev/null
echo "- wpa_supplicant@wlan0 service enabled"

# 6. Enable systemd-networkd
ln -sf /lib/systemd/system/systemd-networkd.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" 2>/dev/null
echo "- systemd-networkd service enabled"

# 7. Simple wifi-start for rfkill (this worked)
mkdir -p "$ROOTFS/usr/local/bin"
cat > "$ROOTFS/usr/local/bin/wifi-start.sh" << 'EOF'
#!/bin/bash
sleep 2
rfkill unblock wifi
sleep 1
ip link set wlan0 up
EOF
chmod +x "$ROOTFS/usr/local/bin/wifi-start.sh"
echo "- wifi-start.sh created"

# 8. Enable wifi-start service
cat > "$ROOTFS/etc/systemd/system/wifi-start.service" << 'EOF'
[Unit]
Description=WiFi Startup
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-start.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
ln -sf /etc/systemd/system/wifi-start.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/wifi-start.service" 2>/dev/null
echo "- wifi-start.service enabled"

# 9. Remove legacy /etc/network/interfaces changes
cat > "$ROOTFS/etc/network/interfaces" << 'EOF'
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source /etc/network/interfaces.d/*
EOF
echo "- Reset /etc/network/interfaces to default"

echo ""
echo "Done! This replicates the working configuration:"
echo "  - eth0: NetworkManager with DHCP (default)"
echo "  - wlan0: wpa_supplicant + systemd-networkd (192.168.1.9)"
echo ""
echo "Unmount: sync && sudo umount /media/sander/bootfs /media/sander/rootfs"
