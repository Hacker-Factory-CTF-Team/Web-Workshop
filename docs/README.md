# Documentación técnica

Documentación del laboratorio local de pentesting web. Para empezar, lee el [README principal](../README.md): tiene el tutorial completo de instalación, uso y desinstalación. Aquí está el detalle de cada parte.

La documentación es solo técnica. No incluye soluciones, walkthroughs ni pistas sobre las vulnerabilidades de las aplicaciones.

| Tema | Documento |
|---|---|
| **Instalación** | [Índice de instalación](installation/README.md) |
| | [Linux por distribución](installation/linux.md) |
| | [KVM/QEMU y VM de Kali](installation/kvm.md) |
| | [VirtualBox](installation/virtualbox.md) |
| | Windows 11: pendiente (se documentará al final, marcado *no probado*) |
| **Red** | [Configuración de red](networking/README.md) |
| | [Firewall en Linux (`pentestlab-fw`)](networking/firewall-linux.md) |
| **Kali** | [Preparación de Kali y kit de herramientas](kali/preparacion.md) |
| **Gestión** | [Uso del gestor](management/gestor.md) |
| | [Recursos y límites](management/recursos.md) |
| | [Restauración de laboratorios](management/restauracion.md) |
| | [Actualización de aplicaciones](management/actualizaciones.md) |
| **Aplicaciones** | [DVWA](labs/dvwa.md) · [Juice Shop](labs/juice-shop.md) · [WebGoat + WebWolf](labs/webgoat.md) · [Mutillidae II](labs/mutillidae.md) |
| **Pruebas** | [Cómo se prueba el laboratorio](testing/pruebas.md) |
| **Problemas** | [Resolución de problemas](troubleshooting/README.md) |
| **Compatibilidad** | [Matriz de compatibilidad](compatibilidad.md) |
| **Decisiones** | [ADR 0001: arquitectura de red](adr/0001-arquitectura-proxy-l4-redes-internas.md) |
| | [ADR 0002: salida del proxy y DNS](adr/0002-salida-del-proxy-firewall-y-dns.md) |
| | [ADR 0003: gestor en Python estándar](adr/0003-gestor-python-biblioteca-estandar.md) |
| | [ADR 0004: fijado de versiones](adr/0004-fijado-de-versiones.md) |
