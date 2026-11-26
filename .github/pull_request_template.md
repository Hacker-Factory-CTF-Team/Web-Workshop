<!--
Gracias por contribuir. Rellena lo que aplique y borra lo que no.
Guía: CONTRIBUTING.md · Invariantes de seguridad: docs/architecture/invariantes-seguridad.md
-->

## Qué resuelve

<!-- El problema o la necesidad, y por qué merece la pena. Enlaza la Issue: "Closes #123". -->

Closes #

## Qué cambia

<!-- Descripción de la implementación y de los archivos o componentes afectados. -->

## Pruebas realizadas

<!-- Marca solo lo que hayas ejecutado de verdad e indica el entorno (distribución, hipervisor, versión de Docker). -->

- [ ] `python3 -m unittest discover -s tests -t .`
- [ ] `./manager start` y `./manager network-check` con los laboratorios afectados
- [ ] Pruebas con paquetes reales: `kali-probe.sh` (Kali) y/o `sudo tests/network/linux-netns.sh test` (LAN emulada)
- [ ] Sesión completa sin VM: `bash tests/network/linux-validation-session.sh`
- [ ] ShellCheck / PSScriptAnalyzer (cambios en scripts)
- [ ] Solo documentación: he comprobado los enlaces y que lo descrito coincide con el código

Entorno:

## Seguridad

<!-- Ver docs/architecture/invariantes-seguridad.md -->

- [ ] El cambio **no debilita ninguna invariante de seguridad**, o lo explico aquí y está justificado en un ADR
- [ ] No añade puertos publicados, redes no internas, salida a Internet ni servicios de administración
- [ ] Las imágenes o recursos nuevos están fijados por digest / SHA-256 en `config/versions.json`
- [ ] No añade dependencias externas de Python ni secretos al repositorio

<!-- Si cambia scripts/linux/pentestlab-fw.sh, indica que hay que reinstalarlo:
     scripts/linux/install.sh --phase firewall -->

## Documentación

- [ ] He actualizado la documentación afectada (o no hace falta)
- [ ] Lo que marco como *probado* lo he ejecutado; lo demás queda como *no probado*
