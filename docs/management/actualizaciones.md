# Actualización de aplicaciones

Las versiones de todas las imágenes y recursos están fijadas en `config/versions.json`, con tag y digest para cada imagen y URL y SHA-256 para cada recurso. Ese archivo es el **conjunto de versiones probado**: solo cambia cuando un mantenedor valida una versión nueva siguiendo este procedimiento. El motivo está en el [ADR 0004](../adr/0004-fijado-de-versiones.md).

Nunca se usa `latest` (la política lo prohíbe) y el gestor no actualiza nada por su cuenta.

## 1. Para usuarios del laboratorio

```bash
./manager update --check        # solo consulta; no cambia nada
```

Para cada imagen, muestra la versión fijada y si hay una más reciente publicada que encaje con su patrón de tags (`tag_pattern`).

Que haya una versión nueva **no** significa que debas usarla. Cuando el repositorio incorpore un conjunto nuevo:

1. actualiza tu copia del repositorio;
2. ejecuta `./manager update`. Descarga las imágenes del conjunto y ofrece recrear los laboratorios en marcha, conservando sus datos;
3. si `scripts/linux/pentestlab-fw.sh` ha cambiado, ejecuta `scripts/linux/install.sh --phase firewall`;
4. opcionalmente, libera espacio con `docker image prune` (borra las imágenes que ya no use ningún contenedor).

## 2. Para mantenedores: incorporar una versión nueva

### 2.1 Elegir la versión

```bash
./manager update --check
```

- Revisa las notas de la versión del proyecto (enlace `upstream` en `versions.json`), sobre todo los cambios en variables de entorno, puertos, usuario del contenedor, rutas de datos y healthcheck.
- Para nginx (`EDGE_IMAGE`) solo se aceptan ramas estables, con el número menor par (`1.30.x`, `1.32.x`).
- **DVWA** no publica versiones, solo `latest` y tags con el commit corto. `update --check` avisa cuando `latest` cambia. Busca entonces el tag del commit correspondiente en https://github.com/digininja/DVWA/pkgs/container/dvwa.

### 2.2 Obtener el digest

```bash
docker pull webgoat/webgoat:v2026.6          # ejemplo
docker image inspect webgoat/webgoat:v2026.6 --format '{{index .RepoDigests 0}}'
```

El digest que se fija es el que muestra `docker pull` (`Digest: sha256:...`), que es el mismo que devuelve `RepoDigests`. En imágenes multiplataforma corresponde al índice, no al manifiesto de una arquitectura concreta.

### 2.3 Editar `config/versions.json`

En la entrada de la imagen:
- cambia `tag` y `digest`;
- si el proyecto cambia su esquema de tags, revisa también `tag_pattern`.

En la cabecera:
- incrementa `set_version` (formato `AAAA.MM.N`);
- pon la fecha de validación en `validated_on`.

Para un **recurso** (por ejemplo, el LDIF de Mutillidae):
- cambia `url`, apuntando siempre a un **commit concreto** y nunca a una rama;
- actualiza `sha256`:

  ```bash
  curl -fsSL "<url>" | sha256sum
  ```

### 2.4 Validar

Todas estas comprobaciones deben pasar antes de publicar el cambio:

```bash
python3 -m unittest discover -s tests -t .      # incluye la política sobre los compose reales
./manager install LAB
./manager --yes reset LAB                        # arranque limpio con las comprobaciones fail-closed
./manager network-check LAB
./manager restart LAB                            # los datos persisten (si es persistente)
./manager --yes reset-data LAB                   # vuelve al estado inicial y los ganchos funcionan
```

Comprueba también a mano:

- la aplicación carga desde Kali y desde el anfitrión, y se puede iniciar sesión con las credenciales iniciales de su [ficha](../labs/);
- los ganchos de inicialización (base de datos de DVWA y de Mutillidae, LDAP) terminan sin errores;
- `./manager logs LAB` no muestra errores nuevos al arrancar;
- el consumo en reposo (`./manager status`) sigue siendo razonable para los límites de [recursos](recursos.md);
- si la aplicación necesita algún servicio externo nuevo, documéntalo como limitación en su ficha. Nunca se abre la salida a Internet.

Por último, ejecuta las [pruebas de red](../testing/pruebas.md) (niveles 3 y 4, o 5).

### 2.5 Registrar

- Si cambian las credenciales, las limitaciones o los requisitos, actualiza la ficha de la aplicación en `docs/labs/`.
- Anota la versión validada en las notas de la versión del repositorio y, si cambia el entorno probado, en la [matriz de compatibilidad](../compatibilidad.md).

## 3. Imágenes y digest actuales

Conjunto `2026.11.2`, validado el 2026-11-23 (`2026.11.2`: busybox 1.37.0 → 1.38.0):

| Variable | Imagen | Tag |
|---|---|---|
| `EDGE_IMAGE` | `nginx` | `1.30.7-alpine` |
| `HELPER_IMAGE` | `busybox` | `1.38.0` |
| `DVWA_IMAGE` | `ghcr.io/digininja/dvwa` | `502ac15` |
| `DVWA_DB_IMAGE` | `mariadb` | `10.11.19` |
| `JUICE_SHOP_IMAGE` | `bkimminich/juice-shop` | `v20.4.0` |
| `WEBGOAT_IMAGE` | `webgoat/webgoat` | `v2026.5` |
| `MUTILLIDAE_WWW_IMAGE` | `webpwnized/mutillidae` | `www-2.12.7` |
| `MUTILLIDAE_DB_IMAGE` | `webpwnized/mutillidae` | `database-2.12.7` |
| `MUTILLIDAE_LDAP_IMAGE` | `webpwnized/mutillidae` | `ldap-2.12.7` |

Los digest están en `config/versions.json`.
