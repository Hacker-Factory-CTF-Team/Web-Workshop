#!/usr/bin/env bash
# Modular tool kit for the Kali VM of the pentesting lab.
# Self-contained: only needs this file and modules/*.conf next to it.
#
#   kali/install.sh                       interactive menu
#   kali/install.sh --list                modules, tools and status
#   kali/install.sh --install all         install every module
#   kali/install.sh --install recon,dev   install some modules
#   kali/install.sh --update [all|MODS]   update installed tools of the modules
#   kali/install.sh --check [--host IP] [--ports P,P,...] [--full]
#                                         tool status + connectivity with the host
#
# Run it as the normal Kali user (sudo is used for APT). Packages come from
# the configured APT repositories, preferably the official Kali ones.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODDIR="$HERE/modules"
PROBE="$HERE/../tests/network/kali-probe.sh"
HOST=192.168.157.1
PORTS=(4280 3000 8080 9090 8081 8443)

if [[ -t 1 ]]; then C_G=$'\e[32m' C_R=$'\e[31m' C_Y=$'\e[33m' C_B=$'\e[1m' C_0=$'\e[0m'; else C_G="" C_R="" C_Y="" C_B="" C_0=""; fi
ok()   { printf '  %s[OK]%s    %s\n' "$C_G" "$C_0" "$1"; }
bad()  { printf '  %s[FALLO]%s %s\n' "$C_R" "$C_0" "$1"; }
warn() { printf '  %s[AVISO]%s %s\n' "$C_Y" "$C_0" "$1"; }
info() { printf '          %s\n' "$1"; }
step() { printf '\n%s==> %s%s\n' "$C_B" "$1" "$C_0"; }
die()  { printf '%sERROR:%s %s\n' "$C_R" "$C_0" "$1" >&2; [[ -n ${2:-} ]] && printf 'Cómo solucionarlo: %s\n' "$2" >&2; exit "${3:-1}"; }

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# ------------------------------------------------------------- modules ---
MODULES=()                 # module ids, in file order
declare -A MOD_NAME MOD_DESC MOD_TOOLS   # MOD_TOOLS[id]="tool1 tool2"
declare -A TOOL_CMD TOOL_PKGS             # per tool id

load_modules() {
    local f id line key val tid cmd pkgs
    [[ -d $MODDIR ]] || die "no se encuentra $MODDIR" "Copia la carpeta kali/ completa (install.sh y modules/)."
    for f in "$MODDIR"/*.conf; do
        [[ -e $f ]] || continue
        id=$(basename "$f" .conf); id=${id#[0-9][0-9]-}
        MODULES+=("$id"); MOD_TOOLS[$id]=""
        while IFS= read -r line || [[ -n $line ]]; do
            [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
            key=${line%%=*}; val=${line#*=}
            case $key in
                name) MOD_NAME[$id]=$val ;;
                description) MOD_DESC[$id]=$val ;;
                tool)
                    IFS='|' read -r tid cmd pkgs <<<"$val"
                    [[ -n $tid && -n $cmd && -n $pkgs ]] || die "línea inválida en $(basename "$f"): $line"
                    TOOL_CMD[$tid]=$cmd; TOOL_PKGS[$tid]=$pkgs
                    MOD_TOOLS[$id]+="$tid " ;;
                *) die "clave desconocida en $(basename "$f"): $key" ;;
            esac
        done <"$f"
    done
    [[ ${#MODULES[@]} -gt 0 ]] || die "no hay módulos en $MODDIR"
}

SEL=()
resolve_modules() {  # "all" | "a,b" -> SEL (runs in the main shell so die() exits)
    local arg=${1:-all} m id found want
    SEL=()
    if [[ $arg == all ]]; then SEL=("${MODULES[@]}"); return; fi
    IFS=',' read -ra want <<<"$arg"
    for m in "${want[@]}"; do
        found=0
        for id in "${MODULES[@]}"; do [[ $id == "$m" ]] && found=1; done
        [[ $found -eq 1 ]] || die "módulo desconocido: '$m'" "Módulos: ${MODULES[*]} (o 'all')." 2
        SEL+=("$m")
    done
}

# ---------------------------------------------------------------- tools ---
tool_installed() { command -v "${TOOL_CMD[$1]}" >/dev/null 2>&1; }

pkg_installed() { [[ $(dpkg-query -W -f='${Status}' "$1" 2>/dev/null) == "install ok installed" ]]; }

pkg_candidate() {  # prints the candidate version or nothing
    local c; c=$(LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')
    [[ -n $c && $c != "(none)" ]] && echo "$c"
}

pick_package() {  # tool -> first package name with an APT candidate
    local p
    for p in ${TOOL_PKGS[$1]}; do
        if [[ -n $(pkg_candidate "$p") ]]; then echo "$p"; return 0; fi
    done
    return 1
}

pkg_origin_is_kali() { grep -q 'kali\.org' <<<"$(LC_ALL=C apt-cache madison "$1" 2>/dev/null)"; }

APT_UPDATED=0
apt_refresh() {
    [[ $APT_UPDATED -eq 1 ]] && return 0
    step "Actualizando la lista de paquetes (apt-get update)"
    if ! as_root apt-get update -qq </dev/null; then
        die "no se pudo actualizar la lista de paquetes" \
            "Kali necesita Internet por su adaptador NAT (en KVM: tras './manager start' en el anfitrión). Prueba: ping -c2 1.1.1.1"
    fi
    APT_UPDATED=1
}

FAILED=()
install_tool() {
    local t=$1 pkg
    if tool_installed "$t"; then ok "$t: ya instalado ($(command -v "${TOOL_CMD[$t]}"))"; return 0; fi
    apt_refresh
    if ! pkg=$(pick_package "$t"); then
        bad "$t: ningún paquete disponible (${TOOL_PKGS[$t]})"
        info "Revisa /etc/apt/sources.list (debe incluir kali-rolling) y ejecuta 'sudo apt update'."
        FAILED+=("$t"); return 1
    fi
    pkg_origin_is_kali "$pkg" || warn "$t: el paquete '$pkg' no procede de los repositorios de Kali"
    info "instalando $t (paquete $pkg $(pkg_candidate "$pkg"))..."
    if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" </dev/null >/dev/null; then
        bad "$t: falló 'apt-get install $pkg'"
        info "Ejecútalo a mano para ver el error: sudo apt-get install $pkg"
        FAILED+=("$t"); return 1
    fi
    hash -r
    if tool_installed "$t"; then ok "$t: instalado y verificado (${TOOL_CMD[$t]})"
    else bad "$t: el paquete '$pkg' se instaló pero no aparece el comando '${TOOL_CMD[$t]}'"; FAILED+=("$t"); return 1; fi
}

update_tool() {
    local t=$1 p pkgs=()
    if ! tool_installed "$t"; then info "$t: no instalado (se omite; usa --install)"; return 0; fi
    for p in ${TOOL_PKGS[$t]}; do pkg_installed "$p" && pkgs+=("$p"); done
    if [[ ${#pkgs[@]} -eq 0 ]]; then warn "$t: instalado fuera de APT; no se actualiza"; return 0; fi
    if as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --only-upgrade "${pkgs[@]}" </dev/null >/dev/null; then
        ok "$t: al día (${pkgs[*]} $(dpkg-query -W -f='${Version}' "${pkgs[0]}"))"
    else
        bad "$t: falló la actualización de ${pkgs[*]}"; FAILED+=("$t")
    fi
}

# ------------------------------------------------------------- commands ---
cmd_list() {
    local id t
    for id in "${MODULES[@]}"; do
        printf '\n%s%s%s (%s) - %s\n' "$C_B" "${MOD_NAME[$id]}" "$C_0" "$id" "${MOD_DESC[$id]}"
        for t in ${MOD_TOOLS[$id]}; do
            if tool_installed "$t"; then ok "$t"; else info "$t: no instalado"; fi
        done
    done
}

cmd_install() {
    local id t
    resolve_modules "$1"
    for id in "${SEL[@]}"; do
        step "Módulo ${MOD_NAME[$id]} ($id)"
        for t in ${MOD_TOOLS[$id]}; do install_tool "$t"; done
    done
}

cmd_update() {
    local id t
    resolve_modules "$1"
    apt_refresh
    for id in "${SEL[@]}"; do
        step "Actualizando ${MOD_NAME[$id]} ($id)"
        for t in ${MOD_TOOLS[$id]}; do update_tool "$t"; done
    done
}

# 0 = open, 1 = refused, 2 = no answer
tcp() {
    timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
    case $? in 0) return 0 ;; 124) return 2 ;; *) return 1 ;; esac
}

cmd_check() {
    local full=$1 id t missing=0 lab_if p code nat_if
    step "Sistema"
    if grep -qx 'ID=kali' /etc/os-release 2>/dev/null; then ok "$(. /etc/os-release; echo "$PRETTY_NAME")"
    else warn "no parece Kali Linux ($(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-desconocido}"))"; fi
    if grep -rqs 'kali-rolling' /etc/apt/sources.list /etc/apt/sources.list.d/; then ok "repositorio kali-rolling configurado"
    else warn "no se encuentra el repositorio kali-rolling en /etc/apt/sources.list*"; fi

    step "Herramientas"
    for id in "${MODULES[@]}"; do
        for t in ${MOD_TOOLS[$id]}; do
            if tool_installed "$t"; then ok "$id/$t"; else bad "$id/$t no instalado"; missing=$((missing + 1)); fi
        done
    done
    [[ $missing -gt 0 ]] && FAILED+=("herramientas: $missing sin instalar (kali/install.sh --install all)")

    step "Red"
    lab_if=$(ip -4 -o addr | awk -v p="${HOST%.*}." 'index($4, p) == 1 {print $2; exit}')
    if [[ -n $lab_if ]]; then ok "adaptador de laboratorio: $lab_if ($(ip -4 -o addr show dev "$lab_if" | awk '{print $4; exit}'))"
    else bad "ningún adaptador con IP en ${HOST%.*}.0/24"; info "Conecta el adaptador 1 a la red de laboratorio (pentestlab / vboxnetN)."; FAILED+=("red de laboratorio"); fi
    if [[ -n $lab_if && -n $(ip -4 route show default dev "$lab_if") ]]; then
        bad "la red de laboratorio da la ruta por defecto: Internet no irá por el NAT"
        info "En Kali: nmcli connection modify <conexión de $lab_if> ipv4.never-default yes ipv4.ignore-auto-dns yes"
        FAILED+=("ruta por defecto")
    fi
    nat_if=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}' | grep -vx "${lab_if:-none}" | head -1)
    if [[ -n $nat_if ]] && curl -s -o /dev/null -m 8 https://http.kali.org/; then ok "Internet por el adaptador NAT ($nat_if)"
    else warn "sin Internet por el adaptador NAT (no impide usar el laboratorio; sí instalar herramientas)"; fi

    step "Conectividad con el anfitrión ($HOST)"
    if ping -c1 -W2 "$HOST" >/dev/null 2>&1; then ok "ping al anfitrión"; else bad "sin ping al anfitrión"; FAILED+=("ping"); fi
    for p in "${PORTS[@]}"; do
        if tcp "$HOST" "$p"; then
            code=$(curl -sk -o /dev/null -m 10 -w '%{http_code}' "$([[ $p == 8443 ]] && echo https || echo http)://$HOST:$p/")
            ok "$HOST:$p (HTTP $code)"
        else
            bad "$HOST:$p no accesible"; FAILED+=("puerto $p")
        fi
    done
    [[ " ${FAILED[*]} " == *" puerto "* ]] && info "¿Están arrancados los laboratorios? En el anfitrión: ./manager status"

    if [[ $full -eq 1 ]]; then
        step "Prueba de aislamiento completa (kali-probe.sh)"
        if [[ -f $PROBE ]]; then bash "$PROBE" --host "$HOST" || FAILED+=("kali-probe.sh")
        else warn "no se encuentra $PROBE (clona el repositorio completo para usarlo)"; fi
    fi
}

summary() {
    echo
    if [[ ${#FAILED[@]} -eq 0 ]]; then printf '%sTodo correcto.%s\n' "$C_G" "$C_0"; return 0; fi
    local f list=""
    for f in "${FAILED[@]}"; do list+="${list:+; }$f"; done
    printf '%sCon problemas:%s %s\n' "$C_R" "$C_0" "$list"
    return 1
}

# ----------------------------------------------------------------- menu ---
menu() {
    local choice sel i
    while true; do
        printf '\n%sKit de herramientas de Kali - laboratorio de pentesting web%s\n' "$C_B" "$C_0"
        i=1
        for id in "${MODULES[@]}"; do
            local n=0 tot=0
            for t in ${MOD_TOOLS[$id]}; do tot=$((tot + 1)); tool_installed "$t" && n=$((n + 1)); done
            printf '  %d) %-30s %d/%d instaladas\n' "$i" "${MOD_NAME[$id]}" "$n" "$tot"
            i=$((i + 1))
        done
        echo "  a) Instalar todos los módulos"
        echo "  u) Actualizar las herramientas instaladas"
        echo "  c) Comprobar preparación y conectividad"
        echo "  l) Listar herramientas"
        echo "  q) Salir"
        read -r -p "Opción (números separados por comas para instalar módulos): " choice || return 0
        FAILED=()
        case $choice in
            q|Q|"") return 0 ;;
            a|A) cmd_install all; summary ;;
            u|U) cmd_update all; summary ;;
            c|C) cmd_check 0; summary ;;
            l|L) cmd_list ;;
            *)
                sel=()
                IFS=',' read -ra nums <<<"$choice"
                for i in "${nums[@]}"; do
                    i=${i//[[:space:]]/}
                    if [[ $i =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#MODULES[@]} )); then sel+=("${MODULES[$((i - 1))]}")
                    else warn "opción no válida: '$i'"; sel=(); break; fi
                done
                [[ ${#sel[@]} -gt 0 ]] && { cmd_install "$(IFS=,; echo "${sel[*]}")"; summary; } ;;
        esac
    done
}

# ----------------------------------------------------------------- main ---
ACTION=""; ARG=""; FULL=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --list) ACTION=list; shift ;;
        --install) ACTION=install; ARG=${2:-}; [[ -n $ARG ]] || usage; shift 2 ;;
        --update) ACTION=update; if [[ -n ${2:-} && $2 != --* ]]; then ARG=$2; shift 2; else ARG=all; shift; fi ;;
        --check) ACTION=check; shift ;;
        --full) FULL=1; shift ;;
        --host) HOST=${2:-}; [[ $HOST =~ ^[0-9]+(\.[0-9]+){3}$ ]] || die "IP no válida: '$HOST'" "" 2; shift 2 ;;
        --ports) IFS=',' read -ra PORTS <<<"${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) usage ;;
    esac
done

command -v apt-get >/dev/null || die "este kit es para Kali Linux (se necesita APT)"
load_modules

case $ACTION in
    list) cmd_list ;;
    install) cmd_install "$ARG"; summary ;;
    update) cmd_update "$ARG"; summary ;;
    check) cmd_check "$FULL"; summary ;;
    "")
        [[ -t 0 ]] || usage
        menu ;;
esac
