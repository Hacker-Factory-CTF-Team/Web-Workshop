# Instalación en Windows 11

> [!WARNING]
> **Estado: no probado.** Los scripts de Windows (`scripts\windows\install.ps1`, `scripts\windows\poc-network.ps1` y `manager.ps1`) están escritos y analizados estáticamente: PowerShell los analiza sin errores, PSScriptAnalyzer no da avisos y la lógica de las reglas del firewall tiene pruebas unitarias. **Nunca se han ejecutado en un equipo Windows.** Si eres la primera persona que lo prueba, empieza por la [PoC de red](#prueba-de-red-poc) y comparte su resultado (`state\windows-poc.log`).

## 1. Cómo funciona en Windows

| | Linux | Windows |
|---|---|---|
| Contenedores | Docker Engine | **Docker Desktop** (backend WSL2) |
| Red de laboratorio | KVM o VirtualBox | **VirtualBox** (Host-only `VirtualBox Host-Only Ethernet Adapter #N`) |
| IP de laboratorio | `192.168.157.1` (KVM) / `192.168.57.1` (VirtualBox) | `192.168.57.1` |
| Firewall | `pentestlab-fw` (iptables, en memoria) | **Reglas del grupo `PentestLab` del Firewall de Windows** (persistentes) |
| Gestor | `./manager` | `.\manager.ps1` |

Los puertos se publican igual que en Linux, solo en `127.0.0.1` y en la IP de laboratorio, y el gestor bloquea el despliegue si algún puerto escucha en otra dirección. Las aplicaciones siguen en redes internas, sin salida.

Lo que **no** se puede igualar en Windows está en [riesgos residuales](#7-diferencias-y-riesgos-residuales).

## 2. Requisitos

| Requisito | Detalle |
|---|---|
| Sistema | Windows 11, con la virtualización activada en la BIOS/UEFI |
| Docker Desktop | Con backend WSL2 y Docker Engine ≥ 28 (`winget install -e --id Docker.DockerDesktop`; necesita `wsl --install`) |
| Python | ≥ 3.10 (`winget install -e --id Python.Python.3.12`) |
| VirtualBox | 7.x (`winget install -e --id Oracle.VirtualBox`) |
| PowerShell | 5.1 (incluido en Windows) o 7. Algunas fases necesitan **Ejecutar como administrador** |
| RAM | 16 GiB recomendados (Docker Desktop reserva memoria para su VM, más Kali) |
| Disco | ~5 GB para imágenes, más la VM de Kali |

Docker Desktop activa la *Plataforma de máquina virtual* de Windows. VirtualBox 7 funciona sobre ella, pero puede ir más lento: una tortuga verde en la barra de estado de la VM lo indica. Es el comportamiento conocido de VirtualBox con Hyper-V, aún sin comprobar en este proyecto.

**Política de ejecución.** Si Windows impide ejecutar los scripts, lánzalos así:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1
```

Si descargaste el repositorio como ZIP, quita también la marca de "descargado de Internet":

```powershell
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
```

**Alias de Python de la Microsoft Store.** Si `python` abre la tienda, desactiva `python.exe` en *Configuración → Aplicaciones → Configuración avanzada de aplicaciones → Alias de ejecución de aplicaciones*. `manager.ps1` busca primero `py -3` y descarta el alias, pero conviene quitarlo.

## 3. Instalación

Desde la carpeta del repositorio, en PowerShell **como administrador**:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1
```

Sin `-Phase`, ejecuta la detección y pregunta por cada fase:

| Fase | Qué hace | Administrador |
|---|---|---|
| `Detect` | Windows, virtualización, Docker Desktop, Compose, Python, VirtualBox, interfaces Host-only, perfiles del firewall y espacio libre | No |
| `Deps` | Ofrece instalar con `winget` lo que falte | No (winget puede pedir elevación) |
| `Network` | Reutiliza o crea una interfaz Host-only con `192.168.57.1/24` y DHCP (`.100`–`.199`, sin pasarela ni DNS). Guarda la plataforma `windows-virtualbox`, la IP y el alias de Windows del adaptador | **Sí** |
| `Firewall` | Crea las reglas del grupo `PentestLab` ([sección 5](#5-reglas-del-firewall-de-windows)) | **Sí** |
| `Images` | `.\manager.ps1 install all` | No |
| `Validate` | `.\manager.ps1 diagnose` | No |
| `Uninstall` | Deshace lo registrado en `state\installer.json` | **Sí** |

Para una fase suelta: `... install.ps1 -Phase Network -LabIp 192.168.58.1`. Opciones: `-Phase`, `-LabIp`, `-Prefix` y `-Yes`.

Si la subred se solapa con otra interfaz, el instalador se detiene; elige otra con `-LabIp`. VirtualBox para Windows no tiene la restricción de rangos Host-only (`networks.conf`) que tiene en Linux.

### Prueba de red (PoC)

**Antes del primer uso**, con Docker Desktop en marcha y la fase `Network` hecha:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\poc-network.ps1
```

Crea contenedores y redes temporales (`plab-poc-*`), que elimina al terminar, y responde:

| Pregunta | Esperado |
|---|---|
| ¿Docker Desktop publica en la IP Host-only y **solo** ahí? | Sí; escucha solo en `192.168.57.1`; no responde en `127.0.0.1` ni en la IP LAN |
| Alternativa `127.0.0.1` + `netsh interface portproxy` (como administrador) | Informativo |
| Red interna: ¿salida TCP, DNS externo, `host.docker.internal`? | Todo cerrado |
| Red no interna (como el proxy): ¿salida TCP? | Riesgo residual documentado (informativo) |
| Red no interna: ¿`host.docker.internal`? | Cerrado |
| `dns: 127.0.0.1`: ¿nombres internos sí y externos no? | Sí / no |

El resultado se guarda en `state\windows-poc.log`. Si alguna respuesta no es la esperada, **no uses el laboratorio** y comparte el registro: puede requerir otro mecanismo de publicación, como `portproxy`.

## 4. Primer uso

```powershell
powershell -ExecutionPolicy Bypass -File .\manager.ps1 start
```

En el resto de la documentación, `./manager <comando>` equivale en Windows a `.\manager.ps1 <comando>`.

`start` hace en Windows las mismas comprobaciones que en Linux. Lo específico de Windows:
- Docker Desktop con Engine ≥ 28;
- la interfaz de laboratorio con su IP;
- **todos los perfiles del Firewall de Windows activos**;
- **las reglas del grupo `PentestLab` idénticas a las que corresponden a la configuración actual**. Si cambias un puerto con `config set-port` o la red, `start` se bloquea hasta que repitas la fase `Firewall`.

Después: `.\manager.ps1 network-check`.

**VM de Kali** en VirtualBox ([detalle](virtualbox.md#3-vm-de-kali)):
- **adaptador 1**: *Adaptador solo-anfitrión*, el `VirtualBox Host-Only Ethernet Adapter #N` que indicó el instalador;
- **adaptador 2**: *NAT*.

Dentro de Kali, la IP del anfitrión es `192.168.57.1`:

```bash
kali/install.sh --check --host 192.168.57.1
bash tests/network/kali-probe.sh --host 192.168.57.1 --lan <IP de tu router> --host-lan <IP LAN del anfitrión>
```

## 5. Reglas del Firewall de Windows

Las genera el gestor a partir de la configuración (`.\manager.ps1 config firewall-spec` muestra el JSON) y las crea la fase `Firewall`. Todas son de entrada, para cualquier perfil, y se refieren a la IP de laboratorio:

| Regla | Acción | Qué cubre |
|---|---|---|
| `PentestLab - Bloquear puertos del laboratorio fuera de la red de laboratorio` | Bloquear | Cualquier protocolo desde cualquier origen **fuera** de la subred de laboratorio, aunque un equipo de la LAN añada una ruta |
| `PentestLab - Permitir Kali en la interfaz de laboratorio` | Permitir | TCP a los **puertos de los laboratorios**, desde la subred de laboratorio y solo por el adaptador Host-only |
| `PentestLab - Bloquear a Kali otros puertos TCP del anfitrion` | Bloquear | TCP al resto de puertos desde la subred de laboratorio. En Windows, bloquear gana a permitir, así que ninguna otra regla puede abrir servicios a Kali |
| `PentestLab - Bloquear a Kali los puertos UDP del anfitrion` | Bloquear | UDP desde la subred de laboratorio |
| `PentestLab - Permitir ping de Kali al anfitrion` | Permitir | ICMPv4 eco desde la subred de laboratorio |

A diferencia de Linux, **estas reglas son persistentes**: sobreviven a los reinicios. Se quitan con la fase `Uninstall` o con:

```powershell
Get-NetFirewallRule -Group PentestLab | Remove-NetFirewallRule
```

Si el grupo contiene reglas que no están en la especificación, el gestor también se bloquea.

## 6. Desinstalar

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1 -Phase Uninstall
```

Detiene los laboratorios y quita las reglas del firewall, el DHCP y la interfaz Host-only, si los creó el instalador. Los datos y las imágenes se borran igual que en Linux ([desinstalación](../management/desinstalacion.md)).

## 7. Diferencias y riesgos residuales

| Tema | Linux | Windows |
|---|---|---|
| Salida del proxy `edge` | Bloqueada por `pentestlab-fw` | **Abierta.** Docker Desktop no permite filtrarla desde el anfitrión. El proxy es nginx L4 endurecido (sin root, solo lectura, sin capacidades) y sin DNS externo. El gestor lo muestra como aviso ([ADR 0002](../adr/0002-salida-del-proxy-firewall-y-dns.md)) |
| Contenedores → servicios del anfitrión | Bloqueado | Depende de Docker Desktop (`host.docker.internal`). El gestor lo comprueba y, en Windows, avisa en vez de bloquear. La PoC lo mide |
| NAT de Kali → anfitrión | KVM: bloqueado por `pentestlab-fw` | El NAT de VirtualBox (`10.0.2.2`) puede dar acceso a servicios del anfitrión en `127.0.0.1`. `kali-probe.sh` lo comprueba |
| Persistencia del firewall | Reglas en memoria, reaplicadas en cada `start` | Reglas persistentes, verificadas en cada `start` |
| Zona horaria de WebGoat | La del anfitrión | UTC, salvo `.\manager.ps1 config set-timezone Europe/Madrid` |

## 8. Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| *No se puede cargar el archivo ... la ejecución de scripts está deshabilitada* | Usa `powershell -ExecutionPolicy Bypass -File ...` y `Unblock-File` ([sección 2](#2-requisitos)) |
| `se necesita Python 3.10 o superior` | Instala Python y abre una terminal nueva. Desactiva el alias de la tienda |
| `El daemon de Docker no responde` | Abre Docker Desktop y espera a *Engine running* |
| La fase `Network` dice *Windows no muestra el adaptador* | Reinicia el equipo: el controlador de VirtualBox se instala al crear la interfaz. Después repite la fase |
| `start`: *reglas PentestLab ... no coincide con la configuración actual* | Has cambiado puertos o la red. Repite `install.ps1 -Phase Firewall` como administrador |
| `start`: *perfiles desactivados* | Activa el Firewall de Windows en todos los perfiles |
| `start`: *escucha en 0.0.0.0* | Docker Desktop no respetó la IP de publicación. Es un bloqueo de seguridad: ejecuta la PoC y comparte el registro |
