# Añadir un laboratorio

Guía técnica para incorporar una aplicación vulnerable nueva. Antes de implementar nada, **abre una Issue con la plantilla *Propuesta de laboratorio*** para que los responsables valoren si encaja en el taller ([proceso](../project/README.md#4-cómo-se-evalúan-las-propuestas)). Esta guía da por hecho que la propuesta está aceptada.

Usa como referencia el laboratorio existente más parecido:

| Si tu aplicación... | Mira |
|---|---|
| Tiene un único contenedor, sin datos persistentes | `labs/juice-shop/` |
| Tiene aplicación + base de datos y un gancho de inicialización | `labs/dvwa/` |
| Publica varios puertos, o necesita un inicializador de volumen | `labs/webgoat/` |
| Tiene varios servicios auxiliares, HTTPS y un recurso descargado | `labs/mutillidae/` |

## 1. Criterios previos

Antes de escribir el `compose.yaml`, comprueba que la aplicación:

- tiene **imagen oficial** publicada por su proyecto en Docker Hub o GHCR, con tags inmutables o al menos con digest estable. El gestor no construye imágenes ([ADR 0004](../adr/0004-fijado-de-versiones.md));
- **funciona sin Internet**. Lo que dependa de servicios externos se documenta como limitación; nunca se abre la salida ([invariante R9](../architecture/invariantes-seguridad.md#2-exposición-y-red));
- se puede servir a través de un **proxy TCP** (L4) en los mismos puertos que verá el navegador, o tolera que la URL use la IP de laboratorio (como WebGoat);
- no necesita `privileged`, capacidades añadidas, modos `host`, dispositivos ni el socket de Docker;
- tiene una licencia compatible con su uso en el taller. Los recursos que no se puedan redistribuir bajo MIT se descargan en `install` y se verifican por SHA-256, como el LDIF de Mutillidae;
- cabe en los recursos de un participante ([recursos](../management/recursos.md)).

## 2. Archivos del laboratorio

Crea `labs/<id>/` con tres archivos. `<id>` es el identificador que se usará en la CLI (`./manager start <id>`), en minúsculas y con guiones.

### 2.1 `lab.json`

Lo lee `config.py`. Los laboratorios se descubren recorriendo `labs/*/lab.json`: no hay que registrarlo en ningún otro sitio del gestor.

```json
{
  "id": "ejemplo",
  "name": "Ejemplo",
  "description": "Descripción corta (tecnologías)",
  "project": "plab-ejemplo",
  "images": ["EDGE_IMAGE", "EJEMPLO_IMAGE"],
  "assets": [],
  "endpoints": {
    "http": {"default_port": 8090, "env": "EJEMPLO_PORT", "scheme": "http", "path": "/", "label": "Ejemplo"}
  },
  "services": {
    "edge": {"cpus": 0.25, "memory": "64m", "cpus_env": "EDGE_CPUS", "memory_env": "EDGE_MEMORY"},
    "app": {"cpus": 1.0, "memory": "512m", "cpus_env": "EJEMPLO_CPUS", "memory_env": "EJEMPLO_MEMORY"}
  },
  "persistence": {"default": "persistent", "supported": ["persistent", "ephemeral"]},
  "post_start": []
}
```

*Ejemplo ilustrativo: el laboratorio `ejemplo` no existe.*

| Campo | Notas |
|---|---|
| `project` | Debe ser `plab-<id>` (lo comprueba `tests/unit/test_labs.py`) |
| `images` | Variables definidas en `config/versions.json`. Incluye siempre `EDGE_IMAGE` y, si hay un inicializador, `HELPER_IMAGE` |
| `assets` | Claves de `assets` en `config/versions.json` |
| `endpoints` | Un endpoint por puerto publicado. `env` es la variable que recibe el puerto en `state/<id>.env`. El puerto por defecto debe estar entre 1024 y 65535 y no coincidir con el de otro laboratorio (`config.validate`) |
| `services` | Los servicios con límites de CPU y memoria configurables. Sus nombres son los que acepta `./manager logs <id> <servicio>` y `config set-resources` |
| `persistence` | `supported` puede ser solo `["ephemeral"]` si la aplicación regenera sus datos al arrancar (Juice Shop). `note` explica el motivo al usuario |
| `post_start` | Ganchos que se ejecutan tras arrancar. `check` (opcional) es un comando por `docker compose exec`; si termina con 0, el gancho se omite. `run` es `{"type": "exec", "service", "command", "ok_exit_codes"}` o `{"type": "http", "endpoint", "path"}` (petición a `127.0.0.1`) |
| `prefer_lab_ip` | `true` si la aplicación construye enlaces absolutos y hay que usar la IP de laboratorio también desde el anfitrión (WebGoat) |

### 2.2 `compose.yaml`

Requisitos, casi todos comprobados por la [política](../architecture/invariantes-seguridad.md):

- `name: plab-<id>`;
- servicio `edge` que extiende `../_common/edge/edge.compose.yaml`, con:
  - `LAB_HTTP_PORT` en `environment` (lo usa su healthcheck) y una variable `LAB_*` por cada puerto adicional;
  - la plantilla montada en `/etc/nginx/templates/lab.conf.stream-template:ro`;
  - cada puerto publicado **dos veces**, en `127.0.0.1` y en `${LAB_HOST_IP:?...}`, con el mismo número dentro y fuera;
  - `networks: [edge, front]`;
- el resto de servicios:
  - `image: ${VARIABLE:?}`, nunca una imagen literal (`test_labs.py`);
  - solo redes internas;
  - `restart: "no"`, `security_opt: ["no-new-privileges:true"]`, `cpus` y `mem_limit` desde las variables de `lab.json` (con el valor por defecto como respaldo) y `pids_limit`;
  - un `healthcheck`, porque `start` espera con `docker compose up --wait`;
  - la etiqueta `org.pentestlab.role` (`app`, `db`...). Los servicios de ejecución única llevan `init` y `network_mode: none`;
- redes:
  - `edge` con `driver: bridge` y bridge `plabe-<abreviatura>`;
  - las demás con `internal: true`, `driver: bridge` y bridge `plabi-<abreviatura>-<letra>`;
  - **15 caracteres como máximo** en el nombre del bridge (límite de Linux);
  - una red por función (`front` para proxy ↔ aplicación, `data` para aplicación ↔ base de datos...), de forma que el proxy no vea los servicios auxiliares;
- volúmenes de datos con la etiqueta `org.pentestlab.data: "true"`.

No publiques puertos de servicios auxiliares, no añadas consolas de administración y no montes rutas del anfitrión salvo en solo lectura.

### 2.3 `edge.conf.stream-template`

La imagen oficial de nginx la procesa con `envsubst` al arrancar. Solo están definidas las variables `LAB_*` del servicio `edge`, así que las variables propias de nginx (`$upstream_app`) llegan intactas.

```nginx
# Rendered by the nginx entrypoint (envsubst). Only ${LAB_*} vars are set.
server {
    listen ${LAB_HTTP_PORT};
    set $upstream_app app:80;
    proxy_pass $upstream_app;
}
```

`proxy_pass` con una variable obliga a nginx a resolver el nombre en cada conexión con el DNS de Docker (`resolver` de `labs/_common/edge/nginx.conf`). Así el proxy arranca aunque la aplicación aún no exista y sigue funcionando si la aplicación se recrea con otra IP. Si la aplicación sirve HTTPS, se reenvía como TCP sin terminar TLS (ver `labs/mutillidae/`).

## 3. Versiones fijadas

Añade cada imagen nueva a `config/versions.json` siguiendo el [procedimiento de actualización](../management/actualizaciones.md#2-para-mantenedores-incorporar-una-versión-nueva):

```json
"EJEMPLO_IMAGE": {
  "repository": "organizacion/ejemplo",
  "tag": "v1.2.3",
  "digest": "sha256:...",
  "registry": "dockerhub",
  "tag_pattern": "^v\\d+\\.\\d+\\.\\d+$",
  "upstream": "https://github.com/organizacion/ejemplo",
  "used_by": ["ejemplo"]
}
```

*Ejemplo ilustrativo.* `registry` es `dockerhub` o `ghcr` (los que consulta `updates.py`). Incrementa `set_version` y actualiza `validated_on`.

## 4. Puntos que hay que actualizar a mano

El gestor descubre el laboratorio automáticamente, pero hay listas fijas en otros sitios. Búscalas con:

```bash
git grep -nE "4280|juice-shop|mutillidae" -- src scripts kali tests
```

| Archivo | Qué contiene | Qué hacer |
|---|---|---|
| `src/pentestlab/cli.py` | Texto de ayuda de `LAB` con la lista de laboratorios | Añadir el identificador |
| `src/pentestlab/config.py` | Alias de nombres (`juice` → `juice-shop`...) | Opcional |
| `kali/install.sh` | `PORTS`: puertos que comprueba `--check` | Añadir los puertos por defecto (y el esquema si es HTTPS) |
| `tests/network/kali-probe.sh` | `LAB_PORTS`: puertos que deben responder desde Kali y únicos abiertos en `--full-scan` | Añadir los puertos por defecto (y el esquema si es HTTPS) |
| `tests/network/linux-netns.sh` | Puertos internos que se prueban en las IP de los contenedores | Añadir los puertos internos de los servicios nuevos |
| `tests/unit/test_config.py` | Conjunto esperado de puertos por defecto | Añadir los del laboratorio |
| `tests/unit/test_winfw.py` | Conjunto esperado de puertos del Firewall de Windows | Ídem |

Si no actualizas `test_config.py` y `test_winfw.py`, `python3 -m unittest` fallará y te lo recordará. Los scripts de Kali y de red no tienen pruebas automáticas: revísalos tú.

## 5. Documentación

| Documento | Qué añadir |
|---|---|
| `docs/labs/<id>.md` | Ficha con la misma estructura que las existentes: descripción, versión fijada, acceso, credenciales iniciales, servicios y redes, requisitos, inicialización y limitaciones. **Sin soluciones ni pistas** |
| [README](../../README.md) | Filas en las tablas de aplicaciones y de acceso |
| [docs/README.md](../README.md) | Enlace a la ficha |
| [Configuración de red](../networking/README.md) | Puertos (sección 3) y redes con sus bridges (sección 4) |
| [Recursos](../management/recursos.md) | Límites por defecto, consumo medido en reposo y totales |
| [Restauración](../management/restauracion.md) | Volúmenes de datos |
| [Actualizaciones](../management/actualizaciones.md#3-imágenes-y-digest-actuales) | Imágenes del conjunto actual |
| [Preparación de Kali](../kali/preparacion.md#2-red) | URL de acceso y número de puertos |
| [Uso del gestor](../management/gestor.md#1-comandos) | Identificador en la lista de `LAB` |

## 6. Validación

Como mínimo, antes de abrir el Pull Request:

```bash
python3 -m unittest discover -s tests -t .      # incluye la política sobre el compose nuevo
./manager install <id>
./manager start <id>                             # comprobaciones fail-closed completas
./manager network-check <id>
./manager restart <id>                           # los datos persisten (si es persistente)
./manager --yes reset-data <id>                  # vuelve al estado inicial y los ganchos funcionan
./manager logs <id>
./manager status                                 # consumo en reposo para la ficha
```

Y después, con todos los laboratorios en marcha, las pruebas con paquetes reales: `kali-probe.sh` desde Kali y `sudo tests/network/linux-netns.sh test` (o la sesión completa, nivel 5). Detalle en [pruebas](../testing/pruebas.md).

Comprueba también a mano que la aplicación carga desde Kali y desde el anfitrión y que las credenciales iniciales funcionan. En el Pull Request, indica qué has probado y en qué entorno ([plantilla](../../.github/pull_request_template.md)).
