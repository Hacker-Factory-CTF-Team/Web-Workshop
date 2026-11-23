# VirtualBox en Linux

**Estado: no probado con una VM real.** El instalador implementa estos pasos, pero en el equipo de desarrollo no hay VirtualBox. La red Host-only se validó emulada (veth + netns, ver [pruebas](../testing/pruebas.md)). Si lo pruebas, anota el resultado en la [matriz de compatibilidad](../compatibilidad.md).

## 1. Instalar VirtualBox

Instálalo desde tu distribución o desde https://www.virtualbox.org/wiki/Linux_Downloads.

Comprueba que los módulos del kernel están cargados y que tu usuario puede usarlo:

```bash
VBoxManage --version
lsmod | grep vboxdrv
```

## 2. Red de laboratorio (Host-only)

```bash
scripts/linux/install.sh --phase network --hypervisor virtualbox
# con otra subred: --ip 192.168.58.1
```

El instalador:

1. **Reutiliza** una interfaz Host-only que ya tenga la IP de laboratorio. Nunca modifica otras.
2. Si no existe, comprueba que la subred no se solapa con otras interfaces y **crea una nueva** (`VBoxManage hostonlyif create`) con `192.168.57.1/24`. No usa `vboxnet0`, que otras VM suelen compartir.
3. Activa el DHCP de VirtualBox en esa interfaz: servidor `.2`, rango `.100`–`.199`, **sin anunciar pasarela ni DNS** (`--suppress-opt=3 --suppress-opt=6`; sin probar). Si ya había uno configurado, no lo toca.
4. Guarda en `config/local.json` la plataforma `linux-virtualbox`, la IP y el nombre de la interfaz (`vboxnetN`).

El NAT de VirtualBox funciona en espacio de usuario, sin bridge en el anfitrión. Por eso no hay que registrar una interfaz NAT ni tocar el firewall para él, a diferencia de KVM.

### Rango permitido por VirtualBox

Desde la versión 6.1.28, VirtualBox en Linux solo permite redes Host-only dentro de `192.168.56.0/21` (de 192.168.56.0 a 192.168.63.255). La IP por defecto, `192.168.57.1`, está dentro.

Para usar otro rango, añade como root a `/etc/vbox/networks.conf`:

```text
* 10.57.0.0/24
```

El instalador se detiene con este aviso si la IP elegida queda fuera.

## 3. VM de Kali

1. Descarga la imagen **VirtualBox** desde https://www.kali.org/get-kali/#kali-virtual-machines y verifica su SHA-256.
2. Descomprímela con `7z x` e impórtala: *Máquina → Añadir…* y elige el `.vbox`.
3. En *Configuración → Red*:
   - **Adaptador 1**: *Conectado a: Adaptador solo-anfitrión* y *Nombre:* la `vboxnetN` que indicó el instalador;
   - **Adaptador 2**: *Conectado a: NAT*, que da Internet a Kali.
4. Arranca la VM. Usuario y contraseña por defecto: `kali` / `kali`.

Kali recibe una IP `.100`–`.199` por DHCP en el adaptador 1. Comprueba con `ip route` que la ruta por defecto va por el adaptador NAT y no por el de laboratorio. Si no, en Kali: `nmcli connection modify "<conexión del adaptador 1>" ipv4.never-default yes ipv4.ignore-auto-dns yes`. Sigue la [verificación desde Kali](../testing/pruebas.md#3-desde-la-vm-de-kali).

## 4. Particularidades

- VirtualBox crea la interfaz `vboxnetN` en el anfitrión, pero su IP puede no aparecer hasta que se usa por primera vez. Si `./manager start` dice que *ninguna interfaz tiene la IP*, arranca la VM de Kali (o el servicio de VirtualBox) y vuelve a intentarlo.
- El firewall trata `vboxnetN` igual que `virbr-plab`: Kali solo llega a los puertos de los laboratorios ([firewall-linux.md](../networking/firewall-linux.md)).
- **Riesgo residual (sin verificar):** en el NAT de VirtualBox, la pasarela (`10.0.2.2`) suele dar acceso a los servicios del anfitrión, incluidos los que escuchan solo en `127.0.0.1`. VirtualBox hace esas conexiones desde su propio proceso, así que el firewall del laboratorio no puede filtrarlas. `kali-probe.sh` lo comprueba en la sección *servicios del anfitrión por la NIC NAT*.

## 5. Desinstalar

```bash
scripts/linux/install.sh --phase uninstall     # quita el DHCP y la interfaz si los creó el instalador
```

La VM de Kali se elimina desde VirtualBox: *Eliminar → Eliminar todos los archivos*.
