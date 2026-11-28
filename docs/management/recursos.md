# Recursos y límites

Cada contenedor tiene un límite de CPU (`cpus`) y de memoria (`mem_limit`), y un límite de procesos (`pids_limit`). Los límites de CPU y memoria se configuran por servicio; el de procesos es fijo en `compose.yaml`.

La máquina virtual atacante (Kali Linux) se dimensiona y aísla de forma independiente a través del hipervisor (VirtualBox o KVM).

---

## 1. Límites por defecto

### Contenedores de los laboratorios

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

Los límites de los contenedores son **máximos asignables**, no reservas inmediatas de memoria.

Consumo medido en reposo con los 4 laboratorios arrancados (2026-11-22):

| Laboratorio | RAM en reposo |
|---|---:|
| WebGoat | ~390 MiB |
| Mutillidae | ~170 MiB |
| DVWA | ~130 MiB |
| Juice Shop | ~125 MiB |
| Cada proxy `edge` | ~2 MiB |
| **Total** | **~940 MiB** |

### VM de Kali Linux (VirtualBox)

Los scripts del instalador (`scripts/linux/install.sh --phase kali-vm`) asignan por defecto los siguientes recursos a la máquina virtual:

| Recurso | Valor por defecto | Parámetro de ajuste en `install.sh` | Límites permitidos |
|---|---|---|---|
| Memoria RAM | **4096 MiB** (4 GiB) | `--memory MB` | Mínimo `1024` MiB; no puede superar la RAM del anfitrión |
| vCPUs | **4** | `--cpus N` | Mínimo `1`; enteros positivos |
| Memoria de vídeo (VRAM) | **128 MiB** (VMSVGA) | `--vram MB` | Entre `1` y `128` MiB |
| Disco virtual (.vdi) | Dinámico (hasta ~80 GB) | Automático | Requiere al menos 2 GiB libres para registrarse |

### Dimensionamiento recomendado del equipo anfitrión

| Equipo anfitrión | Recomendación de uso |
|---|---|
| **8 GiB de RAM, 4 núcleos** | Ajustar Kali a 2 vCPU y 2048–3072 MiB de RAM (`--cpus 2 --memory 3072`). Ejecutar Kali junto a 1 o 2 laboratorios simultáneos. |
| **16 GiB de RAM, 6+ núcleos** | Valores por defecto (Kali con 4 vCPUs y 4 GiB de RAM) + los 4 laboratorios arrancados simultáneamente. |
| **32+ GiB de RAM, 8+ núcleos** | Entorno holgado para ejecutar los 4 laboratorios, Kali al máximo y herramientas pesadas de análisis/fuzzing. |

---

## 2. Consultar recursos

```bash
./manager list          # CPU y RAM máximas configuradas por laboratorio
./manager status        # consumo actual por contenedor (CPU, memoria uso/límite, PIDs)
./manager config show   # límites efectivos por servicio en config/local.json
```

Para comprobar los recursos asignados a la VM de Kali en VirtualBox:

```bash
VBoxManage showvminfo kali-plab | grep -E "Memory size|Number of CPUs|VRAM size"
```

---

## 3. Cambiar recursos

### En los contenedores (`./manager config`)

```bash
./manager config set-resources webgoat webgoat --memory 2g
./manager config set-resources dvwa db --cpus 0.25 --memory 256m
./manager restart webgoat        # aplica el cambio si el laboratorio estaba en marcha
```

- `--cpus`: número mayor que 0 y como máximo 64 (admite decimales).
- `--memory`: número seguido de `m` (megabytes) o `g` (gigabytes).
- Los valores se guardan en `config/local.json` y se aplican en el siguiente `start` o `restart`.

> [!WARNING]
> Con límites excesivamente bajos, los servicios pueden no alcanzar el estado saludable (*healthy*) antes del tiempo límite de arranque (`start_timeout_seconds`), especialmente WebGoat (Java/JVM) y las bases de datos SQL.

### En la VM de Kali Linux

**Durante el aprovisionamiento automatizado:**
Pasa los argumentos deseados a la fase `kali-vm` del instalador:

```bash
scripts/linux/install.sh --phase kali-vm --memory 2048 --cpus 2 --vram 64
```

**Con la VM ya creada (en caliente / con máquina apagada):**
Apaga la máquina virtual y modifícala directamente con `VBoxManage`:

```bash
VBoxManage modifyvm "kali-plab" --memory 2048 --cpus 2 --vram 128
```

---

## 4. Avisos preventivos del gestor

Antes de iniciar cualquier contenedor, `./manager start` evalúa los recursos del sistema anfitrión y emite advertencias preventivas (sin bloquear el despliegue):

- La memoria máxima requerida por los laboratorios a arrancar supera el **90 % de la memoria libre** disponible en el anfitrión.
- La suma agregada de límites de memoria (los que arrancas más los que ya están en ejecución) supera la memoria total que visualiza el demonio de Docker.
- La suma agregada de límites de CPU supera los núcleos físicos/lógicos disponibles en el anfitrión (el kernel repartirá el tiempo de CPU, pero el rendimiento puede verse degradado). Recuerda siempre reservar CPU suficiente para la máquina virtual de Kali.

---

## 5. Espacio en disco

El almacenamiento requerido se reparte entre contenedores, recursos estáticos y la máquina virtual:

- **Imágenes Docker:** unos 5 GB en total fijadas por digest (DVWA, Juice Shop, WebGoat, Mutillidae y proxys `edge`).
- **Volúmenes de datos:** unos pocos cientos de megabytes que aumentan gradualmente con el almacenamiento persistente de ejercicios.
- **VM de Kali Linux:**
  - Archivo comprimido `.7z` descargado: ~3–4 GB.
  - Disco base `.vdi` (o `.qcow2` en KVM) descomprimido: ~12–15 GB iniciales.
  - El formato de disco es dinámico y se expande a medida que se escriben datos (instalación de paquetes con `kali/install.sh`, diccionarios, capturas, etc.) hasta un tamaño virtual de ~80 GB.
  - El instalador verifica que existan al menos 2 GiB libres adicionales antes de proceder con el registro.

Comprobación de espacio ocupado por Docker:

```bash
docker system df
docker volume ls --filter label=org.pentestlab.data=true
```
