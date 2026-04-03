---
plan_id: 03
title: Stack Modernization — Versiones, Calidad, Peticiones, Notificaciones
status: completed
risk_level: low-medium
depends_on: 01, 02
---

# Plan 03 — Modernización del Stack

## Objetivo

Elevar el stack de "funcional" a "homelab production-grade":

- Versiones pinned (no más sorpresas con `latest`)
- Perfiles de calidad como código (Recyclarr + TRaSH-Guides)
- Interfaz de peticiones de contenido (Overseerr)
- Notificaciones push en el móvil (ntfy)
- Aviso de actualizaciones de imágenes sin auto-update (Diun)
- Backup con un solo comando

---

## Componentes Nuevos

| Servicio | Puerto interno | Propósito |
|---|---|---|
| Recyclarr | — (one-shot) | Quality profiles desde TRaSH-Guides como código |
| Overseerr | 5055 | Peticiones de contenido con auth Plex |
| ntfy | 80 (interno) | Push notifications self-hosted |
| Diun | — | Detectar nuevas versiones de imágenes Docker |

---

## Implementación

### Paso 1 — Pinear versiones de imágenes

Reemplazar todos los `:latest` por versiones semánticas. Migrar de `linuxserver/` (Docker Hub)
a `lscr.io/linuxserver/` (registry oficial de LinuxServer, más estable).

**Obtener versiones actuales instaladas:**

```bash
docker inspect radarr      | jq -r '.[0].Config.Image'
docker inspect sonarr      | jq -r '.[0].Config.Image'
docker inspect prowlarr    | jq -r '.[0].Config.Image'
docker inspect qbittorrent | jq -r '.[0].Config.Image'
docker inspect plex-server | jq -r '.[0].Config.Image'
```

Registrar las versiones en `docker-compose.yml`:

```yaml
# ANTES:
#   image: linuxserver/radarr:latest
# DESPUÉS:
#   image: lscr.io/linuxserver/radarr:5.x.x

services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:5.x.x
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:1.x.x
  radarr:
    image: lscr.io/linuxserver/radarr:5.x.x
  sonarr:
    image: lscr.io/linuxserver/sonarr:4.x.x
  plex:
    image: lscr.io/linuxserver/plex:1.x.x
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:v0.x.x
  caddy:
    image: caddy:2.x.x-alpine
```

**Referencias para versiones actuales:**

- LinuxServer fleet: `https://fleet.linuxserver.io/`
- FlareSolverr releases: `https://github.com/FlareSolverr/FlareSolverr/releases`

**Proceso de actualización futura (manual + controlado):**

```bash
# Diun notifica que hay nueva versión (ver Paso 4)
# 1. Consultar changelog del servicio
# 2. Cambiar versión en docker-compose.yml
# 3. Actualizar solo ese servicio:
docker compose pull radarr
docker compose up -d radarr
```

---

### Paso 2 — Recyclarr: Perfiles de Calidad como Código

Recyclarr sincroniza quality profiles y custom formats de TRaSH-Guides directamente
en Radarr y Sonarr via API. El `custom-format-español.json` del repo es el complemento
perfecto: Recyclarr lo puede referenciar para garantizar que el formato Español esté
siempre configurado.

**Crear `recyclarr/recyclarr.yml`:**

```yaml
radarr:
  notflix-radarr:
    base_url: http://radarr:7878
    api_key: !env_var RADARR_API_KEY

    quality_profiles:
      - name: "Español HD"
        reset_unmatched_scores:
          enabled: true
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
          until_score: 10000
        qualities:
          - name: Bluray-1080p
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
          - name: Bluray-720p

    custom_formats:
      # IDs de TRaSH-Guides para audio/releases en español
      - trash_ids:
          - 4b900e171accbfb172729b63323f9d5e  # Blu-ray
        quality_profiles:
          - name: "Español HD"
            score: 500

sonarr:
  notflix-sonarr:
    base_url: http://sonarr:8989
    api_key: !env_var SONARR_API_KEY

    quality_profiles:
      - name: "Español HD Series"
        upgrade:
          allowed: true
          until_quality: Bluray-1080p
          until_score: 10000
        qualities:
          - name: Bluray-1080p
          - name: WEB 1080p
            qualities:
              - WEBDL-1080p
              - WEBRip-1080p
```

**Añadir servicio al `docker-compose.yml`:**

```yaml
  recyclarr:
    image: ghcr.io/recyclarr/recyclarr:latest
    container_name: recyclarr
    user: "${PUID:-1000}:${PGID:-1000}"
    volumes:
      - ./recyclarr:/config
    env_file: .env
    environment:
      - TZ=${TZ:-Europe/Madrid}
    restart: "no"
    networks:
      - media-network
```

**Añadir al Makefile:**

```makefile
recyclarr:
	@echo $(GREEN)Sincronizando perfiles de calidad con TRaSH-Guides...$(RESET)
	$(COMPOSE) run --rm recyclarr sync

recyclarr-list:
	$(COMPOSE) run --rm recyclarr list custom-formats radarr
```

**Primera ejecución:**

```bash
# Inicializar y validar config antes de sincronizar
docker compose run --rm recyclarr config list
make recyclarr
```

---

### Paso 3 — Overseerr: Interfaz de Peticiones

Overseerr permite solicitar contenido con autenticación Plex y envía las peticiones
automáticamente a Radarr/Sonarr.

**Añadir al `docker-compose.yml`:**

```yaml
  overseerr:
    image: lscr.io/linuxserver/overseerr:latest
    container_name: overseerr
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Europe/Madrid}
    volumes:
      - ./overseerr/config:/config
    restart: unless-stopped
    networks:
      - media-network
```

**Añadir al `Caddyfile` (del Plan 01):**

```caddyfile
overseerr.{$DOMAIN:notflix.internal} {
  reverse_proxy overseerr:5055
}
```

**Actualizar `create-folders` en Makefile:**

```makefile
create-folders:
	mkdir -p {plex,qbittorrent,radarr,sonarr,prowlarr,overseerr,recyclarr}/config
	mkdir -p plex/transcode
	mkdir -p downloads/{movies,tv,incomplete}
	mkdir -p dnsmasq ntfy/data diun
```

**Configuración manual (una vez, no automatizable sin OAuth de Plex):**

1. Abrir `http://overseerr.notflix.internal`
2. Login con cuenta Plex
3. Conectar con Plex server → autodetección dentro de `media-network`
4. Añadir Radarr: URL `http://radarr:7878`, API key desde `.env`
5. Añadir Sonarr: URL `http://sonarr:8989`, API key desde `.env`

---

### Paso 4 — ntfy: Push Notifications Self-Hosted

ntfy es un servidor de notificaciones push ligero. Radarr, Sonarr y Prowlarr tienen
soporte de webhook nativo compatible con ntfy.

**Crear `ntfy/server.yml`:**

```yaml
base-url: http://ntfy.notflix.internal
behind-proxy: true
```

**Añadir al `docker-compose.yml`:**

```yaml
  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: ntfy
    command: serve --config /etc/ntfy/server.yml
    volumes:
      - ./ntfy/server.yml:/etc/ntfy/server.yml:ro
      - ./ntfy/data:/var/lib/ntfy
    environment:
      - TZ=${TZ:-Europe/Madrid}
    restart: unless-stopped
    networks:
      - media-network
```

**Añadir al `Caddyfile`:**

```caddyfile
ntfy.{$DOMAIN:notflix.internal} {
  reverse_proxy ntfy:80
}
```

**Integrar en el provisioner (añadir a `provision.sh` del Plan 02):**

```bash
log "Configurando notificaciones ntfy en Radarr..."
EXISTING=$(radarr_api "notification" | jq '[.[] | select(.name == "ntfy")]')
if ! already_exists "$EXISTING"; then
  radarr_api "notification" \
    -X POST -H "Content-Type: application/json" \
    -d '{
      "name": "ntfy",
      "implementation": "Webhook",
      "configContract": "WebhookSettings",
      "onDownload": true,
      "onUpgrade": true,
      "onHealthIssue": true,
      "fields": [
        {"name": "url",    "value": "http://ntfy:80/notflix-movies"},
        {"name": "method", "value": 0}
      ]
    }'
fi

log "Configurando notificaciones ntfy en Sonarr..."
EXISTING=$(sonarr_api "notification" | jq '[.[] | select(.name == "ntfy")]')
if ! already_exists "$EXISTING"; then
  sonarr_api "notification" \
    -X POST -H "Content-Type: application/json" \
    -d '{
      "name": "ntfy",
      "implementation": "Webhook",
      "configContract": "WebhookSettings",
      "onDownload": true,
      "onUpgrade": true,
      "onHealthIssue": true,
      "fields": [
        {"name": "url",    "value": "http://ntfy:80/notflix-series"},
        {"name": "method", "value": 0}
      ]
    }'
fi
```

**App móvil:** Instalar ntfy (iOS/Android) → suscribirse a:

- `http://ntfy.notflix.internal/notflix-movies`
- `http://ntfy.notflix.internal/notflix-series`

Accesible directamente via Tailscale desde el móvil (si tiene Tailscale instalado).

---

### Paso 5 — Diun: Notificaciones de Actualizaciones

Diun detecta nuevas versiones de imágenes y notifica vía ntfy sin actualizar nada.
Esto da control total sobre cuándo actualizar.

**Crear `diun/diun.yml`:**

```yaml
notif:
  ntfy:
    endpoint: http://ntfy:80
    topic: notflix-updates
    priority: 3

watch:
  workers: 5
  schedule: "0 9 * * 1"  # Lunes a las 9:00
  jitter: 30s

db:
  path: /data/diun.db
```

**Añadir al `docker-compose.yml`:**

```yaml
  diun:
    image: crazymax/diun:latest
    container_name: diun
    command: serve
    volumes:
      - ./diun/diun.yml:/diun.yml:ro
      - ./diun/data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=${TZ:-Europe/Madrid}
    restart: unless-stopped
    networks:
      - media-network
```

Diun autodescubre todos los contenedores del host. Cuando haya nueva versión de
`lscr.io/linuxserver/radarr`, llega una notificación a ntfy → tú decides cuándo actualizar.

---

### Paso 6 — Backup con un Comando

**Añadir al Makefile:**

```makefile
BACKUP_DIR ?= ./backups

backup:
	@echo $(GREEN)Creando backup de configuraciones...$(RESET)
	@mkdir -p $(BACKUP_DIR)
	@tar -czf $(BACKUP_DIR)/notflix-backup-$$(date +%Y%m%d-%H%M%S).tar.gz \
	  radarr/config sonarr/config prowlarr/config \
	  qbittorrent/config overseerr/config recyclarr \
	  dnsmasq ntfy/server.yml diun/diun.yml \
	  Caddyfile docker-compose.yml .env.example
	@echo $(GREEN)Backup guardado en $(BACKUP_DIR)/$(RESET)
	@ls -lh $(BACKUP_DIR)/ | tail -5
```

Nota: `.env` no se incluye en el backup de git, pero sí debería estar en el backup
del servidor. Añadir opcionalmente:

```makefile
backup-full: backup
	@tar -czf $(BACKUP_DIR)/notflix-env-$$(date +%Y%m%d-%H%M%S).tar.gz .env
	@echo $(YELLOW)AVISO: backup-env contiene credenciales. Guardar en lugar seguro.$(RESET)
```

---

### Paso 7 — Nota sobre VPN para qBittorrent (Opcional)

Para privacidad del tráfico torrent, el patrón estándar es usar **Gluetun** como
contenedor VPN y enrutar qBittorrent a través de él.

```yaml
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - VPN_SERVICE_PROVIDER=${VPN_PROVIDER}   # mullvad, protonvpn, etc.
      - VPN_TYPE=wireguard
      - WIREGUARD_PRIVATE_KEY=${VPN_PRIVATE_KEY}
      - SERVER_COUNTRIES=${VPN_COUNTRIES:-Spain,Netherlands}
    ports:
      - "8080:8080"   # qBit WebUI expuesto a través de Gluetun
      - "6881:6881"
      - "6881:6881/udp"
    restart: unless-stopped
    networks:
      - media-network

  qbittorrent:
    network_mode: "service:gluetun"   # Todo el tráfico pasa por la VPN
    # Eliminar ports: (los hereda de Gluetun)
    # Eliminar networks: (usa la red de Gluetun)
    depends_on:
      - gluetun
```

Si se implementa Gluetun, se recomienda un Plan 04 dedicado.

---

## Estructura Final del Stack

```
notflix/
├── Caddyfile
├── docker-compose.yml
├── Makefile
├── .env                      (no en git)
├── .env.example
├── dnsmasq/dnsmasq.conf
├── provisioner/
│   ├── Dockerfile
│   └── provision.sh
├── config-templates/
│   ├── radarr/config.xml
│   ├── sonarr/config.xml
│   └── prowlarr/config.xml
├── recyclarr/recyclarr.yml
├── ntfy/server.yml
├── diun/diun.yml
├── custom-format-español.json
├── backups/                  (no en git)
└── [runtime — en .gitignore]
    ├── downloads/
    ├── plex/
    ├── radarr/
    ├── sonarr/
    ├── prowlarr/
    ├── qbittorrent/
    ├── overseerr/
    └── ntfy/data/
```

---

## Resumen de Comandos Tras los 3 Planes

```bash
make create-folders  # Crear estructura de directorios
make up              # Levantar el stack (provisioner corre automáticamente)
make down            # Parar el stack
make restart         # Reiniciar el stack
make status          # Estado de contenedores
make provision       # Re-ejecutar provisioner (idempotente)
make recyclarr       # Sincronizar quality profiles con TRaSH-Guides
make backup          # Backup de configuraciones
make logs-<servicio> # Logs de un servicio específico
```

---

## Actualización de Documentación (al completar este plan)

Actualizar `README.md` con:

1. **Stack completo**: añadir Overseerr, ntfy, Recyclarr y Diun a la tabla de servicios
2. **Sección "Actualizaciones"**: documentar flujo Diun → revisión changelog → bump de versión
3. **Sección "Quality Profiles"**: cómo usar Recyclarr y la relación con `custom-format-español.json`
4. **Sección "Notificaciones"**: cómo suscribirse a ntfy desde el móvil
5. **Sección "Backup y Restauración"**: `make backup` y proceso de restauración
6. **Sección "Peticiones de contenido"**: flujo Overseerr → Radarr/Sonarr

Actualizar `CLAUDE.md`:
- Tabla de servicios actualizada con Overseerr, ntfy, Recyclarr, Diun
- Añadir sección sobre gestión de versiones (Diun + proceso de actualización manual)
- Documentar la relación entre `custom-format-español.json` y Recyclarr
