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
id -u          # → PUID
id -g          # → PGID
tailscale ip -4  # → TAILSCALE_IP

# Generar API keys:
echo "RADARR_API_KEY=$(openssl rand -hex 16)"
echo "SONARR_API_KEY=$(openssl rand -hex 16)"
echo "PROWLARR_API_KEY=$(openssl rand -hex 16)"
```

Variables a configurar en `.env`:

| Variable | Cómo obtenerla |
|---|---|
| `PUID` / `PGID` | `id -u && id -g` |
| `TAILSCALE_IP` | `tailscale ip -4` |
| `RADARR_API_KEY` | `openssl rand -hex 16` |
| `SONARR_API_KEY` | `openssl rand -hex 16` |
| `PROWLARR_API_KEY` | `openssl rand -hex 16` |
| `QBIT_PASS` | Contraseña segura a elegir |

### 2. Crear estructura de directorios

```bash
make create-folders
```

Si existe `/mnt/media` (disco externo), crea `movies/`, `tv/`, `downloads/` allí y los enlaza simbólicamente. Si no, crea los directorios localmente.

### 3. Liberar el puerto 53 en Ubuntu (una vez)

```bash
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
sudo ss -tulpn | grep ':53'   # verificar que el puerto está libre
```

### 4. Permitir tráfico Tailscale → Docker (una vez)

Docker y Tailscale tienen reglas iptables independientes. Por defecto, el tráfico que llega por la interfaz `tailscale0` no alcanza los contenedores Docker. Hay que añadir una regla y hacerla persistente:

```bash
# Permitir tráfico de Tailscale hacia contenedores Docker
sudo iptables -I DOCKER-USER -i tailscale0 -j ACCEPT

# Instalar iptables-persistent para que la regla sobreviva reinicios
sudo apt install iptables-persistent -y
sudo netfilter-persistent save
```

Verificar que la regla está activa:

```bash
sudo iptables -L DOCKER-USER -n -v
# Debe aparecer: ACCEPT all -- tailscale0 *
```

> Si no se aplica esta regla, los dominios `*.notflix.internal` resolverán correctamente pero el navegador obtendrá "Connection refused" al intentar conectar.

### 5. Configurar Tailscale Split DNS (una vez por tailnet)

Necesario antes de acceder a los servicios por nombre. En `login.tailscale.com/admin/dns`:

1. **DNS** → **Add nameserver** → **Custom**
2. **Nameserver:** IP Tailscale del servidor (`TAILSCALE_IP` del `.env`)
3. **Domain:** `notflix.internal` + activar **"Restrict to domain"**

Verificar desde cualquier dispositivo Tailscale: `dig radarr.notflix.internal` → debe devolver la IP Tailscale del servidor.

### 6. Iniciar el stack

```bash
make up
```

`make up` ejecuta en orden:
1. **seed.sh** — genera `dnsmasq/dnsmasq.conf` desde el template con `TAILSCALE_IP`, y siembra los `config.xml` de los servicios Arr con las API keys del `.env` (si no existen)
2. Levanta todos los servicios en background
3. El **provisioner** arranca automáticamente cuando los servicios están healthy y configura todas las interconexiones vía API

### 7. Cambiar contraseña de qBittorrent (primer arranque)

En el primer arranque, qBittorrent genera una contraseña temporal:

```bash
make logs-qbit | grep -i "temporary password"
# Buscar: "A temporary password is provided for this session: XXXXXX"
```

Accede a **http://qbittorrent.notflix.internal** → **Tools → Options → Web UI → Password** → cambia al valor de `QBIT_PASS` del `.env` → Apply.

Luego re-ejecuta el provisioner para completar la configuración de qBittorrent:

```bash
make provision
```

### 8. Configurar credenciales de Prowlarr, Radarr y Sonarr (primer arranque)

En el primer acceso a cada servicio, el wizard pregunta el método de autenticación y las credenciales:

1. Acceder a **http://prowlarr.notflix.internal**, **http://radarr.notflix.internal** y **http://sonarr.notflix.internal**
2. En el wizard elegir **Forms** y crear usuario (ej: `admin` / `admin`)  
   — o seleccionar **"Authentication Disabled"** si se prefiere sin login (la red ya está protegida por Tailscale)
3. Repetir en los tres servicios

> El provisioner configura todo vía API key y no requiere credenciales web. Este paso es solo para acceder a la UI.

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

> **qBittorrent:** La configuración del download client en Radarr/Sonarr requiere que la contraseña de qBittorrent ya esté cambiada al valor de `QBIT_PASS`. Ver paso 6 de la instalación.
>
> **Prowlarr / Radarr / Sonarr:** En el primer acceso la UI muestra un wizard para configurar autenticación. Ver paso 7.

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

Ver **paso 7** de la instalación. Resumen: obtener contraseña temporal con `make logs-qbit | grep -i "temporary password"`, cambiarla en la WebUI y ejecutar `make provision`.

### Prowlarr / Radarr / Sonarr — Autenticación

Ver **paso 7** de la instalación. En el primer acceso aparece un wizard para elegir método de autenticación y crear credenciales. El provisioner no necesita credenciales web (usa API key).

### Prowlarr — Indexers

- Añadir indexers en `http://prowlarr.notflix.internal` → Settings > Indexers

### Custom Format Español

Settings > Custom Formats > Import → pegar el contenido de `custom-format-español.json`

### Plex

- Bibliotecas: Movies → `/movies`, TV Shows → `/tv`
- Settings > Remote Access > Custom server access URLs: `http://plex.notflix.internal`

## Notas

- El tráfico viaja cifrado por WireGuard (Tailscale) → HTTP interno es seguro.
- Si cambia la IP Tailscale del servidor: actualizar `TAILSCALE_IP` en `.env` y ejecutar `make up` (seed.sh regenera `dnsmasq.conf` automáticamente).
- Los directorios de runtime no están versionados. Hacer `make backup` antes de migrar.
- **Tailscale + Docker iptables:** La regla `iptables -I DOCKER-USER -i tailscale0 -j ACCEPT` es obligatoria. Sin ella el DNS funciona pero HTTP falla. Debe persistirse con `netfilter-persistent save`.
- **dnsmasq:** La imagen `ricardbejarano/dnsmasq` escucha internamente en el puerto 1053 (no 53). El mapeo en `docker-compose.yml` es `53:1053`.

## Apéndice: Disco Externo para Medios

`make create-folders` detecta automáticamente `/mnt/media` y crea allí la estructura de directorios (`movies/`, `tv/`, `downloads/`) con symlinks desde el proyecto. Si quieres usar un disco externo como almacenamiento de medios, sigue estos pasos.

### 1. Formatear y montar el disco (primera vez)

```bash
# Identificar el disco (buscar el de mayor tamaño sin montar)
lsblk

# Formatear en ext4 (⚠️ borra todos los datos del disco)
sudo mkfs.ext4 /dev/sdX

# Crear punto de montaje y montar
sudo mkdir -p /mnt/media
sudo mount /dev/sdX /mnt/media
```

### 2. Montar automáticamente al arranque (fstab)

Sin esta configuración el disco se pierde en cada reinicio del servidor.

```bash
# Obtener UUID del disco
sudo blkid /dev/sdX

# Añadir al fstab (sustituir UUID por el obtenido)
echo 'UUID=<uuid-del-disco> /mnt/media ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

# Verificar que la entrada es correcta
sudo mount -a
df -h | grep media
```

> `nofail` evita que el servidor no arranque si el disco externo no está conectado en el momento del boot.

### 3. Asignar permisos al usuario del servidor

```bash
sudo chown -R calle:calle /mnt/media
```

Sustituir `calle` por el usuario configurado en `PUID`/`PGID` del `.env`.

### Nota sobre nombres de dispositivo

Los nombres `/dev/sdb`, `/dev/sdc`, etc. pueden cambiar entre arranques si hay varios discos. Usar siempre **UUID** en fstab (como en el paso 2) garantiza que el disco correcto se monta en `/mnt/media` independientemente del nombre asignado.

## Licencia

MIT
