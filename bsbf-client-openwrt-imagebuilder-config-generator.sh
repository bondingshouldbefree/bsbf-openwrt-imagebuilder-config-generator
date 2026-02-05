#!/bin/sh
# This script generates a uci-defaults script and a list of packages which can
# be used with OpenWrt's imagebuilder to build an image with BSBF bonding
# solution client.
# Author: Chester A. Unal <chester.a.unal@arinc9.com>

usage() {
	echo "Usage: $0 --server-ipv4 <ADDR> --server-port <PORT> --uuid <UUID> [--v2ray --tcp-in-udp-big-endian --no-luci --dongle-modem --quectel-modem --usb-adapters-and-android-tethering --ios-tethering --mikrotik-tools --debug-tools]"
	exit 1
}

packages="ethtool fping mptcpd ip-full tc-full kmod-sched kmod-sched-bpf coreutils-base64 sing-box-tiny"

# Parse arguments.
while [ $# -gt 0 ]; do
	case "$1" in
	--server-ipv4)
		[ -z "$2" ] && usage
		server_ipv4="$2"
		shift 2
		continue
		;;
	--server-port)
		[ -z "$2" ] && usage
		server_port="$2"
		shift 2
		continue
		;;
	--uuid)
		[ -z "$2" ] && usage
		uuid="$2"
		shift 2
		continue
		;;
	--v2ray)
		packages="$packages -sing-box-tiny v2ray-core kmod-nft-tproxy"
		v2ray=1
		shift
		;;
	--tcp-in-udp-big-endian)
		tcp_in_udp_be=1
		shift
		;;
	--no-luci)
		packages="$packages -luci"
		shift
		;;
	--dongle-modem)
		packages="$packages kmod-usb-net-cdc-ether usb-modeswitch"
		bsbf_usb_netdev_autodhcp=1
		shift
		;;
	--quectel-modem)
		packages="$packages kmod-usb-net-cdc-mbim kmod-usb-serial-option umbim"
		bsbf_quectel_usbnet=1
		bsbf_cdc_mbim=1
		shift
		;;
	--usb-adapters-and-android-tethering)
		packages="$packages kmod-usb-net-cdc-ether kmod-usb-net-rtl8152 kmod-usb-net-rndis"
		bsbf_usb_netdev_autodhcp=1
		shift
		;;
	--ios-tethering)
		packages="$packages kmod-usb-net-ipheth usbmuxd"
		bsbf_usb_netdev_autodhcp=1
		shift
		;;
	--mikrotik-tools)
		packages="$packages mac-telnet-client mac-telnet-discover mac-telnet-ping mac-telnet-server"
		shift
		;;
	--debug-tools)
		packages="$packages curl htop mptcpize tcpdump"
		bsbf_netspeed=1
		shift
		;;
	*)
		usage
		;;
	esac
done

# Show usage if server IPv4 address, server port, and UUID were not provided.
{ [ -z "$server_ipv4" ] || [ -z "$server_port" ] || [ -z "$uuid" ]; } && usage

BSBF_RESOURCES="https://raw.githubusercontent.com/bondingshouldbefree/bsbf-resources/refs/heads/main"

# Decide the proxy programme.
proxy_programme="# sing-box Configuration
cat <<'EOF' > /etc/sing-box/config.json
$(curl -s $BSBF_RESOURCES/resources-client/sing-box.json \
  | jq --arg SERVER "$server_ipv4" \
       --argjson PORT "$server_port" \
       --arg UUID "$uuid" \
       '.outbounds[0].server = $SERVER
        | .outbounds[0].server_port = $PORT
        | .outbounds[0].uuid = $UUID')
EOF

uci delete sing-box.main.user
uci set sing-box.main.enabled='1'
uci commit sing-box"

[ -n "$v2ray" ] && proxy_programme="# v2ray Configuration
cat <<'EOF' > /etc/v2ray/config.json
$(curl -s $BSBF_RESOURCES/resources-client/v2ray.json \
  | jq --arg SERVER "$server_ipv4" \
       --argjson PORT "$server_port" \
       --arg UUID "$uuid" \
       '.outbounds[0].settings.vnext[0].address = $SERVER
        | .outbounds[0].settings.vnext[0].port = $PORT
        | .outbounds[0].settings.vnext[0].users[0].id = $UUID')
EOF

uci set v2ray.enabled.enabled='1'
uci commit v2ray

# Add rule to use routing table 100 for transparent proxy traffic.
uci add network rule
uci set network.@rule[-1].priority='0'
uci set network.@rule[-1].lookup='100'
uci set network.@rule[-1].mark='1'

# Add route to route transparent proxy traffic to the loopback interface.
uci add network route
uci set network.@route[-1].interface='loopback'
uci set network.@route[-1].type='local'
uci set network.@route[-1].target='0.0.0.0/0'
uci set network.@route[-1].table='100'
uci commit network

# nftables Configuration
cat <<'EOF' > /etc/nftables.d/99-bsbf-proxy.nft
$(curl -s $BSBF_RESOURCES/resources-client/99-bsbf-proxy-openwrt.nft)
EOF"

# Decide the TCP-in-UDP object.
tcp_in_udp_endianness="tcp_in_udp_tc_le.o"
[ -n "$tcp_in_udp_be" ] && tcp_in_udp_endianness="tcp_in_udp_tc_be.o"

# Additional options.
[ -n "$bsbf_usb_netdev_autodhcp" ] && additional_options="# bsbf-usb-netdev-autodhcp
cat <<'EOF' > /etc/hotplug.d/usb/99-bsbf-usb-netdev-autodhcp
$(curl -s $BSBF_RESOURCES/bsbf-usb-netdev-autodhcp/files/etc/hotplug.d/net/99-bsbf-usb-netdev-autodhcp)
EOF
"

[ -n "$bsbf_quectel_usbnet" ] && additional_options="$additional_options
# bsbf-quectel-usbnet
cat <<'EOF' > /etc/init.d/bsbf-quectel-usbnet
$(curl -s $BSBF_RESOURCES/bsbf-quectel-usbnet/files/etc/init.d/bsbf-quectel-usbnet)
EOF
chmod +x /etc/init.d/bsbf-quectel-usbnet

cat <<'EOF' > /usr/sbin/bsbf-quectel-usbnet
$(curl -s $BSBF_RESOURCES/bsbf-quectel-usbnet/files/usr/sbin/bsbf-quectel-usbnet)
EOF
chmod +x /usr/sbin/bsbf-quectel-usbnet

/etc/init.d/bsbf-quectel-usbnet enable && /etc/init.d/bsbf-quectel-usbnet start
"

[ -n "$bsbf_netspeed" ] && additional_options="$additional_options
# bsbf-netspeed
cat <<'EOF' > /usr/sbin/bsbf-netspeed
$(curl -s $BSBF_RESOURCES/bsbf-netspeed/files/usr/sbin/bsbf-netspeed)
EOF
chmod +x /usr/sbin/bsbf-netspeed
"

# Generate the uci-defaults script.
cat <<EOF2 > 99-bsbf-bonding
# This script provides the BondingShouldBeFree bonding solution.
# Author: Chester A. Unal <chester.a.unal@arinc9.com>

# Get the interface of lan network.
lan_network_interface="\$(uci get network.lan.device)"

# If LAN is a bridge, get its members.
if echo "\$lan_network_interface" | grep -q '^br'; then
	lan_interfaces="\$(uci get network.@device[0].ports)"

	# Set biggest number interface as lan network.
	lan_network_interface="\$(echo \$lan_interfaces | tr ' ' '\\n' | grep '[0-9]\\+\$' | sort -V | tail -n1)"
	uci set network.lan.device="\$lan_network_interface"

	# Remove bridge interface.
	uci delete network.@device[0]
fi
uci set network.lan.ipaddr='192.168.4.1'

# Get the interface of wan network. It won't be a bridge.
wan_network_interface="\$(uci get network.wan.device)"

# Add a wan network entry for wan network's interface and lan network
# interfaces other than the one used for lan, if there are any.
wan_candidates="\$wan_network_interface \$(echo \$lan_interfaces | tr ' ' '\\n' | grep -v "^\$lan_network_interface\$")"

# Delete existing wan and wan6 networks.
uci delete network.wan
uci delete network.wan6

index=1
for dev in \$wan_candidates; do
	[ -z "\$dev" ] && continue

	uci set network.wan\$index=interface
	uci set network.wan\$index.device="\$dev"
	uci set network.wan\$index.proto='dhcp'
	uci set network.wan\$index.peerdns='0'
	uci set network.wan\$index.metric="\$index"

	# Add every wan network entry to firewall wan zone.
	uci add_list firewall.@zone[1].network="wan\$index"

	index=\$((index + 1))
done

# dnsmasq Configuration
# As we don't want to use the DNS servers advertised by WANs, set up DNS
# forwarding. Use 8.8.8.8 because some ISPs such as rain SA won't reach 1.1.1.1.
uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'

# Commit changes.
uci commit dhcp
uci commit network
uci commit firewall

# mptcpd Configuration
cat <<'EOF' > /etc/mptcpd/mptcpd.conf
$(curl -s $BSBF_RESOURCES/resources-client/mptcpd.conf)
EOF

$proxy_programme

# bsbf-tcp-in-udp
cat <<'EOF' > /etc/hotplug.d/iface/99-bsbf-tcp-in-udp
$(curl -s $BSBF_RESOURCES/bsbf-tcp-in-udp/files/etc/hotplug.d/iface/99-bsbf-tcp-in-udp)
EOF

mkdir -p /usr/local/share/tcp-in-udp
cat <<'EOF' | base64 -d > /usr/local/share/tcp-in-udp/tcp_in_udp_tc.o
$(curl -s $BSBF_RESOURCES/bsbf-tcp-in-udp/files/usr/local/share/tcp-in-udp/$tcp_in_udp_endianness | base64)
EOF

cat <<'EOF' > /usr/sbin/bsbf-tcp-in-udp
$(curl -s $BSBF_RESOURCES/bsbf-tcp-in-udp/files/usr/sbin/bsbf-tcp-in-udp \
  | sed -e "s/^BASE_PORT=.*/BASE_PORT=$server_port/" \
	-e "s/^IPv4=.*/IPv4=\"$server_ipv4\"/")
EOF
chmod +x /usr/sbin/bsbf-tcp-in-udp

# bsbf-mptcp-helper
cat <<'EOF' > /etc/config/bsbf-mptcp-helper
$(curl -s $BSBF_RESOURCES/bsbf-mptcp-helper/files/etc/config/bsbf-mptcp-helper)
EOF

cat <<'EOF' > /etc/hotplug.d/iface/99-bsbf-mptcp-backup
$(curl -s $BSBF_RESOURCES/bsbf-mptcp-helper/files/etc/hotplug.d/iface/99-bsbf-mptcp-backup)
EOF

cat <<'EOF' > /etc/hotplug.d/iface/99-bsbf-mptcp-remove
$(curl -s $BSBF_RESOURCES/bsbf-mptcp-helper/files/etc/hotplug.d/iface/99-bsbf-mptcp-remove)
EOF

cat <<'EOF' > /etc/init.d/bsbf-mptcp-backup
$(curl -s $BSBF_RESOURCES/bsbf-mptcp-helper/files/etc/init.d/bsbf-mptcp-backup)
EOF
chmod +x /etc/init.d/bsbf-mptcp-backup

cat <<'EOF' > /usr/sbin/bsbf-mptcp-backup
$(curl -s $BSBF_RESOURCES/bsbf-mptcp-helper/files/usr/sbin/bsbf-mptcp-backup)
EOF
chmod +x /usr/sbin/bsbf-mptcp-backup

cat <<'EOF' > /usr/sbin/bsbf-mptcp-helper
$(curl -s $BSBF_RESOURCES/bsbf-mptcp-helper/files/usr/sbin/bsbf-mptcp-helper)
EOF
chmod +x /usr/sbin/bsbf-mptcp-helper

/etc/init.d/bsbf-mptcp-backup enable && /etc/init.d/bsbf-mptcp-backup start

# bsbf-route
cat <<'EOF' > /etc/init.d/bsbf-route
$(curl -s $BSBF_RESOURCES/bsbf-route/files/etc/init.d/bsbf-route)
EOF
chmod +x /etc/init.d/bsbf-route

cat <<'EOF' > /usr/sbin/bsbf-route
$(curl -s $BSBF_RESOURCES/bsbf-route/files/usr/sbin/bsbf-route)
EOF
chmod +x /usr/sbin/bsbf-route

/etc/init.d/bsbf-route enable && /etc/init.d/bsbf-route start

$additional_options
EOF2

# Print packages to stdout (single line)
echo "$packages"
