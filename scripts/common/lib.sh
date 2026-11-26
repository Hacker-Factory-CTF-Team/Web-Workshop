# shellcheck shell=bash
# Shared helpers for the Linux installer, the Kali kit and the test scripts.
# Source it; do not execute it.

# Ensure standard administrative binary paths are available in PATH
# (distributions like openSUSE or Debian omit /sbin and /usr/sbin for regular users)
for _p in /usr/local/sbin /usr/sbin /sbin; do
    [[ -d "$_p" && ":$PATH:" != *":$_p:"* ]] && export PATH="$PATH:$_p"
done
unset _p

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    _C_RED=$'\033[31m'; _C_GRN=$'\033[32m'; _C_YLW=$'\033[33m'; _C_BLU=$'\033[1;34m'; _C_RST=$'\033[0m'
else
    _C_RED=""; _C_GRN=""; _C_YLW=""; _C_BLU=""; _C_RST=""
fi

log_step() { printf '%s==>%s %s\n' "$_C_BLU" "$_C_RST" "$*"; }
log_ok()   { printf '  %s[OK]%s   %s\n' "$_C_GRN" "$_C_RST" "$*"; }
log_warn() { printf '  %s[AVISO]%s %s\n' "$_C_YLW" "$_C_RST" "$*"; }
log_fail() { printf '  %s[FALLO]%s %s\n' "$_C_RED" "$_C_RST" "$*"; }
log_info() { printf '  %s\n' "$*"; }
die()      { printf '%sERROR:%s %s\n' "$_C_RED" "$_C_RST" "$1" >&2; [[ -n ${2:-} ]] && printf 'Cómo solucionarlo: %s\n' "$2" >&2; exit "${3:-1}"; }

ASSUME_YES=${ASSUME_YES:-0}

# confirm "question" [default y|n]
confirm() {
    local q=$1 def=${2:-n} ans
    [[ $ASSUME_YES == 1 ]] && return 0
    [[ -t 0 ]] || return 1
    if [[ $def == y ]]; then read -r -p "$q (S/n): " ans; ans=${ans:-s}; else read -r -p "$q (s/N): " ans; fi
    [[ ${ans,,} =~ ^(s|si|sí|y|yes)$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

is_root() { [[ $EUID -eq 0 ]]; }

# Run a command as root, asking for sudo only when needed.
as_root() {
    if is_root; then "$@"; else sudo "$@"; fi
}

# Distro family: debian | fedora | arch | suse | unknown
distro_family() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id=$(. /etc/os-release; echo "${ID:-}")
        # shellcheck disable=SC1091
        like=$(. /etc/os-release; echo "${ID_LIKE:-}")
    fi
    case " $id $like " in
        *" debian "*|*" ubuntu "*|*" kali "*|*" linuxmint "*|*" pop "*) echo debian ;;
        *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*) echo fedora ;;
        *" arch "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*) echo arch ;;
        *" suse "*|*" opensuse "*|*" opensuse-leap "*|*" opensuse-tumbleweed "*) echo suse ;;
        *) echo unknown ;;
    esac
}

repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd; }

# Read a value from the manager's effective configuration (python3 required).
lab_config_get() {
    local root; root=$(repo_root)
    PYTHONPATH="$root/src" python3 - "$1" <<'PY'
import sys
from pentestlab.config import Config
cfg = Config()
key = sys.argv[1]
val = {"ip": cfg.lab_host_ip, "prefix": cfg.lab_prefix, "iface": cfg.lab_interface, "nat": cfg.nat_interface, "platform": cfg.platform}.get(key)
print("" if val is None else val)
PY
}

# Ports of every lab endpoint, space separated.
lab_ports() {
    local root; root=$(repo_root)
    PYTHONPATH="$root/src" python3 -c '
from pentestlab.config import Config
print(" ".join(str(e.port) for l in Config().labs.values() for e in l.endpoints.values()))'
}
