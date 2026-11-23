# Recursos y límites

Cada contenedor tiene un límite de CPU (`cpus`) y de memoria (`mem_limit`), y un límite de procesos (`pids_limit`). Los límites de CPU y memoria se configuran por servicio; el de procesos es fijo en `compose.yaml`.

## 1. Límites por defecto

| Laboratorio | Servicio | CPU | Memoria | PIDs |
|---|---|---:|---:|---:|
| DVWA | `edge` | 0,25 | 64m | 64 |
| | `dvwa` | 1,0 | 512m | 256 |
| | `db` | 0,5 | 512m | 256 |
| Juice Shop | `edge` | 0,25 | 64m | 64 |
| | `juice-shop` | 1,0 | 768m | 256 |
| WebGoat | `edge` | 0,25 | 64m | 64 |
| | `webgoat` | 2,0 | 1536m | 512 |
| Mutillidae | `edge` | 0,25 | 64m | 64 |
| | `www` | 1,0 | 512m | 256 |
| | `database` | 0,5 | 512m | 256 |
| | `directory` | 0,25 | 256m | 256 |
| **Total** | | **7,25** | **~4,8 GiB** | |

Los límites son **máximos**, no reservas.

Consumo medido en reposo con los 4 laboratorios arrancados (2026-11-22):

| Laboratorio | RAM en reposo |
|---|---:|
| WebGoat | ~390 MiB |
| Mutillidae | ~170 MiB |
| DVWA | ~130 MiB |
| Juice Shop | ~125 MiB |
| Cada proxy `edge` | ~2 MiB |
| **Total** | **~940 MiB** |

Suma también la VM de Kali (4 GiB y 2 vCPU recomendados).

| Equipo anfitrión | Recomendación |
|---|---|
| 8 GiB de RAM, 4 núcleos | Kali + 1 o 2 laboratorios a la vez |
| 16 GiB de RAM, 4+ núcleos | Kali + los 4 laboratorios |

## 2. Consultar

```bash
./manager list          # CPU y RAM máximas por laboratorio
./manager status        # consumo actual por contenedor (CPU, memoria uso/límite, PIDs)
./manager config show   # límites efectivos por servicio
```

## 3. Cambiar

```bash
./manager config set-resources webgoat webgoat --memory 2g
./manager config set-resources dvwa db --cpus 0.25 --memory 256m
./manager restart webgoat        # si estaba en marcha
```

- `--cpus`: número mayor que 0 y como máximo 64 (admite decimales).
- `--memory`: número seguido de `m` o `g`.
- Los valores se guardan en `config/local.json` y se aplican en el siguiente `start` o `restart`.

Con límites demasiado bajos, el laboratorio puede no llegar a estar sano (*healthy*) dentro del tiempo de arranque, sobre todo WebGoat (Java) y las bases de datos.

## 4. Avisos antes de arrancar

`start` calcula los recursos y **avisa sin bloquear**. En un terminal pregunta si quieres continuar. Avisa en tres casos:

- la memoria máxima de los laboratorios que vas a arrancar supera el 90 % de la memoria disponible del anfitrión;
- la suma de los límites de memoria (los que arrancas más los que ya están en marcha) supera la memoria que ve Docker;
- la suma de los límites de CPU supera las CPU disponibles. Se repartirán, pero puede ir lento. Recuerda reservar CPU para Kali.

## 5. Disco

- Imágenes: unos 5 GB en total.
- Volúmenes de datos: unos pocos cientos de MB, que crecen con el uso.
- VM de Kali: entre 15 y 80 GB según la imagen y el uso (el qcow2 crece según se escribe).

```bash
docker system df
docker volume ls --filter label=org.pentestlab.data=true
```
