#!/usr/bin/env bash
# Isolation probe to run INSIDE the Kali VM (as the normal user; sudo is only
# used to add temporary /32 routes). Kali has two NICs (workshop requirement): the lab
# network and a NAT adapter for Internet. The probe checks that:
#   - the 6 lab ports work and nothing else on the host is reachable;
#   - the lab network does not hand out a default route;
#   - the host never routes Kali traffic sent through the lab network
#     (Internet, LAN, the host's LAN address), using temporary routes;
#   - host services are not reachable through the NAT NIC either.
#
#   bash kali-probe.sh [--host IP] [--lan IP]... [--host-lan IP] [--full-scan] [--no-sudo]
#
#   --host IP      lab IP of the host (default 192.168.157.1, KVM default)
#   --lan IP       a LAN device (e.g. your router); may be repeated
#   --host-lan IP  the host's own LAN address
#   --full-scan    also nmap all 65535 TCP ports of --host (a few minutes)
#   --no-sudo      skip the routing tests that need temporary routes
#
# Exit code 0 only if every check passes.
set -uo pipefail

HOST=192.168.157.1; LANS=(); HOST_LAN=""; FULL=0; USE_SUDO=1
LAB_PORTS=(4280 3000 8080 9090 8081 8443)
HOST_SERVICES=(22 80 111 443 631 1716 5355 8000 11434)
while [[ $# -gt 0 ]]; do
    case $1 in
        --host) HOST=$2; shift 2 ;;
        --lan) LANS+=("$2"); shift 2 ;;
        --host-lan) HOST_LAN=$2; shift 2 ;;
        --full-scan) FULL=1; shift ;;
        --no-sudo) USE_SUDO=0; shift ;;
        *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
    esac
done

PASS=0; FAIL=0; SKIP=0
pass() { printf '  \e[32mOK\e[0m      %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \e[31mFALLO\e[0m   %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  \e[33mOMITIDO\e[0m %s\n' "$1"; SKIP=$((SKIP + 1)); }
info() { printf '  ·       %s\n' "$1"; }
step() { printf '\n\e[1m== %s\e[0m\n' "$1"; }

# 0 = open, 1 = refused, 2 = no answer (filtered/timeout)
tcp() {
    timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
    case $? in 0) return 0 ;; 124) return 2 ;; *) return 1 ;; esac
}
must_block() {  # ip port description
    tcp "$1" "$2"
    case $? in
        0) fail "$3 ($1:$2) ACCESIBLE" ;;
        1) pass "$3 ($1:$2) rechazado" ;;
        2) pass "$3 ($1:$2) sin respuesta (filtrado)" ;;
    esac
}

# ------------------------------------------------------------ interfaces ---
step "Red de Kali"
ip -4 -br addr | grep -v '^lo ' | sed 's/^/  /'
prefix=${HOST%.*}.
LAB_IF=$(ip -4 -o addr | awk -v p="$prefix" 'index($4, p) == 1 {print $2; exit}')
if [[ -n $LAB_IF ]]; then
    pass "NIC de laboratorio: $LAB_IF (${prefix}x)"
else
    fail "Kali no tiene IP en ${prefix}0/24 (¿NIC de laboratorio conectada? ¿DHCP?)"
fi
if [[ -n $LAB_IF && -n $(ip -4 route show default dev "$LAB_IF") ]]; then
    fail "la red de laboratorio da ruta por defecto ($(ip -4 route show default dev "$LAB_IF" | head -1))"
    info "redefine la red (scripts/linux/install.sh --phase network) o, en Kali: nmcli connection modify <conexión> ipv4.never-default yes"
else
    pass "la red de laboratorio no da ruta por defecto"
fi
NAT_IF=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}' | grep -vx "${LAB_IF:-none}" | head -1)
NAT_GW=""
[[ -n $NAT_IF ]] && NAT_GW=$(ip -4 route show default dev "$NAT_IF" | awk '{print $3; exit}')
if [[ -n $NAT_IF ]]; then
    info "NIC NAT: $NAT_IF (pasarela $NAT_GW)"
    if curl -s -o /dev/null -m 8 https://http.kali.org/; then info "Internet por la NIC NAT: sí"; else info "Internet por la NIC NAT: no (no afecta al aislamiento del laboratorio)"; fi
else
    info "sin NIC NAT con ruta por defecto (Kali no tendrá Internet para actualizarse)"
fi

# --------------------------------------------------------------- the labs ---
step "Kali -> puertos del laboratorio en $HOST (deben funcionar)"
for p in "${LAB_PORTS[@]}"; do
    if tcp "$HOST" "$p"; then
        scheme=http; [[ $p == 8443 ]] && scheme=https
        code=$(curl -sk -o /dev/null -m 10 -w '%{http_code}' "$scheme://$HOST:$p/")
        if [[ $code =~ ^[1-5][0-9][0-9]$ ]]; then pass "$HOST:$p responde HTTP $code"; else fail "$HOST:$p abierto pero sin respuesta HTTP"; fi
    else
        fail "$HOST:$p no accesible (¿laboratorio arrancado?)"
    fi
done
if ping -c1 -W2 "$HOST" >/dev/null 2>&1; then pass "ping al anfitrión"; else fail "sin ping al anfitrión"; fi

step "Kali -> servicios del anfitrión en la red de laboratorio (deben fallar)"
for p in 53 "${HOST_SERVICES[@]}"; do must_block "$HOST" "$p" "anfitrión"; done

# ----------------------------------------------- routing through the host ---
step "Kali -> otros destinos usando el anfitrión como router (deben fallar)"
TARGETS=(1.1.1.1 9.9.9.9 "${LANS[@]}"); [[ -n $HOST_LAN ]] && TARGETS+=("$HOST_LAN")
ADDED=()
cleanup_routes() { for t in "${ADDED[@]}"; do sudo ip route del "$t/32" via "$HOST" dev "$LAB_IF" 2>/dev/null; done; }
trap cleanup_routes EXIT
if [[ -z $LAB_IF ]]; then
    skip "sin NIC de laboratorio"
elif [[ $USE_SUDO -eq 0 ]] || ! sudo -v; then
    skip "rutas temporales: hace falta sudo (o se usó --no-sudo)"
else
    for t in "${TARGETS[@]}"; do
        sudo ip route replace "$t/32" via "$HOST" dev "$LAB_IF" && ADDED+=("$t")
    done
    info "rutas temporales vía $HOST: ${ADDED[*]}"
    must_block 1.1.1.1 443 "Internet vía anfitrión"
    must_block 9.9.9.9 53 "DNS público vía anfitrión"
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then fail "ping a 1.1.1.1 vía anfitrión responde"; else pass "sin ping a Internet vía anfitrión"; fi
    if command -v dig >/dev/null; then
        if dig +time=2 +tries=1 @9.9.9.9 example.com >/dev/null 2>&1; then fail "DNS (UDP) a 9.9.9.9 vía anfitrión responde"; else pass "sin DNS (UDP) vía anfitrión"; fi
    fi
    for ip in "${LANS[@]}"; do
        for p in 22 53 80 443; do must_block "$ip" "$p" "LAN vía anfitrión"; done
        if ping -c1 -W2 "$ip" >/dev/null 2>&1; then fail "ping a $ip vía anfitrión responde"; else pass "sin ping a $ip vía anfitrión"; fi
    done
    if [[ -n $HOST_LAN ]]; then
        for p in 22 "${LAB_PORTS[@]}"; do must_block "$HOST_LAN" "$p" "IP LAN del anfitrión vía red de laboratorio"; done
    fi
    cleanup_routes; ADDED=()
fi

# ------------------------------------------------------ the NAT NIC side ---
if [[ -n $NAT_GW ]]; then
    step "Kali -> servicios del anfitrión por la NIC NAT (deben fallar)"
    for p in "${HOST_SERVICES[@]}"; do must_block "$NAT_GW" "$p" "anfitrión vía NAT"; done
    for p in "${LAB_PORTS[@]}"; do
        if tcp "$NAT_GW" "$p"; then info "$NAT_GW:$p accesible por NAT (laboratorio vía el NAT del hipervisor)"; fi
    done
    if [[ -n $HOST_LAN ]]; then
        for p in 22 "${LAB_PORTS[@]}"; do must_block "$HOST_LAN" "$p" "IP LAN del anfitrión vía NAT"; done
    fi
fi

# -------------------------------------------------------------- full scan ---
if [[ $FULL -eq 1 ]]; then
    step "Escaneo TCP completo de $HOST (solo deben aparecer los puertos del laboratorio)"
    if command -v nmap >/dev/null; then
        open=$(nmap -Pn -n -p- -T4 --max-retries 1 --open -oG - "$HOST" 2>/dev/null \
               | grep -oE '[0-9]+/open' | cut -d/ -f1 | sort -n | tr '\n' ' ')
        expected=$(printf '%s\n' "${LAB_PORTS[@]}" | sort -n | tr '\n' ' ')
        info "abiertos: ${open:-ninguno}"
        if [[ $open == "$expected" ]]; then pass "solo están abiertos los 6 puertos del laboratorio"; else fail "puertos abiertos distintos de los esperados ($expected)"; fi
    else
        fail "nmap no está instalado"
    fi
fi

step "Resultado: $PASS correctas, $FAIL fallidas, $SKIP omitidas"
[[ $FAIL -eq 0 ]]
