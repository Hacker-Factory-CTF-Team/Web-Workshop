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
# ---- opciones específicas de la fase kali-vm -------------------------------
KALI_RECORD="$ROOT/state/kali-vm.json"
KALI_CHECK=0; KALI_READY=0; KALI_ADOPT=0; KALI_REMOVE=0
KALI_VDI_ARG=""; KALI_VBOX_ARG=""; KALI_NAME_ARG=""; KALI_IFACE_ARG=""
KALI_MEM_ARG=4096; KALI_CPUS_ARG=4; KALI_VRAM_ARG=128
KALI_URL="https://www.kali.org/get-kali/#kali-virtual-machines"

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    echo "Opciones: --phase FASE  --hypervisor virtualbox|kvm  --ip IP  --prefix N  --yes"
    echo "Fases: detect deps network firewall images validate uninstall kali-vm"
    echo "Opciones kali-vm: --check --ready --vdi RUTA --vbox RUTA --name NOMBRE"
    echo "  --iface NOMBRE --memory MB --cpus N --vram MB --adopt --remove"
    exit 2
}
while [[ $# -gt 0 ]]; do
    case $1 in
        --phase) PHASE=${2:-}; shift 2 ;;
        --hypervisor) HV=${2:-}; shift 2 ;;
        --ip) LAB_IP=${2:-}; shift 2 ;;
        --prefix) PREFIX=${2:-}; shift 2 ;;
        --yes) export ASSUME_YES=1; shift ;;  # read by confirm() in lib.sh
        --check) KALI_CHECK=1; shift ;;
        --ready) KALI_READY=1; shift ;;
        --adopt) KALI_ADOPT=1; shift ;;
        --remove) KALI_REMOVE=1; shift ;;
        --vdi) KALI_VDI_ARG=${2:-}; shift 2 ;;
        --vbox) KALI_VBOX_ARG=${2:-}; shift 2 ;;
        --name) KALI_NAME_ARG=${2:-}; shift 2 ;;
        --iface) KALI_IFACE_ARG=${2:-}; shift 2 ;;
        --memory) KALI_MEM_ARG=${2:-}; shift 2 ;;
        --cpus) KALI_CPUS_ARG=${2:-}; shift 2 ;;
        --vram) KALI_VRAM_ARG=${2:-}; shift 2 ;;
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

# ----------------------------------------------------------------- kali-vm ---
# Estado de la VM de Kali (state/kali-vm.json). Independiente de
# state/installer.json que usa este mismo instalador.
kali_record_get() {  # clave -> valor (falla si no existe)
    [[ -f $KALI_RECORD ]] || return 1
    python3 - "$KALI_RECORD" "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError):
    raise SystemExit(1)
value = data.get(sys.argv[2])
if value is None or value == "" or value is False:
    raise SystemExit(1)
print(value)
PY
}

kali_record_write() {  # completo nombre uuid vdi vbox iface ip creada
    mkdir -p "$ROOT/state" || die "no se pudo crear $ROOT/state"
    R_COMPLETE=$1 R_NAME=$2 R_UUID=$3 R_VDI=$4 R_VBOX=$5 R_IFACE=$6 R_IP=$7 R_CREATED=$8 \
    python3 - "$KALI_RECORD" <<'PY'
import datetime, json, os, sys
data = {
    "complete": os.environ["R_COMPLETE"] == "1",
    "created_by_script": os.environ["R_CREATED"] == "1",
    "name": os.environ["R_NAME"],
    "uuid": os.environ["R_UUID"],
    "vdi": os.environ["R_VDI"],
    "vbox": os.environ["R_VBOX"] or None,
    "hostonly_iface": os.environ["R_IFACE"],
    "lab_ip": os.environ["R_IP"],
    "configured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
}

# ---------------------------------------------------------------------------
# Ayudas de VirtualBox
# ---------------------------------------------------------------------------
vbox_hostonly_table() {  # una línea por interfaz: nombre|ip|estado
    VBoxManage list hostonlyifs 2>/dev/null | awk '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        /^Name:/      { if (n != "") print n "|" ip "|" st; n = trim(substr($0, 6)); ip = ""; st = "" }
        /^IPAddress:/ { ip = trim(substr($0, 11)) }
        /^Status:/    { st = trim(substr($0, 8)) }
        END           { if (n != "") print n "|" ip "|" st }
    '
}

vm_uuid_by_name() {  # nombre -> uuid (vacío si no existe)
    VBoxManage list vms 2>/dev/null | awk -v want="\"$1\"" '$1 == want { gsub(/[{}]/, "", $2); print $2 }'
}

vm_is_running() {
    VBoxManage list runningvms 2>/dev/null | awk -v want="\"$1\"" '$1 == want { found = 1 } END { exit !found }'
}

showvminfo() {
    VBoxManage showvminfo "$1" --machinereadable 2>/dev/null
}

mri_get() {  # clave machinereadable -> valor (con o sin comillas)
    local vmi="$1" k="$2"
    printf '%s\n' "$vmi" | awk -v k="$k" '
        index($0, k "=") == 1 {
            v = substr($0, length(k) + 2)
            gsub(/^"|"$/, "", v)
            print v
            exit
        }'
}

vbox_version() {  # 7.1.6 a partir de "7.1.6r167084"
    local raw
    raw=$(VBoxManage --version 2>/dev/null) || return 1
    printf '%s\n' "${raw%%r*}" | cut -d' ' -f1
}

vbox_name_of() {  # nombre interno del .vbox oficial
    sed -n 's/.*<Machine [^>]*name="\([^"]*\)".*/\1/p' "$1" | head -n1
}

vbox_disk_of() {  # ruta del disco declarada en el .vbox (puede ser relativa)
    sed -n 's/.*<HardDisk [^>]*location="\([^"]*\)".*/\1/p' "$1" | head -n1
}

abs_path() { realpath -m -- "$1" 2>/dev/null || printf '%s\n' "$1"; }

# ---------------------------------------------------------------------------
# localhost-reachable en el .vbox (VirtualBox 7.x)
# ---------------------------------------------------------------------------
# VirtualBox guarda nat-localhostreachable2 off como <NAT/> y <NAT/> se vuelve
# a leer como "true" al recargar, así que el off NO sobrevive por sí solo: hay
# que dejar localhost-reachable="false" escrito a mano en el .vbox. Dos reglas:
#   1) el sed va DESPUÉS de todo VBoxManage modifyvm, porque cada modifyvm
#      reescribe el .vbox completo desde su memoria (y ahí se pierde);
#   2) también antes de crear/importar la máquina, para que nazca con el false.
vbox_settings_path() {  # nombre_vm -> .vbox real que usa VirtualBox (CfgFile=)
    VBoxManage showvminfo "$1" --machinereadable 2>/dev/null \
        | sed -n 's/^CfgFile="\(.*\)"$/\1/p' || true
}

vbox_patch_localhost() {  # [.vbox] -> sed true->false (sin ruta: el .vbox oficial)
    local f dir stem
    if [[ -n ${1:-} ]]; then
        [[ -f $1 ]] || return 0
        vbox_sed_localhost "$1"
        return 0
    fi
    # Sin ruta explícita: el .vbox oficial que nombra el .vdi (mismo nombre).
    [[ -f ${KALI_VDI:-} ]] || return 0
    dir=$(dirname "$KALI_VDI")
    stem=$(basename "$KALI_VDI"); stem=${stem%.*}
    for f in "$dir"/*.vbox; do
        [[ -e $f ]] || continue
        [[ $(basename "$f") == "$stem".* ]] || continue
        vbox_sed_localhost "$f"
    done
}

vbox_sed_localhost() {  # fichero .vbox -> localhost-reachable="false" garantizado
    # (el comando de cambio.txt, más la forma que VirtualBox escribe al aplicar
    #  'off': <NAT/> sin atributo, que se vuelve a leer como true)
    sed -i -E 's/localhost-reachable="true"/localhost-reachable="false"/g' "$1"
    sed -i -E 's|<NAT ?/>|<NAT localhost-reachable="false"/>|g' "$1"
}

fix_nat_localhostreachable() {  # nombre_vm -> off en VirtualBox y false en el .vbox
    local vm_name="$1" vbox_path
    # 1) En VirtualBox (el off se guarda como <NAT/>, que luego vale "true", por
    #    eso hace falta el paso 2). Se prueba con y sin guion y se reintenta
    #    por si VirtualBox reinicia el valor al conectar la NIC.
    VBoxManage modifyvm "$vm_name" --nat-localhostreachable2 off >/dev/null 2>&1 || \
    VBoxManage modifyvm "$vm_name" --natlocalhostreachable2 off >/dev/null 2>&1 || true
    sleep 1
    VBoxManage modifyvm "$vm_name" --nat-localhostreachable2 off >/dev/null 2>&1 || \
    VBoxManage modifyvm "$vm_name" --natlocalhostreachable2 off >/dev/null 2>&1 || true
    # 2) y solo al final, el sed sobre el .vbox real: es el último gesto que
    #    toca VirtualBox, así que el "false" explícito es lo que queda guardado.
    vbox_path=$(vbox_settings_path "$vm_name")
    vbox_patch_localhost "$vbox_path"
}

# Solo lectura: VirtualBox guarda 'off' como <NAT/> y <NAT/> se vuelve a leer
# como "true" al recargar, así que tras apagar la VM el atributo desaparece.
nat_check() {
    local vbx val nfalse
    have VBoxManage || return 0
    [[ -n ${KALI_VM_NAME:-} ]] || return 0
    vbx=$(vbox_settings_path "$KALI_VM_NAME")
    [[ -f $vbx ]] || return 0
    nfalse=$(grep -c 'localhost-reachable="false"' "$vbx" || true)
    val=$(VBoxManage showvminfo "$KALI_VM_NAME" --machinereadable 2>/dev/null \
        | sed -n 's/^localhostReachable="\(.*\)"$/\1/p' | head -n1 || true)
    if (( nfalse > 0 )) && [[ $val == 0 ]]; then
        log_ok "localhost del anfitrión inalcanzable desde Kali (localhost-reachable=false)"
    else
        log_warn "el .vbox ya no tiene localhost-reachable=\"false\": VirtualBox lo reescribe al apagar la VM."
        log_info "  → se repone con: scripts/linux/install.sh --phase kali-vm --ready"
    fi
}

# ---------------------------------------------------------------------------
# Búsqueda del .vdi / .vbox
# ---------------------------------------------------------------------------
find_vdi() {
    KALI_VDI=""
    if [[ -n $KALI_VDI_ARG ]]; then
        [[ -f $KALI_VDI_ARG ]] || die "el .vdi indicado no existe: $KALI_VDI_ARG"
        KALI_VDI=$(abs_path "$KALI_VDI_ARG")
        return 0
    fi
    local found=() f
    while IFS= read -r f; do
        [[ -n $f ]] && found+=("$f")
    done < <(find "$ROOT" -maxdepth 3 -type f -iname '*.vdi' -not -path '*/.git/*' 2>/dev/null | sort)
    case ${#found[@]} in
        0) return 1 ;;
        1) KALI_VDI=$(abs_path "${found[0]}") ;;
        *)
            log_fail "hay varios .vdi en $ROOT:"
            for f in "${found[@]}"; do log_info "  $f"; done
            die "elige uno con --vdi RUTA" "p. ej. scripts/linux/install.sh --phase kali-vm --vdi ${found[0]}"
            ;;
    esac
}

find_vbox() {
    KALI_VBOX=""
    if [[ -n $KALI_VBOX_ARG ]]; then
        [[ -f $KALI_VBOX_ARG ]] || die "el .vbox indicado no existe: $KALI_VBOX_ARG"
        KALI_VBOX=$(abs_path "$KALI_VBOX_ARG")
        return 0
    fi
    # Se usa el .vbox que declare ESTE .vdi, no el que se llame parecido: el
    # oficial se llama '...-1.16.vbox' y referencia '....vdi'. Además, sus
    # discos son rutas relativas: tiene que estar en la misma carpeta.
    local dir f declared cand
    dir=$(dirname "$KALI_VDI")
    for f in "$dir"/*.vbox; do
        [[ -e $f ]] || continue
        declared=$(vbox_disk_of "$f")
        [[ -n $declared ]] || continue
        case $declared in
            /*) cand=$declared ;;
            *)  cand="$dir/$declared" ;;
        esac
        if [[ $(abs_path "$cand") == "$KALI_VDI" ]]; then
            KALI_VBOX=$(abs_path "$f")
            return 0
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Comprobaciones previas (no requieren el .vdi)
# ---------------------------------------------------------------------------
FAILS=0
kali_fail_check() { log_fail "$1"; [[ -n ${2:-} ]] && log_info "  → $2"; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------------------
# Red del laboratorio: comprobar y, si falta, instalarla como el instalador
# ---------------------------------------------------------------------------
network_ok() {
    local iface ip table
    [[ $(lab_config_get platform 2>/dev/null || true) == linux-virtualbox ]] || return 0
    have VBoxManage || return 0
    iface=${KALI_IFACE_ARG:-$(lab_config_get iface 2>/dev/null || true)}
    ip=$(lab_config_get ip 2>/dev/null || true)
    [[ -n $iface && -n $ip ]] || return 1
    table=$(vbox_hostonly_table 2>/dev/null) || return 1
    printf '%s\n' "$table" | awk -F'|' -v n="$iface" -v ip="$ip" \
        '$1 == n && $2 == ip { found = 1 } END { exit !found }' || return 1
    VBoxManage list dhcpservers 2>/dev/null \
        | grep -q "HostInterfaceNetworking-$iface" || return 1
    return 0
}

provision_kali_network() {
    local cfg_iface
    cfg_iface=$(lab_config_get iface 2>/dev/null || true)
    if [[ -n $KALI_IFACE_ARG && $KALI_IFACE_ARG != "$cfg_iface" ]]; then
        die "no se puede crear una interfaz llamada '$KALI_IFACE_ARG'." \
            "Quita --iface o ajusta config/local.json: VirtualBox nombra las interfaces vboxnetN."
    fi
    log_step "Red Host-only del laboratorio"
    log_info "La red del laboratorio (interfaz Host-only + DHCP) no está configurada."
    log_info "Se instalará con el instalador del proyecto; queda registrada y es reversible."
    if [[ ! -t 0 ]]; then
        log_info "  → Ejecuta: scripts/linux/install.sh --phase network --hypervisor virtualbox --yes"
        return 1
    fi
    if ! confirm "¿Crear/reparar ahora la red Host-only?" y; then
        log_info "cancelado: no se ha modificado VirtualBox."
        return 5
    fi
    "$HERE/install.sh" --phase network --hypervisor virtualbox --yes || \
    die "el instalador no pudo crear la red Host-only." \
        "Revisa la salida anterior o repite: scripts/linux/install.sh --phase network --hypervisor virtualbox --yes"
    log_ok "red del laboratorio lista"
}

preflight() {
    log_step "Comprobaciones de la red y de VirtualBox"
    FAILS=0

    if [[ $(uname -s) != Linux ]]; then
        kali_fail_check "este script es para Linux (VirtualBox de escritorio)." \
            "En Windows usa .\\manager.ps1 y la guía docs/installation/windows.md."
        return 1
    fi
    if [[ $EUID -eq 0 ]]; then
        kali_fail_check "no ejecutes este script como root." \
            "VirtualBox es por usuario: la VM se registraría en el perfil de root."
    else
        log_ok "usuario normal (VirtualBox trabajará con tu perfil)"
    fi
    if [[ ! -f $ROOT/src/pentestlab/__init__.py ]]; then
        kali_fail_check "no encuentro src/pentestlab junto a este script." \
            "Deja install.sh en la raíz del repositorio."
        return 1
    fi

    KALI_PLATFORM=$(lab_config_get platform 2>/dev/null) || KALI_PLATFORM=""
    KALI_LAB_IP=$(lab_config_get ip 2>/dev/null) || KALI_LAB_IP=""
    KALI_LAB_IFACE=$(lab_config_get iface 2>/dev/null) || KALI_LAB_IFACE=""
    [[ -n $KALI_IFACE_ARG ]] && KALI_LAB_IFACE=$KALI_IFACE_ARG

    if [[ $KALI_PLATFORM != linux-virtualbox ]]; then
        kali_fail_check "la plataforma configurada es '${KALI_PLATFORM:-ninguna}', no 'linux-virtualbox'." \
            "Ejecuta scripts/linux/install.sh --phase network --hypervisor virtualbox"
    else
        log_ok "plataforma linux-virtualbox (config/local.json)"
    fi

    if ! have VBoxManage; then
        kali_fail_check "VBoxManage no está en PATH: VirtualBox no está instalado o no se detecta." \
            "Instala VirtualBox 7 y vuelve a abrir la terminal."
        return 1
    fi
    if pgrep -x VirtualBox >/dev/null 2>&1; then
        log_warn "la GUI de VirtualBox está abierta: ciérrala para que no revierta los cambios al salir."
    fi
    KALI_VBOX_VER=$(vbox_version 2>/dev/null) || KALI_VBOX_VER=""
    if [[ -n $KALI_VBOX_VER ]]; then
        log_ok "VirtualBox $KALI_VBOX_VER"
    else
        kali_fail_check "no se pudo obtener la versión de VirtualBox."
    fi
    if [[ -n $KALI_VBOX_VER ]] && printf '7.0.2\n%s\n' "$KALI_VBOX_VER" | sort -V -C 2>/dev/null; then
        log_ok "VirtualBox admite --nat-localhostreachable<N> (7.0.2 o superior)"
    else
        kali_fail_check "VirtualBox ${KALI_VBOX_VER:-desconocido} es anterior a 7.0.2." \
            "--nat-localhostreachable2 no existe; actualiza VirtualBox para poder aplicarlo."
    fi

    if [[ -z $KALI_LAB_IFACE || -z $KALI_LAB_IP ]]; then
        kali_fail_check "la red del laboratorio no está configurada (interfaz o IP vacías)." \
            "Ejecuta scripts/linux/install.sh --phase network --hypervisor virtualbox"
        return 1
    fi

    local table line name ip state
    if ! table=$(vbox_hostonly_table); then
        kali_fail_check "no se pudo listar las interfaces Host-only de VirtualBox." \
            "Comprueba el servicio/controlador de VirtualBox (VBoxManage list hostonlyifs)."
        return 1
    fi
    if [[ -z $table ]]; then
        kali_fail_check "VirtualBox no tiene ninguna interfaz Host-only (falta vboxnet0)." \
            "Recréala con: scripts/linux/install.sh --phase network --hypervisor virtualbox"
        log_info "  → Cierra antes la GUI de VirtualBox: al salir puede sobrescribir la configuración."
        return 1
    fi
    line=$(printf '%s\n' "$table" | awk -F'|' -v n="$KALI_LAB_IFACE" '$1 == n { print; exit }')
    if [[ -z $line ]]; then
        kali_fail_check "la interfaz Host-only '$KALI_LAB_IFACE' no existe en VirtualBox." \
            "Vuelve a ejecutar scripts/linux/install.sh --phase network --hypervisor virtualbox"
    else
        name=${line%%|*}; line=${line#*|}; ip=${line%%|*}; state=${line#*|}
        if [[ $ip == "$KALI_LAB_IP" ]]; then
            log_ok "Host-only $name con la IP del laboratorio ($KALI_LAB_IP)"
        else
            kali_fail_check "Host-only $name tiene ${ip:-sin IP}, no $KALI_LAB_IP." \
                "Repite la fase network o ajusta config/local.json."
        fi
        if [[ $state == Up ]]; then
            log_ok "Host-only $name activa"
        else
            log_warn "Host-only $name está en estado '${state:-desconocido}'."
        fi
        if ip -4 -o addr show dev "$name" 2>/dev/null | grep -q "inet $KALI_LAB_IP/"; then
            log_ok "$name presente en el anfitrión con $KALI_LAB_IP"
        else
            log_warn "$name aún no aparece en el anfitrión (VirtualBox la crea al usarla)."
        fi
        if VBoxManage list dhcpservers 2>/dev/null | grep -q "HostInterfaceNetworking-$name"; then
            log_ok "DHCP de VirtualBox activo en $name (Kali recibirá IP .100-.199)"
        else
            log_warn "no hay servidor DHCP de VirtualBox para $name; Kali podría quedarse sin IP."
            log_info "  → Repite la fase network del instalador."
        fi
    fi

    (( FAILS == 0 ))
}

# ---------------------------------------------------------------------------
# Comprobaciones del disco y de la VM
# ---------------------------------------------------------------------------
disk_checks() {
    log_step "Comprobaciones de la imagen y de la VM"
    FAILS=0

    if ! find_vdi; then
        kali_fail_check "no se encuentra ningún .vdi en $ROOT (máx. 3 niveles)." \
            "Descárgalo y descomprímelo ahí, o indícalo con --vdi RUTA"
        return 1
    fi
    log_ok "imagen: $KALI_VDI"
    if [[ ! -r $KALI_VDI ]]; then
        kali_fail_check "el .vdi no se puede leer: $KALI_VDI" "Revisa sus permisos."
    fi
    local size
    size=$(stat -c %s -- "$KALI_VDI" 2>/dev/null || echo 0)
    if [[ ${size:-0} -gt 0 ]]; then
        log_ok "tamaño: $(du -h -- "$KALI_VDI" | cut -f1)"
    else
        kali_fail_check "el .vdi está vacío o no se puede leer."
    fi
    if ! VBoxManage showmediuminfo disk "$KALI_VDI" >/dev/null 2>&1; then
        kali_fail_check "VirtualBox no reconoce $KALI_VDI como un disco válido." \
            "Comprueba que la descompresión terminó bien (7z x kali-linux-*-virtualbox-amd64.7z)."
    else
        local mtype mstate
        mtype=$(VBoxManage showmediuminfo disk "$KALI_VDI" 2>/dev/null | awk -F': *' '/^Type:/{print $2; exit}')
        mstate=$(VBoxManage showmediuminfo disk "$KALI_VDI" 2>/dev/null | awk -F': *' '/^State:/{print $2; exit}')
        if [[ $mstate == inaccessible ]]; then
            kali_fail_check "el .vdi está registrado pero VirtualBox lo ve 'inaccessible'." \
                "Cierra la VM que lo use, comprueba el archivo y desregistra el medio con 'VBoxManage closemedium disk \"$KALI_VDI\"' (sin --delete)."
        elif [[ $mtype == normal* ]]; then
            log_ok "disco VirtualBox normal (base)"
        else
            log_warn "el disco es de tipo '${mtype:-desconocido}', no 'normal': puede depender de otro disco."
        fi
    fi
    local avail_kb
    avail_kb=$(df -Pk -- "$(dirname "$KALI_VDI")" 2>/dev/null | awk 'NR == 2 { print $4 }')
    if [[ -n $avail_kb && $avail_kb -lt 2097152 ]]; then
        log_warn "quedan menos de 2 GiB libres donde está el .vdi; el disco crecerá al usarlo."
    else
        log_ok "espacio libre suficiente donde está el .vdi"
    fi

    # .vbox oficial (opcional): solo si comparte carpeta con el .vdi.
    find_vbox
    if [[ -n $KALI_VBOX && -n $KALI_NAME_ARG ]]; then
        log_info "--name '$KALI_NAME_ARG': se crea la VM con ese nombre y se conecta el .vdi (sin importar el .vbox)."
        KALI_VBOX=""
    fi
    if [[ -n $KALI_VBOX ]]; then
        local declared cand
        declared=$(vbox_disk_of "$KALI_VBOX")
        if [[ -z $declared ]]; then
            kali_fail_check "el .vbox no declara ningún disco (<HardDisk location=...>)."
            KALI_VBOX=""
        else
            case $declared in
                /*) cand=$declared ;;
                *)  cand="$(dirname "$KALI_VBOX")/$declared" ;;
            esac
            if [[ $(abs_path "$cand") == "$KALI_VDI" ]]; then
                log_ok ".vbox oficial: $KALI_VBOX (apunta a este .vdi)"
            else
                kali_fail_check "el .vbox apunta a '$cand', no al .vdi encontrado." \
                    "Usa --vbox con el correcto o deja solo el .vdi (se creará la VM a mano)."
                KALI_VBOX=""
            fi
        fi
    else
        log_info "sin .vbox que importar: se creará la VM y se conectará el .vdi."
    fi

    # Nombre: el del .vbox si se importa; si no, --name o kali-plab.
    if [[ -n $KALI_VBOX ]]; then
        KALI_VM_NAME=$(vbox_name_of "$KALI_VBOX")
        [[ -n $KALI_VM_NAME ]] || kali_fail_check "no se pudo leer el nombre de la máquina del .vbox."
    else
        KALI_VM_NAME=${KALI_NAME_ARG:-kali-plab}
        if ! [[ $KALI_VM_NAME =~ ^[A-Za-z0-9._-]+$ ]]; then
            kali_fail_check "nombre de VM no válido: '$KALI_VM_NAME'." "Usa letras, números, punto, guion o guion bajo."
        fi
    fi

    KALI_EXISTING_UUID=$(vm_uuid_by_name "$KALI_VM_NAME")
    KALI_MACHINE_FOLDER=$(VBoxManage list systemproperties 2>/dev/null \
        | awk -F': *' '/^Default machine folder:/{print $2; exit}')
    if [[ -n $KALI_MACHINE_FOLDER && -z $KALI_EXISTING_UUID && -d "$KALI_MACHINE_FOLDER/$KALI_VM_NAME" ]]; then
        kali_fail_check "queda la carpeta huérfana de una VM anterior: $KALI_MACHINE_FOLDER/$KALI_VM_NAME" \
            "Si no la necesitas: rm -rf \"$KALI_MACHINE_FOLDER/$KALI_VM_NAME\"  (o usa --name OTRO)"
    fi
    kali_recorded_uuid=$(kali_record_get uuid 2>/dev/null) || kali_recorded_uuid=""
    if [[ -n $KALI_EXISTING_UUID ]]; then
        if [[ -n $kali_recorded_uuid && $kali_recorded_uuid == "$KALI_EXISTING_UUID" ]]; then
            log_ok "la VM '$KALI_VM_NAME' ya la registró este script ($KALI_EXISTING_UUID): se reaplica la configuración"
        elif (( KALI_ADOPT > 0 )); then
            if vm_is_running "$KALI_VM_NAME"; then
                kali_fail_check "la VM '$KALI_VM_NAME' está en marcha; apágala antes de reconfigurarla."
            elif showvminfo "$KALI_VM_NAME" | grep -Fq "=\"$KALI_VDI\""; then
                log_ok "se adopta la VM existente '$KALI_VM_NAME': usa este mismo .vdi"
            else
                kali_fail_check "la VM '$KALI_VM_NAME' existe pero no usa $KALI_VDI." \
                    "No se toca: elige otro --name o elimínala tú desde VirtualBox."
            fi
        else
            kali_fail_check "ya existe una VM llamada '$KALI_VM_NAME' y no la creó este script." \
                "Usa --name OTRO, o --adopt si estás seguro de que usa este mismo .vdi."
        fi
    else
        log_ok "no hay ninguna VM registrada con el nombre '$KALI_VM_NAME'"
    fi

    if vm_is_running "$KALI_VM_NAME" 2>/dev/null; then
        kali_fail_check "la VM '$KALI_VM_NAME' está en marcha; apágala antes de cambiar sus adaptadores."
    fi

    if ! [[ $KALI_MEM_ARG =~ ^[0-9]+$ ]] || (( KALI_MEM_ARG < 1024 )); then
        kali_fail_check "--memory debe ser un número de MiB (mínimo 1024)."
    else
        local total_mb
        total_mb=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
        if (( total_mb > 0 && KALI_MEM_ARG > total_mb )); then
            kali_fail_check "la VM pide ${KALI_MEM_ARG} MiB y el anfitrión tiene ${total_mb} MiB."
        else
            log_ok "RAM de la VM: ${KALI_MEM_ARG} MiB"
        fi
    fi
    if ! [[ $KALI_CPUS_ARG =~ ^[0-9]+$ ]] || (( KALI_CPUS_ARG < 1 )); then
        kali_fail_check "--cpus debe ser un número entero (mínimo 1)."
    else
        log_ok "vCPU de la VM: $KALI_CPUS_ARG"
    fi
    if ! [[ $KALI_VRAM_ARG =~ ^[0-9]+$ ]] || (( KALI_VRAM_ARG < 1 || KALI_VRAM_ARG > 128 )); then
        kali_fail_check "--vram debe ser un número de MiB entre 1 y 128."
    else
        log_ok "memoria de vídeo: ${KALI_VRAM_ARG} MiB"
    fi

    (( FAILS == 0 ))
}

plan_summary() {
    log_step "Plan (solo se tocará esta VM)"
    log_info "  VM:            $KALI_VM_NAME"
    if [[ -n $KALI_VBOX ]]; then
        log_info "  Origen:        registrar el .vbox oficial"
        log_info "                 $KALI_VBOX"
    else
        log_info "  Origen:        crear la VM y conectar el .vdi"
    fi
    log_info "  Disco:         $KALI_VDI"
    log_info "  Adaptador 1:   Host-only '$KALI_LAB_IFACE' ($KALI_LAB_IP)"
    log_info "  Adaptador 2:   NAT (Internet para Kali)"
    log_info "  Extra:         --nat-localhostreachable2 off"
    log_info "  RAM / vCPU:    ${KALI_MEM_ARG} MiB / ${KALI_CPUS_ARG}"
    log_info "  Vídeo:         controlador VMSVGA, ${KALI_VRAM_ARG} MiB de VRAM"
    log_info "  Integración:   portapapeles y arrastrar-soltar bidireccionales"
    log_info "  Registro:      $KALI_RECORD"
    log_info "  Deshacer:      scripts/linux/install.sh --phase kali-vm --remove"
}

# ---------------------------------------------------------------------------
# Pausa de descarga: el enlace y el visto bueno del usuario
# ---------------------------------------------------------------------------
download_gate() {
    log_step "Paso de la imagen de Kali"
    log_info "Descarga la imagen oficial para VirtualBox desde:"
    log_info "  $KALI_URL"
    log_info ""
    log_info "Descomprímela (7z x) y deja el .vdi en:"
    log_info "  $ROOT"
    log_info "El script NO descarga nada por ti: espera tu confirmación."
    if (( KALI_READY )); then
        log_ok "continuando: has indicado que la imagen ya está descargada (--ready)"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        die "la pausa de descarga necesita un terminal interactivo." \
            "Ejecútalo en una terminal o usa --ready si el .vdi ya está descargado."
    fi
    # Aquí no vale --yes: la pausa de descarga siempre pide el visto bueno.
    local ans
    read -r -p "¿Ya has descargado y descomprimido la imagen de Kali? (s/N): " ans
    if [[ ${ans,,} =~ ^(s|si|sí|y|yes)$ ]]; then
        return 0
    fi
    log_info "De acuerdo: no se toca VirtualBox."
    log_info "Cuando la tengas, vuelve a ejecutar: scripts/linux/install.sh --phase kali-vm"
    return 5
}

# ---------------------------------------------------------------------------
# Aplicar los cambios en VirtualBox
# ---------------------------------------------------------------------------
apply_vm() {
    log_step "Registro de la VM en VirtualBox"
    local created=0 uuid=""

    # ANTES de crear la máquina: el .vbox oficial queda con
    # localhost-reachable="false" (ver vbox_patch_localhost), de modo que si
    # VirtualBox lo importa la VM ya nace con el localhost del anfitrión
    # inalcanzable desde Kali.
    vbox_patch_localhost "$KALI_VBOX"

    if [[ -n $KALI_EXISTING_UUID ]]; then
        uuid=$KALI_EXISTING_UUID
        log_ok "se reutiliza la VM ya registrada ($uuid)"
    else
        local reg_out=""
        if [[ -n $KALI_VBOX ]]; then
            if reg_out=$(VBoxManage registervm "$KALI_VBOX" 2>&1); then
                created=1
                uuid=$(vm_uuid_by_name "$KALI_VM_NAME")
                log_ok "máquina registrada desde el .vbox oficial"
            else
                log_warn "VirtualBox no pudo importar el .vbox:"
                printf '%s\n' "$reg_out" | sed 's/^/  /'
                log_info "  → se crea la VM desde el .vdi (el arranque es el mismo)."
                KALI_VBOX=""
                if [[ -n $(vm_uuid_by_name "$KALI_VM_NAME") ]]; then
                    kali_record_write 0 "$KALI_VM_NAME" "" "$KALI_VDI" "" "$KALI_LAB_IFACE" "$KALI_LAB_IP" 1
                    die "el .vbox quedó registrado a medias." \
                        "scripts/linux/install.sh --phase kali-vm --remove lo desregistra (el .vdi no se borra)."
                fi
            fi
        fi
        if (( created == 0 )); then
            if ! VBoxManage createvm --name "$KALI_VM_NAME" --ostype Debian_64 --register; then
                die "VirtualBox no pudo crear la VM '$KALI_VM_NAME'." "Revisa 'VBoxManage list vms'."
            fi
            created=1
            uuid=$(vm_uuid_by_name "$KALI_VM_NAME")
            log_ok "máquina creada y registrada (Debian_64)"
            if ! VBoxManage storagectl "$KALI_VM_NAME" --name SATA --add sata --controller IntelAhci \
                    --portcount 1 --bootable on; then
                kali_record_write 0 "$KALI_VM_NAME" "$uuid" "$KALI_VDI" "$KALI_VBOX" "$KALI_LAB_IFACE" "$KALI_LAB_IP" "$created"
                die "no se pudo añadir el controlador SATA." \
                    "scripts/linux/install.sh --phase kali-vm --remove desregistra la VM incompleta."
            fi
            if ! VBoxManage storageattach "$KALI_VM_NAME" --storagectl SATA --port 0 --device 0 \
                    --type hdd --medium "$KALI_VDI"; then
                kali_record_write 0 "$KALI_VM_NAME" "$uuid" "$KALI_VDI" "$KALI_VBOX" "$KALI_LAB_IFACE" "$KALI_LAB_IP" "$created"
                die "no se pudo conectar el .vdi a la VM." \
                    "scripts/linux/install.sh --phase kali-vm --remove desregistra la VM incompleta."
            fi
            log_ok "disco conectado: $KALI_VDI"
        fi
    fi

    [[ -n $uuid ]] || uuid=$(vm_uuid_by_name "$KALI_VM_NAME")
    kali_record_write 0 "$KALI_VM_NAME" "$uuid" "$KALI_VDI" "$KALI_VBOX" "$KALI_LAB_IFACE" "$KALI_LAB_IP" "$created"

    # Adaptadores y arranque. El ajuste NAT va en una llamada aparte: al crear
    # la VM, VirtualBox inicializa el motor NAT al conectar la NIC y puede
    # pisar el valor si se pasa en la misma orden.
    if ! VBoxManage modifyvm "$KALI_VM_NAME" \
            --memory "$KALI_MEM_ARG" --cpus "$KALI_CPUS_ARG" \
            --graphicscontroller vmsvga --vram "$KALI_VRAM_ARG" \
            --clipboard-mode bidirectional --draganddrop bidirectional \
            --boot1 disk --boot2 dvd --boot3 none --boot4 none \
            --nic1 hostonly --hostonlyadapter1 "$KALI_LAB_IFACE" --cableconnected1 on \
            --nic2 nat --cableconnected2 on; then
        die "la VM existe, pero VirtualBox rechazó la configuración de red/RAM." \
            "scripts/linux/install.sh --phase kali-vm --remove la desregistra (el .vdi no se borra)."
    fi
    log_ok "adaptadores: 1=Host-only $KALI_LAB_IFACE, 2=NAT"

    # Aplicar --nat-localhostreachable2 off: se modifica el .vbox que VirtualBox
    # usa realmente y se aplica por línea de comandos, con reintento por si
    # VirtualBox reinició el valor al conectar la NIC.
    fix_nat_localhostreachable "$KALI_VM_NAME"
    log_ok "--nat-localhostreachable2 off aplicado"


    # Verificación real con lo que VirtualBox tiene guardado.
    log_step "Verificación"
    local vmi bad=0 key want val
    vmi=$(showvminfo "$KALI_VM_NAME")
    while IFS='|' read -r key want; do
        val=$(mri_get "$vmi" "$key")
        if [[ $val == "$want" ]]; then
            log_ok "$key = $want"
        else
            log_fail "$key = '${val:-sin valor}' (esperado '$want')"
            bad=1
        fi
    done <<EOF
nic1|hostonly
hostonlyadapter1|$KALI_LAB_IFACE
nic2|nat
memory|$KALI_MEM_ARG
cpus|$KALI_CPUS_ARG
graphicscontroller|vmsvga
vram|$KALI_VRAM_ARG
EOF

    # Portapapeles y arrastrar-soltar: el nombre de la clave varía según la
    # versión de VirtualBox, así que se prueban las variantes conocidas.
    local clip dnd
    clip=$(mri_get "$vmi" clipboard); [[ -z $clip ]] && clip=$(mri_get "$vmi" clipboard_mode)
    dnd=$(mri_get "$vmi" draganddrop); [[ -z $dnd ]] && dnd=$(mri_get "$vmi" drag_and_drop)
    [[ -z $dnd ]] && dnd=$(mri_get "$vmi" draganddrop_mode)
    if [[ $clip == bidirectional ]]; then
        log_ok "portapapeles compartido = bidirectional"
    else
        log_fail "portapapeles compartido = '${clip:-sin valor}' (esperado 'bidirectional')"
        bad=1
    fi
    if [[ $dnd == bidirectional ]]; then
        log_ok "arrastrar y soltar = bidirectional"
    else
        log_fail "arrastrar y soltar = '${dnd:-sin valor}' (esperado 'bidirectional')"
        bad=1
    fi

    # El ajuste NAT se expone en showvminfo --machinereadable bajo varias
    # claves posibles según la versión de VirtualBox:
    #   localhostReachable        (valor numérico: 0 = off, 1 = on)
    #   natlocalhostreachable2    (valor: off / on)
    #   nat-localhostreachable2   (valor: off / on)
    # Se prueban todas las variantes conocidas.
    nat_read() {  # clave -> devuelve el valor o vacío
        local k="$1" v
        v=$(mri_get "$vmi" "$k")
        [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
        v=$(mri_get "$vmi" "nat${k#nat}")      # prueba sin guion: nat + localhostreachable2
        [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
        v=$(mri_get "$vmi" "${k%-*}")          # prueba sin sufijo numérico si aplica
        [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
        return 1
    }

    local nat_val
    nat_val=$(mri_get "$vmi" localhostReachable)
    [[ -z $nat_val ]] && nat_val=$(mri_get "$vmi" nat-localhostreachable2)
    [[ $nat_val == off ]] && nat_val=0
    if [[ $nat_val != 0 ]]; then
        VBoxManage modifyvm "$KALI_VM_NAME" --nat-localhostreachable2 off >/dev/null 2>&1
        VMINFO=$(showvminfo "$KALI_VM_NAME")
        nat_val=$(mri_get "$vmi" localhostReachable)
        [[ -z $nat_val ]] && nat_val=$(mri_get "$vmi" nat-localhostreachable2)
        [[ $nat_val == off ]] && nat_val=0
    fi
    if [[ $nat_val == 0 ]]; then
        log_ok "nat-localhostreachable2 off (localhostReachable = 0)"
    else
        log_fail "nat-localhostreachable2 sigue en '${nat_val:-sin valor}' (esperado off/0)."
        log_info "  Desde Kali, prueba: curl http://10.0.2.2 (debe fallar si off está aplicado)."
        bad=1
    fi

    if printf '%s\n' "$vmi" | grep -Fq "=\"$KALI_VDI\""; then
        log_ok "el .vdi está conectado a la VM"
    else
        log_fail "no se ve el .vdi conectado en showvminfo"
        bad=1
    fi
    if [[ -n $uuid ]]; then
        log_ok "registro de VirtualBox: $KALI_VM_NAME ($uuid)"
    fi

    # Última operación de todas: el .vbox que VirtualBox usa realMENTE se deja
    # con localhost-reachable="false" explícito. Va al final y sin ningún
    # VBoxManage después, porque cada modifyvm (y el propio apagado de la VM)
    # reescribe el .vbox y deja <NAT/>, que vale "true" al recargar.
    vbox_patch_localhost "$(vbox_settings_path "$KALI_VM_NAME")"

    if (( bad )); then
        kali_record_write 0 "$KALI_VM_NAME" "$uuid" "$KALI_VDI" "$KALI_VBOX" "$KALI_LAB_IFACE" "$KALI_LAB_IP" "$created"
        die "la VM quedó registrada, pero la verificación falló." \
            "Revisa 'VBoxManage showvminfo $KALI_VM_NAME' o deshaz con scripts/linux/install.sh --phase kali-vm --remove"
    fi
    kali_record_write 1 "$KALI_VM_NAME" "$uuid" "$KALI_VDI" "$KALI_VBOX" "$KALI_LAB_IFACE" "$KALI_LAB_IP" "$created"

    log_step "VM de Kali lista"
    log_ok "arráncala desde VirtualBox o con: VBoxManage startvm \"$KALI_VM_NAME\""
    log_info "Usuario/contraseña por defecto de la imagen oficial: kali / kali (cámbiala con 'passwd')."
    log_info "Siguiente: kali/install.sh --install all dentro de Kali (docs/kali/preparacion.md)."
}

remove_vm() {
    local recorded name uuid
    recorded=$(kali_record_get name 2>/dev/null) || recorded=""
    if [[ -z $recorded ]]; then
        die "no hay ninguna VM registrada por este script ($KALI_RECORD)." \
            "Este comando solo desregistra lo que creó la fase kali-vm del instalador."
    fi
    name=${KALI_NAME_ARG:-$recorded}
    uuid=$(vm_uuid_by_name "$name")
    if [[ -z $uuid ]]; then
        rm -f "$KALI_RECORD"
        log_ok "la VM '$name' ya no está registrada; se limpia $KALI_RECORD"
        return 0
    fi
    if vm_is_running "$name"; then
        die "la VM '$name' está encendida." "Apágala y repite el comando."
    fi
    log_info "Se desregistrará la VM '$name' ($uuid)."
    log_info "El .vdi descargado NO se borra; sigue en: $(kali_record_get vdi 2>/dev/null || echo '?')"
    confirm "¿Desregistrar la VM de VirtualBox?" n || { log_info "cancelado"; return 5; }
    if ! VBoxManage unregistervm "$name"; then
        die "VirtualBox no pudo desregistrar la VM." "Ciérrala y comprueba 'VBoxManage list vms'."
    fi
    rm -f "$KALI_RECORD"
    log_ok "VM desregistrada. El disco y la imagen descargada se conservan."
    local sys_def
    sys_def=$(VBoxManage list systemproperties 2>/dev/null \
        | awk -F': *' '/^Default machine folder:/{print $2; exit}')
    if [[ -n $sys_def && -d "$sys_def/$name" ]]; then
        log_info "Queda la carpeta de configuración: $sys_def/$name"
        log_info "Bórrala si no vas a reutilizar esa VM: rm -rf \"$sys_def/$name\""
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Flujo principal de kali-vm
# ---------------------------------------------------------------------------
vm_flow() {
    if (( KALI_REMOVE )); then
        remove_vm
        return $?
    fi

    # Sin red Host-only no hay VM posible: se instala (o repara) primero, igual
    # que hace el instalador del proyecto. En --check no se modifica nada.
    if (( ! KALI_CHECK )); then
        network_ok || provision_kali_network || return $?
    fi

    preflight || return 1

    if (( KALI_CHECK )); then
        disk_checks || return 1
        nat_check
        log_step "Resultado"
        log_ok "todo listo: se puede ejecutar scripts/linux/install.sh --phase kali-vm"
        return 0
    fi

    download_gate || return $?
    disk_checks || return 1
    plan_summary
    if ! confirm "¿Crear/registrar la VM y aplicar esta configuración?" n; then
        log_info "cancelado: no se ha modificado VirtualBox."
        return 5
    fi
    apply_vm
}

# ---------------------------------------------------------------------------
# Fase kali-vm del instalador
# ---------------------------------------------------------------------------
phase_kali_vm() {
    have VBoxManage || die "VirtualBox no está instalado" "Instala VirtualBox 7 (docs/installation/virtualbox.md)."
    vm_flow
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
        case $fam in
            debian) log_info "KVM: $(pkg_cmd qemu-system-x86 libvirt-daemon-system virt-manager)" ;;
            fedora) log_info "KVM: sudo dnf install -y @virtualization" ;;
            arch) log_info "KVM: $(pkg_cmd qemu-desktop libvirt virt-manager dnsmasq)" ;;
            *) log_info "KVM: instala QEMU, libvirt, virt-manager y dnsmasq con el gestor de paquetes de tu distribución" ;;
        esac
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
        kali-vm) phase_kali_vm ;;
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
