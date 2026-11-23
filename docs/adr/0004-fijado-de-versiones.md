# ADR 0004: fijado de versiones por tag y digest

- **Estado:** aceptada
- **Fecha:** 2026-11-22

## Contexto

El laboratorio debe ser reproducible: todos los participantes deben tener las mismas versiones, que son las que se validaron. Tiene que funcionar sin Internet después de la instalación y no debe cambiar por sorpresa.

Los tags de Docker son mutables. `latest` cambia sin aviso, y una aplicación vulnerable a propósito puede cambiar de comportamiento, de puertos o de usuario entre versiones.

Particularidades de cada proyecto:
- **DVWA** no publica versiones: solo `latest` y tags con el commit corto;
- **Mutillidae** necesita un LDIF que no está en sus imágenes y tiene licencia GPL-3.0.

## Decisión

- Todas las imágenes se fijan en `config/versions.json` con **tag y digest**. El gestor las referencia como `repositorio:tag@sha256:...`, así que Docker usa el digest aunque el tag cambie.
- **DVWA** se fija por su tag de commit (`502ac15`) más el digest.
- **Nunca `latest`**. La política rechaza imágenes sin digest, con `latest` o sin tag.
- Los **recursos** externos se fijan por URL a un commit concreto, con SHA-256. El LDIF de Mutillidae se descarga en `./manager install`, se verifica y no se redistribuye.
- `config/versions.json` es el **conjunto de versiones probado**. Tiene un número de versión (`set_version`) y una fecha de validación (`validated_on`), y solo lo modifican los mantenedores tras seguir el [procedimiento de actualización](../management/actualizaciones.md).
- `./manager update --check` consulta los registros (Docker Hub y GHCR) con el patrón de tags de cada imagen. Es solo informativo. `./manager update` aplica el conjunto del repositorio, nunca la última versión publicada.
- Para nginx, solo se aceptan ramas estables (número menor par).

## Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| Solo tag | Mutable: dos participantes podrían tener imágenes distintas |
| Solo digest | Ilegible y difícil de mantener. El tag documenta qué versión es |
| `latest` con actualización automática | Contradice la reproducibilidad y la validación previa |
| Construir las imágenes localmente | Más tiempo de instalación, dependencia de Internet para compilar y builds difíciles de reproducir |
| Incluir el LDIF en el repositorio | Licencia GPL-3.0, distinta de la MIT del repositorio |

## Consecuencias

- Las actualizaciones de seguridad de las imágenes base no llegan solas. Para un laboratorio aislado y vulnerable a propósito es aceptable; `update --check` las hace visibles.
- Incorporar una versión exige el procedimiento de validación completo.
- Cada imagen se referencia por digest aunque `docker image ls` muestre su tag. Si alguien vuelve a etiquetar localmente una imagen con el mismo tag, no afecta al laboratorio.
