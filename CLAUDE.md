# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**Notflix** is a Docker-based self-hosted media server stack running on **Ubuntu Server**, accessible via **Tailscale**. It orchestrates services for automated media acquisition and streaming, exposed via a Caddy reverse proxy with local domain names (`*.notflix.internal`).

## Requisitos del Servidor

- Ubuntu Server + Docker Engine v2 + Docker Compose plugin
- Tailscale instalado y autenticado
- Puerto 53 libre (deshabilitar stub listener de systemd-resolved)

## Common Commands

```bash
make create-folders   # Inicializar estructura de directorios (una vez)
make up               # Sembrar configs + levantar stack + provisioner automático
make down             # Parar el stack
make restart          # Reiniciar el stack
make status           # Estado de los contenedores
make provision        # Re-ejecutar el provisioner manualmente (idempotente)
make logs             # Logs de todos los servicios
make logs-<servicio>  # Logs individuales: plex, qbit, radarr, sonarr, prowlarr, flare, caddy, provisioner
```

## Architecture

Todos los servicios corren en la red Docker `media-network`. Caddy actúa como reverse proxy
enrutando por nombre de host. dnsmasq resuelve `*.notflix.internal` → IP Tailscale del servidor.
El cliente Tailscale en cada dispositivo usa Split DNS para dirigir queries `.notflix.internal`
al dnsmasq del servidor automáticamente.

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

**Data flow:** Prowlarr (+ FlareSolverr) → Radarr/Sonarr → qBittorrent → `downloads/` → Plex

## Configuración vía `.env`

Toda la configuración variable está en `.env` (no versionado). Referencia: `.env.example`.

```env
PUID=1000                  # id -u en el servidor
PGID=1000                  # id -g en el servidor
TZ=Europe/Madrid
DOMAIN=notflix.internal
RADARR_API_KEY=...         # openssl rand -hex 16
SONARR_API_KEY=...
PROWLARR_API_KEY=...
QBIT_USER=admin
QBIT_PASS=...
```

## Zero-Touch Provisioning

El stack se autoconfigura mediante dos mecanismos:

### 1. Pre-seed de config.xml (`provisioner/seed.sh`)

Ejecutado por `make up` **antes** de arrancar los servicios (via `docker compose run --rm --no-deps provisioner /seed.sh`). Copia los templates de `config-templates/` a los directorios de configuración sustituyendo las variables del `.env` con `envsubst`. Esto garantiza que los servicios Arr arrancan con la API key conocida en lugar de generar una aleatoria.

- Es idempotente: no sobreescribe si `config.xml` ya existe
- Templates en: `config-templates/{radarr,sonarr,prowlarr}/config.xml`

### 2. Provisioner API (`provisioner/provision.sh`)

Contenedor one-shot (`restart: "no"`) que arranca automáticamente después de que todos los servicios pasan sus health checks. Configura vía API:

- FlareSolverr como proxy en Prowlarr
- Conexión Prowlarr ↔ Radarr y Prowlarr ↔ Sonarr (fullSync)
- qBittorrent como download client en Radarr y Sonarr
- Root folders `/movies` y `/tv`

Re-ejecutable manualmente con `make provision`.

### Timing

```
make up
  ├── docker compose run --no-deps provisioner /seed.sh   (escribe config.xml ANTES de arrancar)
  └── docker compose up -d
        ├── servicios arrancan con config.xml ya sembrado
        └── provisioner (depends_on: healthy) → configura interconexiones via API
```

## What's Version-Controlled vs. Ignored

El `.gitignore` excluye los directorios de configuración runtime (`plex/`, `radarr/`, etc.)
y el `.env`. Se versionan:

- `docker-compose.yml` — definición del stack
- `Makefile` — comandos
- `Caddyfile` — configuración del reverse proxy
- `dnsmasq/dnsmasq.conf` — resolución DNS local (contiene IP Tailscale, actualizar al migrar)
- `.env.example` — plantilla de variables de entorno
- `config-templates/` — templates XML con variables para pre-seed
- `provisioner/` — Dockerfile + scripts de seed y provision
- `custom-format-español.json` — custom format importable en Radarr/Sonarr
- `.claude/plans/` — planes de implementación por fases

## Adding or Modifying Services

1. Añadir el servicio a `docker-compose.yml` con `networks: [media-network]` y variables `${PUID}`, `${PGID}`, `${TZ}`
2. Añadir entrada en `Caddyfile`: `servicio.{$DOMAIN:notflix.internal} { reverse_proxy servicio:<puerto> }`
3. Añadir `make logs-<servicio>` al Makefile
4. Si el servicio tiene API key, añadir template en `config-templates/` y extender `seed.sh` y `provision.sh`
5. Actualizar README.md y CLAUDE.md

## DNS: Tailscale Split DNS

La IP en `dnsmasq/dnsmasq.conf` (`address=/.notflix.internal/100.x.x.x`) debe ser la IP
Tailscale del servidor (`tailscale ip -4`). Si cambia, actualizar ese archivo y ejecutar
`docker compose restart dnsmasq`.

El Split DNS se configura una sola vez en el panel de Tailscale:
DNS → Add nameserver → Custom → IP Tailscale → Domain: `notflix.internal` → Restrict to domain.
