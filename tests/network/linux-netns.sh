#!/usr/bin/env bash
# Real-packet isolation tests on a Linux host (requires root).
#
# Uses network namespaces to emulate, on the same host:
#   * "kali": a VM attached to the lab interface (DHCP replaced by static IP)
#   * "lan" : another machine on a different interface that adds a route to
#             the lab IP and to Docker subnets through this host (the classic
#             way to reach "localhost only" services from the LAN)
#
#   sudo tests/network/linux-netns.sh setup-sim   # optional: emulated Host-only NIC (no VirtualBox/KVM needed)
#   sudo tests/network/linux-netns.sh test        # labs must be running (./manager start ...)
#   sudo tests/network/linux-netns.sh cleanup
#
# With a real vboxnet/virbr interface, only the "lan" namespace is created and
# the Kali side is tested from the real Kali VM with tests/network/kali-probe.sh.
set -uo pipefail
# shellcheck source=../../scripts/common/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/common/lib.sh"

NS_KALI=plab-kali
NS_LAN=plab-lan
# Interface names must NOT start with "plab": the firewall treats plab+ as
# Docker lab bridges (PLAB-IN/PLAB-FWD drop everything new from them).
SIM_HOST=simlab-h
SIM_PEER=simlab-k
LAN_HOST=simlan-h
LAN_PEER=simlan-n
LEGACY_IFACES="plabsim-h plablan-h"   # names used before 2026-11-22
LAN_NET_HOST=10.250.250.1
LAN_NET_PEER=10.250.250.2

is_root || die "ejecuta este script como root (sudo)." "" 2
cmd=${1:-}

IP=$(lab_config_get ip); PREFIX=$(lab_config_get prefix); IFACE=$(lab_config_get iface)
PORTS=$(lab_ports)
PASS=0; FAILN=0
pass() { log_ok "$*"; PASS=$((PASS + 1)); }
failt() { log_fail "$*"; FAILN=$((FAILN + 1)); }

tcp_open() {  # ns host port -> 0 if a TCP connection succeeds
    ip netns exec "$1" timeout 3 bash -c "exec 3<>/dev/tcp/$2/$3" 2>/dev/null
}

setup_sim() {
    [[ -n $IP ]] || die "no hay IP de laboratorio configurada" "./manager config set-network --platform linux-virtualbox --ip 192.168.57.1 --interface $SIM_HOST"
    if ip link show "$SIM_HOST" >/dev/null 2>&1; then log_warn "$SIM_HOST ya existe"; return; fi
    if grep -qw "inet $IP" <<<"$(ip -4 -o addr)"; then die "la IP $IP ya existe en otra interfaz; no se crea la simulación"; fi
    ip netns add "$NS_KALI"
    ip link add "$SIM_HOST" type veth peer name "$SIM_PEER"
    ip link set "$SIM_PEER" netns "$NS_KALI"
    ip addr add "$IP/$PREFIX" dev "$SIM_HOST"
    ip link set "$SIM_HOST" up
    local kali_ip; kali_ip=$(python3 -c "import ipaddress,sys; n=ipaddress.ip_interface('$IP/$PREFIX').network; print(list(n.hosts())[99])")
    ip -n "$NS_KALI" addr add "$kali_ip/$PREFIX" dev "$SIM_PEER"
    ip -n "$NS_KALI" link set "$SIM_PEER" up
    ip -n "$NS_KALI" link set lo up
    # Like a VM whose NAT adapter is absent: try to use the host as gateway.
    ip -n "$NS_KALI" route add default via "$IP"
    log_ok "interfaz Host-only emulada: $SIM_HOST ($IP/$PREFIX) <-> netns $NS_KALI ($kali_ip)"
    log_info "Configura el gestor con: ./manager config set-network --platform linux-virtualbox --ip $IP --interface $SIM_HOST"
}

setup_lan() {
    grep -qw "$NS_LAN" <<<"$(ip netns list)" && return
    ip netns add "$NS_LAN"
    ip link add "$LAN_HOST" type veth peer name "$LAN_PEER"
    ip link set "$LAN_PEER" netns "$NS_LAN"
    ip addr add "$LAN_NET_HOST/30" dev "$LAN_HOST"
    ip link set "$LAN_HOST" up
    ip -n "$NS_LAN" addr add "$LAN_NET_PEER/30" dev "$LAN_PEER"
    ip -n "$NS_LAN" link set "$LAN_PEER" up
    ip -n "$NS_LAN" link set lo up
    # An attacker on the LAN routes everything (lab IP, Docker subnets) via the host.
    ip -n "$NS_LAN" route add default via "$LAN_NET_HOST"
}

run_tests() {
    [[ -n $IP && -n $IFACE ]] || die "configuración de red incompleta"
    ip link show "$IFACE" >/dev/null 2>&1 || die "la interfaz $IFACE no existe"
    setup_lan
    log_step "LAN -> servicios del laboratorio (deben fallar)"
    for p in $PORTS; do
        if tcp_open "$NS_LAN" "$IP" "$p"; then failt "LAN alcanza $IP:$p"; else pass "LAN no alcanza $IP:$p"; fi
        if tcp_open "$NS_LAN" 127.0.0.1 "$p"; then failt "LAN alcanza 127.0.0.1:$p"; else pass "LAN no alcanza 127.0.0.1:$p"; fi
        if tcp_open "$NS_LAN" "$LAN_NET_HOST" "$p"; then failt "LAN alcanza $LAN_NET_HOST:$p"; else pass "LAN no alcanza la IP del anfitrión en su red ($p)"; fi
    done
    log_step "LAN -> IPs internas de los contenedores (deben fallar)"
    while read -r cip cport; do
        [[ -z $cip ]] && continue
        if tcp_open "$NS_LAN" "$cip" "$cport"; then failt "LAN alcanza el contenedor $cip:$cport"; else pass "LAN no alcanza $cip:$cport"; fi
    done < <(docker ps -q --filter label=org.pentestlab.role | xargs -r docker inspect \
        -f '{{range $n, $c := .NetworkSettings.Networks}}{{$c.IPAddress}}{{"\n"}}{{end}}' | sort -u | while read -r a; do
            [[ -n $a ]] && for p in 80 443 3000 3306 389 8080 9090 4280 8081 8443; do echo "$a $p"; done; done)

    if grep -qw "$NS_KALI" <<<"$(ip netns list)"; then
        log_step "Kali (emulada) -> laboratorio (deben funcionar)"
        for p in $PORTS; do
            if grep -q "$IP:$p->" <<<"$(docker ps --format '{{.Ports}}')"; then
                if tcp_open "$NS_KALI" "$IP" "$p"; then pass "Kali alcanza $IP:$p"; else failt "Kali NO alcanza $IP:$p"; fi
            fi
        done
        log_step "Kali (emulada) -> otros destinos a través del anfitrión (deben fallar)"
        for dst in 1.1.1.1:443 9.9.9.9:53 "$LAN_NET_PEER:22"; do
            if tcp_open "$NS_KALI" "${dst%:*}" "${dst##*:}"; then failt "Kali enruta hacia $dst"; else pass "Kali no enruta hacia $dst"; fi
        done
        for p in 22 1716 5355 11434; do
            if grep -qE "^(0\.0\.0\.0|\*|\[::\]):$p$" <<<"$(ss -Htln | awk '{print $4}')"; then
                if tcp_open "$NS_KALI" "$IP" "$p"; then failt "Kali alcanza el servicio del anfitrión $IP:$p"; else pass "Kali no alcanza el servicio del anfitrión :$p"; fi
            fi
        done
        if ip netns exec "$NS_KALI" ping -c1 -W2 "$IP" >/dev/null 2>&1; then pass "Kali hace ping al anfitrión"; else failt "Kali no hace ping al anfitrión"; fi
    fi
    log_step "Resultado: $PASS correctas, $FAILN fallidas"
    [[ $FAILN -eq 0 ]]
}

cleanup() {
    ip netns del "$NS_LAN" 2>/dev/null && log_ok "netns $NS_LAN eliminado"
    ip link del "$LAN_HOST" 2>/dev/null
    ip netns del "$NS_KALI" 2>/dev/null && log_ok "netns $NS_KALI eliminado"
    ip link del "$SIM_HOST" 2>/dev/null && log_ok "$SIM_HOST eliminado"
    for i in $LEGACY_IFACES; do ip link del "$i" 2>/dev/null && log_ok "$i (nombre antiguo) eliminado"; done
    return 0
}

case $cmd in
    setup-sim) setup_sim ;;
    test) run_tests ;;
    cleanup) cleanup ;;
    *) echo "Uso: sudo $0 {setup-sim|test|cleanup}"; exit 2 ;;
esac
