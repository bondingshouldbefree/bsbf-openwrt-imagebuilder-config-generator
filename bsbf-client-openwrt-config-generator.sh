#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2025-2026 Chester A. Unal <chester.a.unal@arinc9.com>

usage() {
	echo "Usage: $0 --server-ipv4 <ADDR> --server-port <PORT> --uuid <UUID> [--no-luci --dongle-modem --quectel-modem --usb-adapters-and-android-tethering --ios-tethering --mikrotik-tools --diag-tools --perf-test]"
	exit 1
}

packages="bsbf-bonding kmod-sched kmod-sched-bpf kmod-nft-tproxy"

# Parse arguments.
while [ $# -gt 0 ]; do
	case "$1" in
	--server-ipv4)
		[ -z "$2" ] && usage
		server_ipv4="$2"
		shift 2
		;;
	--server-port)
		[ -z "$2" ] && usage
		server_port="$2"
		shift 2
		;;
	--uuid)
		[ -z "$2" ] && usage
		uuid="$2"
		shift 2
		;;
	--no-luci)
		packages="$packages -luci"
		shift
		;;
	--dongle-modem)
		packages="$packages bsbf-usb-netdev-autodhcp kmod-usb-net-cdc-ether usb-modeswitch"
		shift
		;;
	--quectel-modem)
		packages="$packages bsbf-quectel-usbnet kmod-usb-serial-option umbim"
		shift
		;;
	--usb-adapters-and-android-tethering)
		packages="$packages bsbf-usb-netdev-autodhcp kmod-usb-net-cdc-ether kmod-usb-net-rtl8152 kmod-usb-net-rndis"
		shift
		;;
	--ios-tethering)
		packages="$packages bsbf-usb-netdev-autodhcp kmod-usb-net-ipheth usbmuxd"
		shift
		;;
	--mikrotik-tools)
		packages="$packages mac-telnet-client mac-telnet-discover mac-telnet-ping mac-telnet-server"
		shift
		;;
	--diag-tools)
		packages="$packages bsbf-netspeed curl htop ss kmod-inet-mptcp-diag"
		shift
		;;
	--perf-test)
		packages="$packages kmod-sched-flower kmod-veth coreutils-nproc iperf3"
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

# Generate the uci-defaults script.
cat <<EOF2 >> 99-bsbf-bonding-2
# xray Configuration
cat <<'EOF' > /etc/xray/config.json
$(curl -s $BSBF_RESOURCES/resources-client/xray.json \
  | jq --arg SERVER "$server_ipv4" \
       --argjson PORT "$server_port" \
       --arg UUID "$uuid" '
        .outbounds[0].settings.address = $SERVER
      | .outbounds[0].settings.port = $PORT
      | .outbounds[0].settings.id = $UUID')
EOF

# bsbf-tcp-in-udp Configuration
cat <<'EOF' > /usr/sbin/bsbf-tcp-in-udp
$(curl -s $BSBF_RESOURCES/resources-client/bsbf-tcp-in-udp \
  | sed -e "s/^BASE_PORT=.*/BASE_PORT=$server_port/" \
	-e "s/^IPv4=.*/IPv4=\"$server_ipv4\"/")
EOF
EOF2

# Print packages to stdout in a single line.
echo "$packages"
