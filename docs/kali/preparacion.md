# Preparación de Kali

Kali es la máquina desde la que se atacan los laboratorios. Corre como VM en el mismo anfitrión, con dos adaptadores de red.

La creación de la VM depende del hipervisor:
- [KVM/QEMU](../installation/kvm.md#3-vm-de-kali) (probado);
- [VirtualBox](../installation/virtualbox.md#3-vm-de-kali).

## 1. VM recomendada

| Recurso | Valor |
|---|---|
| Imagen | Oficial de Kali para tu hipervisor, verificada por SHA-256: https://www.kali.org/get-kali/#kali-virtual-machines |
| RAM | 4 GiB (2 GiB como mínimo; Burp Suite y ZAP consumen bastante) |
| vCPU | 2 |
| Adaptador 1 | Red de laboratorio: `pentestlab` en KVM o `vboxnetN` (solo-anfitrión) en VirtualBox |
| Adaptador 2 | NAT: red `default` en KVM o *NAT* en VirtualBox. Da Internet a Kali para actualizaciones y herramientas |
| Usuario inicial | `kali` / `kali` (cámbiala con `passwd`) |

Ten en cuenta los recursos de Kali al decidir cuántos laboratorios arrancas a la vez ([recursos](../management/recursos.md)).

## 2. Red

| | Adaptador de laboratorio (`eth0`) | Adaptador NAT (`eth1`) |
|---|---|---|
| IP | DHCP, `.100`–`.199` de la subred de laboratorio | DHCP del hipervisor (KVM: `192.168.122.x`) |
| Ruta por defecto | **No** (el DHCP no anuncia pasarela) | Sí |
| DNS | No | Sí |
| Alcanza | Los 6 puertos de los laboratorios y el ping al anfitrión. Nada más | Internet y tu LAN, como cualquier VM con NAT |
| No alcanza | Ningún otro servicio del anfitrión. El anfitrión tampoco reenvía nada de lo que entra por aquí | Los servicios del anfitrión ni los laboratorios (KVM, con el firewall aplicado) |

El aislamiento que exige el diseño es el de las **aplicaciones**: no tienen salida y no son accesibles desde la LAN. La NIC NAT es de Kali y no cambia eso.

URL con la configuración por defecto de KVM (con VirtualBox, cambia `192.168.157.1` por `192.168.57.1`). También las muestra `./manager status`, en la columna *DESDE KALI*.

| Aplicación | URL |
|---|---|
| DVWA | `http://192.168.157.1:4280/` |
| Juice Shop | `http://192.168.157.1:3000/` |
| WebGoat | `http://192.168.157.1:8080/WebGoat/` |
| WebWolf | `http://192.168.157.1:9090/WebWolf/` |
| Mutillidae | `http://192.168.157.1:8081/` y `https://192.168.157.1:8443/` (certificado autofirmado) |

En KVM, el NAT de Kali depende de las reglas de `pentestlab-fw`. Tras reiniciar el anfitrión, no hay Internet en Kali hasta el siguiente `./manager start` ([detalle](../installation/kvm.md#red-nat-y-firewall)).

## 3. Kit de herramientas (`kali/install.sh`)

El kit instala y verifica las herramientas del taller, organizadas en módulos. Se ejecuta **dentro de Kali**, como usuario normal (usa `sudo` para APT), y necesita Internet por el adaptador NAT.

### Llevarlo a Kali

Solo necesita la carpeta `kali/` (`install.sh` y `modules/`). Para la comprobación completa, también `tests/network/kali-probe.sh`. Clona el repositorio en Kali o copia esas carpetas, manteniendo la estructura.

### Módulos

| ID | Módulo | Herramientas (comando) |
|---|---|---|
| `recon` | Reconocimiento | nmap, whatweb |
| `web-enum` | Enumeración web | gobuster, ffuf, wfuzz |
| `vuln` | Análisis de vulnerabilidades | nikto, zaproxy |
| `proxy` | Interceptación HTTP | burpsuite (Burp Suite Community) |
| `http-api` | Pruebas HTTP/API | curl, httpie (`http`) |
| `dev` | Desarrollo y utilidades | git, python3, pipx |

### Uso

```bash
kali/install.sh                          # menú interactivo
kali/install.sh --list                   # módulos y estado de cada herramienta
kali/install.sh --install all            # todos los módulos
kali/install.sh --install recon,web-enum # algunos módulos
kali/install.sh --update                 # actualiza las herramientas ya instaladas (o --update recon,dev)
kali/install.sh --check                  # sistema, herramientas, red y conectividad con el anfitrión
kali/install.sh --check --full           # además, kali-probe.sh (prueba de aislamiento completa)
kali/install.sh --check --host 192.168.57.1   # VirtualBox (por defecto 192.168.157.1, KVM)
```

Cómo funciona:

- **Detecta lo ya instalado** por el comando de cada herramienta y no lo reinstala.
- **Paquetes desde APT**, preferiblemente de los repositorios de Kali. Cada herramienta tiene uno o varios nombres de paquete posibles y usa el primero que APT puede instalar. Si el paquete elegido no procede de `kali.org`, avisa.
- **Verifica cada instalación**: después de instalar, comprueba que el comando existe.
- **`--update`** solo actualiza los paquetes instalados de los módulos indicados (`apt-get install --only-upgrade`).
- **Errores comprensibles**, siempre con *Cómo solucionarlo*: sin Internet, módulo desconocido, paquete inexistente, etc.
- **`--check`** comprueba:
  - que es Kali y tiene el repositorio `kali-rolling`;
  - el estado de todas las herramientas;
  - que hay un adaptador en la red de laboratorio y que esa red no da ruta por defecto;
  - si hay Internet por NAT (solo informa);
  - el ping al anfitrión y los 6 puertos por HTTP (`--ports` para otros puertos).
- Código de salida: 0 si todo es correcto, 1 si hubo fallos y 2 si el uso es incorrecto.

### Añadir herramientas

Cada módulo es un fichero `kali/modules/NN-id.conf`. Se lee como texto; nunca se ejecuta:

```text
name=Reconocimiento
description=Descubrimiento de servicios e identificación de tecnologías web
# tool=id|comando de verificación|paquetes alternativos, en orden de preferencia
tool=nmap|nmap|nmap
tool=wfuzz|wfuzz|wfuzz python3-wfuzz
```

Los comentarios van siempre en su propia línea, empezando por `#`.

Probado el 2026-11-23 en la VM de Kali real (KVM): `--install all`, la repetición sin reinstalar, el menú y `--check --full`. También en un contenedor `kalilinux/kali-rolling`: instalación, no duplicación, actualización, nombre alternativo, paquete inexistente, módulo desconocido, menú y `--check`. Todos los paquetes tienen candidato en `kali-rolling`.

## 4. Verificar

Con los laboratorios arrancados, ejecuta dentro de Kali `tests/network/kali-probe.sh` ([cómo](../testing/pruebas.md#3-desde-la-vm-de-kali)). Debe terminar con `0 fallidas`.

## 5. Instantánea

Cuando Kali esté preparada, haz una instantánea para volver a ese estado entre sesiones del taller. Estos comandos no se han probado todavía. La VM creada con `virt-install` como en [kvm.md](../installation/kvm.md) usa BIOS y disco qcow2, que admiten instantáneas internas.

```bash
virsh -c qemu:///system snapshot-create-as kali-plab limpia "Kali preparada para el taller"
virsh -c qemu:///system snapshot-revert kali-plab limpia
```

En VirtualBox: *Instantáneas → Tomar*.
