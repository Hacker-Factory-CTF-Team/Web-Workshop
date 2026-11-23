#!/usr/bin/env bash
# Linux installer for the pentesting lab (Docker Engine + VirtualBox or KVM/QEMU).
#
#   scripts/linux/install.sh                      # guided: detect, show plan, run selected phases
#   scripts/linux/install.sh --phase detect       # one phase only
#   scripts/linux/install.sh --phase network --hypervisor kvm --ip 192.168.157.1
#
# Phases: detect deps network firewall images validate uninstall
# Every change is reversible with --phase uninstall and is limited to objects
# created by this installer (recorded in state/installer.json).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../common/lib.sh
source "$HERE/../common/lib.sh"
ROOT=$(repo_root)
MANAGER="$ROOT/manager"
RECORD="$ROOT/state/installer.json"
FW_SRC="$HERE/pentestlab-fw.sh"
FW_DST=/usr/local/sbin/pentestlab-fw

PHASE=""; HV=""; LAB_IP=""; PREFIX=24
usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    echo "Opciones: --phase FASE  --hypervisor virtualbox|kvm  --ip IP  --prefix N  --yes"
    exit 2
}
while [[ $# -gt 0 ]]; do
    case $1 in
        --phase) PHASE=${2:-}; shift 2 ;;
        --hypervisor) HV=${2:-}; shift 2 ;;
        --ip) LAB_IP=${2:-}; shift 2 ;;
        --prefix) PREFIX=${2:-}; shift 2 ;;
        --yes) export ASSUME_YES=1; shift ;;  # read by confirm() in lib.sh
        -h|--help) usage ;;
        *) usage ;;
    esac
done

[[ $(uname -s) == Linux ]] || die "este instalador es para Linux; en Windows usa scripts\\windows\\install.ps1"
# Run as the normal user: privileged steps use sudo internally. Under sudo the
# sudoers rule would name root and config/state files would become root-owned.
[[ $EUID -eq 0 && -n ${SUDO_USER:-} ]] && die "no ejecutes el instalador con sudo" \
    "Ejecútalo como tu usuario: scripts/linux/install.sh (pedirá sudo solo cuando haga falta)." 2
grep -qi microsoft /proc/version 2>/dev/null && die "no ejecutes el instalador dentro de WSL" "En Windows usa scripts\\windows\\install.ps1 desde PowerShell."

record_set() {  # key value
    mkdir -p "$ROOT/state"
    python3 - "$RECORD" "$1" "$2" <<'PY'
import json, sys, os
path, key, val = sys.argv[1:4]
data = json.load(open(path)) if os.path.exists(path) else {}
data[key] = val
json.dump(data, open(path, "w"), indent=2)
PY
}
record_get() { [[ -f $RECORD ]] && python3 -c "import json,sys; print(json.load(open('$RECORD')).get('$1',''))" || true; }

netmask_of() { python3 -c "import ipaddress; print(ipaddress.ip_network('0.0.0.0/$1').netmask)"; }
nth_host() { python3 -c "import ipaddress; print(list(ipaddress.ip_interface('$1/$2').network.hosts())[$3])"; }
subnet_conflicts() {  # ip prefix [own_iface] -> prints conflicting "iface addr"
    python3 - "$1" "$2" "${3:-}" <<'PY'
import ipaddress, json, subprocess, sys
ip, prefix, own = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lab = ipaddress.ip_interface(f"{ip}/{prefix}").network
for i in json.loads(subprocess.run(["ip", "-j", "addr"], capture_output=True, text=True).stdout):
    if i["ifname"] == own:
        continue
    for a in i.get("addr_info", []):
        if a.get("family") == "inet":
            n = ipaddress.ip_interface(f"{a['local']}/{a['prefixlen']}").network
            if n.overlaps(lab) and not n.network_address.is_loopback:
                print(f"{i['ifname']} {a['local']}/{a['prefixlen']}")
PY
}

# ---------------------------------------------------------------- detect ---
phase_detect() {
    log_step "Sistema"
    # shellcheck disable=SC1091
    log_info "$(. /etc/os-release; echo "$PRETTY_NAME") - familia: $(distro_family) - kernel $(uname -r)"
    log_step "Contenedores"
    if have docker; then
        if docker info >/dev/null 2>&1; then
            log_ok "Docker Engine $(docker version --format '{{.Server.Version}}') ($(docker info --format '{{.OperatingSystem}}'))"
            local fw; fw=$(docker info --format '{{if .FirewallBackend}}{{.FirewallBackend.Driver}}{{end}}' 2>/dev/null || true)
            log_info "backend de firewall de Docker: ${fw:-desconocido (anterior a 28.x)}"
            docker info --format '{{.SecurityOptions}}' | grep -q rootless && log_warn "Docker rootless no está soportado"
        else
            log_warn "docker instalado pero el daemon no responde o tu usuario no tiene permiso (grupo docker)"
        fi
        docker compose version --short >/dev/null 2>&1 && log_ok "Docker Compose $(docker compose version --short)" || log_warn "falta Docker Compose v2"
    else
        log_warn "Docker no está instalado"
    fi
    id -nG | grep -qw docker && log_ok "usuario en el grupo docker" || log_warn "tu usuario no está en el grupo docker (o se usará sudo)"
    log_step "Hipervisores"
    have VBoxManage && log_ok "VirtualBox $(VBoxManage --version 2>/dev/null)" || log_info "VirtualBox: no detectado"
    if have virsh; then
        log_ok "libvirt $(virsh --version 2>/dev/null)"
        systemctl is-active --quiet libvirtd 2>/dev/null || systemctl is-active --quiet virtqemud 2>/dev/null \
            && log_ok "servicio libvirt activo" || log_warn "libvirtd/virtqemud no está activo"
        [[ -e /dev/kvm ]] && log_ok "/dev/kvm disponible" || log_warn "/dev/kvm no existe (¿virtualización desactivada en la BIOS?)"
    else
        log_info "KVM/libvirt: no detectado"
    fi
    log_step "Redes existentes relacionadas"
    ip -br -4 addr | grep -E '^(vboxnet|virbr|plab)' | sed 's/^/  /' || log_info "ninguna interfaz vboxnet*/virbr*"
    have VBoxManage && VBoxManage list hostonlyifs 2>/dev/null | grep -E '^(Name|IPAddress|NetworkMask):' | paste - - - | sed 's/^/  vbox: /' || true
    have virsh && virsh -c qemu:///system net-list --all 2>/dev/null | sed -n '3,$p' | sed '/^$/d;s/^/  libvirt:/' || true
    log_step "Recursos"
    log_info "CPU: $(nproc)  RAM total: $(free -h | awk '/^Mem/{print $2}')  disponible: $(free -h | awk '/^Mem/{print $7}')"
    log_info "Espacio libre para Docker: $(df -h --output=avail "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /)" 2>/dev/null | tail -1 | tr -d ' ') (las imágenes ocupan ~5 GB)"
    log_step "Herramientas auxiliares"
    for t in python3 ip ss iptables curl; do have "$t" && log_ok "$t" || log_warn "falta $t"; done
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null || log_warn "se necesita Python >= 3.10"
    log_step "Configuración actual del laboratorio"
    log_info "plataforma=$(lab_config_get platform) ip=$(lab_config_get ip)/$(lab_config_get prefix) interfaz=$(lab_config_get iface)"
}

# ------------------------------------------------------------------ deps ---
pkg_cmd() {  # prints the install command for the distro family
    case $(distro_family) in
        debian) echo "sudo apt-get update && sudo apt-get install -y $*" ;;
        fedora) echo "sudo dnf install -y $*" ;;
        arch) echo "sudo pacman -S --needed $*" ;;
        suse) echo "sudo zypper install -y $*" ;;
        *) echo "(instala con el gestor de paquetes de tu distribución) $*" ;;
    esac
}

phase_deps() {
    local missing=() fam; fam=$(distro_family)
    have python3 || missing+=(python3)
    have ip || missing+=(iproute2)
    have ss || missing+=(iproute2)
    have iptables || missing+=(iptables)
    have curl || missing+=(curl)
    if [[ ${#missing[@]} -gt 0 ]]; then
        local pkgs; pkgs=$(printf '%s\n' "${missing[@]}" | sort -u | tr '\n' ' ')
        [[ $fam == fedora || $fam == suse ]] && pkgs=${pkgs//iproute2/iproute}
        log_warn "faltan paquetes básicos: $pkgs"
        local c; c=$(pkg_cmd "$pkgs")
        if [[ $fam != unknown ]] && confirm "¿Instalarlos ahora con: $c ?" y; then
            eval "$c"
        else
            log_info "Instálalos manualmente: $c"
        fi
    else
        log_ok "paquetes básicos presentes"
    fi
    if ! have docker || ! docker compose version >/dev/null 2>&1; then
        log_warn "Docker Engine / Compose no están instalados. No se instalan automáticamente."
        case $fam in
            debian) log_info "Sigue https://docs.docker.com/engine/install/ (Debian/Ubuntu) o: $(pkg_cmd docker.io docker-compose-v2)" ;;
            fedora) log_info "Sigue https://docs.docker.com/engine/install/fedora/ (repositorio docker-ce)" ;;
            arch) log_info "$(pkg_cmd docker docker-compose)" ;;
            suse) log_info "$(pkg_cmd docker docker-compose)" ;;
            *) log_info "https://docs.docker.com/engine/install/" ;;
        esac
        log_info "Después: sudo systemctl enable --now docker && sudo usermod -aG docker \$USER (cierra sesión y vuelve a entrar)"
    fi
    if have docker && docker info >/dev/null 2>&1; then
        local v; v=$(docker version --format '{{.Server.Version}}')
        [[ ${v%%.*} -ge 28 ]] && log_ok "Docker $v (>= 28)" || log_fail "Docker $v < 28: actualízalo antes de continuar"
    fi
    if ! have VBoxManage && ! have virsh; then
        log_warn "no hay hipervisor. Instala VirtualBox (docs/installation/virtualbox.md) o KVM/libvirt (docs/installation/kvm.md)."
        log_info "KVM: $(pkg_cmd "$( [[ $fam == debian ]] && echo 'qemu-system-x86 libvirt-daemon-system virt-manager' || echo 'qemu-full libvirt virt-manager dnsmasq')")"
    fi
}

# --------------------------------------------------------------- network ---
pick_hypervisor() {
    [[ -n $HV ]] && return
    local opts=()
    have VBoxManage && opts+=(virtualbox)
    have virsh && opts+=(kvm)
    [[ ${#opts[@]} -eq 0 ]] && die "no se detecta VirtualBox ni libvirt" "Instala uno (fase deps)."
    if [[ ${#opts[@]} -eq 1 ]]; then HV=${opts[0]}; return; fi
    [[ -t 0 ]] || die "hay varios hipervisores; indica --hypervisor virtualbox|kvm"
    read -r -p "Hipervisor a usar [virtualbox/kvm]: " HV
}

check_ip_free() {  # ip prefix own_iface
    local err; err=$(PYTHONPATH="$ROOT/src" python3 -c "from pentestlab.hostenv import validate_lab_ip; print(validate_lab_ip('$1') or '')")
    [[ -z $err ]] || die "$err"
    local c; c=$(subnet_conflicts "$1" "$2" "${3:-}")
    if [[ -n $c ]]; then
        die "la subred $1/$2 se solapa con interfaces existentes:"$'\n'"$c" \
            "Elige otra subred privada libre con --ip (p. ej. 192.168.58.1 para VirtualBox o 192.168.158.1 para KVM)."
    fi
}

network_virtualbox() {
    have VBoxManage || die "VirtualBox no está instalado"
    LAB_IP=${LAB_IP:-192.168.57.1}
    local mask; mask=$(netmask_of "$PREFIX")
    # Existing host-only interface already holding the lab IP? Reuse it, never modify others.
    local existing
    existing=$(VBoxManage list hostonlyifs | awk -v ip="$LAB_IP" '/^Name:/{n=$2} /^IPAddress:/{if($2==ip) print n}')
    if [[ -n $existing ]]; then
        log_ok "se reutiliza la interfaz Host-only existente $existing ($LAB_IP)"
        check_ip_free "$LAB_IP" "$PREFIX" "$existing"
    else
        check_ip_free "$LAB_IP" "$PREFIX" ""
        # VirtualBox >= 6.1.28 only allows 192.168.56.0/21 unless /etc/vbox/networks.conf says otherwise.
        if ! python3 -c "import ipaddress,sys; sys.exit(0 if ipaddress.ip_address('$LAB_IP') in ipaddress.ip_network('192.168.56.0/21') else 1)"; then
            if ! grep -qs "$(echo "$LAB_IP" | cut -d. -f1-3)" /etc/vbox/networks.conf; then
                log_warn "VirtualBox solo permite por defecto 192.168.56.0/21 para Host-only."
                log_info "Añade (como root) a /etc/vbox/networks.conf la línea:  * ${LAB_IP%.*}.0/$PREFIX"
                die "rango Host-only no permitido por VirtualBox" "Edita /etc/vbox/networks.conf o usa una IP en 192.168.56.0/21."
            fi
        fi
        confirm "Se creará una interfaz Host-only nueva con IP $LAB_IP/$PREFIX y DHCP. ¿Continuar?" y || die "cancelado" "" 5
        local out; out=$(VBoxManage hostonlyif create 2>&1) || die "no se pudo crear la interfaz: $out"
        existing=$(sed -n "s/.*Interface '\([^']*\)'.*/\1/p" <<<"$out")
        [[ -n $existing ]] || die "no se pudo identificar la interfaz creada: $out"
        VBoxManage hostonlyif ipconfig "$existing" --ip "$LAB_IP" --netmask "$mask"
        record_set vbox_hostonlyif "$existing"
        log_ok "creada $existing con $LAB_IP/$PREFIX"
    fi
    # DHCP for Kali on the lab network (server .2, pool .100-.199)
    local srv lo hi
    srv=$(nth_host "$LAB_IP" "$PREFIX" 1); lo=$(nth_host "$LAB_IP" "$PREFIX" 99); hi=$(nth_host "$LAB_IP" "$PREFIX" 198)
    if grep -q "HostInterfaceNetworking-$existing" <<<"$(VBoxManage list dhcpservers)"; then
        log_ok "servidor DHCP de VirtualBox ya configurado para $existing (no se modifica)"
    else
        # No router (3) / DNS (6) option: Kali uses its NAT adapter for Internet.
        # NOT TESTED on real VirtualBox (see docs/installation/virtualbox.md).
        VBoxManage dhcpserver add --interface="$existing" --server-ip="$srv" --netmask="$mask" \
            --lower-ip="$lo" --upper-ip="$hi" --suppress-opt=3 --suppress-opt=6 --enable
        record_set vbox_dhcp "$existing"
        log_ok "DHCP activado en $existing: $lo - $hi"
    fi
    ip link show "$existing" >/dev/null 2>&1 || log_warn "$existing aún no aparece en el sistema; aparecerá al usar VirtualBox"
    # VirtualBox NAT runs in userspace (no host bridge): no --nat-interface.
    "$MANAGER" config set-network --platform linux-virtualbox --ip "$LAB_IP" --prefix "$PREFIX" --interface "$existing" --nat-interface ""
    log_info "Kali: adaptador 1 'Adaptador solo-anfitrión' -> $existing y adaptador 2 'NAT' (docs/installation/virtualbox.md)."
}

kvm_lab_network_xml() {  # name bridge ip mask lo hi
    # forward mode 'route' (no NAT): libvirt's 'isolated' mode rejects all
    # forwarded traffic, including Kali -> published Docker ports (DNAT).
    # pentestlab-fw confines the bridge so Kali can only reach lab edges.
    # The empty DHCP options 3 (router) and 6 (DNS) stop dnsmasq from
    # announcing a gateway/DNS: Kali must route Internet traffic through its
    # NAT NIC, never through the lab network.
    cat <<EOF
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
  <name>$1</name>
  <forward mode='route'/>
  <bridge name='$2' stp='on' delay='0'/>
  <dns enable='no'/>
  <ip address='$3' netmask='$4'>
    <dhcp>
      <range start='$5' end='$6'/>
    </dhcp>
  </ip>
  <dnsmasq:options>
    <dnsmasq:option value='dhcp-option=3'/>
    <dnsmasq:option value='dhcp-option=6'/>
  </dnsmasq:options>
</network>
EOF
}

# Kali's second NIC (Internet for updates/tools, a workshop requirement): libvirt's NAT
# network 'default'. Its bridge is passed to pentestlab-fw (--nat-iface),
# because Docker's FORWARD policy (DROP) would otherwise break its NAT.
kvm_nat_network() {
    local V=(env LC_ALL=C virsh -c qemu:///system) nat=default br
    if ! as_root "${V[@]}" net-info "$nat" >/dev/null 2>&1; then
        log_warn "no existe la red NAT '$nat' de libvirt: Kali no tendrá Internet por su segunda NIC."
        log_info "Créala con virt-manager (Editar > Detalles de la conexión > Redes virtuales) y repite esta fase."
        "$MANAGER" config set-network --nat-interface ""
        return
    fi
    br=$(as_root "${V[@]}" net-info "$nat" | awk '/^Bridge:/{print $2}')
    [[ -n $br ]] || die "no se pudo obtener el bridge de la red '$nat'"
    if ! grep -qE '^Active:.*yes' <<<"$(as_root "${V[@]}" net-info "$nat")"; then
        confirm "La red NAT '$nat' ($br) para la segunda NIC de Kali está parada. ¿Iniciarla?" y && as_root "${V[@]}" net-start "$nat"
    fi
    if ! grep -qE '^Autostart:.*yes' <<<"$(as_root "${V[@]}" net-info "$nat")"; then
        confirm "¿Iniciar la red '$nat' automáticamente al arrancar el sistema?" y && as_root "${V[@]}" net-autostart "$nat"
    fi
    "$MANAGER" config set-network --nat-interface "$br"
    log_ok "NIC NAT de Kali: red libvirt '$nat' (bridge $br), gestionada por pentestlab-fw"
}

network_kvm() {
    have virsh || die "libvirt (virsh) no está instalado"
    LAB_IP=${LAB_IP:-192.168.157.1}
    local name=pentestlab bridge=virbr-plab mask lo hi xml
    mask=$(netmask_of "$PREFIX"); lo=$(nth_host "$LAB_IP" "$PREFIX" 99); hi=$(nth_host "$LAB_IP" "$PREFIX" 198)
    local V=(env LC_ALL=C virsh -c qemu:///system)
    if as_root "${V[@]}" net-info "$name" >/dev/null 2>&1; then
        grep -q "address='$LAB_IP'" <<<"$(as_root "${V[@]}" net-dumpxml "$name")" \
            || die "la red '$name' existe con otra IP" "Revísala con 'virsh -c qemu:///system net-dumpxml $name' o usa esa IP con --ip."
        if grep -q "dhcp-option=3" <<<"$(as_root "${V[@]}" net-dumpxml "$name")"; then
            log_ok "la red libvirt '$name' ya existe y está al día (no se modifica)"
        elif [[ -n $(record_get libvirt_network) ]]; then
            # Created by an older version of this installer: it announces a gateway.
            log_warn "la red '$name' anuncia una pasarela por DHCP: Kali enviaría su tráfico de Internet a la red de laboratorio."
            log_info "Hay que redefinirla. Apaga antes la VM de Kali: sus NIC en '$name' se desconectan."
            confirm "¿Redefinir la red '$name' ahora?" y || die "cancelado" "" 5
            as_root "${V[@]}" net-destroy "$name" >/dev/null 2>&1 || true
            as_root "${V[@]}" net-undefine "$name"
            xml=$(mktemp); kvm_lab_network_xml "$name" "$bridge" "$LAB_IP" "$mask" "$lo" "$hi" >"$xml"
            as_root "${V[@]}" net-define "$xml"; rm -f "$xml"
            as_root "${V[@]}" net-autostart "$name"
            log_ok "red libvirt '$name' redefinida"
        else
            log_warn "la red '$name' no la creó este instalador y anuncia una pasarela por DHCP; no se modifica."
            log_info "En Kali: nmcli connection modify <conexión de laboratorio> ipv4.never-default yes ipv4.ignore-auto-dns yes"
        fi
    else
        check_ip_free "$LAB_IP" "$PREFIX" ""
        confirm "Se creará la red libvirt '$name' ($bridge, $LAB_IP/$PREFIX, DHCP sin pasarela, sin NAT). ¿Continuar?" y || die "cancelado" "" 5
        xml=$(mktemp); kvm_lab_network_xml "$name" "$bridge" "$LAB_IP" "$mask" "$lo" "$hi" >"$xml"
        as_root "${V[@]}" net-define "$xml"; rm -f "$xml"
        record_set libvirt_network "$name"
        confirm "¿Iniciar la red automáticamente al arrancar el sistema?" y && as_root "${V[@]}" net-autostart "$name"
        log_ok "red libvirt '$name' definida"
    fi
    grep -qE '^Active:.*yes' <<<"$(as_root "${V[@]}" net-info "$name")" || as_root "${V[@]}" net-start "$name"
    "$MANAGER" config set-network --platform linux-kvm --ip "$LAB_IP" --prefix "$PREFIX" --interface "$bridge"
    kvm_nat_network
    log_info "Kali necesita dos NIC: la red '$name' (laboratorio) y la red 'default' (NAT). Ver docs/installation/kvm.md."
}

phase_network() {
    pick_hypervisor
    case $HV in
        virtualbox) network_virtualbox ;;
        kvm) network_kvm ;;
        *) die "hipervisor no soportado: $HV" ;;
    esac
}

# -------------------------------------------------------------- firewall ---
phase_firewall() {
    local ip iface nat fwargs; ip=$(lab_config_get ip); iface=$(lab_config_get iface); nat=$(lab_config_get nat)
    [[ -n $ip && -n $iface ]] || die "primero configura la red (fase network)"
    fwargs=(--ip "$ip" --iface "$iface"); [[ -n $nat ]] && fwargs+=(--nat-iface "$nat")
    log_step "Instalando $FW_DST (copia root:root de scripts/linux/pentestlab-fw.sh)"
    log_info "Solo crea las cadenas PLAB-FWD / PLAB-IN / PLAB-IN6; no toca otras reglas. Detalle: docs/networking/firewall-linux.md"
    confirm "¿Continuar (requiere sudo)?" y || die "cancelado" "" 5
    as_root install -m 0755 -o root -g root "$FW_SRC" "$FW_DST"
    record_set firewall_helper "$FW_DST"
    # Optional: let ./manager verify/apply the lab rules without a password prompt.
    # Scope: only this root-owned helper and only its verify/apply sub-commands.
    if [[ ${PLAB_SUDOERS:-ask} != no ]] && [[ -d /etc/sudoers.d ]] && \
       { [[ ${PLAB_SUDOERS:-} == yes ]] || confirm "¿Permitir que tu usuario ejecute 'pentestlab-fw verify/apply' sin contraseña (sudoers acotado)?" n; }; then
        local tmp; tmp=$(mktemp)
        printf '%s ALL=(root) NOPASSWD: %s verify *, %s apply *\n' "$(id -un)" "$FW_DST" "$FW_DST" >"$tmp"
        if as_root visudo -cf "$tmp" >/dev/null; then
            as_root install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/pentestlab-fw
            record_set sudoers /etc/sudoers.d/pentestlab-fw
            log_ok "sudoers acotado instalado en /etc/sudoers.d/pentestlab-fw"
        else
            log_warn "visudo rechazó la regla; no se instala"
        fi
        rm -f "$tmp"
    fi
    if docker info >/dev/null 2>&1 && grep -qw "inet $ip" <<<"$(ip -4 -o addr show dev "$iface" 2>/dev/null)"; then
        as_root "$FW_DST" apply "${fwargs[@]}"
        as_root "$FW_DST" verify "${fwargs[@]}" && log_ok "reglas verificadas"
    else
        log_warn "la interfaz $iface ($ip) o Docker no están disponibles ahora; ./manager aplicará las reglas al iniciar."
    fi
}

# ----------------------------------------------------------- images/valid ---
phase_images() { "$MANAGER" install all; }
phase_validate() {
    "$MANAGER" diagnose || true
    log_info "Inicia un laboratorio y ejecuta './manager network-check' y 'sudo tests/network/linux-netns.sh test'."
}

# ------------------------------------------------------------- uninstall ---
phase_uninstall() {
    log_step "Desinstalación (solo elementos creados por este instalador)"
    log_info "Los laboratorios se detienen pero sus volúmenes de datos no se borran (usa ./manager reset para eso)."
    confirm "¿Continuar?" n || die "cancelado" "" 5
    "$MANAGER" stop all || true
    if [[ -x $FW_DST ]]; then
        as_root "$FW_DST" remove || true
        as_root rm -f "$FW_DST"
        log_ok "pentestlab-fw eliminado"
    fi
    [[ -n $(record_get sudoers) ]] && as_root rm -f /etc/sudoers.d/pentestlab-fw && log_ok "regla sudoers eliminada"
    local n; n=$(record_get libvirt_network)
    if [[ -n $n ]]; then
        as_root virsh -c qemu:///system net-destroy "$n" 2>/dev/null || true
        as_root virsh -c qemu:///system net-undefine "$n" && log_ok "red libvirt $n eliminada"
    fi
    n=$(record_get vbox_dhcp); [[ -n $n ]] && VBoxManage dhcpserver remove --interface="$n" 2>/dev/null && log_ok "DHCP de $n eliminado"
    n=$(record_get vbox_hostonlyif); [[ -n $n ]] && VBoxManage hostonlyif remove "$n" && log_ok "interfaz $n eliminada"
    rm -f "$RECORD"
    log_info "Las imágenes Docker se conservan: 'docker image ls' / 'docker image rm' para borrarlas."
}

# ------------------------------------------------------------------ main ---
run_phase() {
    case $1 in
        detect) phase_detect ;;
        deps) phase_deps ;;
        network) phase_network ;;
        firewall) phase_firewall ;;
        images) phase_images ;;
        validate) phase_validate ;;
        uninstall) phase_uninstall ;;
        *) die "fase desconocida: $1" "Fases: detect deps network firewall images validate uninstall" 2 ;;
    esac
}

if [[ -n $PHASE ]]; then
    run_phase "$PHASE"
    exit 0
fi

log_step "Instalador del laboratorio (Linux). Fase 1: detección (solo lectura)"
phase_detect
echo
log_step "Fases disponibles"
cat <<'EOF'
  deps      comprobar dependencias y mostrar/instalar lo que falta (con confirmación)
  network   crear o reutilizar la red Host-only (VirtualBox) o la red libvirt (KVM)
  firewall  instalar y aplicar pentestlab-fw (sudo)
  images    descargar imágenes fijadas y recursos (./manager install)
  validate  diagnóstico final
EOF
for p in deps network firewall images validate; do
    if confirm "¿Ejecutar la fase '$p'?" y; then run_phase "$p"; else log_info "fase '$p' omitida"; fi
done
