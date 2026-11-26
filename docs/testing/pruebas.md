# Cómo se prueba el laboratorio

Las pruebas están organizadas por niveles. Los primeros no necesitan root ni red; los últimos inyectan paquetes reales desde otras interfaces.

| Nivel | Qué valida | Comando | Requiere |
|---|---|---|---|
| 1 | Lógica del gestor y política de seguridad | `python3 -m unittest discover -s tests -t .` | Python (y Compose para `tests/security`) |
| 2 | Aislamiento de los labs en marcha, desde dentro de Docker | `./manager network-check` | Labs arrancados |
| 3 | Lo que ve Kali | `tests/network/kali-probe.sh` dentro de Kali | VM de Kali |
| 4 | Lo que ve un equipo de la LAN | `sudo tests/network/linux-netns.sh test` | root |
| 5 | Todo lo anterior sin VM (red emulada) | `bash tests/network/linux-validation-session.sh` | root |
| W | Comportamiento de red de Docker Desktop en Windows | `scripts\windows\poc-network.ps1` ([detalle](../installation/windows.md#prueba-de-red-poc)) | Windows (administrador para `portproxy`) |

## 1. Pruebas unitarias y de política

```bash
python3 -m unittest discover -s tests -t .
```

- **`tests/unit/`**: no usan Docker ni red; todo lo externo se simula. Cubren:
  - la configuración y sus validaciones (puertos duplicados, prefijo `plab`);
  - la política estática;
  - los conflictos de puertos, con sockets reales (un puerto en LISTEN cuenta como ocupado y uno en TIME_WAIT no);
  - `update --check`;
  - la sonda de aislamiento;
  - la validación de la IP de laboratorio;
  - el menú y el ciclo de vida;
  - las reglas del Firewall de Windows (`test_winfw.py`): la especificación cubre toda la red salvo la subred de laboratorio y todo el rango de puertos, y la verificación entiende el formato real de Windows (máscaras, valores sueltos) y detecta reglas que faltan, duplicadas, desactivadas, desfasadas o ajenas.
- **`tests/security/`**: ejecutan `docker compose config` sobre los 4 laboratorios reales y les aplican la política. También comprueban que una serie de *overrides* hostiles (puerto en `0.0.0.0`, `privileged`, socket de Docker, `latest`...) se rechazan. No crean contenedores. Se omiten si no está el plugin `docker compose`.

Las pruebas no escriben en el repositorio. Cada error corregido tiene su prueba de regresión.

## 2. `./manager network-check`

Repite sobre los laboratorios en marcha las comprobaciones de `start`:
- plataforma y firewall;
- política;
- puertos publicados y sockets;
- sondas de salida, de acceso al anfitrión, entre laboratorios y de segmentación interna;
- HTTP.

Devuelve 3 si falla algo crítico. Detalle en [configuración de red](../networking/README.md#6-qué-se-comprueba-en-cada-arranque).

No inyecta tráfico desde otra interfaz. Para eso están los niveles 3 y 4.

## 3. Desde la VM de Kali

`tests/network/kali-probe.sh` se ejecuta **dentro de Kali**, como usuario normal y con los laboratorios arrancados. Pide la contraseña de `sudo` para añadir rutas temporales (ver abajo).

`kali/install.sh --check --full` lo ejecuta automáticamente si el repositorio está en Kali, después de comprobar las herramientas y la conectividad básica.

### Pasar el script a Kali

Kali no puede llegar a ningún servicio del anfitrión salvo los laboratorios, así que no puede descargarlo del anfitrión. Usa el portapapeles de la consola de la VM (SPICE en virt-manager; *Portapapeles compartido* en VirtualBox):

```bash
cat > kali-probe.sh          # pega el contenido, Enter y Ctrl+D
```

### Ejecutarlo

```bash
bash kali-probe.sh                                   # KVM (IP 192.168.157.1)
bash kali-probe.sh --host 192.168.57.1               # VirtualBox
bash kali-probe.sh --lan 192.168.1.1 --host-lan 192.168.1.50 --full-scan   # tu router y la IP LAN del anfitrión
```

| Opción | Significado |
|---|---|
| `--host IP` | IP de laboratorio del anfitrión (por defecto `192.168.157.1`) |
| `--lan IP` | Un equipo de tu LAN, por ejemplo el router (`ip route` en el anfitrión muestra la pasarela). Se puede repetir |
| `--host-lan IP` | La IP del anfitrión en la LAN |
| `--full-scan` | nmap a los 65535 puertos TCP de `--host`. Tarda unos minutos porque los puertos filtrados no responden |
| `--no-sudo` | Omite las pruebas que necesitan rutas temporales |

Qué comprueba:

| Sección | Debe ocurrir |
|---|---|
| Red de Kali | Hay una NIC con IP en la subred de laboratorio y **esa red no da ruta por defecto**. Informa (sin contar como fallo) de la NIC NAT y de si hay Internet |
| Puertos del laboratorio | Los 6 responden por HTTP y hay ping al anfitrión |
| Servicios del anfitrión en la red de laboratorio | Bloqueados: 53, 22, 80, 111, 443, 631, 1716, 5355, 8000 y 11434 |
| El anfitrión como router | Añade rutas /32 temporales **a través de la IP de laboratorio del anfitrión** hacia 1.1.1.1, 9.9.9.9, `--lan` y `--host-lan`, y comprueba que no pasa nada: TCP, ping y DNS por UDP (con `dig`). Las rutas se quitan al terminar, también si se interrumpe |
| Servicios del anfitrión por la NIC NAT | Bloqueados en la pasarela NAT y en `--host-lan` (KVM: lo garantiza `pentestlab-fw`. VirtualBox: un FALLO aquí se corrige en la VM, no en el laboratorio, ver [NAT de Kali](../installation/virtualbox.md#nat-de-kali-y-servicios-locales-del-anfitrión)) |
| `--full-scan` | Solo los 6 puertos del laboratorio abiertos en la IP de laboratorio |

Las rutas temporales simulan a alguien que intenta usar el anfitrión como router por la red de laboratorio. Sin ellas, con la NIC NAT, ese tráfico saldría por el NAT y la prueba no demostraría nada.

> [!NOTE]
> `kali-probe.sh` comprueba siempre los **6 puertos por defecto** (4280, 3000, 8080, 9090, 8081 y 8443) y no tiene opción para cambiarlos. Si has cambiado algún puerto con `./manager config set-port`, sus resultados sobre los puertos del laboratorio y `--full-scan` no son fiables. `kali/install.sh --check` sí admite `--ports P,P,...`.

En los bloqueos, *rechazado* (RST) y *sin respuesta* (filtrado) cuentan los dos como correctos. Lo esperado es *sin respuesta*, porque el firewall descarta los paquetes. El script termina con código 0 solo si no hay ningún fallo.

## 4. LAN emulada

```bash
sudo tests/network/linux-netns.sh test       # con los labs arrancados
sudo tests/network/linux-netns.sh cleanup    # al terminar
```

Crea el *network namespace* `plab-lan`, unido al anfitrión por un par veth (`simlan-h` ↔ `simlan-n`, 10.250.250.0/30). Ese namespace hace de equipo de la LAN y **enruta todo a través del anfitrión**, que es la forma clásica de alcanzar servicios "solo locales". Comprueba que no llega a:

- los puertos de los labs en la IP de laboratorio, en `127.0.0.1` y en la IP del anfitrión en esa LAN;
- las IP internas de todos los contenedores, en los puertos habituales.

Funciona igual con la interfaz real (`virbr-plab`, `vboxnetN`) que con la emulada.

## 5. Validación completa sin VM

Para equipos sin hipervisor o para el CI:

```bash
bash tests/network/linux-validation-session.sh       # como tu usuario; pide sudo
```

1. Crea una interfaz de laboratorio emulada con `linux-netns.sh setup-sim`: `simlab-h` (192.168.57.1) y una "Kali" en la netns `plab-kali` (192.168.57.100).
2. Instala el firewall.
3. Ejecuta `install` y `start all`.
4. Ejecuta `network-check` y `linux-netns.sh test`, que también prueba el lado Kali desde la netns.

Guarda todo en `state/linux-validation-session.log` y devuelve un código distinto de 0 si falla un paso crítico.

> [!WARNING]
> Este script **cambia `config/local.json`** a la red emulada (`linux-virtualbox`, `simlab-h`). Antes guarda una copia en `state/local.json.antes-validacion` y, al terminar, indica cómo restaurarla:
>
> ```bash
> ./manager stop all
> sudo tests/network/linux-netns.sh cleanup
> cp state/local.json.antes-validacion config/local.json
> ./manager start
> ```

Las interfaces emuladas **no** pueden empezar por `plab`, porque el firewall las trataría como bridges de Docker y los resultados no serían válidos. Por eso se llaman `simlab-*` y `simlan-*`.

## 6. Diagnóstico de red

Si una prueba de red falla sin motivo claro:

```bash
bash tests/network/linux-diag.sh        # como tu usuario; pide sudo
```

Registra en `state/linux-diag.log`:
- las interfaces y las netns;
- los contadores de `PLAB-IN`;
- las primeras reglas de `INPUT`;
- las reglas nftables relevantes;
- la configuración ICMP;
- una ejecución de `linux-netns.sh test`.

Está pensado para la red emulada (usa la netns `plab-kali`).

## 7. Calidad del código

```bash
# ShellCheck sin instalarlo (imagen oficial, sin red y en solo lectura), con los mismos archivos que el CI
docker run --rm --network none -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 \
  --severity=warning --external-sources $(git ls-files '*.sh') manager
python3 -m compileall -q src tests
```

El resto de comprobaciones del job `lint` (sintaxis Bash y validez de los JSON) están en la [guía de desarrollo](../development/README.md#validación-rápida).

El workflow de CI (`.github/workflows/ci.yml`) tiene tres jobs:
- `lint`: `bash -n`, ShellCheck, `compileall`, la validez de los JSON y PSScriptAnalyzer (severidad *Warning*) sobre los `.ps1`;
- `unit`: con Python 3.10, 3.12 y 3.13;
- `integration`: `linux-validation-session.sh` en `ubuntu-latest`.

## 8. Qué probar tras cada cambio

| Cambio | Pruebas mínimas |
|---|---|
| Código Python del gestor | Nivel 1 |
| `compose.yaml`, `lab.json` o `versions.json` | Niveles 1 y 2, y el arranque del laboratorio afectado |
| `pentestlab-fw.sh` o el instalador | Niveles 1–4 (o 5) y ShellCheck; reinstalar el firewall |
| Nueva versión de una aplicación | [Procedimiento de actualización](../management/actualizaciones.md) |
| Nuevo laboratorio | [Validación de la guía](../development/nuevo-laboratorio.md#6-validación) |
| Scripts de Windows | Nivel 1 (`test_winfw.py`) y PSScriptAnalyzer; nivel W si tienes Windows |
| Solo documentación | Enlaces internos y que lo descrito coincide con el código |
| Nuevo equipo o hipervisor | Niveles 2–4 y anotar el resultado en la [matriz](../compatibilidad.md) |

Las invariantes que protegen estas pruebas están en [invariantes de seguridad](../architecture/invariantes-seguridad.md).
