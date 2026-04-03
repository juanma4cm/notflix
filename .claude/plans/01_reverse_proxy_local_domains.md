---
plan_id: 01
title: Reverse Proxy + Dominios locales vía Tailscale Split DNS
status: completed
risk_level: low
depends_on: none
---

# Plan 01 — Reverse Proxy + Acceso por Dominio Local

## Contexto y Objetivo

El stack corre en un **Ubuntu Server** accesible desde cualquier dispositivo via **Tailscale**.
El objetivo es pasar de `100.x.x.x:7878` a `radarr.notflix.internal` en todos los
dispositivos de la red Tailscale, sin configuración manual en cada cliente.

**¿Por qué HTTP y no HTTPS?**
Tailscale usa WireGuard (cifrado E2E entre dispositivos). El tráfico `radarr.notflix.internal`
viaja ya cifrado por el túnel Tailscale. Añadir TLS encima es redundante y añade complejidad
(gestión de certificados, warnings en el navegador para CAs locales). HTTP dentro de Tailscale
es la práctica estándar en homelabs.

**Modelo DNS (Tailscale Split DNS):**
Tailscale permite definir en su panel de administración un nameserver personalizado para
un dominio concreto. Cualquier dispositivo en la red Tailscale que pregunte por
`*.notflix.internal` será redirigido automáticamente al dnsmasq del servidor. Cero
configuración manual en clientes.

---

## Fixes detectados en el compose actual

- `plex` no tiene `networks: [media-network]` → no puede comunicarse con otros contenedores por nombre. **Se corrige aquí.**
- `PUID=501 / PGID=20` están hardcodeados (valores macOS). Se mueven a `.env` con valores Ubuntu estándar (1000:1000).
- `COMPOSE = docker-compose` usa la CLI v1 (deprecated). Se actualiza a `docker compose`.

---

## Archivos a Crear / Modificar

```
notflix/
├── Caddyfile                  ← NUEVO
├── dnsmasq/
│   └── dnsmasq.conf           ← NUEVO
├── .env.example               ← NUEVO
├── .env                       ← NUEVO (local, en .gitignore)
├── docker-compose.yml         ← MODIFICAR
└── Makefile                   ← MODIFICAR
```

---

## Implementación

### Paso 1 — Crear `.env.example`

```env
# Sistema
PUID=1000
PGID=1000
TZ=Europe/Madrid

# Dominio interno (accesible desde todos los dispositivos Tailscale)
DOMAIN=notflix.internal
```

Crear `.env` real:
```bash
cp .env.example .env
# Ajustar PUID/PGID al usuario que corre Docker en el servidor:
# id -u && id -g
```

Añadir al `.gitignore`:
```
.env
backups/
```

### Paso 2 — Crear `dnsmasq/dnsmasq.conf`

```ini
# Resuelve *.notflix.internal → IP Tailscale del servidor
# Sustituir 100.x.x.x por la IP Tailscale real del servidor (tailscale ip -4)
address=/.notflix.internal/100.x.x.x

domain-needed
bogus-priv
no-resolv
```

La IP se puede hacer dinámica en el futuro usando la IP del contenedor Caddy
dentro de la red Docker, pero la IP Tailscale del servidor es estable y más explícita.

### Paso 3 — Crear `Caddyfile`

```caddyfile
{
  # Sin HTTPS automático: HTTP puro dentro de la red Tailscale
  auto_https off
  admin off
}

radarr.{$DOMAIN:notflix.internal} {
  reverse_proxy radarr:7878
}

sonarr.{$DOMAIN:notflix.internal} {
  reverse_proxy sonarr:8989
}

prowlarr.{$DOMAIN:notflix.internal} {
  reverse_proxy prowlarr:9696
}

qbittorrent.{$DOMAIN:notflix.internal} {
  reverse_proxy qbittorrent:8080 {
    header_up Host {upstream_hostport}
  }
}

flaresolverr.{$DOMAIN:notflix.internal} {
  reverse_proxy flaresolverr:8191
}

plex.{$DOMAIN:notflix.internal} {
  reverse_proxy plex-server:32400 {
    header_up Host {upstream_hostport}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}
```

`{$DOMAIN:notflix.internal}` lee la variable de entorno `DOMAIN` del contenedor Caddy,
con `notflix.internal` como fallback.

### Paso 4 — Modificar `docker-compose.yml`

```yaml
services:

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    ports:
      - "80:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    environment:
      - DOMAIN=${DOMAIN:-notflix.internal}
    restart: unless-stopped
    networks:
      - media-network

  dnsmasq:
    image: ricardbejarano/dnsmasq:latest
    container_name: dnsmasq
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - ./dnsmasq/dnsmasq.conf:/etc/dnsmasq.conf:ro
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
    networks:
      - media-network

  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Europe/Madrid}
      - WEBUI_PORT=8080
      - TORRENTING_PORT=6881
    volumes:
      - ./qbittorrent/config:/config
      - ./downloads:/downloads
    ports:
      - "6881:6881"
      - "6881:6881/udp"
    restart: unless-stopped
    networks:
      - media-network

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Europe/Madrid}
    volumes:
      - ./prowlarr/config:/config
    restart: unless-stopped
    networks:
      - media-network

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=${TZ:-Europe/Madrid}
    restart: unless-stopped
    networks:
      - media-network

  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Europe/Madrid}
    volumes:
      - ./radarr/config:/config
      - ./downloads:/downloads
      - ./downloads/movies:/movies
    restart: unless-stopped
    networks:
      - media-network

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Europe/Madrid}
    volumes:
      - ./sonarr/config:/config
      - ./downloads:/downloads
      - ./downloads/tv:/tv
    restart: unless-stopped
    networks:
      - media-network

  plex:
    image: linuxserver/plex:latest
    container_name: plex-server
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ:-Europe/Madrid}
      - VERSION=docker
    ports:
      - "32400:32400/tcp"
      - "1900:1900/udp"
      - "32410:32410/udp"
      - "32412:32412/udp"
      - "32413:32413/udp"
      - "32414:32414/udp"
    volumes:
      - ./plex/config:/config
      - ./plex/transcode:/transcode
      - ./downloads/movies:/movies
      - ./downloads/tv:/tv
    restart: unless-stopped
    networks:
      - media-network     # BUG FIX: faltaba en el compose original

networks:
  media-network:
    driver: bridge
```

### Paso 5 — Ubuntu: liberar puerto 53

`systemd-resolved` ocupa el puerto 53 en Ubuntu por defecto. Hay que desactivar
su stub listener para que dnsmasq pueda escuchar:

```bash
# En el servidor Ubuntu
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

# Verificar que el puerto 53 está libre
sudo ss -tulpn | grep ':53'
```

Esto no afecta a la resolución DNS del propio servidor Ubuntu (sigue usando
systemd-resolved para sus propias queries, solo deja el puerto 53 libre).

### Paso 6 — Tailscale Split DNS

En el panel de administración de Tailscale (`login.tailscale.com/admin/dns`):

1. **DNS** → **Add nameserver** → **Custom**
2. **Nameserver:** IP Tailscale del servidor (`tailscale ip -4` en el servidor)
3. **Domain:** `notflix.internal`
4. Activar **"Restrict to domain"**

A partir de este momento, todos los dispositivos en la red Tailscale que consulten
`*.notflix.internal` serán dirigidos al dnsmasq del servidor, sin ninguna
configuración en los clientes.

Verificar desde otro dispositivo Tailscale:
```bash
dig radarr.notflix.internal
# Debe devolver la IP Tailscale del servidor (100.x.x.x)
```

### Paso 7 — Configurar Plex para acceso detrás de proxy

En Plex Web → Settings → Remote Access → **Custom server access URLs**:
```
http://plex.notflix.internal
```

### Paso 8 — Actualizar Makefile

```makefile
# CLI de Docker Compose v2
COMPOSE = docker compose

GREEN  := "\033[0;32m"
YELLOW := "\033[0;33m"
RESET  := "\033[0m"

.PHONY: create-folders up down restart status logs provision \
        logs-plex logs-qbit logs-radarr logs-sonarr logs-prowlarr logs-flare logs-caddy \
        help

create-folders:
	mkdir -p {plex,qbittorrent,radarr,sonarr,prowlarr}/config
	mkdir -p plex/transcode
	mkdir -p downloads/{movies,tv,incomplete}
	mkdir -p dnsmasq

up:
	@echo $(GREEN)Levantando todos los servicios...$(RESET)
	$(COMPOSE) up -d

down:
	@echo $(YELLOW)Deteniendo todos los servicios...$(RESET)
	$(COMPOSE) down

restart:
	@echo $(YELLOW)Reiniciando todos los servicios...$(RESET)
	$(COMPOSE) restart

status:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

logs-plex:
	$(COMPOSE) logs -f plex

logs-qbit:
	$(COMPOSE) logs -f qbittorrent

logs-radarr:
	$(COMPOSE) logs -f radarr

logs-sonarr:
	$(COMPOSE) logs -f sonarr

logs-prowlarr:
	$(COMPOSE) logs -f prowlarr

logs-flare:
	$(COMPOSE) logs -f flaresolverr

logs-caddy:
	$(COMPOSE) logs -f caddy

help:
	@echo "Comandos disponibles:"
	@echo "  make up              - Inicia todos los servicios"
	@echo "  make down            - Detiene todos los servicios"
	@echo "  make restart         - Reinicia todos los servicios"
	@echo "  make status          - Muestra el estado de los servicios"
	@echo "  make logs            - Muestra logs de todos los servicios"
	@echo "  make logs-<servicio> - Logs de un servicio específico"
```

---

## URLs Tras Implementación

| Servicio | URL |
|---|---|
| Radarr | http://radarr.notflix.internal |
| Sonarr | http://sonarr.notflix.internal |
| Prowlarr | http://prowlarr.notflix.internal |
| qBittorrent | http://qbittorrent.notflix.internal |
| FlareSolverr | http://flaresolverr.notflix.internal |
| Plex | http://plex.notflix.internal |

Accesibles desde cualquier dispositivo conectado a la red Tailscale.

---

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|---|---|
| Puerto 53 ocupado por systemd-resolved | Paso 5: deshabilitar DNSStubListener |
| Tailscale Split DNS no propaga a todos los clientes | `tailscale set --accept-dns=true` en cada cliente |
| qBittorrent rechaza WebUI con host incorrecto | `header_up Host` en Caddyfile ya lo resuelve |
| Plex local discovery necesita puertos UDP directos | Se mantienen expuestos en el compose |
| dnsmasq con IP hardcodeada si cambia la IP Tailscale | Las IPs Tailscale son estables; documentar si cambia |

---

## Actualización de Documentación (al completar este plan)

Actualizar `README.md` con:

1. **Prerequisitos del servidor**: Ubuntu Server con Docker Engine (v2), Tailscale instalado
2. **Variables de entorno**: Sección sobre `.env` y cómo obtener PUID/PGID (`id -u && id -g`)
3. **Setup DNS (una vez por instalación)**:
   - Paso de `systemd-resolved` en Ubuntu
   - Configuración de Tailscale Split DNS en el panel admin
4. **URLs de acceso**: Tabla con dominios `*.notflix.internal`
5. **Quick Start actualizado**:
```bash
cp .env.example .env        # Editar PUID, PGID, TZ
make create-folders
make up
# Configurar Tailscale Split DNS (ver README § DNS)
```

Actualizar `CLAUDE.md`:
- Cambiar tabla de puertos → tabla de URLs con dominios
- Añadir nota sobre `.env` como fuente de configuración
- Añadir sección "Requisitos del servidor" (Ubuntu + Tailscale)
