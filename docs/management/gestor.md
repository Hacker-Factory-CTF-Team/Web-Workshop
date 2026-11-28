# Uso del gestor

`./manager` (en Windows, `.\manager.ps1`) es el único punto de entrada para manejar los laboratorios:

- en Linux es un lanzador Bash que comprueba Python ≥ 3.10 y ejecuta el paquete `src/pentestlab`;
- usa solo la biblioteca estándar de Python ([ADR 0003](../adr/0003-gestor-python-biblioteca-estandar.md));
- invoca `docker` y `docker compose`.

No uses `docker compose up` directamente en `labs/<lab>/`. Te saltarías las comprobaciones de aislamiento, y además faltarían las variables que genera el gestor en `state/<lab>.env`.

## 1. Comandos

```text
./manager [--yes] COMANDO [opciones]
```

`LAB` es `dvwa`, `juice-shop`, `webgoat`, `mutillidae` o `all`. Si no indicas ninguno, se aplica a todos. También se aceptan los alias `juice` y `juiceshop` (Juice Shop), `webwolf` (WebGoat) y `mutillidae2`.

### Información

| Comando | Qué muestra |
|---|---|
| `list` | Laboratorios, puertos, modo de persistencia y CPU/RAM máximas (suma de límites) |
| `status [LAB...]` | Estado (`en ejecución`, `detenido`, `unhealthy`...), salud de cada contenedor, URL y consumo actual |
| `logs LAB [SERVICIO] [-f] [-n N]` | Registros de un laboratorio o de un servicio (`edge`, `db`, `www`...). `-f` sigue la salida; `-n` indica las líneas (100 por defecto) |
| `diagnose` | Informe del entorno: SO, hipervisores, Docker, memoria, interfaces, validez de la configuración, dependencias y estado. No incluye secretos |
| `network-check [LAB...]` | Pruebas de aislamiento (ver [configuración de red](../networking/README.md#6-qué-se-comprueba-en-cada-arranque)) |
| `config show` | Configuración efectiva |

### Ciclo de vida

| Comando | Qué hace |
|---|---|
| `install [LAB...]` | Descarga las imágenes fijadas por digest, los recursos con SHA-256 y, en Linux con VirtualBox, automatiza la red y el paso de la VM de Kali (ver abajo) |
| `start [LAB...]` | Comprobaciones, arranque y verificación (ver abajo) |
| `stop [LAB...]` | Detiene los contenedores. Los datos se conservan |
| `restart [LAB...]` | `stop` + `start` conservando los datos, también en modo efímero |
| `reset-data [LAB...]` | **Destructivo.** Elimina los contenedores y volúmenes del laboratorio y lo vuelve a arrancar desde el estado inicial |
| `reset [LAB...]` | **Destructivo.** Además, borra el estado generado (`state/<lab>.env`, `state/<lab>/`), vuelve a ejecutar `install` (incluyendo la comprobación de Kali) y arranca |
| `update --check [LAB...]` | Consulta si hay versiones nuevas publicadas. No cambia nada |
| `update [LAB...]` | Aplica el conjunto de versiones de `config/versions.json`, vuelve a ejecutar `install` y ofrece recrear los labs en marcha |

Ver [restauración](restauracion.md) y [actualizaciones](actualizaciones.md).

### Configuración (`config/local.json`)

| Comando | Ejemplo |
|---|---|
| `config set-port LAB ENDPOINT PUERTO` | `./manager config set-port webgoat webwolf 9091` |
| `config set-persistence LAB persistent\|ephemeral` | `./manager config set-persistence dvwa ephemeral` |
| `config set-resources LAB SERVICIO [--cpus N] [--memory M]` | `./manager config set-resources webgoat webgoat --memory 2g` |
| `config set-timezone ZONA` | `./manager config set-timezone Europe/Madrid` (o `auto`) |
| `config firewall-spec` | Muestra en JSON las reglas del Firewall de Windows que corresponden a la configuración actual. Lo usa el instalador de Windows |
| `config set-network ...` | Lo usa el instalador; no lo necesitas a mano. `--nat-interface virbr0` (o `""` para quitarlo) registra el bridge NAT de Kali en KVM |

Cada cambio se valida antes de guardarse:
- puertos entre 1024 y 65535 y sin repetir entre laboratorios;
- memoria en formato `512m` o `2g`;
- CPU mayor que 0 y como máximo 64.

Si el laboratorio está en marcha, el gestor avisa de que hay que aplicar el cambio con `./manager restart LAB`.

`config/defaults.json` no se edita. Lo que configuras queda en `config/local.json`, que no se versiona.

La zona horaria solo afecta a WebGoat. Con `auto` se toma de `/etc/localtime`.

### Opciones globales

- `--yes`: responde "sí" a todas las confirmaciones, incluidas las destructivas. **Nunca** se salta una comprobación de seguridad. En `install`, propaga `ASSUME_YES=1` a las fases que invoca.
- `--accept-port-suggestions` (en `start`, `restart`, `reset-data` y `reset`): acepta el puerto alternativo propuesto (ver abajo).

## 2. Menú interactivo

`./manager` sin argumentos (o `./manager menu`) abre un menú con las operaciones habituales:

| Opción | Acción |
|---|---|
| 1 | Estado de los laboratorios |
| 2 / 3 / 4 | Iniciar / detener / reiniciar |
| 5 | Ver registros |
| 6 | Restaurar datos (`reset-data`) |
| 7 | Reconstruir desde cero (`reset`) |
| 8 | Descargar o verificar imágenes (`install`) y paso guiado de la VM de Kali |
| 9 | Comprobar el aislamiento de red |
| 10 | Diagnóstico completo |
| 11 | Cambiar el puerto de un laboratorio |
| 12 | Cambiar el modo de persistencia |
| 13 | Comprobar actualizaciones (sin aplicar) |
| 0 | Salir |

Si un cambio de puerto no es válido, el menú lo revierte y no deja nada a medias.

## 3. Qué hace `install`

El ciclo de instalación implementado en el gestor (`lifecycle.py`) automatiza la preparación completa del laboratorio y de la máquina atacante en Linux con VirtualBox:

1. **Descarga y verificación de imágenes Docker:**
   - Consulta las imágenes fijadas por digest en `config/versions.json` para cada laboratorio solicitado y ejecuta `docker pull`.
2. **Descarga y verificación de recursos adicionales:**
   - Descarga recursos estáticos externos (como el archivo LDIF de Mutillidae) y valida su integridad mediante suma de verificación SHA-256.
3. **Paso de la VM de Kali (`_kali_vm_step`):**
   Tras descargar los contenedores, el gestor evalúa el entorno de virtualización:
   - **Aprovisionamiento automático de red:** Si la plataforma no está definida en `config/local.json` (`platform is None`), el gestor ejecuta automáticamente `scripts/linux/install.sh --phase network --hypervisor virtualbox --yes`. Al terminar con éxito, recarga dinámicamente la configuración en caliente (`self.cfg = Config()`) sin requerir intervención manual previa.
   - **Comprobación de plataforma y dependencias:** Valida que la plataforma activa sea `linux-virtualbox` y que el binario `VBoxManage` esté presente en el anfitrión. En otras plataformas (ej. KVM o Windows) o si falta VirtualBox, muestra un aviso informativo y continúa sin bloquear el proceso.
   - **Detección de interactividad:** Comprueba si se dispone de terminal interactivo (`ui.interactive()`). En entornos desatendidos o scripts CI sin TTY, omite el paso con un aviso para evitar bloqueos.
   - **Propagación de `--yes`:** Si el gestor se ejecutó con `./manager --yes install`, transmite `ASSUME_YES=1` al instalador.
   - **Invocación desacoplada y tolerancia a fallos:** Lanza `scripts/linux/install.sh --phase kali-vm`.
     - Si el usuario cancela voluntariamente (código `5`), el gestor emite un aviso (`ui.warn`), pero **no interrumpe el éxito de la instalación**: los contenedores del laboratorio quedan listos para su uso.
     - Si ocurre algún error en la creación o verificación de la VM, el gestor avisa y sugiere el comando de diagnóstico (`--check`), manteniendo igualmente los laboratorios disponibles.

> Dado que `reset` y `update` ejecutan internamente `install`, ambos comandos se benefician automáticamente de esta verificación y orquestación.

## 4. Qué hace `start`

La misma secuencia, en diagrama: [arquitectura](../architecture/README.md#qué-hace-start). Los estados que muestra `status` y cómo se pasa de uno a otro: [estados de un laboratorio](../architecture/README.md#estados-de-un-laboratorio).

1. **Preflight (fail-closed):**
   - no estar en WSL;
   - Docker ≥ 28 y Compose ≥ 2.24;
   - plataforma configurada y coherente (por ejemplo, rechaza Docker Desktop en Linux);
   - la interfaz de laboratorio existe, tiene su IP y no hay solapamientos;
   - el firewall: SHA-256 del ayudante instalado igual al del repositorio y `sudo pentestlab-fw verify`. Si faltan las reglas, ofrece aplicarlas.
2. **Dependencias:**
   - imágenes presentes por digest y recursos con su SHA-256 (si falta algo: `./manager install LAB`);
   - conflictos de puertos (ver abajo);
   - avisos de recursos ([recursos](recursos.md)).
3. **Política estática** sobre `docker compose config --format json`, es decir, sobre lo que Docker va a desplegar realmente:
   - solo el proxy `edge` publica puertos, solo por TCP y solo en `127.0.0.1` o la IP de laboratorio;
   - el proxy es el único en la red no interna, es `read_only`, tiene `cap_drop: [ALL]` y `dns: [127.0.0.1]`;
   - las demás redes son `internal: true`, con el driver `bridge`, sin IPv6 y con bridges `plabe-*`/`plabi-*`;
   - imágenes fijadas por digest y sin `latest`;
   - sin `privileged`, sin modos `host` (red, PID, IPC...), sin dispositivos, sin socket de Docker y con los *bind mounts* en solo lectura;
   - `no-new-privileges`, `restart: "no"` y límite de memoria en cada servicio.
4. `docker compose up --no-start` y **sondas reales** en cada red, antes de exponer nada.
5. `docker compose up --wait` (hasta 300 s, según `start_timeout_seconds`).
6. **Verificaciones posteriores:**
   - puertos publicados;
   - sockets en escucha;
   - las sondas otra vez, con la segmentación interna;
   - HTTP en `127.0.0.1` y en la IP de laboratorio.
7. **Ganchos de inicialización** (creación de la base de datos de DVWA y de Mutillidae, carga del LDAP) e impresión de las URL.

Si algo falla, ejecuta `docker compose down` del laboratorio, que **conserva los volúmenes**, y termina con un código distinto de 0.

## 5. Conflictos de puertos

Si un puerto configurado está ocupado en `127.0.0.1` o en la IP de laboratorio:

1. el gestor muestra el proceso que lo usa (si no puede identificarlo, sugiere `sudo ss -tlnp`);
2. propone el siguiente puerto libre;
3. en un terminal, pregunta si aceptas; sin terminal, solo lo acepta con `--accept-port-suggestions`;
4. si aceptas, guarda el puerto en `config/local.json` y las URL se actualizan.

Si no aceptas, termina con código 1 sin publicar nada. **Nunca cambia un puerto en silencio.**

Las conexiones en `TIME_WAIT` (por ejemplo, justo después de un `stop`) no cuentan como puerto ocupado.

## 6. Códigos de salida

| Código | Significado |
|---|---|
| 0 | Correcto |
| 1 | Error recuperable (el mensaje indica cómo solucionarlo) |
| 2 | Uso incorrecto |
| 3 | **Bloqueo de seguridad** (fail-closed). No hay opción para saltárselo |
| 4 | Falta una dependencia (Docker, Python, imágenes...) |
| 5 | Cancelado: confirmación rechazada, o falta de TTY sin `--yes` en una operación destructiva |

> En el paso de la VM de Kali durante `install`, si se cancela la confirmación interactiva (código 5), el gestor lo maneja como advertencia sin interrumpir el código de salida de los contenedores.

## 7. Archivos generados

| Archivo | Contenido |
|---|---|
| `config/local.json` | Tu configuración: red, puertos, persistencia, límites y zona horaria (aprovisionada automáticamente si falta al ejecutar `install`) |
| `state/<lab>.env` | Variables para Compose (imágenes, puertos, IP, límites). Se regenera en cada operación; no lo edites |
| `state/mutillidae/mutillidae.ldif` | LDIF oficial descargado y verificado |
| `state/installer.json` | Lo que ha creado el instalador (para `--phase uninstall`) |
| `state/kali-vm.json` | Registro de la VM de Kali creada o configurada en VirtualBox (`name`, `uuid`, `vdi`, `vbox`, `hostonly_iface`, `lab_ip`, `complete`). Generado durante el paso de la VM |
| `state/*.log` | Registros de las sesiones de prueba de red |
