# ADR 0003: gestor en Python con solo la biblioteca estándar

- **Estado:** aceptada
- **Fecha:** 2026-11-22

## Contexto

El gestor debe:
- funcionar en Linux y en Windows 11 con la misma lógica;
- ofrecer CLI y menú interactivo;
- ejecutar comprobaciones de red con sockets, analizar JSON de `docker compose config` y consultar registros de imágenes.

Los participantes del taller no deberían tener que instalar dependencias adicionales ni entornos virtuales, y no se quiere duplicar lógica entre scripts.

## Decisión

- **Python ≥ 3.10, solo con la biblioteca estándar**: `argparse`, `json`, `subprocess`, `socket`, `ipaddress`, `urllib`, `hashlib`...
- El código está en el paquete `src/pentestlab/`. No se llama `manager/`, porque chocaría con el lanzador `./manager`.
- **Lanzadores finos por plataforma**:
  - `./manager` en Bash, que comprueba la versión de Python;
  - `manager.ps1` en Windows.
- **Instaladores nativos**: `scripts/linux/install.sh` (Bash) y `scripts/windows/install.ps1` (PowerShell). Solo hacen lo que exige el sistema: crear redes del hipervisor, instalar el firewall, etc. El resto lo delegan en el gestor.
- Todos los mensajes al usuario están en español, con una línea "Cómo solucionarlo" y códigos de salida estables.

## Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| Bash + PowerShell con la lógica duplicada | Dos implementaciones que divergen. Probar las comprobaciones de red en PowerShell es más difícil |
| Python con dependencias (click, rich, docker SDK) | Exige pip o un entorno virtual en cada equipo. Añade cadena de suministro y versiones que gestionar |
| Go o Rust compilados | Habría que publicar binarios por plataforma y montar un proceso de build. Más difícil de auditar para los participantes |
| SDK de Docker en lugar de la CLI | Dependencia externa. La política se aplica sobre la salida de `docker compose config`, que es lo que Compose despliega de verdad |

## Consecuencias

- Python 3.10 es un requisito en el anfitrión. Está disponible en las distribuciones soportadas y es fácil de instalar en Windows.
- Las pruebas (`unittest`) tampoco necesitan dependencias. El CI las ejecuta con Python 3.10, 3.12 y 3.13.
- La interacción con Docker se hace con la CLI, así que los cambios en su salida JSON exigen mantenimiento (por ejemplo, el estado de salud de los contenedores parados).
