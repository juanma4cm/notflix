# Notflix — Media Server Stack

Stack Docker para servidor multimedia personal. Incluye Plex, Radarr, Sonarr y herramientas complementarias, accesible desde cualquier dispositivo via Tailscale.

## Servicios

| Servicio | URL | Descripción |
|---|---|---|
| Plex | http://plex.notflix.internal | Streaming multimedia |
| Radarr | http://radarr.notflix.internal | Gestión automatizada de películas |
| Sonarr | http://sonarr.notflix.internal | Gestión automatizada de series |
| Prowlarr | http://prowlarr.notflix.internal | Gestor centralizado de indexadores |
| FlareSolverr | http://flaresolverr.notflix.internal | Bypass de protecciones Cloudflare |
| qBittorrent | http://qbittorrent.notflix.internal | Cliente torrent |

> Los dominios `*.notflix.internal` son accesibles desde cualquier dispositivo en la red Tailscale gracias al Split DNS configurado en el servidor.

## Prerrequisitos del Servidor

- Ubuntu Server con **Docker Engine** (v2) y **Docker Compose plugin** instalados
- **Tailscale** instalado y autenticado en el servidor
- `make` instalado (`sudo apt install make`)

## Instalación

### 1. Preparar el entorno

```bash
git clone <repo-url> notflix
cd notflix
cp .env.example .env
```

Editar `.env` con los valores del servidor:

```bash
# Obtener PUID y PGID del usuario que ejecuta Docker:
id -u   # → PUID
id -g   # → PGID
```

### 2. Crear estructura de directorios

```bash
make create-folders
```

### 3. Configurar la IP Tailscale en dnsmasq

```bash
# En el servidor, obtener la IP Tailscale:
tailscale ip -4
# Editar dnsmasq/dnsmasq.conf y sustituir 100.x.x.x por la IP obtenida
```

### 4. Liberar el puerto 53 en Ubuntu (una vez)

`systemd-resolved` ocupa el puerto 53 por defecto. Hay que liberar el stub listener:

```bash
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
# Verificar que el puerto está libre:
sudo ss -tulpn | grep ':53'
```

### 5. Iniciar el stack

```bash
make up
```

### 6. Configurar Tailscale Split DNS (una vez por tailnet)

En el panel de Tailscale (`login.tailscale.com/admin/dns`):

1. **DNS** → **Add nameserver** → **Custom**
2. **Nameserver:** IP Tailscale del servidor (la del paso 3)
3. **Domain:** `notflix.internal`
4. Activar **"Restrict to domain"**

A partir de aquí, cualquier dispositivo que se una a la red Tailscale resolverá `*.notflix.internal` automáticamente.

Verificar desde cualquier dispositivo Tailscale:

```bash
dig radarr.notflix.internal
# Debe devolver la IP Tailscale del servidor
```

## Comandos Make

| Comando | Descripción |
|---|---|
| `make create-folders` | Crea la estructura de directorios |
| `make up` | Inicia todos los servicios |
| `make down` | Detiene todos los servicios |
| `make restart` | Reinicia todos los servicios |
| `make status` | Estado de los contenedores |
| `make logs` | Logs de todos los servicios |
| `make logs-<servicio>` | Logs de un servicio específico (plex, qbit, radarr, sonarr, prowlarr, flare, caddy) |

## Configuración de Servicios

### qBittorrent

- Accede a http://qbittorrent.notflix.internal
- La primera vez se genera una contraseña temporal en los logs:

```bash
make logs-qbit
# Buscar: "A temporary password is provided for this session: XXXXXX"
```

- Configuración recomendada (Tools > Options > Downloads):
  - Default Save Path: `/downloads`
  - Keep incomplete torrents in: `/downloads/incomplete`
  - Desactivar "Create subfolder for torrents"

### Prowlarr

- Accede a http://prowlarr.notflix.internal
- FlareSolverr ya está disponible internamente en `http://flaresolverr:8191`
- Settings > Indexer Proxies → añadir FlareSolverr con esa URL
- Settings > Apps → añadir Radarr (`http://radarr:7878`) y Sonarr (`http://sonarr:8989`)

### Radarr

- Accede a http://radarr.notflix.internal
- Settings > Media Management > Movies Folder: `/movies`
- Settings > Download Clients → añadir qBittorrent (host: `qbittorrent`, puerto: `8080`)

### Sonarr

- Accede a http://sonarr.notflix.internal
- Configuración idéntica a Radarr pero con carpeta `/tv`

> **Custom Format Español:** el archivo `custom-format-español.json` de la raíz puede importarse en Radarr/Sonarr desde Settings > Custom Formats > Import.

### Plex

- Accede a http://plex.notflix.internal
- Añadir bibliotecas: Movies → `/movies`, TV Shows → `/tv`
- Settings > Remote Access > Custom server access URLs: `http://plex.notflix.internal`

## Notas

- Todo el tráfico entre dispositivos ya va cifrado por WireGuard (Tailscale), por eso se usa HTTP en lugar de HTTPS internamente.
- Las IPs Tailscale son estables. Si cambia la IP del servidor, actualizar `dnsmasq/dnsmasq.conf` y reiniciar el contenedor `dnsmasq`.
- Los directorios de configuración de servicios (`radarr/`, `sonarr/`, etc.) no están versionados. Hacer backup antes de migrar el servidor.

## Licencia

MIT
