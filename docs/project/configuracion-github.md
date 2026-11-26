# Configuración de GitHub pendiente

Ajustes del repositorio que **no se pueden aplicar desde los archivos del repositorio** y que deben hacer los responsables con permisos de administración. Estado comprobado el 2026-11-26 con `gh repo view` y la API de GitHub (solo lectura):

| Ajuste | Estado actual |
|---|---|
| Issues | Habilitadas |
| Discussions | **Deshabilitadas** |
| Wiki | Deshabilitada |
| Reporte privado de vulnerabilidades | **Deshabilitado** |
| Protección de la rama `main` | **Ninguna** |
| Etiquetas | Solo las de GitHub por defecto |
| Descripción y *topics* del repositorio | Vacíos |

Los comandos de este documento **no se han ejecutado**: son la propuesta para que los responsables la apliquen. Necesitan `gh` autenticado con permisos de administración.

## 1. Reporte privado de vulnerabilidades

Es el canal que propone [SECURITY.md](../../SECURITY.md). Sin él, no existe ningún canal privado para comunicar un problema de seguridad.

- Web: *Settings → Code security → Private vulnerability reporting → Enable*.
- CLI:

  ```bash
  gh api -X PUT repos/Hacker-Factory-CTF-Team/Web-Workshop/private-vulnerability-reporting
  ```

Después, actualiza la sección *Cómo informar* de `SECURITY.md` para indicar que el canal está activo (botón *Report a vulnerability* en la pestaña *Security*) y quita el procedimiento provisional.

## 2. GitHub Discussions

**Recomendación: habilitarlas.** Las Issues sirven para solicitudes concretas con seguimiento; hoy no hay sitio para ideas preliminares, debates sobre temáticas de talleres o experiencias de participantes, y acabarían como Issues difíciles de cerrar.

- Web: *Settings → General → Features → Discussions*.

Categorías iniciales propuestas:

| Categoría | Formato | Para |
|---|---|---|
| Anuncios | *Announcement* (solo responsables) | Nuevas versiones del conjunto probado, fechas de talleres |
| Ideas | *Open-ended discussion* | Ideas preliminares de funcionalidades o laboratorios, antes de convertirlas en Issue |
| Preguntas | *Question and answer* | Dudas sobre la instalación o el uso que no son un error |
| Talleres | *Open-ended discussion* | Temáticas de futuros talleres y experiencias de sesiones pasadas |
| Arquitectura | *Open-ended discussion* | Debates de diseño antes de redactar un ADR |

Una vez habilitadas:

1. Añade este enlace a `.github/ISSUE_TEMPLATE/config.yml`, en `contact_links`:

   ```yaml
   - name: Ideas y preguntas (Discussions)
     url: https://github.com/Hacker-Factory-CTF-Team/Web-Workshop/discussions
     about: Para ideas preliminares, debates y dudas que todavía no son una solicitud concreta.
   ```

2. Actualiza el estado de Discussions en [el proyecto](README.md#3-dónde-participar), en [CONTRIBUTING](../../CONTRIBUTING.md) y en el [README](../../README.md#participar).

## 3. Etiquetas

Propuesta descrita en [el proyecto](README.md#5-etiquetas). Las existentes no se modifican.

```bash
R=Hacker-Factory-CTF-Team/Web-Workshop
gh label create "laboratorio"                    -R $R --color 1d76db --description "Propuesta o cambio de un laboratorio"
gh label create "seguridad"                      -R $R --color b60205 --description "Afecta a las invariantes de seguridad"
gh label create "prioridad: alta"                -R $R --color d93f0b --description "Prioridad alta"
gh label create "prioridad: baja"                -R $R --color c2e0c6 --description "Prioridad baja"
gh label create "estado: pendiente de revisión"  -R $R --color fbca04 --description "Pendiente de que la revisen los responsables"
gh label create "estado: necesita información"   -R $R --color f9d0c4 --description "Falta información para evaluarla"
gh label create "estado: aceptada"               -R $R --color 0e8a16 --description "Aceptada; puede implementarse"
gh label create "estado: pospuesta"              -R $R --color bfdadc --description "Se retomará más adelante"
for a in "gestor" "red y firewall" "laboratorios" "instaladores" "kali" "windows" "ci y pruebas"; do
  gh label create "área: $a" -R $R --color 5319e7 --description "Área: $a"
done
```

## 4. Protección de la rama `main`

Hoy cualquiera con permiso de escritura puede publicar directamente en `main`. Recomendación, mediante *Settings → Rules → Rulesets* (o *Branches → Branch protection rules*):

- exigir Pull Request antes de fusionar, con al menos **una aprobación**;
- exigir que pasen los *checks* del CI: `lint`, `unit (3.10)`, `unit (3.12)`, `unit (3.13)` e `integration`;
- impedir *force push* y el borrado de la rama.

Cuando esté configurado, actualiza la sección de revisión de [CONTRIBUTING](../../CONTRIBUTING.md#6-revisión), que ahora indica que no hay protección.

## 5. CODEOWNERS (cuando haya responsables designados)

Un archivo `.github/CODEOWNERS` pediría revisión automática a los responsables de las partes sensibles. No se ha creado porque el repositorio no identifica a sus responsables. Rutas candidatas:

```text
# Ejemplo: sustituye @usuario por los responsables reales
/scripts/linux/pentestlab-fw.sh   @usuario
/src/pentestlab/policy.py         @usuario
/src/pentestlab/isolation.py      @usuario
/labs/_common/                    @usuario
/config/versions.json             @usuario
/.github/workflows/               @usuario
```

Combinado con la protección de rama (*Require review from Code Owners*), garantiza que ningún cambio en estas rutas se fusione sin su revisión.

## 6. Descripción y *topics*

Ayudan a encontrar el repositorio y a entender qué es desde la portada de la organización:

```bash
gh repo edit Hacker-Factory-CTF-Team/Web-Workshop \
  --description "Laboratorio local y aislado para el taller de seguridad web de Hackers Factory: aplicaciones vulnerables en Docker y Kali Linux" \
  --add-topic security --add-topic pentesting --add-topic web-security --add-topic docker --add-topic workshop
```
