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
    subgraph REPO["Repositorio (versionado)"]
        direction TB
        INST["Instaladores<br/>scripts/linux/install.sh<br/>scripts/windows/install.ps1"]:::mgr
        LAUNCH["Lanzadores<br/>manager · manager.ps1"]:::mgr
        PKG["Gestor<br/>src/pentestlab"]:::mgr
        CFG["config/defaults.json<br/>config/versions.json"]:::cfg
        LABS["labs/LAB/<br/>lab.json · compose.yaml"]:::cfg
        FWSRC["scripts/linux/<br/>pentestlab-fw.sh"]:::cfg
    end
    subgraph LOCALG["Generado localmente"]
        direction TB
        LOCAL["config/local.json"]:::gen
        ENV["state/LAB.env"]:::gen
    end
    subgraph SYS["Sistema anfitrión"]
        direction TB
        HV["Red de laboratorio<br/>libvirt · Host-only"]:::host
        FWBIN["/usr/local/sbin/<br/>pentestlab-fw"]:::fw
        DOCKER[("Docker Engine<br/>Docker Desktop")]:::host
    end

    INST -- "config set-network<br/>install · diagnose" --> LAUNCH
    LAUNCH --> PKG
    CFG --> PKG
    LABS --> PKG
    PKG -- "lee y escribe" --> LOCAL
    PKG -- genera --> ENV
    INST -- crea --> HV
    INST -- "copia como root" --> FWBIN
    FWSRC -. "SHA-256 en cada start" .-> FWBIN
    PKG -- "sudo verify · apply" --> FWBIN
    PKG -- "CLI docker compose<br/>--env-file state/LAB.env" --> DOCKER

    classDef kali fill:#ede9fe,stroke:#5b21b6,color:#111827
    classDef mgr fill:#dbeafe,stroke:#1e40af,color:#111827
    classDef host fill:#dbeafe,stroke:#1e40af,color:#111827
    classDef cfg fill:#e0f2fe,stroke:#0369a1,color:#111827
    classDef gen fill:#f8fafc,stroke:#64748b,stroke-dasharray:4 3,color:#111827
    classDef fw fill:#dcfce7,stroke:#166534,color:#111827
    classDef edge fill:#fef3c7,stroke:#b45309,color:#111827
    classDef vuln fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef net fill:#fff7ed,stroke:#c2410c,color:#111827
    classDef ext fill:#f3f4f6,stroke:#4b5563,color:#111827
    style REPO fill:none,stroke:#1e40af
    style LOCALG fill:none,stroke:#64748b,stroke-dasharray:6 4
    style SYS fill:none,stroke:#166534
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

### Instalación guiada (Linux con KVM)

El instalador solo hace lo que exige el sistema y delega el resto en el gestor ([ADR 0003](../adr/0003-gestor-python-biblioteca-estandar.md)). Con VirtualBox, la fase `network` usa `VBoxManage` en lugar de `virsh` y no registra red NAT.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant I as install.sh
    participant V as libvirt (virsh)
    participant M as ./manager
    participant F as pentestlab-fw
    participant D as Docker

    U->>I: scripts/linux/install.sh --hypervisor kvm
    Note over I: Fase detect: distribución, Docker, hipervisores, redes
    Note over U,I: Antes de cada fase (deps, network, firewall,<br/>images, validate) pregunta si se ejecuta
    rect rgba(59, 130, 246, 0.08)
        Note over I,M: Fase network
        I->>V: net-define pentestlab si no existe, y net-start (sudo)
        I->>M: config set-network --platform linux-kvm --ip --interface virbr-plab
        I->>V: red default (NAT): iniciar y autostart, si aceptas
        I->>M: config set-network --nat-interface virbr0
    end
    rect rgba(34, 197, 94, 0.08)
        Note over I,F: Fase firewall
        I->>F: copia root:root 0755 en /usr/local/sbin
        opt Si aceptas
            I->>I: /etc/sudoers.d/pentestlab-fw (solo verify y apply)
        end
        opt Si la interfaz y Docker están disponibles
            I->>F: apply + verify
        end
    end
    rect rgba(245, 158, 11, 0.08)
        Note over I,D: Fases images y validate
        I->>M: install all
        M->>D: docker pull de cada imagen por digest
        M->>M: descarga y verifica recursos (SHA-256)
        I->>M: diagnose
    end
    Note over I: Todo lo creado queda en state/installer.json<br/>para --phase uninstall
```

## 3. Topología de red y límites de confianza

Tres zonas con distinto nivel de confianza: la VM de Kali (atacante), el anfitrión y cada laboratorio, que se trata como **comprometido**. En verde, las conexiones permitidas; en rojo punteado, las que bloquean las redes internas de Docker y el firewall del anfitrión.

```mermaid
flowchart LR
    NET(["LAN / Internet"]):::ext
    subgraph KALI["VM de Kali · atacante"]
        direction TB
        K0["eth0<br/>red de laboratorio"]:::kali
        K1["eth1<br/>NAT"]:::kali
    end
    subgraph HOST["Anfitrión · confiable"]
        direction TB
        LIP["virbr-plab / vboxnetN<br/>IP de laboratorio"]:::host
        LO["127.0.0.1"]:::host
        SVC["Servicios del anfitrión<br/>SSH, DNS, ..."]:::host
        subgraph LAB["Laboratorio plab-LAB · se asume comprometido"]
            direction LR
            EDGE["edge<br/>nginx L4"]:::edge
            APP["Aplicación"]:::vuln
            AUX[("BD / LDAP")]:::vuln
        end
    end

    K0 -- "TCP a los puertos de los labs<br/>DHCP · ping" --> LIP
    LIP -- "DNAT de Docker" --> EDGE
    LO -- "puerto publicado" --> EDGE
    EDGE -- front --> APP
    APP -- "data · ldap" --> AUX
    K1 -- NAT --> NET

    NET -. "LAN → IP de laboratorio" .-x LIP
    K0 -. "otros servicios<br/>del anfitrión" .-x SVC
    LAB -. "contenedores → anfitrión" .-x SVC
    LAB -. "salida a LAN e Internet *" .-x NET

    classDef kali fill:#ede9fe,stroke:#5b21b6,color:#111827
    classDef mgr fill:#dbeafe,stroke:#1e40af,color:#111827
    classDef host fill:#dbeafe,stroke:#1e40af,color:#111827
    classDef cfg fill:#e0f2fe,stroke:#0369a1,color:#111827
    classDef gen fill:#f8fafc,stroke:#64748b,stroke-dasharray:4 3,color:#111827
    classDef fw fill:#dcfce7,stroke:#166534,color:#111827
    classDef edge fill:#fef3c7,stroke:#b45309,color:#111827
    classDef vuln fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef net fill:#fff7ed,stroke:#c2410c,color:#111827
    classDef ext fill:#f3f4f6,stroke:#4b5563,color:#111827
    linkStyle 0,1,2,3,4,5 stroke:#15803d,stroke-width:2px
    linkStyle 6,7,8,9 stroke:#b91c1c,stroke-width:1.5px
    style KALI fill:none,stroke:#5b21b6
    style HOST fill:none,stroke:#1e40af
    style LAB fill:none,stroke:#b91c1c,stroke-dasharray:6 4
```

\* En Windows, el proxy `edge` sí tiene salida: es un riesgo residual aceptado ([ADR 0002](../adr/0002-salida-del-proxy-firewall-y-dns.md)). Además, el anfitrión no enruta hacia la LAN ni hacia Internet nada de lo que Kali envía por `eth0`. La segmentación detallada de cada laboratorio está en [configuración de red](../networking/README.md#4-redes-docker-de-cada-laboratorio).

Tres capas se complementan:

1. **Docker.** Las aplicaciones y sus servicios auxiliares solo están en redes `internal: true`. El proxy `edge` es el único contenedor en una red no interna y el único que publica puertos, solo en `127.0.0.1` y en la IP de laboratorio.
2. **Firewall del anfitrión.** Cubre lo que Docker no puede: la salida del proxy, el acceso de los contenedores al anfitrión, la LAN hacia la IP de laboratorio y que el anfitrión enrute el tráfico de Kali. En Linux es `pentestlab-fw`; en Windows, las reglas del grupo `PentestLab`, con [riesgos residuales documentados](../installation/windows.md#7-diferencias-y-riesgos-residuales).
3. **Comprobaciones del gestor.** Política estática y conexiones reales antes y después de cada arranque.

El detalle de subredes, bridges, puertos y DNS está en [configuración de red](../networking/README.md).

## 4. Ciclo de vida de los laboratorios

### Qué hace `start`

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant M as ./manager
    participant F as pentestlab-fw
    participant D as Docker
    participant P as Sonda busybox

    U->>M: ./manager start LAB
    rect rgba(34, 197, 94, 0.08)
        Note over M,F: Preflight de la plataforma (fail-closed)
        M->>M: WSL, Docker ≥ 28, Compose ≥ 2.24, plataforma, interfaz e IP
        M->>F: sudo verify (antes compara el SHA-256 con el repositorio)
        Note right of F: En Windows se comparan las reglas<br/>del grupo PentestLab
        opt Reglas ausentes
            M->>U: ¿Aplicarlas?
            M->>F: sudo apply + verify
        end
    end
    break Fallo crítico
        M-->>U: SecurityBlock · código 3
    end
    M->>D: imágenes por digest y recursos con SHA-256
    break Falta alguna
        M-->>U: DependencyError · código 4
    end
    M->>M: conflictos de puertos, validación, avisos de recursos
    M->>D: docker compose config --format json
    M->>M: política estática
    rect rgba(239, 68, 68, 0.07)
        Note over M,P: Si algo falla desde aquí: docker compose down (conserva los volúmenes)
        opt Modo efímero y laboratorio parado
            M->>D: down --volumes
        end
        M->>D: up --no-start (crea redes y contenedores)
        M->>P: docker run en cada red del laboratorio
        P-->>M: salida, acceso al anfitrión, otros labs y segmentación: todo debe estar cerrado
        M->>D: up --wait (healthchecks)
        M->>D: puertos publicados (y sockets en escucha en el anfitrión)
        M->>P: sondas otra vez
        M->>M: HTTP en 127.0.0.1 y en la IP de laboratorio (informativo)
        M->>D: ganchos post_start (exec o HTTP)
    end
    M-->>U: URL de acceso
```

Si falla una comprobación de seguridad (preflight, política, sondas o verificación posterior), el código de salida es 3; si el laboratorio no llega a estar sano o falla un gancho, es 1. Cualquier excepción a partir de `up --no-start`, incluida la interrupción con Ctrl+C, ejecuta `docker compose down --remove-orphans` antes de propagarse (`lifecycle.py`, `_start_one`). Los volúmenes se conservan.

Las operaciones destructivas (`reset-data`, `reset`) piden escribir el identificador del laboratorio y después pasan por el mismo `start` completo. `restart` es `stop` + `start` conservando los datos. Detalle de cada comando: [uso del gestor](../management/gestor.md).

### Estados de un laboratorio

El estado no se guarda en ningún sitio: `./manager status` lo deduce de los contenedores del proyecto `plab-<lab>` (`Manager.state` en `lifecycle.py`), sin contar los de inicialización ni las sondas.

```mermaid
stateDiagram-v2
    state "no desplegado" as ND
    state "arrancando" as ARR
    state "en ejecución" as RUN
    state "unhealthy" as UNH
    state "parcial" as PAR
    state "detenido" as STOP

    [*] --> ND
    ND --> ARR: start
    ARR --> RUN: healthchecks correctos
    ARR --> ND: fallo (compose down)
    RUN --> UNH: falla un healthcheck
    UNH --> RUN: se recupera
    RUN --> STOP: stop
    UNH --> STOP: stop
    PAR --> STOP: stop
    STOP --> ARR: start, restart
    STOP --> ND: reset-data, reset

    note right of PAR
        Estado derivado: unos contenedores
        en marcha y otros no
    end note
    note right of STOP
        reset-data y reset también actúan sobre
        un laboratorio en marcha: borran contenedores
        y volúmenes y vuelven a arrancar
    end note
```

## 5. Flujo de configuración

```mermaid
flowchart LR
    subgraph IN["Entradas"]
        direction TB
        DEF["config/defaults.json"]:::cfg
        LOC["config/local.json"]:::gen
        VER["config/versions.json"]:::cfg
        LJ["labs/*/lab.json"]:::cfg
    end
    CLI["config set-*<br/>instaladores"]:::mgr
    MERGE["Config()<br/>fusión y validación"]:::mgr
    ENVF["state/LAB.env"]:::gen
    COMPOSE["docker compose<br/>-f labs/LAB/compose.yaml"]:::host

    CLI -- "valida y guarda" --> LOC
    DEF --> MERGE
    LOC --> MERGE
    VER --> MERGE
    LJ --> MERGE
    MERGE -- "render_env()" --> ENVF
    ENVF -- "--env-file" --> COMPOSE

    classDef kali fill:#ede9fe,stroke:#5b21b6,color:#111827
    classDef mgr fill:#dbeafe,stroke:#1e40af,color:#111827
    classDef host fill:#dbeafe,stroke:#1e40af,color:#111827
    classDef cfg fill:#e0f2fe,stroke:#0369a1,color:#111827
    classDef gen fill:#f8fafc,stroke:#64748b,stroke-dasharray:4 3,color:#111827
    classDef fw fill:#dcfce7,stroke:#166534,color:#111827
    classDef edge fill:#fef3c7,stroke:#b45309,color:#111827
    classDef vuln fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef net fill:#fff7ed,stroke:#c2410c,color:#111827
    classDef ext fill:#f3f4f6,stroke:#4b5563,color:#111827
    style IN fill:none,stroke:#64748b
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
