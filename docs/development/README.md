# Guía de desarrollo

Para quien va a modificar el gestor, los laboratorios, los scripts o las pruebas. Antes de empezar, lee la [arquitectura](../architecture/README.md) y las [invariantes de seguridad](../architecture/invariantes-seguridad.md). El flujo de trabajo con GitHub (Issues, ramas y Pull Requests) está en [CONTRIBUTING](../../CONTRIBUTING.md).

## 1. Entorno de desarrollo

No todo el trabajo necesita el laboratorio completo. Elige el nivel que corresponda a tu cambio:

| Para... | Necesitas |
|---|---|
| Documentación | Git y un editor |
| Código Python del gestor y pruebas unitarias | Git y Python ≥ 3.10. Sin dependencias: solo la biblioteca estándar |
| Pruebas de política sobre los `compose.yaml` reales (`tests/security/`) | Además, la CLI `docker` con el plugin `docker compose`. No crea contenedores |
| Arrancar laboratorios, `network-check` y pruebas de red | Un anfitrión Linux preparado como indica la [instalación](../installation/README.md), con root para los niveles 4 y 5 |
| Scripts de Windows | Windows 11 con Docker Desktop y VirtualBox (**nunca probado**; ver [windows.md](../installation/windows.md)) |
| Lint como el CI | ShellCheck y, para los `.ps1`, PowerShell 7 con PSScriptAnalyzer |

### Obtener el código

```bash
git clone https://github.com/Hacker-Factory-CTF-Team/Web-Workshop.git
cd Web-Workshop
```

Si no tienes permiso de escritura en el repositorio, haz antes un *fork* en GitHub y clona tu copia ([CONTRIBUTING](../../CONTRIBUTING.md#3-flujo-de-trabajo)).

### Validación rápida

Estos comandos no necesitan root, red ni laboratorios en marcha, y son los mismos que ejecuta el job `lint`/`unit` del CI:

```bash
python3 -m unittest discover -s tests -t .                      # pruebas unitarias y de política
python3 -m compileall -q src tests                              # sintaxis Python
for f in $(git ls-files '*.json'); do python3 -m json.tool "$f" > /dev/null || echo "JSON inválido: $f"; done
for f in $(git ls-files '*.sh') manager; do head -n1 "$f" | grep -q bash && bash -n "$f"; done   # sintaxis Bash
```

ShellCheck, con la misma severidad y la misma lista de archivos que el CI:

```bash
shellcheck --severity=warning --external-sources $(git ls-files '*.sh') manager
```

Sin instalarlo, con la imagen oficial ([pruebas](../testing/pruebas.md#7-calidad-del-código)).

El CI usa Python 3.10 como mínimo de sintaxis: no uses construcciones más recientes (por ejemplo, `type X = ...` de 3.12 o los *f-strings* anidados de 3.12).

## 2. Mapa del repositorio

```text
manager, manager.ps1         lanzadores del gestor (Linux / Windows)
src/pentestlab/              gestor: un módulo por responsabilidad (ver arquitectura)
config/defaults.json         valores por defecto (no se editan a mano)
config/versions.json         conjunto de versiones probado: imágenes (tag + digest) y recursos (URL + SHA-256)
config/local.json            configuración de cada equipo (generada, no versionada)
labs/_common/edge/           proxy nginx L4 común y endurecido
labs/<lab>/                  lab.json, compose.yaml y edge.conf.stream-template de cada aplicación
scripts/common/lib.sh        utilidades Bash compartidas (mensajes, confirmaciones, lectura de config)
scripts/linux/               instalador por fases y firewall (pentestlab-fw.sh)
scripts/windows/             instalador por fases y prueba de red de Docker Desktop
kali/                        kit de herramientas para la VM de Kali (install.sh + modules/*.conf)
tests/unit/                  pruebas sin Docker ni red (todo lo externo se simula)
tests/security/              política aplicada a los compose reales con `docker compose config`
tests/network/               pruebas con paquetes reales (Kali, LAN emulada, sesión completa)
docs/                        documentación (índice en docs/README.md)
.github/                     CI, plantillas de Issues y de Pull Requests
state/                       generado (no versionado): <lab>.env, recursos descargados, registros
```

Responsabilidad de cada módulo de `src/pentestlab/`: [arquitectura, sección 2](../architecture/README.md#módulos-del-gestor).

## 3. Dónde hacer cada cambio

| Quiero... | Archivos | Documentación que hay que actualizar | Pruebas mínimas |
|---|---|---|---|
| Añadir un laboratorio | `labs/<lab>/`, `config/versions.json` y varios scripts | Ver la [guía específica](nuevo-laboratorio.md) | Las de la guía |
| Cambiar un comando o una opción del gestor | `cli.py`, `lifecycle.py`, `menu.py` si aparece en el menú | [gestor.md](../management/gestor.md) y, si es habitual, el README | Nivel 1 y prueba nueva en `tests/unit/` |
| Cambiar la política estática | `policy.py` | [Invariantes](../architecture/invariantes-seguridad.md), [gestor.md](../management/gestor.md#3-qué-hace-start) | Nivel 1, incluido `tests/security/` |
| Cambiar las sondas de aislamiento | `isolation.py` | [Configuración de red](../networking/README.md#6-qué-se-comprueba-en-cada-arranque) | Niveles 1 y 2 |
| Cambiar el firewall de Linux | `scripts/linux/pentestlab-fw.sh` | [firewall-linux.md](../networking/firewall-linux.md) | Niveles 1 a 4 (o 5) y ShellCheck. Hay que reinstalarlo (abajo) |
| Cambiar las reglas del Firewall de Windows | `isolation.py` (`windows_firewall_spec`), `scripts/windows/install.ps1` | [windows.md](../installation/windows.md#5-reglas-del-firewall-de-windows) | `tests/unit/test_winfw.py`, PSScriptAnalyzer |
| Cambiar el instalador | `scripts/linux/install.sh`, `scripts/windows/install.ps1` | [installation/](../installation/README.md), [desinstalación](../management/desinstalacion.md) | Niveles 1 a 4 (o 5) y ShellCheck/PSScriptAnalyzer |
| Actualizar la versión de una aplicación | `config/versions.json` | Ficha en `docs/labs/` y [actualizaciones](../management/actualizaciones.md#3-imágenes-y-digest-actuales) | [Procedimiento de actualización](../management/actualizaciones.md#2-para-mantenedores-incorporar-una-versión-nueva) |
| Añadir una herramienta al kit de Kali | `kali/modules/NN-id.conf` | [preparacion.md](../kali/preparacion.md#módulos) | `kali/install.sh --list` y `--install <módulo>` en Kali |
| Cambiar límites por defecto | `labs/<lab>/lab.json` (`services`) | [recursos.md](../management/recursos.md) | Nivel 1 y arranque del laboratorio |

Los niveles de prueba están definidos en [pruebas](../testing/pruebas.md).

### Cambios en `pentestlab-fw.sh`

`./manager start` compara el SHA-256 de `/usr/local/sbin/pentestlab-fw` con el de `scripts/linux/pentestlab-fw.sh` y se bloquea si no coinciden. Después de editar el script:

```bash
scripts/linux/install.sh --phase firewall    # reinstala la copia y reaplica las reglas
```

Cualquier persona que actualice el repositorio tendrá que hacer lo mismo: indícalo en la descripción del Pull Request.

## 4. Convenciones

### Idioma

- **Español** en la documentación, los mensajes al usuario (CLI, menú, instaladores y kit de Kali), las plantillas de GitHub y los mensajes de commit.
- **Inglés** en los comentarios del código, los *docstrings* y los nombres de identificadores, como en el código existente.

### Python (`src/pentestlab/`, `tests/`)

- Python ≥ 3.10 y **solo la biblioteca estándar** ([ADR 0003](../adr/0003-gestor-python-biblioteca-estandar.md)). Una dependencia externa necesita un ADR.
- `from __future__ import annotations` y anotaciones de tipos, como el resto de módulos.
- Los errores previstos se lanzan como `LabError` (o `DependencyError`, `SecurityBlock`, `Aborted`) con un `hint` que diga cómo solucionarlo. Los códigos de salida de `errors.py` son estables: no cambies su significado.
- Lo que afecta al aislamiento es **fail-closed**: si no se puede comprobar, se bloquea (`SecurityBlock`).
- Docker se usa a través de su CLI (`docker.py`, `Manager.compose`), no de un SDK.
- Solo `config.py` escribe `config/local.json`. El estado generado va a `state/`.

### Pruebas

- `unittest` de la biblioteca estándar; los archivos se llaman `tests/unit/test_<módulo>.py`.
- Usa `TempConfigMixin` (`tests/helpers.py`) para no leer ni escribir el `config/local.json` real.
- Las pruebas unitarias no usan Docker ni la red: simula lo externo con `unittest.mock`.
- Cada error corregido lleva su prueba de regresión; cada regla nueva de la política, un caso en `tests/unit/test_policy.py` y, si es posible, un *override* hostil en `tests/security/test_compose_policy.py`.

### Bash

- `#!/usr/bin/env bash` y `set -euo pipefail` (o `set -uo pipefail` si el script gestiona sus errores, como `kali/install.sh`).
- Sin avisos de ShellCheck con `--severity=warning`.
- Los mensajes de error siguen el patrón de `scripts/common/lib.sh`: `die "qué pasó" "cómo solucionarlo" [código]`.
- Los instaladores se ejecutan como el usuario normal y usan `sudo` solo en los pasos que lo necesitan. Todo lo que crean se registra en `state/installer.json` para poder deshacerlo.

### PowerShell

- Compatible con Windows PowerShell 5.1 (`#Requires -Version 5.1`) y con PowerShell 7.
- Sin avisos de PSScriptAnalyzer con severidad *Warning*.

### Compose y laboratorios

- Ver la [guía para añadir un laboratorio](nuevo-laboratorio.md) y las [invariantes](../architecture/invariantes-seguridad.md). La política rechaza la mayoría de errores, pero no todos.

### Documentación

- Escribe para quien la va a usar: participantes, colaboradores o responsables ([índice](../README.md)).
- **Solo técnica**: no incluyas soluciones, *walkthroughs* ni pistas sobre las vulnerabilidades de las aplicaciones.
- Marca como **probado** solo lo que hayas ejecutado de verdad, con fecha y entorno; el resto, como *no probado*. Actualiza la [matriz de compatibilidad](../compatibilidad.md) cuando corresponda.
- Enlaces relativos entre documentos. Los diagramas (Mermaid o texto) deben reflejar el comportamiento real del código.
- **No cambies de sitio los documentos existentes sin revisar el código**: el instalador y el gestor imprimen rutas como `docs/installation/kvm.md` o `docs/management/actualizaciones.md` en sus mensajes. Busca antes con `git grep -n "docs/"`.
- Si un cambio de código altera lo que hace un comando, actualiza su documentación en el mismo Pull Request.

## 5. Ejecutar el laboratorio mientras desarrollas

- Usa siempre `./manager`. No ejecutes `docker compose up` en `labs/<lab>/`: te saltarías las comprobaciones y faltarían las variables de `state/<lab>.env`.
- `./manager network-check` repite las comprobaciones de aislamiento sobre los laboratorios en marcha.
- `tests/network/linux-validation-session.sh` cambia tu `config/local.json` a una red emulada; guarda una copia y explica cómo restaurarla ([detalle](../testing/pruebas.md#5-validación-completa-sin-vm)).
- Para volver a un estado conocido: [resolución de problemas](../troubleshooting/README.md#volver-a-un-estado-conocido).
