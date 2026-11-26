# Política de seguridad

Web Workshop despliega aplicaciones **vulnerables a propósito**. Lo que protege a quien lo usa es el aislamiento que lo rodea: redes internas, proxy único, firewall del anfitrión y comprobaciones *fail-closed*. Esta política explica qué problemas de seguridad comunicar y cómo hacerlo.

## Qué se considera una vulnerabilidad

**Sí**, cualquier problema que debilite el aislamiento o la seguridad del equipo del participante, por ejemplo:

- una aplicación o un contenedor del laboratorio alcanza Internet, la LAN, otro laboratorio o servicios del anfitrión;
- un puerto del laboratorio es accesible desde la LAN o desde una interfaz no prevista;
- el gestor despliega a pesar de que una comprobación debería haberlo bloqueado, o una comprobación se puede saltar;
- la política estática acepta un `compose.yaml` que incumple alguna [invariante de seguridad](docs/architecture/invariantes-seguridad.md);
- `pentestlab-fw`, la regla de sudoers que instala el instalador o los instaladores permiten escalar privilegios o modifican reglas ajenas;
- Kali puede usar el anfitrión como router o alcanzar servicios del anfitrión que deberían estar bloqueados;
- la verificación de imágenes (digest) o de recursos (SHA-256) se puede eludir;
- `./manager diagnose` u otro comando muestra secretos;
- problemas en el workflow de CI que permitan ejecutar código con permisos del repositorio.

**No** se consideran vulnerabilidades de este proyecto:

- **las vulnerabilidades de las aplicaciones del taller** (DVWA, Juice Shop, WebGoat, Mutillidae): son intencionadas. Si encuentras una no intencionada, comunícala a su proyecto original;
- las credenciales por defecto de esas aplicaciones y de sus bases de datos, que son públicas y solo existen dentro de redes internas;
- los **riesgos residuales ya documentados**: la salida del proxy y el acceso al anfitrión con Docker Desktop en Windows ([ADR 0002](docs/adr/0002-salida-del-proxy-firewall-y-dns.md), [windows.md](docs/installation/windows.md#7-diferencias-y-riesgos-residuales)) y la pasarela NAT de VirtualBox ([virtualbox.md](docs/installation/virtualbox.md#4-particularidades)). Si tienes información nueva sobre ellos (por ejemplo, una forma de explotarlos o de cerrarlos), sí interesa;
- configuraciones que el propio gestor rechaza (Docker rootless, backend `nftables`, Docker Desktop para Linux) o modificaciones manuales que se saltan el gestor, como ejecutar `docker compose up` directamente.

## Versiones afectadas

El proyecto no publica versiones: solo se mantiene la rama `main`. Comprueba que el problema se reproduce con su última versión.

## Cómo informar

**No abras una Issue, una Discussion ni un Pull Request públicos con los detalles** de una vulnerabilidad de aislamiento: otras personas podrían estar usando el laboratorio en ese momento.

> [!NOTE]
> **Canal privado pendiente de habilitar.** A fecha de 2026-11-26, el repositorio no tiene activado el reporte privado de vulnerabilidades de GitHub ni ha publicado ningún otro contacto privado. Los responsables tienen los pasos para activarlo en [configuración de GitHub](docs/project/configuracion-github.md#1-reporte-privado-de-vulnerabilidades).

Mientras tanto:

1. Si en la pestaña [*Security*](https://github.com/Hacker-Factory-CTF-Team/Web-Workshop/security) del repositorio aparece el botón **Report a vulnerability**, úsalo: es el canal preferente.
2. Si no aparece, abre una Issue en blanco (*Blank issue*, al final de la lista de plantillas) **sin detalles técnicos**, solo con el título *"Solicitud de contacto privado para un problema de seguridad"* y el componente afectado (por ejemplo, "firewall de Linux"). Los responsables te propondrán un canal privado.

## Qué incluir en el reporte

- Componente afectado: gestor (`src/pentestlab/`), firewall (`scripts/linux/pentestlab-fw.sh` o reglas de Windows), instalador, un `compose.yaml`, el kit de Kali, el CI...
- Plataforma: SO del anfitrión, hipervisor, versiones de Docker Engine y Compose. La salida de `./manager diagnose` ayuda, pero **revísala antes**: incluye las IP de tus interfaces.
- Pasos para reproducirlo, desde una instalación estándar.
- Qué ocurre y qué debería ocurrir: qué conexión se consigue, desde dónde y hacia dónde.
- Impacto: qué puede hacer alguien que lo aproveche.
- Si lo conoces, una propuesta de corrección.

## Qué pasará después

Los responsables confirmarán la recepción, evaluarán el problema y te mantendrán al tanto en el canal privado. El equipo no ha fijado plazos de respuesta. Cuando haya corrección:

- se publicará en `main` con una prueba de regresión, como el resto de correcciones;
- si afecta a los participantes, se indicará qué deben hacer (por ejemplo, actualizar el repositorio y reinstalar el firewall con `scripts/linux/install.sh --phase firewall`);
- se te reconocerá el hallazgo si lo deseas.

## Uso responsable del laboratorio

- Ataca solo las aplicaciones del laboratorio, en tu propio equipo.
- No expongas los laboratorios a Internet ni a tu red local, ni cambies la configuración de red para hacerlos accesibles desde otros equipos.
- No desactives las comprobaciones del gestor ni ejecutes los laboratorios fuera de él.
