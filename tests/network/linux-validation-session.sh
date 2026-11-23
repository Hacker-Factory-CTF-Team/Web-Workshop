#!/usr/bin/env bash
# Privileged end-to-end validation on a Linux host WITHOUT VirtualBox/KVM:
# emulates the Host-only NIC with a veth + netns ("Kali") and a "LAN" netns.
# Run as your normal user (it calls sudo when needed):
#   bash tests/network/linux-validation-session.sh
# Full output is saved to state/linux-validation-session.log
#
# Set PLAB_SUDOERS=no to skip installing the scoped sudoers rule for
# pentestlab-fw verify/apply (default here: yes, for unattended re-runs).
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT" || exit 1
mkdir -p state
LOG="$ROOT/state/linux-validation-session.log"
exec > >(tee "$LOG") 2>&1
FAILED=()
set -x
sudo -v || exit 1
iptables --version
sudo iptables -S DOCKER-USER | head -5
sudo iptables -S INPUT | head -5
cat /proc/sys/net/bridge/bridge-nf-call-iptables
./manager stop all
./manager config set-network --platform linux-virtualbox --ip 192.168.57.1 --prefix 24 --interface simlab-h
sudo tests/network/linux-netns.sh cleanup
sudo tests/network/linux-netns.sh setup-sim || FAILED+=("setup-sim")
PLAB_SUDOERS=${PLAB_SUDOERS:-yes} ASSUME_YES=1 scripts/linux/install.sh --phase firewall || FAILED+=("install.sh --phase firewall")
sudo /usr/local/sbin/pentestlab-fw status
./manager --yes install all || FAILED+=("./manager --yes install all")
./manager --yes start all || FAILED+=("./manager --yes start all")
./manager status
./manager network-check || FAILED+=("./manager network-check")
sudo tests/network/linux-netns.sh test || FAILED+=("sudo tests/network/linux-netns.sh test")
set +x
echo "=== FIN DE LA SESIÓN ==="
if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf 'FALLARON: %s\n' "${FAILED[@]}"
    exit 1
fi
echo "Todos los pasos críticos superados."
