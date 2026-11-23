#!/usr/bin/env bash
# Network diagnostics for the lab interface (run as your normal user; uses sudo).
# Saves everything to state/linux-diag.log. Useful when a netns test fails.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT" || exit 1
mkdir -p state
exec > >(tee "$ROOT/state/linux-diag.log") 2>&1
set -x
sudo -v || exit 1
source scripts/common/lib.sh; IP=$(lab_config_get ip)
ip -br addr
sudo ip netns list
sudo ip -n plab-kali -br addr
sudo ip -n plab-kali route
sudo iptables -Z PLAB-IN
sudo ip netns exec plab-kali ping -c2 -W2 "$IP"
sudo iptables -L PLAB-IN -v -n --line-numbers
sudo iptables -L INPUT -v -n --line-numbers | head -8
sudo nft list ruleset | grep -nE '^table|hook (input|prerouting)|policy drop|icmp'
sysctl net.ipv4.icmp_echo_ignore_all net.ipv4.icmp_echo_ignore_broadcasts
sudo tests/network/linux-netns.sh test
set +x
echo "=== FIN DEL DIAGNÓSTICO ==="
