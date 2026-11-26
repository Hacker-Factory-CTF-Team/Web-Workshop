# Invariantes de seguridad

Este documento recoge las propiedades de seguridad que el laboratorio mantiene hoy y que **ninguna contribución puede debilitar**. Es la lista de comprobación que usan quienes revisan un Pull Request.

> [!IMPORTANT]
> Una contribución no es válida solo porque funcione. También tiene que conservar estas garantías. Si un cambio necesita relajar alguna, hay que proponerlo antes en una Issue, justificarlo y registrarlo en un ADR nuevo.

Cada invariante indica **dónde se aplica** y **cómo se comprueba**. Lo que no se comprueba automáticamente aparece marcado como *convención*: la revisión humana es la única barrera.

## 1. Principios

1. **Las aplicaciones están comprometidas.** Se diseña como si cualquier contenedor de laboratorio estuviera bajo el control de quien lo ataca.
2. **Fail-closed.** Si una garantía no se puede comprobar, el gestor no despliega. Ninguna opción permite saltarse una comprobación de seguridad: `--yes` solo responde a confirmaciones (`errors.py`, `SecurityBlock`, código de salida 3).
3. **Se comprueba lo que se despliega.** La política se aplica sobre `docker compose config --format json` (el modelo final, tras interpolación y `extends`) y se complementa con conexiones reales, no solo con la lectura de archivos.
4. **Solo se afirma lo probado.** La documentación marca como *no probado* lo que no se ha ejecutado de verdad.

## 2. Exposición y red

| # | Invariante | Dónde se aplica | Cómo se comprueba |
|---|---|---|---|
| R1 | Solo el servicio `edge` publica puertos, solo TCP y solo en `127.0.0.1` o en la IP de laboratorio. Nunca en `0.0.0.0` ni `::` | `labs/*/compose.yaml`; `policy.py` | Política en cada `start`; `isolation.published_ports` y `listening_sockets` tras arrancar; `tests/security/test_compose_policy.py` (caso `0.0.0.0`) |
| R2 | Las aplicaciones y sus servicios auxiliares solo están en redes `internal: true`. `edge` es el único servicio en la red no interna `edge` | `compose.yaml`; `policy.py` | Política; sondas de salida a Internet en cada red (`isolation.network_probes`); test de política (caso `internal: true`) |
| R3 | Cada laboratorio tiene su propio proxy y sus propias redes. Ningún laboratorio alcanza a otro | `compose.yaml` (un proyecto `plab-<lab>` por laboratorio) | Sondas "aislamiento entre laboratorios" |
| R4 | Dentro de un laboratorio, cada servicio solo alcanza las redes que necesita: el proxy no ve la base de datos | Redes `front`, `data`, `ldap` | Sondas "segmentación interna" |
| R5 | Sin redes externas, solo el driver `bridge` y sin IPv6 | `policy.py` | Política |
| R6 | Los bridges se llaman `plabe-*` (proxy) o `plabi-*` (internas), con 15 caracteres como máximo. El prefijo `plab` está reservado: la interfaz de laboratorio y la NAT no pueden empezar por él | `compose.yaml`; `policy.py`; `config.py` (`validate`); `pentestlab-fw.sh` | Política; `tests/unit/test_labs.py`; `tests/unit/test_config.py` |
| R7 | El proxy usa `dns: ["127.0.0.1"]`: resuelve nombres internos, pero no externos ([ADR 0002](../adr/0002-salida-del-proxy-firewall-y-dns.md)) | `labs/_common/edge/edge.compose.yaml`; `policy.py` | Política; sonda DNS con el DNS real de cada red; `test_labs.py` (regresión) |
| R8 | El DHCP de la red de laboratorio no anuncia pasarela ni DNS: la ruta por defecto de Kali va por su NIC NAT | `scripts/linux/install.sh` (fase `network`), `scripts/windows/install.ps1` | `kali/install.sh --check`; `tests/network/kali-probe.sh` |
| R9 | Las aplicaciones no necesitan Internet. Si una función depende de un servicio externo, se documenta como limitación en su ficha; **nunca se abre la salida** | Fichas en `docs/labs/` | *Convención* (revisión) y sondas de salida |
| R10 | No se despliegan consolas de administración ni se publican servicios auxiliares (bases de datos, LDAP, phpMyAdmin...) | `compose.yaml` | R1 (solo `edge` publica) y *convención* para no añadir consolas |

## 3. Contenedores

| # | Invariante | Dónde se aplica | Cómo se comprueba |
|---|---|---|---|
| C1 | Sin `privileged`, sin modos `host` (`network_mode`, `pid`, `ipc`, `userns_mode`, `uts`, `cgroup`) y sin dispositivos | `policy.py` | Política; test de política (caso `privileged`) |
| C2 | Sin socket ni datos de Docker montados; los *bind mounts* son de solo lectura | `policy.py` | Política; test de política (caso `socket`) |
| C3 | `security_opt: no-new-privileges:true` en todos los servicios y sin perfiles `unconfined` | `compose.yaml`; `policy.py` | Política |
| C4 | `cap_add` solo `CHOWN`/`FOWNER` y solo en servicios con `network_mode: none` (el inicializador de volumen de WebGoat) | `policy.py` | Política |
| C5 | `restart: "no"`: tras reiniciar el anfitrión nada arranca sin pasar por las comprobaciones | `compose.yaml`; `policy.py` | Política |
| C6 | Límite de memoria en todo servicio con red | `compose.yaml`; `policy.py` | Política |
| C7 | El proxy es `read_only`, tiene `cap_drop: [ALL]` y corre como usuario no root (`101:101`) | `edge.compose.yaml`; `policy.py` | Política para `read_only` y `cap_drop`. El **usuario no root es *convención*:** la política no lo comprueba |
| C8 | Límite de PIDs en cada servicio | `compose.yaml` | *Convención*: la política no lo comprueba |
| C9 | Solo `edge` puede usar `extra_hosts` | `policy.py` | Política |

## 4. Firewall del anfitrión

| # | Invariante | Dónde se aplica | Cómo se comprueba |
|---|---|---|---|
| F1 | En Linux, `pentestlab-fw` solo crea y borra sus cadenas (`PLAB-FWD`, `PLAB-IN`, `PLAB-IN6`) y un salto a cada una. No vacía ni modifica otras reglas | `scripts/linux/pentestlab-fw.sh` | Revisión; niveles 3 a 5 de las [pruebas](../testing/pruebas.md) |
| F2 | Nada nuevo sale de un bridge `plab+`; los contenedores no abren conexiones al anfitrión; la IP de laboratorio solo se alcanza por la interfaz de laboratorio; Kali solo llega a los bridges `plabe+` | `pentestlab-fw.sh` ([reglas](../networking/firewall-linux.md#3-reglas)) | Sondas del gestor; `linux-netns.sh test`; `kali-probe.sh` |
| F3 | Antes de cada `start`: el SHA-256 de la copia instalada coincide con el del repositorio y `verify` compara las reglas **exactamente**, incluida su posición y `br_netfilter` | `isolation.linux_firewall`; `pentestlab-fw.sh verify` | Preflight de `start` y `network-check` |
| F4 | Las reglas de Linux no persisten; el gestor las reaplica antes de exponer nada | `pentestlab-fw.sh`; `lifecycle.preflight` | Preflight |
| F5 | La regla de sudoers opcional solo permite `pentestlab-fw verify` y `apply` | `install.sh` (fase `firewall`) | Revisión |
| F6 | En Windows, las reglas del grupo `PentestLab` se generan desde la configuración (`config firewall-spec`) y deben coincidir **exactamente** con las activas. Una regla de más, de menos o desfasada bloquea el arranque | `isolation.windows_firewall_spec`, `compare_windows_rules` | `tests/unit/test_winfw.py`; preflight en Windows |
| F7 | Los riesgos residuales aceptados (salida del proxy y acceso al anfitrión con Docker Desktop) se muestran como **aviso**. Convertir un fallo crítico en aviso es un cambio de seguridad | `isolation.network_probes` (`warning_only`) | Revisión; [ADR 0002](../adr/0002-salida-del-proxy-firewall-y-dns.md) |

## 5. Cadena de suministro

| # | Invariante | Dónde se aplica | Cómo se comprueba |
|---|---|---|---|
| S1 | Todas las imágenes se fijan por **tag y digest** en `config/versions.json`. Nunca `latest` ni imágenes sin tag | `versions.json`; `config.validate`; `policy.py` | Política; `test_labs.py` (las imágenes salen de variables `${VAR:?}`) |
| S2 | Los recursos externos se descargan de una URL fijada a un **commit** y se verifican por SHA-256. Si no coincide, no se usan | `versions.json` (`assets`); `lifecycle.fetch_asset` | En cada `install`; `asset_ok` en cada `start` |
| S3 | No se redistribuyen recursos con licencias incompatibles con MIT (el LDIF GPL-3.0 de Mutillidae se descarga) | `versions.json` | *Convención* |
| S4 | El gestor solo usa la biblioteca estándar de Python ([ADR 0003](../adr/0003-gestor-python-biblioteca-estandar.md)) | `src/pentestlab/` | *Convención*; el CI no instala dependencias |
| S5 | Las acciones de GitHub del CI están fijadas por SHA de commit y el workflow solo tiene `contents: read` | `.github/workflows/ci.yml` | Revisión |
| S6 | `config/versions.json` solo cambia tras el [procedimiento de actualización](../management/actualizaciones.md) | Proceso | Revisión |

## 6. Comportamiento del gestor

| # | Invariante | Dónde se aplica |
|---|---|---|
| G1 | Los laboratorios se manejan siempre con `./manager`. No se documentan ni se recomiendan atajos con `docker compose up` | Documentación; los `compose.yaml` fallan sin las variables de `state/<lab>.env` |
| G2 | Si un despliegue falla, se deshace (`docker compose down`) conservando los volúmenes | `lifecycle._start_one` |
| G3 | Nunca se cambia un puerto en silencio: el usuario lo acepta o pasa `--accept-port-suggestions` | `ports.resolve_conflicts`; `tests/unit/test_ports.py` |
| G4 | Las operaciones destructivas exigen escribir el identificador del laboratorio o `--yes` explícito; sin terminal, se niegan (código 5) | `ui.confirm_destructive` |
| G5 | Los errores dicen qué falló y cómo solucionarlo, sin trazas de Python para errores previstos | `errors.LabError` (`hint`) |
| G6 | `diagnose` no muestra secretos. Sí muestra información del equipo (SO, interfaces y sus IP), que el usuario debe revisar antes de publicarla | `lifecycle.diagnose` |
| G7 | Los instaladores se ejecutan como el usuario normal (rechazan `sudo`) y solo deshacen lo que registraron en `state/installer.json` | `install.sh`, `install.ps1` |
| G8 | Las pruebas no escriben en el repositorio ni en el `config/local.json` de quien las ejecuta | `tests/helpers.py` (`TempConfigMixin`) |

## 7. Credenciales

Las aplicaciones usan credenciales **por defecto y públicas** de sus propios proyectos (por ejemplo, la base de datos de DVWA o el administrador de LDAP de Mutillidae, en `compose.yaml` y `lab.json`). Son aceptables porque solo existen dentro de redes internas sin salida y forman parte del ejercicio. Reglas:

- no se añaden secretos reales (tokens, claves de API, contraseñas personales) al repositorio, ni siquiera para servicios externos que una aplicación necesite;
- no se publican puertos de servicios auxiliares para "facilitar" el acceso con esas credenciales;
- las credenciales que necesita el participante se documentan en la ficha del laboratorio.

## 8. Cómo verificar que un cambio no rompe nada

La tabla [Qué probar tras cada cambio](../testing/pruebas.md#8-qué-probar-tras-cada-cambio) indica las pruebas mínimas según lo que se modifique. Como regla general:

- **cualquier cambio en `src/`, `labs/` o `config/`:** `python3 -m unittest discover -s tests -t .`;
- **cualquier cambio que afecte a la red o al firewall:** además, `./manager network-check` y las pruebas con paquetes reales (niveles 3 y 4, o 5);
- **una prueba nueva por cada invariante nueva** y una prueba de regresión por cada fallo corregido, como hace el resto de la suite.

Si encuentras una forma de romper una de estas garantías en el código actual, no abras una Issue pública con los detalles: sigue la [política de seguridad](../../SECURITY.md).
