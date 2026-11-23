# Restauración de laboratorios

## 1. Dónde están los datos

| Laboratorio | Volúmenes (`plab-<lab>_*`) | Contenido |
|---|---|---|
| DVWA | `plab-dvwa_db-data` | Base de datos MariaDB (usuarios, nivel de seguridad, datos introducidos) |
| Juice Shop | ninguno | La aplicación regenera su base de datos en cada arranque |
| WebGoat | `plab-webgoat_webgoat-data` | Usuarios y progreso de las lecciones (WebGoat y WebWolf) |
| Mutillidae | `plab-mutillidae_db-data`, `_ldap-data`, `_ldap-config` | Base de datos MariaDB y directorio OpenLDAP |

Todos llevan la etiqueta `org.pentestlab.data=true`.

## 2. Modos de persistencia

| Modo | Comportamiento |
|---|---|
| `persistent` (por defecto, salvo Juice Shop) | Los datos sobreviven a `stop`, `start`, `restart` y a reiniciar el equipo |
| `ephemeral` | Cada `start` de un laboratorio **parado** borra sus volúmenes y arranca desde el estado inicial. `restart` conserva los datos |

```bash
./manager config set-persistence dvwa ephemeral
./manager config set-persistence dvwa persistent
```

**Juice Shop solo admite el modo efímero.** Es una decisión de diseño del proyecto: regenera su base de datos cada vez que arranca el proceso, así que cualquier arranque, incluido `restart`, vuelve al estado inicial. Para conservar el progreso de los retos, usa la función de *continue code* de la propia aplicación.

## 3. Operaciones

| Necesito... | Comando | Datos |
|---|---|---|
| Pausar | `./manager stop LAB` | Se conservan |
| Reiniciar sin perder nada | `./manager restart LAB` | Se conservan, también en modo efímero |
| Volver al estado inicial de los datos | `./manager reset-data LAB` | **Se borran** y el laboratorio se vuelve a arrancar |
| Reconstruir todo (datos y estado generado) | `./manager reset LAB` | **Se borran**, se reinstalan los recursos y se arranca |
| Estado inicial en cada sesión | `config set-persistence LAB ephemeral` y después `stop` + `start` | Se borran en cada `start` |

### `reset-data`

1. Pide confirmación.
2. `docker compose down --volumes --remove-orphans`.
3. `start`: comprobaciones completas y ganchos de inicialización, que vuelven a crear la base de datos de DVWA con sus usuarios por defecto, o la de Mutillidae con su directorio LDAP.

### `reset`

Hace lo mismo que `reset-data` y además:
- borra `state/<lab>.env` y `state/<lab>/`; en Mutillidae, esto incluye el LDIF;
- ejecuta `install` para ese laboratorio: descarga solo las imágenes que falten y vuelve a descargar y verificar los recursos.

Úsalo si sospechas que el estado generado está dañado.

### Confirmación

Las operaciones destructivas piden que **escribas el identificador del laboratorio** (por ejemplo `dvwa`). Si no coincide, se cancelan.

Sin terminal interactivo, se niegan con el código 5, salvo que pases `--yes` de forma explícita:

```bash
./manager --yes reset-data dvwa
```

## 4. Copia de seguridad manual

El gestor no hace copias de seguridad. Si quieres guardar el estado de un laboratorio persistente antes de restaurarlo, detenlo y archiva su volumen. Por ejemplo, con la imagen busybox que ya usa el laboratorio:

```bash
./manager stop webgoat
docker run --rm --network none -v plab-webgoat_webgoat-data:/data:ro -v "$PWD:/backup" \
  "$(python3 -c 'import json; i = json.load(open("config/versions.json"))["images"]["HELPER_IMAGE"]; print(i["repository"] + "@" + i["digest"])')" \
  tar -czf /backup/webgoat-data.tgz -C /data .
```

Para restaurarla, haz lo inverso con el laboratorio detenido (`tar -xzf` dentro del volumen).
