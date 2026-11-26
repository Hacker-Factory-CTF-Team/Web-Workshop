# Arquitectura

Visión de conjunto de los componentes del laboratorio, cómo se relacionan y por qué están organizados así. Describe la implementación actual; las decisiones de fondo están en los [ADR](#6-decisiones-de-diseño-adr) y las garantías que no se pueden debilitar, en las [invariantes de seguridad](invariantes-seguridad.md).

## 1. Objetivo del diseño

El laboratorio despliega aplicaciones **vulnerables a propósito** en el equipo de cada participante. Todo el diseño parte de una premisa: **las aplicaciones se van a comprometer**. Por eso:

- solo deben ser accesibles desde la VM de Kali y desde el propio anfitrión;
- no deben tener salida a Internet ni a la LAN, ni verse entre ellas;
- un error de configuración debe impedir el despliegue (*fail-closed*), nunca exponer el laboratorio.

## 2. Componentes

```mermaid
flowchart LR
    subgraph repo["Repositorio"]
        LAUNCH["manager / manager.ps1<br/>(lanzadores)"]
        PKG["src/pentestlab<br/>(gestor en Python)"]
        CFG["config/defaults.json<br/>config/versions.json"]
        LOCAL["config/local.json<br/>(generado)"]
        LABS["labs/LAB/<br/>lab.json, compose.yaml,<br/>plantilla del proxy"]
        ENV["state/LAB.env<br/>(generado)"]
        INST["scripts/linux/install.sh<br/>scripts/windows/install.ps1"]
        FWSRC["scripts/linux/pentestlab-fw.sh"]
    end
    DOCKER[("Docker Engine /<br/>Docker Desktop")]
    FWBIN["/usr/local/sbin/pentestlab-fw<br/>(copia instalada, root)"]
    HV["Red de laboratorio<br/>(libvirt o Host-only)"]

    LAUNCH --> PKG
    PKG -- lee --> CFG
    PKG -- lee y escribe --> LOCAL
    PKG -- lee --> LABS
    PKG -- genera --> ENV
    PKG -- "docker / docker compose (CLI)" --> DOCKER
    PKG -- "sudo verify / apply" --> FWBIN
    INST -- "config set-network, install, diagnose" --> LAUNCH
    INST -- crea --> HV
    INST -- "copia (fase firewall)" --> FWBIN
    FWSRC -. "SHA-256 comparado en cada start" .- FWBIN
```

| Componente | Ubicación | Responsabilidad |
|---|---|---|
| Lanzadores | `manager`, `manager.ps1` | Comprueban Python ≥ 3.10 y ejecutan `python -m pentestlab` con `src/` en el `PYTHONPATH` |
| Gestor | `src/pentestlab/` | Toda la lógica: CLI, menú, ciclo de vida, política, sondas, firewall de Windows. Solo biblioteca estándar ([ADR 0003](../adr/0003-gestor-python-biblioteca-estandar.md)) |
| Definición de laboratorios | `labs/<lab>/` | `lab.json` (metadatos que lee el gestor), `compose.yaml` (servicios y redes) y `edge.conf.stream-template` (escuchas del proxy) |
| Proxy común | `labs/_common/edge/` | Servicio `edge` endurecido que cada laboratorio extiende (`extends`) y `nginx.conf` en modo `stream` (L4) |
| Configuración | `config/` | `defaults.json` (no se edita), `versions.json` (conjunto de versiones probado) y `local.json` (configuración de cada equipo, no versionada) |
| Estado generado | `state/` | `<lab>.env` para Compose, recursos descargados (LDIF de Mutillidae), `installer.json` y registros. No se versiona |
| Instaladores | `scripts/linux/install.sh`, `scripts/windows/install.ps1` | Lo que exige el sistema: red del hipervisor, firewall, dependencias. El resto lo delegan en el gestor |
| Firewall de Linux | `scripts/linux/pentestlab-fw.sh` | Cadenas iptables propias del laboratorio ([detalle](../networking/firewall-linux.md)) |
| Kit de Kali | `kali/` | Instalación y verificación de herramientas dentro de la VM ([detalle](../kali/preparacion.md#3-kit-de-herramientas-kaliinstallsh)) |
| Pruebas | `tests/` | Unitarias, de política sobre los compose reales y de red con paquetes reales ([detalle](../testing/pruebas.md)) |

### Módulos del gestor

| Módulo | Qué contiene |
|---|---|
| `cli.py` | Analizador de argumentos (`argparse`) y despacho de comandos, incluidos los subcomandos `config` |
| `menu.py` | Menú interactivo; llama a las mismas operaciones que la CLI |
| `lifecycle.py` | Clase `Manager`: `install`, `start`, `stop`, `restart`, `reset-data`, `reset`, `update`, `status`, `logs`, `network-check`, `diagnose` y ganchos `post_start` |
| `config.py` | Carga y fusiona `defaults.json` + `local.json`, lee `labs/*/lab.json`, valida y genera `state/<lab>.env`. Es el único módulo que escribe `config/local.json` |
| `policy.py` | Política estática sobre la salida de `docker compose config --format json` |
| `isolation.py` | Comprobaciones con conexiones reales (sondas busybox), puertos publicados, sockets, HTTP, verificación de `pentestlab-fw` y especificación/verificación de las reglas del Firewall de Windows |
| `docker.py` | Envoltorio fino de la CLI de Docker y comprobación de versiones mínimas |
| `hostenv.py` | Consultas de solo lectura al sistema: SO, interfaces, memoria, propietario de un puerto, zona horaria, hipervisores |
| `ports.py` | Detección de puertos ocupados y propuesta de alternativas |
| `resources.py` | Avisos de CPU y memoria antes de arrancar y consumo actual |
| `updates.py` | `update --check`: consulta Docker Hub y GHCR sin aplicar nada |
| `ui.py`, `errors.py` | Mensajes al usuario (en español, con "Cómo solucionarlo") y códigos de salida |

## 3. Topología de red

```mermaid
flowchart LR
    NET(["LAN / Internet"])
    subgraph VM["VM de Kali"]
        ETH0["eth0<br/>red de laboratorio"]
        ETH1["eth1<br/>NAT"]
    end
    subgraph HOST["Anfitrión"]
        LABIF["virbr-plab / vboxnetN<br/>IP de laboratorio"]
        LO["127.0.0.1"]
        subgraph PRJ["Proyecto Compose plab-LAB (uno por laboratorio)"]
            EDGE["edge: nginx L4<br/>red edge, bridge plabe-*<br/>(no interna)"]
            APP["aplicación<br/>red front, bridge plabi-*-f<br/>(interna)"]
            AUX[("base de datos / LDAP<br/>redes data, ldap: plabi-*<br/>(internas)")]
        end
    end

    ETH0 -- "solo los puertos de los laboratorios" --> LABIF
    LABIF -- "DNAT de Docker" --> EDGE
    LO -- "DNAT de Docker" --> EDGE
    EDGE -- "front" --> APP
    APP -- "data / ldap" --> AUX
    ETH1 --> NET
    NET -. "bloqueado por el firewall" .-> LABIF
    EDGE -. "sin salida (Linux: pentestlab-fw)" .-> NET
```

Tres capas se complementan:

1. **Docker.** Las aplicaciones y sus servicios auxiliares solo están en redes `internal: true`. El proxy `edge` es el único contenedor en una red no interna y el único que publica puertos, solo en `127.0.0.1` y en la IP de laboratorio.
2. **Firewall del anfitrión.** Cubre lo que Docker no puede: la salida del proxy, el acceso de los contenedores al anfitrión, la LAN hacia la IP de laboratorio y que el anfitrión enrute el tráfico de Kali. En Linux es `pentestlab-fw`; en Windows, las reglas del grupo `PentestLab`, con [riesgos residuales documentados](../installation/windows.md#7-diferencias-y-riesgos-residuales).
3. **Comprobaciones del gestor.** Política estática y conexiones reales antes y después de cada arranque.

El detalle de subredes, bridges, puertos y DNS está en [configuración de red](../networking/README.md).

## 4. Ciclo de vida de `start`

```mermaid
flowchart TD
    A["./manager start LAB..."] --> B{"Preflight:<br/>WSL, Docker ≥ 28, Compose ≥ 2.24,<br/>plataforma, interfaz de laboratorio,<br/>firewall verificado"}
    B -- "fallo crítico" --> X1["SecurityBlock<br/>código 3"]
    B -- ok --> C{"Imágenes por digest<br/>y recursos con SHA-256"}
    C -- faltan --> X2["DependencyError<br/>código 4"]
    C -- ok --> D["Conflictos de puertos<br/>(propone, nunca cambia en silencio)"]
    D --> E["Validación de la configuración<br/>y avisos de recursos"]
    E --> F{"Política estática sobre<br/>docker compose config"}
    F -- incumple --> X1
    F -- cumple --> G["Modo efímero: down --volumes<br/>(si el lab estaba parado)"]
    G --> H["docker compose up --no-start"]
    H --> I{"Sondas reales en cada red<br/>(antes de exponer nada)"}
    I -- fallo --> R["docker compose down<br/>(conserva los volúmenes)"]
    I -- ok --> J{"docker compose up --wait<br/>(healthchecks)"}
    J -- "no llega a sano" --> R
    J -- ok --> K{"Verificación posterior:<br/>puertos publicados, sockets,<br/>sondas otra vez"}
    K -- fallo --> R
    K -- ok --> L["HTTP en 127.0.0.1 e IP de laboratorio<br/>(informativo)"]
    L --> M{"Ganchos post_start<br/>(BD de DVWA y Mutillidae, LDAP)"}
    M -- fallo --> R
    M -- ok --> N["URL de acceso"]
    R --> X3["Se propaga el error:<br/>código 3 si falla una sonda o la verificación,<br/>1 en el resto de casos"]
```

Cualquier excepción a partir de `up --no-start`, incluida la interrupción con Ctrl+C, ejecuta `docker compose down --remove-orphans` antes de propagarse (`lifecycle.py`, `_start_one`). Los volúmenes se conservan.

Las operaciones destructivas (`reset-data`, `reset`) piden escribir el identificador del laboratorio y después pasan por el mismo `start` completo. `restart` es `stop` + `start` conservando los datos. Detalle de cada comando: [uso del gestor](../management/gestor.md).

## 5. Flujo de configuración

```mermaid
flowchart LR
    DEF["config/defaults.json"] --> MERGE["Config()<br/>(fusión)"]
    LOC["config/local.json"] --> MERGE
    LJ["labs/*/lab.json"] --> MERGE
    VER["config/versions.json"] --> MERGE
    MERGE --> RENDER["render_env()"]
    RENDER --> ENVF["state/LAB.env"]
    ENVF --> COMPOSE["docker compose<br/>--env-file state/LAB.env"]
    CLI["./manager config set-*<br/>instaladores"] -- "valida y guarda" --> LOC
```

- Los laboratorios se **descubren** recorriendo `labs/*/lab.json`. No hay un registro central.
- `state/<lab>.env` se regenera en cada operación con las imágenes (`repositorio:tag@digest`), puertos, IP de laboratorio, límites y zona horaria. Por eso los `compose.yaml` usan `${VAR:?}` y fallan si se ejecutan fuera del gestor.
- Solo `config/local.json` se escribe, siempre de forma atómica (archivo temporal + `os.replace`).

## 6. Decisiones de diseño (ADR)

| ADR | Decisión |
|---|---|
| [0001](../adr/0001-arquitectura-proxy-l4-redes-internas.md) | Proxy nginx L4 por laboratorio; aplicaciones solo en redes internas; publicación en `127.0.0.1` y en la IP de laboratorio |
| [0002](../adr/0002-salida-del-proxy-firewall-y-dns.md) | Firewall propio y verificado en el anfitrión; DNS del proxy a `127.0.0.1`; riesgos residuales en Windows |
| [0003](../adr/0003-gestor-python-biblioteca-estandar.md) | Gestor en Python con solo la biblioteca estándar; instaladores nativos finos |
| [0004](../adr/0004-fijado-de-versiones.md) | Imágenes fijadas por tag y digest; recursos por commit y SHA-256 |

Una propuesta que cambie alguna de estas decisiones debe añadir un ADR nuevo (`docs/adr/NNNN-titulo.md`, con las secciones *Contexto*, *Decisión*, *Alternativas descartadas* y *Consecuencias*) en lugar de reescribir el existente. Ver [CONTRIBUTING](../../CONTRIBUTING.md#decisiones-de-arquitectura).

## 7. Limitaciones conocidas

- **Windows no está probado.** La salida del proxy queda abierta con Docker Desktop y el acceso de los contenedores al anfitrión depende de Docker Desktop: el gestor lo muestra como aviso, no como fallo ([ADR 0002](../adr/0002-salida-del-proxy-firewall-y-dns.md)).
- **El firewall de Linux no persiste.** Tras reiniciar, nada está expuesto (ningún servicio arranca solo), pero en KVM Kali no tiene Internet hasta el siguiente `start`.
- **Solo Docker con backend `iptables`.** Docker rootless, Docker Desktop para Linux y el backend `nftables` se bloquean ([compatibilidad](../compatibilidad.md#no-soportado)).
- **El gestor no ve el tráfico de otras interfaces.** Las sondas se ejecutan dentro de Docker; lo que ve la LAN o Kali se comprueba con las [pruebas de red](../testing/pruebas.md) (niveles 3 a 5).
- **Algunos scripts asumen los puertos por defecto.** `tests/network/kali-probe.sh` comprueba siempre los 6 puertos por defecto y no tiene opción para otros; `kali/install.sh --check` admite `--ports`. Si cambias puertos con `set-port`, sus resultados no son fiables.
- **La interacción con Docker depende de la salida JSON de su CLI**, que puede cambiar entre versiones ([ADR 0003](../adr/0003-gestor-python-biblioteca-estandar.md#consecuencias)).
