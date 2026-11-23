# OWASP Juice Shop

| | |
|---|---|
| **Descripción** | Tienda online moderna e intencionadamente insegura, con retos de distinta dificultad y un marcador (*Score Board*) integrado |
| **Tecnologías** | Node.js, Express, Angular; SQLite y MarsDB embebidas. Imagen *distroless* (sin shell) |
| **Versión fijada** | `bkimminich/juice-shop:v20.4.0` |
| **Identificador** | `juice-shop` (proyecto Compose `plab-juice-shop`) |
| **Persistencia** | Solo `ephemeral` |
| **Documentación oficial** | https://owasp.org/www-project-juice-shop/ y https://github.com/juice-shop/juice-shop |
| **Licencia** | MIT (proyecto Juice Shop) |

## Acceso

| Desde | URL (por defecto) |
|---|---|
| Kali | `http://<IP de laboratorio>:3000/` |
| Anfitrión | `http://127.0.0.1:3000/` |

**Credenciales iniciales:** no hay ninguna cuenta para el participante. Registra una desde la propia aplicación.

## Servicios

| Servicio | Imagen | Función | Puerto interno | Redes |
|---|---|---|---|---|
| `edge` | nginx 1.30 (alpine) | Proxy L4, único publicado | 3000 | `edge`, `front` |
| `juice-shop` | Juice Shop | Aplicación y datos | 3000 | `front` |

No tiene servicios auxiliares ni volúmenes.

## Requisitos

- Límites por defecto: 1,25 CPU y 832 MiB en total.
- Consumo medido en reposo: ~125 MiB.
- No necesita Internet para funcionar.

## Persistencia

Juice Shop regenera su base de datos **cada vez que arranca**. Es una decisión de diseño del proyecto. Cualquier `start` o `restart` vuelve al estado inicial: se pierden las cuentas registradas y los retos resueltos.

Para conservar el progreso, usa la función oficial de *continue code* desde el *Score Board* antes de detener el laboratorio.

## Limitaciones

Sin salida a Internet, **6 retos no pueden completarse**, porque dependen de servicios externos:

| Retos | Dependencia |
|---|---|
| *AI Debugging*, *Chatbot Prompt Injection*, *Greedy Chatbot Manipulation*, *System Prompt Extraction* | Un LLM local en `localhost:11434` que el laboratorio no despliega |
| *Mint the Honey Pot*, *Wallet Depletion* | Servicios Web3/Alchemy en Internet |

El resto de la aplicación funciona sin conexión.
