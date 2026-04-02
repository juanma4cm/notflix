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
# PUID y PGID del usuario que ejecuta Docker:
id -u   # → PUID
id -g   # → PGID

# Generar API keys para los servicios Arr:
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
# En el servidor, obtener la IP Tailscale:
tailscale ip -4
# Editar dnsmasq/dnsmasq.conf y sustituir 100.x.x.x por la IP obtenida
```

### 4. Liberar el puerto 53 en Ubuntu (una vez)

`systemd-resolved` ocupa el puerto 53 por defecto:

```bash
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
sudo ss -tulpn | grep ':53'   # verificar que el puerto está libre
```

### 5. Iniciar el stack

```bash
make up
```

`make up` hace tres cosas en orden:
1. Siembra los `config.xml` en los servicios Arr (con las API keys del `.env`) si no existen
2. Levanta todos los servicios en background
3. El contenedor `provisioner` arranca automáticamente cuando todos los servicios están healthy, y configura las interconexiones vía API

### 6. Configurar Tailscale Split DNS (una vez por tailnet)

En el panel de Tailscale (`login.tailscale.com/admin/dns`):

1. **DNS** → **Add nameserver** → **Custom**
2. **Nameserver:** IP Tailscale del servidor (la del paso 3)
3. **Domain:** `notflix.internal`
4. Activar **"Restrict to domain"**

Verificar desde cualquier dispositivo Tailscale:

```bash
dig radarr.notflix.internal
# Debe devolver la IP Tailscale del servidor
```

## Lo que se configura automáticamente

Tras `make up`, el provisioner configura:

| Configuración | Estado |
|---|---|
| FlareSolverr como proxy en Prowlarr | Automático |
| Prowlarr conectado a Radarr (fullSync) | Automático |
| Prowlarr conectado a Sonarr (fullSync) | Automático |
| qBittorrent como download client en Radarr | Automático |
| qBittorrent como download client en Sonarr | Automático |
| Root folders `/movies` y `/tv` en Radarr/Sonarr | Automático |
| Indexers en Prowlarr | Manual (requieren credenciales) |
| Biblioteca de Plex | Manual (requiere PLEX_CLAIM token) |

> **Nota sobre qBittorrent:** En el primer arranque, qBittorrent genera una contraseña temporal que aparece en los logs (`make logs-qbit`). Cámbiala en la WebUI al valor de `QBIT_PASS` del `.env` y luego ejecuta `make provision` para completar su configuración.

## Reinstalación / Migración

Para migrar el stack a otro servidor o reinstalar desde cero:

```bash
# 1. Copiar al nuevo servidor:
rsync -av --exclude='downloads/' notflix/ nuevo-servidor:~/notflix/
# Incluir también los directorios */config si quieres mantener la configuración

# 2. En el nuevo servidor:
make up
```

Si los directorios `*/config` están presentes, el provisioner detecta los `config.xml` existentes y no los sobreescribe. Las interconexiones se reconfiguran igualmente (son idempotentes).

## Comandos Make

| Comando | Descripción |
|---|---|
| `make create-folders` | Crea la estructura de directorios |
| `make up` | Siembra configs, levanta servicios y ejecuta el provisioner |
| `make down` | Detiene todos los servicios |
| `make restart` | Reinicia todos los servicios |
| `make status` | Estado de los contenedores |
| `make provision` | Re-ejecuta el provisioner manualmente (idempotente) |
| `make logs` | Logs de todos los servicios |
| `make logs-<servicio>` | Logs individuales: `plex`, `qbit`, `radarr`, `sonarr`, `prowlarr`, `flare`, `caddy`, `provisioner` |

## Configuración Manual Post-Arranque

### qBittorrent

La primera vez qBittorrent genera una contraseña temporal:

```bash
make logs-qbit
# Buscar: "A temporary password is provided for this session: XXXXXX"
```

Cambiarla en Tools > Options > Web UI > Password al valor de `QBIT_PASS` del `.env`.

### Prowlarr

- Accede a http://prowlarr.notflix.internal
- Añadir indexers: Settings > Indexers (requieren cuentas en los trackers)

### Plex

- Accede a http://plex.notflix.internal
- Añadir bibliotecas: Movies → `/movies`, TV Shows → `/tv`
- Settings > Remote Access > Custom server access URLs: `http://plex.notflix.internal`

### Custom Format Español

El archivo `custom-format-español.json` de la raíz puede importarse en Radarr/Sonarr:
Settings > Custom Formats > Import

## Notas

- El tráfico entre dispositivos va cifrado por WireGuard (Tailscale), por eso se usa HTTP internamente.
- Las IPs Tailscale son estables. Si cambia la del servidor, actualizar `dnsmasq/dnsmasq.conf` y reiniciar `dnsmasq` (`docker compose restart dnsmasq`).
- Los directorios de runtime (`radarr/`, `sonarr/`, etc.) no están versionados. Incluirlos en backups antes de migrar.

## Licencia

MIT
