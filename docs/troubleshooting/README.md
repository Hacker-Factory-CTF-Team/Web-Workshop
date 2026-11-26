# Resolución de problemas

## Primeros pasos

```bash
./manager diagnose              # entorno, configuración, dependencias y estado (sin secretos)
./manager status                # salud de cada contenedor
./manager logs LAB [SERVICIO]   # registros
./manager network-check         # aislamiento
```

Todos los errores del gestor terminan con una línea **"Cómo solucionarlo"**. El código de salida indica el tipo de problema ([códigos](../management/gestor.md#5-códigos-de-salida)).

Si no encuentras la solución aquí, abre una Issue con la plantilla [*Informe de error*](https://github.com/Hacker-Factory-CTF-Team/Web-Workshop/issues/new/choose) y adjunta la salida de `./manager diagnose`. No contiene secretos, pero sí las IP de tus interfaces de red: revísala antes de publicarla. Si el problema rompe el aislamiento, no lo publiques: sigue la [política de seguridad](../../SECURITY.md).

## Instalación

| Síntoma | Causa y solución |
|---|---|
| `no ejecutes el instalador con sudo` | Ejecútalo como tu usuario: `scripts/linux/install.sh`. Pide sudo solo cuando hace falta |
| `Docker Engine X es demasiado antiguo (mínimo 28)` | Actualiza Docker desde el repositorio oficial ([linux.md](../installation/linux.md#2-docker-por-distribución)) |
| `Docker usa el backend 'nftables'` | Solo se soporta el backend `iptables` de Docker. Quita la opción `firewall-backend` de `/etc/docker/daemon.json` y reinicia Docker |
| `Docker rootless no está soportado` | Usa el Docker del sistema (`sudo systemctl enable --now docker`) |
| `failed to connect to the docker API` | Docker no está en marcha (`sudo systemctl start docker`) o tu usuario no está en el grupo `docker` (cierra sesión tras `usermod -aG docker`) |
| `la subred ... se solapa con interfaces existentes` | Elige otra con `--ip` ([red](../networking/README.md#cambiar-la-subred)) |
| `rango Host-only no permitido por VirtualBox` | Usa una IP en 192.168.56.0/21 o edita `/etc/vbox/networks.conf` ([virtualbox.md](../installation/virtualbox.md#rango-permitido-por-virtualbox)) |
| `./manager install`: no se pudo descargar | Comprueba la conexión del anfitrión y vuelve a ejecutarlo. Las imágenes ya descargadas no se repiten |
| `SHA-256 ... no coincide` (LDIF) | La descarga está corrupta o ha cambiado. No se usa. Vuelve a intentarlo y, si persiste, avisa a los mantenedores |

## `start` se bloquea (código 3)

Es el comportamiento *fail-closed*: algo no garantiza el aislamiento. Lee las líneas `[FALLO]`.

| Mensaje | Causa y solución |
|---|---|
| `ninguna interfaz tiene la IP ...` | La red de laboratorio no está levantada. KVM: `virsh -c qemu:///system net-start pentestlab`. VirtualBox: arranca la VM de Kali o el servicio de VirtualBox |
| `la IP X está en 'A' pero la configurada es 'B'` | Otra interfaz tiene la IP. Revisa con `ip -br addr` y vuelve a ejecutar la fase `network` |
| `el asistente de firewall no está instalado` | `scripts/linux/install.sh --phase firewall` |
| `la copia instalada no coincide con la del repositorio` | Has actualizado el repositorio y cambió `pentestlab-fw.sh`. Vuelve a ejecutar `scripts/linux/install.sh --phase firewall` |
| `firewall del anfitrión (pentestlab-fw)` fallido | Las reglas no están aplicadas (es normal tras reiniciar) o algo insertó reglas por delante. Acepta cuando `start` ofrezca aplicarlas, o `sudo pentestlab-fw apply --ip IP --iface IFACE`. Mira el motivo con `sudo pentestlab-fw verify --ip IP --iface IFACE` |
| `bridge-nf-call-iptables != 1` | `br_netfilter` no está cargado. `pentestlab-fw apply` lo carga; si falla, `sudo modprobe br_netfilter` |
| `salida a Internet: conexión saliente posible` en `*_edge` | El firewall no filtra el bridge del proxy. Reaplica las reglas y comprueba que el bridge se llama `plabe-*` |
| `acceso al anfitrión` | Un contenedor llega a un servicio del anfitrión. Comprueba que la regla 3 de `PLAB-IN` está activa: `sudo iptables -L PLAB-IN -v -n` |
| `la configuración Compose incumple la política` | Alguien ha modificado un `compose.yaml` o ha añadido un override. Las líneas siguientes dicen qué regla incumple ([política](../management/gestor.md#3-qué-hace-start)) |
| `Interfaz de laboratorio '...': no puede empezar por 'plab'` | Renombra la interfaz: el prefijo está reservado ([firewall](../networking/firewall-linux.md#4-prefijo-reservado-plab)) |

## Arranque

| Síntoma | Causa y solución |
|---|---|
| `el puerto N ... está ocupado por: <proceso>` | Acepta el puerto propuesto, libera el puerto o fija otro con `./manager config set-port` ([conflictos](../management/gestor.md#4-conflictos-de-puertos)) |
| `... no llegó a estado saludable` | El mensaje incluye los últimos registros. Lo más habitual: límites de memoria demasiado bajos (sube con `set-resources`) o una máquina muy cargada (aumenta `start_timeout_seconds` en `config/local.json`) |
| `faltan dependencias` | `./manager install LAB` |
| Falla `Crear la base de datos de DVWA` o `Inicializar la base de datos de Mutillidae` | Revisa `./manager logs LAB db` o `database`. Si los datos están dañados: `./manager reset-data LAB` |
| Operación destructiva: `requiere confirmación` (código 5) | Sin terminal no se puede confirmar. Ejecútala en un terminal o añade `--yes` |

## Acceso desde Kali

| Síntoma | Causa y solución |
|---|---|
| Kali no tiene IP | Comprueba que la NIC está en la red de laboratorio y que el DHCP funciona (`virsh net-dhcp-leases pentestlab`). Si Kali arrancó antes que el laboratorio, con ufw activo puede que no haya ninguna regla que acepte el DHCP: la de `PLAB-IN` se aplica en el `start`. Arranca un laboratorio y renueva la IP en Kali (no verificado: en las pruebas, Kali arrancó con las reglas ya aplicadas) |
| Kali no llega a un puerto | `./manager status` (¿está el laboratorio en marcha?), `ping <IP de laboratorio>` desde Kali y `tests/network/kali-probe.sh` ([pruebas](../testing/pruebas.md#3-desde-la-vm-de-kali)) |
| WebGoat no enlaza bien con WebWolf | Entra por la IP de laboratorio, no por `127.0.0.1` ([ficha](../labs/webgoat.md#acceso)) |
| Kali no tiene Internet (KVM) | `eth1` sin IP o sin ruta: el NAT depende de las reglas de `pentestlab-fw`, que se aplican en `./manager start` ([kvm.md](../installation/kvm.md#5-problemas-frecuentes)) |
| Kali tiene la ruta por defecto por la red de laboratorio | La red anuncia pasarela (versión antigua del instalador): repite la fase `network` con Kali apagada. En VirtualBox: `nmcli ... ipv4.never-default yes` ([virtualbox.md](../installation/virtualbox.md#3-vm-de-kali)) |
| `kali-probe.sh` (VirtualBox): `FALLO anfitrión vía NAT (10.0.3.2:N) ACCESIBLE` | El NAT de VirtualBox da a Kali acceso al `127.0.0.1` del anfitrión. No rompe el aislamiento respecto a la LAN ni bloquea el laboratorio, pero expone los servicios locales del anfitrión a Kali. Con la VM apagada: `VBoxManage modifyvm "<VM>" --nat-localhostreachable2 off` ([detalle](../installation/virtualbox.md#nat-de-kali-y-servicios-locales-del-anfitrión)) |
| Aviso de certificado en Mutillidae HTTPS | Es normal: el certificado es autofirmado |

## Pruebas de red

| Síntoma | Causa y solución |
|---|---|
| `linux-netns.sh test`: `la interfaz X no existe` | La interfaz de `config/local.json` no está levantada, o es la emulada (`simlab-h`) y no existe. Crea la emulada con `sudo tests/network/linux-netns.sh setup-sim` o restaura la real ([pruebas](../testing/pruebas.md#5-validación-completa-sin-vm)) |
| Fallos LAN que no tienen sentido | Comprueba que ninguna interfaz de prueba empieza por `plab`. Ejecuta `bash tests/network/linux-diag.sh` y revisa `state/linux-diag.log` |
| Tras `linux-validation-session.sh`, `start` usa `simlab-h` | El script cambia la configuración de red. Restáurala ([pruebas](../testing/pruebas.md#5-validación-completa-sin-vm)) |

## Windows

Ver [problemas frecuentes en Windows](../installation/windows.md#8-problemas-frecuentes).

## Volver a un estado conocido

```bash
./manager stop all
./manager --yes reset LAB                    # un laboratorio desde cero
scripts/linux/install.sh --phase firewall    # reinstalar y reaplicar el firewall
```

Desinstalación completa: [guía de desinstalación](../management/desinstalacion.md).
