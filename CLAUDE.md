# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**Notflix** is a Docker-based self-hosted media server stack running on **Ubuntu Server**, accessible via **Tailscale**. All services are exposed via a Caddy reverse proxy using `*.notflix.internal` domains, resolved automatically on all Tailscale devices via Split DNS.

## Requisitos del Servidor

- Ubuntu Server + Docker Engine v2 + Docker Compose plugin
- Tailscale instalado y autenticado
- Puerto 53 libre (deshabilitar stub listener de systemd-resolved)

## Common Commands

```bash
make create-folders    # Inicializar estructura de directorios (una vez)
make up                # Sembrar configs + levantar stack + provisioner automático
make down              # Parar el stack
make restart           # Reiniciar el stack
make status            # Estado de los contenedores
make provision         # Re-ejecutar el provisioner manualmente (idempotente)
make recyclarr         # Sincronizar quality profiles con TRaSH-Guides
make backup            # Backup de configuraciones (sin .env)
make backup-full       # Backup completo incluyendo .env
make logs              # Logs de todos los servicios
make logs-<servicio>   # Logs individuales (ver make help para lista completa)
```

## Architecture

```
Dispositivo Tailscale → Split DNS → dnsmasq (puerto 53) → IP Tailscale del servidor
                                                              ↓
                                                          Caddy (puerto 80)
                                                              ↓
                                              Contenedor del servicio (red interna)
```

| Servicio | Puerto interno | URL |
|---|---|---|
| Caddy | 80 | — (reverse proxy) |
| dnsmasq | 53 | — (DNS) |
| qBittorrent | 8080 | http://qbittorrent.notflix.internal |
| Prowlarr | 9696 | http://prowlarr.notflix.internal |
| FlareSolverr | 8191 | http://flaresolverr.notflix.internal |
| Radarr | 7878 | http://radarr.notflix.internal |
| Sonarr | 8989 | http://sonarr.notflix.internal |
| Plex | 32400 | http://plex.notflix.internal |
| Overseerr | 5055 | http://overseerr.notflix.internal |
| ntfy | 80 | http://ntfy.notflix.internal |
| Recyclarr | — | one-shot (`make recyclarr`) |
| Diun | — | daemon, notifica vía ntfy |

**Data flow:** Prowlarr (+ FlareSolverr) → Radarr/Sonarr → qBittorrent → `downloads/` → Plex
**Requests flow:** Overseerr → Radarr/Sonarr → (download flow above)
**Notifications:** Radarr/Sonarr → ntfy → móvil via Tailscale

## Configuración vía `.env`

Todo lo configurable está en `.env` (no versionado). Referencia: `.env.example`.

Variables clave:
- `PUID` / `PGID` — usuario del servidor (`id -u && id -g`)
- `DOMAIN` — dominio base (default: `notflix.internal`)
- `RADARR_API_KEY`, `SONARR_API_KEY`, `PROWLARR_API_KEY` — generar con `openssl rand -hex 16`
- `QBIT_USER` / `QBIT_PASS` — credenciales qBittorrent
- `RADARR_VERSION`, `SONARR_VERSION`, etc. — versiones de imágenes (ver sección versiones)

## Gestión de Versiones

Las imágenes usan `lscr.io/linuxserver/` (registry oficial LinuxServer) en lugar de Docker Hub.
Las versiones se controlan via variables en `.env` (`RADARR_VERSION=latest`).

**Proceso de pinning tras el primer despliegue:**
```bash
docker inspect radarr | jq -r '.[0].Config.Image'
# Copiar la versión al .env: RADARR_VERSION=5.x.x
```

**Proceso de actualización controlada:**
1. Diun notifica (via ntfy, tópico `notflix-updates`) que hay nueva versión
2. Revisar changelog del servicio
3. Actualizar `RADARR_VERSION` en `.env`
4. `docker compose pull radarr && docker compose up -d radarr`

## Zero-Touch Provisioning

El stack se autoconfigura en dos fases:

### 1. Pre-seed de config.xml (`provisioner/seed.sh`)

Ejecutado por `make up` **antes** de `docker compose up -d` via `--no-deps`. Copia
`config-templates/{radarr,sonarr,prowlarr}/config.xml` (con `envsubst`) a los
directorios de configuración. Garantiza que los servicios Arr arrancan con la API key
conocida del `.env` en lugar de generar una aleatoria.

### 2. Provisioner API (`provisioner/provision.sh`)

Contenedor one-shot (`restart: "no"`) con `depends_on: service_healthy`. Configura:
- FlareSolverr en Prowlarr
- Prowlarr ↔ Radarr / Sonarr (fullSync)
- qBittorrent como download client en Radarr y Sonarr
- Root folders `/movies` y `/tv`
- Notificaciones ntfy en Radarr y Sonarr

Re-ejecutable con `make provision` (idempotente).

## Quality Profiles — Recyclarr

`recyclarr/recyclarr.yml` define perfiles de calidad sincronizados desde TRaSH-Guides.
Complementa `custom-format-español.json` (importable manualmente en Radarr/Sonarr).
Ejecutar con `make recyclarr` tras el provisioning inicial.

## What's Version-Controlled vs. Ignored

Versionado:
- `docker-compose.yml`, `Makefile`, `Caddyfile`
- `dnsmasq/dnsmasq.conf` — contiene IP Tailscale del servidor (actualizar al migrar)
- `.env.example` — plantilla sin credenciales
- `config-templates/` — templates XML para pre-seed
- `provisioner/` — Dockerfile + seed.sh + provision.sh
- `recyclarr/recyclarr.yml`, `ntfy/server.yml`, `diun/diun.yml`
- `custom-format-español.json`
- `.claude/plans/`

No versionado (`.gitignore`):
- `.env` — contiene credenciales
- `/radarr/`, `/sonarr/`, `/prowlarr/`, `/qbittorrent/`, `/plex/`, `/overseerr/` — datos runtime
- `/ntfy/data/`, `/diun/data/` — datos runtime (configs sí versionadas)
- `backups/`

## Adding or Modifying Services

1. Añadir a `docker-compose.yml` con `networks: [media-network]`, variables `${PUID}/${PGID}/${TZ}`
2. Añadir al `Caddyfile`: `servicio.{$DOMAIN:notflix.internal} { reverse_proxy servicio:<puerto> }`
3. Añadir `make logs-<servicio>` al Makefile
4. Si tiene API key: añadir template en `config-templates/`, extender `seed.sh` y `provision.sh`
5. Añadir a `.gitignore` si el directorio de runtime no debe versionarse
6. Actualizar README.md y CLAUDE.md

## DNS: Tailscale Split DNS

`dnsmasq/dnsmasq.conf` contiene la IP Tailscale del servidor. Si cambia:
```bash
# Editar dnsmasq/dnsmasq.conf → actualizar 100.x.x.x
docker compose restart dnsmasq
```

Configuración única en Tailscale admin:
DNS → Add nameserver → Custom → IP Tailscale → Domain: `notflix.internal` → Restrict to domain.
