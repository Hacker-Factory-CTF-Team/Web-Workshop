# Documentación

Índice de toda la documentación del laboratorio, organizada por perfil y por finalidad. Para una visión general y el inicio rápido, empieza por el [README principal](../README.md).

La documentación es solo técnica: no incluye soluciones, *walkthroughs* ni pistas sobre las vulnerabilidades de las aplicaciones.

## Participantes: instalar y usar el laboratorio

### Primeros pasos

| Documento | Contenido |
|---|---|
| [Instalación: orden y fases](installation/README.md) | Qué instalar y en qué orden; qué hace cada fase del instalador de Linux |
| [Linux por distribución](installation/linux.md) | Requisitos que comprueba el gestor, Docker por distribución, firewall e imágenes |
| [KVM/QEMU y VM de Kali](installation/kvm.md) | Red de laboratorio y NAT con libvirt; creación de la VM (**probado**) |
| [VirtualBox en Linux](installation/virtualbox.md) | Red Host-only y VM de Kali (*no probado*) |
| [Windows 11](installation/windows.md) | Docker Desktop, VirtualBox, reglas del firewall y riesgos residuales (*no probado*) |
| [Preparación de Kali](kali/preparacion.md) | Red de la VM, URL de acceso y kit de herramientas `kali/install.sh` |

### Guía de uso

| Documento | Contenido |
|---|---|
| [Uso del gestor](management/gestor.md) | Todos los comandos, el menú, qué hace `start`, conflictos de puertos y códigos de salida |
| [Restauración](management/restauracion.md) | Persistencia, `reset-data`, `reset` y copias de seguridad manuales |
| [Recursos y límites](management/recursos.md) | CPU, memoria y disco; cómo ajustarlos |
| [Actualizaciones](management/actualizaciones.md) | Cómo se actualizan las aplicaciones (usuarios y mantenedores) |
| [Desactivar y desinstalar](management/desinstalacion.md) | Pausar, quitar el firewall, desinstalar y qué se instala dónde |
| [Resolución de problemas](troubleshooting/README.md) | Síntomas habituales y su solución |

### Aplicaciones

[DVWA](labs/dvwa.md) · [Juice Shop](labs/juice-shop.md) · [WebGoat + WebWolf](labs/webgoat.md) · [Mutillidae II](labs/mutillidae.md): versión fijada, acceso, credenciales iniciales, servicios, requisitos y limitaciones.

## Infraestructura: red, firewall y pruebas

| Documento | Contenido |
|---|---|
| [Configuración de red](networking/README.md) | Subredes, NIC NAT de Kali, puertos, redes Docker, DNS y qué se comprueba en cada arranque |
| [Firewall en Linux (`pentestlab-fw`)](networking/firewall-linux.md) | Reglas una por una, verificación, no persistencia y convivencia con otros firewalls |
| [Cómo se prueba el laboratorio](testing/pruebas.md) | Niveles de prueba, de las unitarias a los paquetes reales desde Kali y la LAN |
| [Matriz de compatibilidad](compatibilidad.md) | Qué se ha probado, dónde, con qué versiones, y qué no está soportado |

## Colaboradores y desarrolladores

| Documento | Contenido |
|---|---|
| [CONTRIBUTING](../CONTRIBUTING.md) | Tipos de contribución, flujo de trabajo, Pull Requests y revisión |
| [Arquitectura](architecture/README.md) | Componentes, módulos del gestor, topología de red, ciclo de vida de `start` y limitaciones (con diagramas) |
| [Invariantes de seguridad](architecture/invariantes-seguridad.md) | Garantías que ninguna contribución puede debilitar, dónde se aplican y cómo se comprueban |
| [Guía de desarrollo](development/README.md) | Entorno, validación, mapa del repositorio, dónde hacer cada cambio y convenciones |
| [Añadir un laboratorio](development/nuevo-laboratorio.md) | Criterios, archivos, versiones, puntos que actualizar a mano y validación |
| Decisiones de diseño (ADR) | [0001: arquitectura de red](adr/0001-arquitectura-proxy-l4-redes-internas.md) · [0002: salida del proxy y DNS](adr/0002-salida-del-proxy-firewall-y-dns.md) · [0003: gestor en Python estándar](adr/0003-gestor-python-biblioteca-estandar.md) · [0004: fijado de versiones](adr/0004-fijado-de-versiones.md) |

## Proyecto y responsables

| Documento | Contenido |
|---|---|
| [El proyecto](project/README.md) | Objetivos, principios, canales de participación, evaluación de propuestas y etiquetas |
| [Configuración de GitHub pendiente](project/configuracion-github.md) | Ajustes que deben aplicar los responsables: reporte privado de vulnerabilidades, Discussions, etiquetas, protección de rama |
| [Política de seguridad](../SECURITY.md) | Qué comunicar y cómo |

## Organización de los archivos

Las carpetas de `docs/` se agrupan por tema (`installation/`, `management/`, `networking/`...), no por perfil. **No se renombran ni se mueven**: el instalador y el gestor imprimen algunas de estas rutas en sus mensajes (por ejemplo, `docs/installation/kvm.md` o `docs/management/actualizaciones.md`). Antes de mover un documento, busca sus referencias con `git grep -n "docs/"`.
