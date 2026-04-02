# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**Notflix** is a Docker-based self-hosted media server stack running on **Ubuntu Server**, accessible via **Tailscale**. It orchestrates 8 services for automated media acquisition and streaming, exposed via a Caddy reverse proxy with local domain names (`*.notflix.internal`).

## Requisitos del Servidor

- Ubuntu Server + Docker Engine v2 + Docker Compose plugin
- Tailscale instalado y autenticado
- Puerto 53 libre (deshabilitar stub listener de systemd-resolved)

## Common Commands

```bash
make create-folders   # Inicializar estructura de directorios (una vez)
make up               # Levantar el stack
make down             # Parar el stack
make restart          # Reiniciar el stack
make status           # Estado de los contenedores
make logs             # Logs de todos los servicios
make logs-<servicio>  # Logs individuales: plex, qbit, radarr, sonarr, prowlarr, flare, caddy
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
PUID=1000        # id -u en el servidor
PGID=1000        # id -g en el servidor
TZ=Europe/Madrid
DOMAIN=notflix.internal
```

## What's Version-Controlled vs. Ignored

El `.gitignore` excluye los directorios de configuración de servicios en runtime
(`plex/`, `radarr/`, etc.) y el `.env`. Se versionan:

- `docker-compose.yml` — definición del stack
- `Makefile` — comandos
- `Caddyfile` — configuración del reverse proxy
- `dnsmasq/dnsmasq.conf` — resolución DNS local
- `.env.example` — plantilla de variables de entorno
- `custom-format-español.json` — custom format importable en Radarr/Sonarr
- `.claude/plans/` — planes de implementación por fases

## Adding or Modifying Services

1. Añadir el servicio a `docker-compose.yml` con `networks: [media-network]` y variables `${PUID}`, `${PGID}`, `${TZ}`
2. Añadir entrada en `Caddyfile`: `servicio.{$DOMAIN:notflix.internal} { reverse_proxy servicio:<puerto> }`
3. Añadir `make logs-<servicio>` al Makefile
4. Actualizar README.md con la nueva URL y configuración

## DNS: Tailscale Split DNS

La IP en `dnsmasq/dnsmasq.conf` (`address=/.notflix.internal/100.x.x.x`) debe ser la IP
Tailscale del servidor (`tailscale ip -4`). Si cambia, actualizar ese archivo y reiniciar
el contenedor dnsmasq.

El Split DNS se configura una sola vez en el panel de Tailscale:
DNS → Add nameserver → Custom → IP Tailscale del servidor → Domain: `notflix.internal` → Restrict to domain.
