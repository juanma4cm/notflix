# Notflix — Media Server Stack

Stack Docker para servidor multimedia personal. Accesible desde cualquier dispositivo via Tailscale.

## Servicios

| Servicio | URL | Descripción |
|---|---|---|
| Plex | http://plex.notflix.internal | Streaming multimedia |
| Overseerr | http://overseerr.notflix.internal | Peticiones de contenido |
| Radarr | http://radarr.notflix.internal | Gestión automatizada de películas |
| Sonarr | http://sonarr.notflix.internal | Gestión automatizada de series |
| Prowlarr | http://prowlarr.notflix.internal | Gestor centralizado de indexadores |
| qBittorrent | http://qbittorrent.notflix.internal | Cliente torrent |
| ntfy | http://ntfy.notflix.internal | Notificaciones push |
| FlareSolverr | http://flaresolverr.notflix.internal | Bypass de protecciones Cloudflare |

> Los dominios `*.notflix.internal` son accesibles desde cualquier dispositivo en la red Tailscale.

## Prerrequisitos del Servidor

- Ubuntu Server con **Docker Engine** (v2) y **Docker Compose plugin**
- **Tailscale** instalado y autenticado
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
id -u   # → PUID
id -g   # → PGID

# Generar API keys:
echo "RADARR_API_KEY=$(openssl rand -hex 16)"
echo "SONARR_API_KEY=$(openssl rand -hex 16)"
echo "PROWLARR_API_KEY=$(openssl rand -hex 16)"
```

### 2. Crear estructura de directorios

```bash
make create-folders
```

### 3. Configurar la IP Tailscale en dnsmasq

```bash
tailscale ip -4
# Editar dnsmasq/dnsmasq.conf → sustituir 100.x.x.x por la IP obtenida
```

### 4. Liberar el puerto 53 en Ubuntu (una vez)

```bash
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
sudo ss -tulpn | grep ':53'   # verificar que el puerto está libre
```

### 5. Iniciar el stack

```bash
make up
```

`make up` ejecuta en orden:
1. Siembra los `config.xml` en los servicios Arr con las API keys del `.env` (si no existen)
2. Levanta todos los servicios en background
3. El `provisioner` arranca automáticamente cuando los servicios están healthy y configura todas las interconexiones vía API

### 6. Configurar Tailscale Split DNS (una vez por tailnet)

En `login.tailscale.com/admin/dns`:

1. **DNS** → **Add nameserver** → **Custom**
2. **Nameserver:** IP Tailscale del servidor
3. **Domain:** `notflix.internal` + activar **"Restrict to domain"**

Verificar: `dig radarr.notflix.internal` → debe devolver la IP Tailscale del servidor.

## Lo que se configura automáticamente

Tras `make up`, el provisioner configura:

| Configuración | Estado |
|---|---|
| FlareSolverr como proxy en Prowlarr | Automático |
| Prowlarr ↔ Radarr / Sonarr (fullSync) | Automático |
| qBittorrent como download client en Radarr y Sonarr | Automático |
| Root folders `/movies` y `/tv` | Automático |
| Notificaciones ntfy en Radarr y Sonarr | Automático |
| Indexers en Prowlarr | Manual (requieren credenciales) |
| Biblioteca de Plex | Manual (requiere PLEX_CLAIM token) |
| Overseerr (requiere OAuth Plex) | Manual |

> **Nota sobre qBittorrent:** En el primer arranque genera una contraseña temporal visible en `make logs-qbit`. Cámbiala en la WebUI al valor de `QBIT_PASS` del `.env` y ejecuta `make provision` de nuevo.

## Versiones y Actualizaciones

Las versiones de las imágenes se controlan en `.env` (`RADARR_VERSION`, etc.).

**Flujo recomendado:**

1. **Diun** notifica cada lunes si hay nuevas versiones disponibles (llega a ntfy)
2. Consultar el changelog del servicio
3. Actualizar la versión en `.env`
4. Aplicar solo ese servicio:

```bash
docker compose pull radarr
docker compose up -d radarr
```

**Pinear versiones tras el primer despliegue:**

```bash
# Obtener versión actual de cada servicio:
docker inspect radarr      | jq -r '.[0].Config.Image'
docker inspect sonarr      | jq -r '.[0].Config.Image'
docker inspect prowlarr    | jq -r '.[0].Config.Image'
docker inspect qbittorrent | jq -r '.[0].Config.Image'
docker inspect plex-server | jq -r '.[0].Config.Image'
# Copiar las versiones al .env
```

## Quality Profiles con Recyclarr

Recyclarr sincroniza perfiles de calidad y custom formats desde TRaSH-Guides directamente en Radarr y Sonarr. Complementa el `custom-format-español.json` del repo.

```bash
make recyclarr          # Sincronizar perfiles
make recyclarr-list     # Ver custom formats disponibles para Radarr
```

La configuración está en `recyclarr/recyclarr.yml` y es versionada junto al proyecto.

## Notificaciones Push

ntfy envía notificaciones cuando se completan descargas o hay problemas de salud.

**Suscribirse desde el móvil** (requiere Tailscale en el dispositivo):

- App ntfy (iOS/Android) → suscribirse a:
  - `http://ntfy.notflix.internal/notflix-movies`
  - `http://ntfy.notflix.internal/notflix-series`
  - `http://ntfy.notflix.internal/notflix-updates` (actualizaciones de imágenes via Diun)

## Peticiones de Contenido — Overseerr

1. Acceder a http://overseerr.notflix.internal
2. Login con cuenta Plex
3. Conectar Plex server (autodetección en `media-network`)
4. Añadir Radarr: URL `http://radarr:7878`, API key desde `.env`
5. Añadir Sonarr: URL `http://sonarr:8989`, API key desde `.env`

## Backup

```bash
make backup       # Backup de configs (sin .env)
make backup-full  # Backup completo incluyendo .env (contiene credenciales)
```

Los backups se guardan en `./backups/` con timestamp. Para restaurar:

```bash
cd notflix
tar -xzf backups/notflix-backup-YYYYMMDD-HHMMSS.tar.gz
make up
```

## Reinstalación / Migración

```bash
# Copiar al nuevo servidor (incluir */config para mantener configuración):
rsync -av --exclude='downloads/' notflix/ nuevo-servidor:~/notflix/

# En el nuevo servidor:
make up
```

## Comandos Make

| Comando | Descripción |
|---|---|
| `make create-folders` | Crea la estructura de directorios |
| `make up` | Siembra configs, levanta el stack y ejecuta el provisioner |
| `make down` | Detiene todos los servicios |
| `make restart` | Reinicia todos los servicios |
| `make status` | Estado de los contenedores |
| `make provision` | Re-ejecuta el provisioner (idempotente) |
| `make recyclarr` | Sincroniza quality profiles con TRaSH-Guides |
| `make backup` | Backup de configuraciones |
| `make backup-full` | Backup completo con `.env` |
| `make logs-<servicio>` | Logs individuales: `plex`, `qbit`, `radarr`, `sonarr`, `prowlarr`, `flare`, `caddy`, `provisioner`, `overseerr`, `ntfy`, `diun` |

## Configuración Manual Post-Arranque

### qBittorrent

```bash
make logs-qbit
# Buscar: "A temporary password is provided for this session: XXXXXX"
```

Cambiar la contraseña en Tools > Options > Web UI > Password al valor de `QBIT_PASS` del `.env`.

### Prowlarr

- Añadir indexers en http://prowlarr.notflix.internal → Settings > Indexers

### Custom Format Español

Settings > Custom Formats > Import → pegar el contenido de `custom-format-español.json`

### Plex

- Bibliotecas: Movies → `/movies`, TV Shows → `/tv`
- Settings > Remote Access > Custom server access URLs: `http://plex.notflix.internal`

## Notas

- El tráfico viaja cifrado por WireGuard (Tailscale) → HTTP interno es seguro.
- Si cambia la IP Tailscale del servidor: actualizar `dnsmasq/dnsmasq.conf` + `docker compose restart dnsmasq`.
- Los directorios de runtime no están versionados. Hacer `make backup` antes de migrar.

## Licencia

MIT
