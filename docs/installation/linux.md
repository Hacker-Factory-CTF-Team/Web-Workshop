# Instalación en Linux

| Distribución | Estado |
|---|---|
| Arch Linux / CachyOS | **Probado** (Docker Engine 29.10, Compose 5.8) |
| Debian / Ubuntu | No probado. El instalador reconoce la familia y muestra los comandos |
| Fedora | No probado. Ídem |
| openSUSE | No probado. Ídem |

## 1. Requisitos que comprueba el gestor

El gestor se niega a desplegar si no se cumple alguno de estos requisitos:

- **Docker Engine ≥ 28** en modo normal (rootful). En versiones anteriores se puede llegar desde la LAN a puertos publicados en `127.0.0.1`.
- **Docker Compose ≥ 2.24** (plugin v2: `docker compose`).
- **Backend de firewall `iptables`** en Docker. Compruébalo con:

  ```bash
  docker info --format '{{.FirewallBackend.Driver}}'     # debe decir iptables
  ```

  `iptables` sobre nf_tables (iptables-nft) es válido. Lo que no está soportado es el backend `nftables` nativo de Docker.
- **Sin Docker rootless ni Docker Desktop para Linux.** Docker Desktop publica los puertos desde su propia VM, fuera del firewall del anfitrión.
- **Python ≥ 3.10.**
- Fuera de WSL.

## 2. Docker por distribución

### Arch Linux / CachyOS (probado)

```bash
sudo pacman -S --needed docker docker-compose python iproute2 iptables curl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"     # cierra sesión y vuelve a entrar
```

### Debian / Ubuntu (no probado)

Los paquetes `docker.io` de la distribución pueden ser anteriores a la 28. Usa el repositorio oficial de Docker: https://docs.docker.com/engine/install/ (secciones Debian/Ubuntu). Instala los paquetes `docker-ce` y `docker-compose-plugin`, y después:

```bash
sudo apt-get install -y python3 iproute2 iptables curl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
docker version --format '{{.Server.Version}}'      # debe ser >= 28
```

### Fedora (no probado)

Usa el repositorio `docker-ce`: https://docs.docker.com/engine/install/fedora/. El paquete `moby-engine` de Fedora no se ha evaluado. Los mismos pasos de `systemctl` y `usermod`.

## 3. Hipervisor y red de laboratorio

- [KVM/QEMU](kvm.md) (probado).
- [VirtualBox](virtualbox.md).

Ambas guías terminan con la fase `network` del instalador, que deja `config/local.json` con:
- la plataforma (`linux-kvm` o `linux-virtualbox`);
- la IP de laboratorio del anfitrión;
- el nombre de la interfaz.

## 4. Firewall e imágenes

```bash
scripts/linux/install.sh --phase firewall
scripts/linux/install.sh --phase images        # equivale a ./manager install
```

En la fase `firewall`:
1. Copia `scripts/linux/pentestlab-fw.sh` a `/usr/local/sbin/pentestlab-fw`, con propietario root y permisos 0755.
2. Pregunta si quieres una regla en `/etc/sudoers.d/pentestlab-fw` que permita a tu usuario ejecutar **solo** `pentestlab-fw verify` y `pentestlab-fw apply` sin contraseña. Sin ella, cada `./manager start` pide la contraseña de sudo. Para responder sin preguntas: `PLAB_SUDOERS=yes` o `PLAB_SUDOERS=no`.
3. Si la interfaz de laboratorio ya existe, aplica y verifica las reglas. Si no, lo hará `./manager start` más adelante.

El detalle de las reglas está en [firewall-linux.md](../networking/firewall-linux.md).

En la fase `images` se descargan unos 5 GB de imágenes, fijadas por digest, y el LDIF de Mutillidae, verificado por SHA-256. Es el único momento en que hace falta Internet.

> Si actualizas el repositorio y cambia `scripts/linux/pentestlab-fw.sh`, la copia instalada deja de coincidir y `./manager start` se bloquea. Vuelve a ejecutar `scripts/linux/install.sh --phase firewall`.

## 5. Comprobar la instalación

```bash
scripts/linux/install.sh --phase validate      # ./manager diagnose
./manager start
./manager network-check
```

Después, haz la [verificación desde Kali](../testing/pruebas.md#3-desde-la-vm-de-kali).
