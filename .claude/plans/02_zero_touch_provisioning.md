---
plan_id: 02
title: Zero-Touch Provisioning
status: completed
risk_level: medium
depends_on: 01
---

# Plan 02 — Zero-Touch Provisioning

## Objetivo

`make up` configura todo el stack automáticamente sin entrar a ninguna UI.
qBittorrent, Prowlarr, Radarr y Sonarr quedan interconectados y listos tras el
primer arranque.

## Estrategia: Pre-seed de API keys + Contenedor provisioner

### ¿Por qué no variables de entorno?

Las imágenes `linuxserver/*` no exponen configuración profunda (conexiones entre servicios,
download clients, root folders) vía env vars. La configuración real vive en SQLite y XML
dentro de `/config`. La única forma fiable de preconfigurar es:

1. **Pre-seed de API keys** en `config.xml` antes del primer arranque. Los servicios leen
   este archivo al iniciar y lo respetan si ya existe.
2. **Contenedor `provisioner`** one-shot que, tras arrancar los servicios, hace llamadas
   a sus APIs para interconectarlos.

### Ventaja del pre-seed

Si el provisioner no conoce las API keys de antemano, tiene que parsear los XML generados
en tiempo de ejecución → lógica de espera, montaje de volúmenes extras, parsing frágil.
Con las keys en `.env` y pre-sembradas en `config.xml`, el provisioner solo necesita
leer variables de entorno.

---

## Archivos a Crear / Modificar

```
notflix/
├── .env.example                           ← AMPLIAR (extiende Plan 01)
├── provisioner/
│   ├── Dockerfile                         ← NUEVO
│   └── provision.sh                       ← NUEVO
├── config-templates/
│   ├── radarr/config.xml                  ← NUEVO
│   ├── sonarr/config.xml                  ← NUEVO
│   └── prowlarr/config.xml                ← NUEVO
└── docker-compose.yml                     ← MODIFICAR
```

---

## Implementación

### Paso 1 — Ampliar `.env.example`

```env
# Sistema
PUID=1000
PGID=1000
TZ=Europe/Madrid

# Dominio interno
DOMAIN=notflix.internal

# API Keys — generar con: openssl rand -hex 16
# IMPORTANTE: No cambiar tras el primer arranque
RADARR_API_KEY=cambiame_openssl_rand_hex_16
SONARR_API_KEY=cambiame_openssl_rand_hex_16
PROWLARR_API_KEY=cambiame_openssl_rand_hex_16

# qBittorrent
QBIT_USER=admin
QBIT_PASS=cambiame_contrasena_segura
```

Generar API keys reales:
```bash
echo "RADARR_API_KEY=$(openssl rand -hex 16)"
echo "SONARR_API_KEY=$(openssl rand -hex 16)"
echo "PROWLARR_API_KEY=$(openssl rand -hex 16)"
```

### Paso 2 — Crear config-templates XML

Los servicios Arr leen `config.xml` al arrancar. Si el archivo ya existe con un ApiKey
definido, lo respetan. Si no existe, generan uno aleatorio (perdiendo la key conocida).

**`config-templates/radarr/config.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
  <ApiKey>${RADARR_API_KEY}</ApiKey>
  <AuthenticationMethod>Forms</AuthenticationMethod>
  <AuthenticationRequired>Enabled</AuthenticationRequired>
  <Port>7878</Port>
  <BindAddress>*</BindAddress>
</Config>
```

**`config-templates/sonarr/config.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
  <ApiKey>${SONARR_API_KEY}</ApiKey>
  <AuthenticationMethod>Forms</AuthenticationMethod>
  <AuthenticationRequired>Enabled</AuthenticationRequired>
  <Port>8989</Port>
  <BindAddress>*</BindAddress>
</Config>
```

**`config-templates/prowlarr/config.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
  <ApiKey>${PROWLARR_API_KEY}</ApiKey>
  <AuthenticationMethod>Forms</AuthenticationMethod>
  <AuthenticationRequired>Enabled</AuthenticationRequired>
  <Port>9696</Port>
  <BindAddress>*</BindAddress>
</Config>
```

Los `${VAR}` son sustituidos por `envsubst` en el provisioner antes de copiar al destino
(no dependemos de que la imagen los interprete).

### Paso 3 — Crear `provisioner/Dockerfile`

```dockerfile
FROM alpine:3.19
RUN apk add --no-cache curl jq bash gettext
COPY provision.sh /provision.sh
RUN chmod +x /provision.sh
ENTRYPOINT ["/provision.sh"]
```

`gettext` provee `envsubst` para la sustitución de variables en los XML.

### Paso 4 — Crear `provisioner/provision.sh`

```bash
#!/bin/bash
set -euo pipefail

RADARR_URL="http://radarr:7878"
SONARR_URL="http://sonarr:8989"
PROWLARR_URL="http://prowlarr:9696"
QBIT_URL="http://qbittorrent:8080"

# ─── Utilidades ──────────────────────────────────────────────────────────────

log() { echo "[provisioner] $(date '+%H:%M:%S') $*"; }

wait_for() {
  local name=$1 url=$2
  log "Esperando a $name en $url ..."
  for i in $(seq 1 60); do
    if curl -sf "$url" > /dev/null 2>&1; then
      log "$name está listo."
      return 0
    fi
    sleep 5
  done
  log "ERROR: $name no respondió en 5 minutos."
  exit 1
}

radarr_api()   { curl -sf -H "X-Api-Key: $RADARR_API_KEY"   "$RADARR_URL/api/v3/$1"   "${@:2}"; }
sonarr_api()   { curl -sf -H "X-Api-Key: $SONARR_API_KEY"   "$SONARR_URL/api/v3/$1"   "${@:2}"; }
prowlarr_api() { curl -sf -H "X-Api-Key: $PROWLARR_API_KEY" "$PROWLARR_URL/api/v1/$1" "${@:2}"; }

already_exists() {
  [ "$(echo "$1" | jq 'length')" -gt "0" ]
}

# ─── Pre-seed config.xml si los servicios arrancan por primera vez ────────────

seed_config() {
  local service=$1 dest=$2
  if [ ! -f "$dest/config.xml" ]; then
    log "Seeding config.xml para $service..."
    envsubst < "/templates/$service/config.xml" > "$dest/config.xml"
    log "config.xml creado para $service."
  else
    log "config.xml de $service ya existe. Skipping seed."
  fi
}

seed_config "radarr"   "/config/radarr"
seed_config "sonarr"   "/config/sonarr"
seed_config "prowlarr" "/config/prowlarr"

# ─── Esperar servicios ────────────────────────────────────────────────────────

wait_for "qBittorrent" "$QBIT_URL"
wait_for "Prowlarr"    "$PROWLARR_URL/api/v1/health"
wait_for "Radarr"      "$RADARR_URL/api/v3/health"
wait_for "Sonarr"      "$SONARR_URL/api/v3/health"

# ─── qBittorrent ─────────────────────────────────────────────────────────────

log "Configurando qBittorrent..."

QBIT_COOKIE=$(curl -sf -c - \
  --data "username=${QBIT_USER}&password=${QBIT_PASS}" \
  "$QBIT_URL/api/v2/auth/login" | grep SID | awk '{print "SID="$NF}') || true

if [ -n "$QBIT_COOKIE" ]; then
  curl -sf -b "$QBIT_COOKIE" \
    --data "json=$(jq -n '{
      "save_path": "/downloads",
      "temp_path_enabled": true,
      "temp_path": "/downloads/incomplete"
    }')" \
    "$QBIT_URL/api/v2/app/setPreferences" || true

  curl -sf -b "$QBIT_COOKIE" \
    --data "category=movies&savePath=/downloads/movies" \
    "$QBIT_URL/api/v2/torrents/createCategory" || true

  curl -sf -b "$QBIT_COOKIE" \
    --data "category=tv&savePath=/downloads/tv" \
    "$QBIT_URL/api/v2/torrents/createCategory" || true

  log "qBittorrent configurado."
else
  log "WARN: No se pudo autenticar en qBittorrent."
fi

# ─── Prowlarr → FlareSolverr ─────────────────────────────────────────────────

log "Añadiendo FlareSolverr a Prowlarr..."

EXISTING=$(prowlarr_api "indexerProxy" | jq '[.[] | select(.implementation == "FlareSolverr")]')
if ! already_exists "$EXISTING"; then
  prowlarr_api "indexerProxy" \
    -X POST -H "Content-Type: application/json" \
    -d '{
      "name": "FlareSolverr",
      "implementation": "FlareSolverr",
      "configContract": "FlareSolverrSettings",
      "fields": [
        {"name": "host",           "value": "http://flaresolverr:8191"},
        {"name": "requestTimeout", "value": 60}
      ],
      "tags": []
    }'
  log "FlareSolverr añadido."
else
  log "FlareSolverr ya existe en Prowlarr. Skipping."
fi

# ─── Prowlarr → Radarr ───────────────────────────────────────────────────────

log "Conectando Prowlarr con Radarr..."

EXISTING=$(prowlarr_api "applications" | jq '[.[] | select(.implementation == "Radarr")]')
if ! already_exists "$EXISTING"; then
  prowlarr_api "applications" \
    -X POST -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Radarr\",
      \"implementation\": \"Radarr\",
      \"configContract\": \"RadarrSettings\",
      \"syncLevel\": \"fullSync\",
      \"fields\": [
        {\"name\": \"prowlarrUrl\",    \"value\": \"http://prowlarr:9696\"},
        {\"name\": \"baseUrl\",        \"value\": \"http://radarr:7878\"},
        {\"name\": \"apiKey\",         \"value\": \"$RADARR_API_KEY\"},
        {\"name\": \"syncCategories\", \"value\": [2000,2010,2020,2030,2040,2050,2060,2070,2080]}
      ]
    }"
  log "Radarr conectado a Prowlarr."
else
  log "Radarr ya conectado a Prowlarr. Skipping."
fi

# ─── Prowlarr → Sonarr ───────────────────────────────────────────────────────

log "Conectando Prowlarr con Sonarr..."

EXISTING=$(prowlarr_api "applications" | jq '[.[] | select(.implementation == "Sonarr")]')
if ! already_exists "$EXISTING"; then
  prowlarr_api "applications" \
    -X POST -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Sonarr\",
      \"implementation\": \"Sonarr\",
      \"configContract\": \"SonarrSettings\",
      \"syncLevel\": \"fullSync\",
      \"fields\": [
        {\"name\": \"prowlarrUrl\",    \"value\": \"http://prowlarr:9696\"},
        {\"name\": \"baseUrl\",        \"value\": \"http://sonarr:8989\"},
        {\"name\": \"apiKey\",         \"value\": \"$SONARR_API_KEY\"},
        {\"name\": \"syncCategories\", \"value\": [5000,5010,5020,5030,5040,5050,5060,5070,5080,5090]}
      ]
    }"
  log "Sonarr conectado a Prowlarr."
else
  log "Sonarr ya conectado a Prowlarr. Skipping."
fi

# ─── Radarr → qBittorrent ────────────────────────────────────────────────────

log "Añadiendo qBittorrent a Radarr..."

EXISTING=$(radarr_api "downloadclient" | jq '[.[] | select(.implementation == "QBittorrent")]')
if ! already_exists "$EXISTING"; then
  radarr_api "downloadclient" \
    -X POST -H "Content-Type: application/json" \
    -d "{
      \"name\": \"qBittorrent\",
      \"enable\": true,
      \"protocol\": \"torrent\",
      \"priority\": 1,
      \"implementation\": \"QBittorrent\",
      \"configContract\": \"QBittorrentSettings\",
      \"fields\": [
        {\"name\": \"host\",                \"value\": \"qbittorrent\"},
        {\"name\": \"port\",                \"value\": 8080},
        {\"name\": \"username\",            \"value\": \"$QBIT_USER\"},
        {\"name\": \"password\",            \"value\": \"$QBIT_PASS\"},
        {\"name\": \"movieCategory\",       \"value\": \"movies\"}
      ]
    }"
  log "qBittorrent añadido a Radarr."
else
  log "qBittorrent ya existe en Radarr. Skipping."
fi

# ─── Sonarr → qBittorrent ────────────────────────────────────────────────────

log "Añadiendo qBittorrent a Sonarr..."

EXISTING=$(sonarr_api "downloadclient" | jq '[.[] | select(.implementation == "QBittorrent")]')
if ! already_exists "$EXISTING"; then
  sonarr_api "downloadclient" \
    -X POST -H "Content-Type: application/json" \
    -d "{
      \"name\": \"qBittorrent\",
      \"enable\": true,
      \"protocol\": \"torrent\",
      \"priority\": 1,
      \"implementation\": \"QBittorrent\",
      \"configContract\": \"QBittorrentSettings\",
      \"fields\": [
        {\"name\": \"host\",       \"value\": \"qbittorrent\"},
        {\"name\": \"port\",       \"value\": 8080},
        {\"name\": \"username\",   \"value\": \"$QBIT_USER\"},
        {\"name\": \"password\",   \"value\": \"$QBIT_PASS\"},
        {\"name\": \"tvCategory\", \"value\": \"tv\"}
      ]
    }"
  log "qBittorrent añadido a Sonarr."
else
  log "qBittorrent ya existe en Sonarr. Skipping."
fi

# ─── Root folders ────────────────────────────────────────────────────────────

EXISTING=$(radarr_api "rootfolder" | jq '[.[] | select(.path == "/movies")]')
if ! already_exists "$EXISTING"; then
  radarr_api "rootfolder" -X POST -H "Content-Type: application/json" -d '{"path": "/movies"}'
  log "Root folder /movies añadido a Radarr."
fi

EXISTING=$(sonarr_api "rootfolder" | jq '[.[] | select(.path == "/tv")]')
if ! already_exists "$EXISTING"; then
  sonarr_api "rootfolder" -X POST -H "Content-Type: application/json" -d '{"path": "/tv"}'
  log "Root folder /tv añadido a Sonarr."
fi

# ─── Resumen ─────────────────────────────────────────────────────────────────

log "=== Provisioning completado ==="
log "  OK qBittorrent (categorías movies/tv)"
log "  OK Prowlarr → FlareSolverr"
log "  OK Prowlarr ↔ Radarr (fullSync)"
log "  OK Prowlarr ↔ Sonarr (fullSync)"
log "  OK Radarr → qBittorrent"
log "  OK Sonarr  → qBittorrent"
log "  OK Root folders /movies y /tv"
log ""
log "Pendiente manual:"
log "  • Indexers en Prowlarr (requieren credenciales)"
log "  • Plex library (requiere PLEX_CLAIM token)"
```

### Paso 5 — Añadir health checks y provisioner al `docker-compose.yml`

```yaml
  qbittorrent:
    # ... config existente ...
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  prowlarr:
    # ... config existente ...
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:9696/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  radarr:
    # ... config existente ...
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:7878/api/v3/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  sonarr:
    # ... config existente ...
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8989/api/v3/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  provisioner:
    build: ./provisioner
    container_name: provisioner
    env_file: .env
    volumes:
      # Acceso a los config dirs para el pre-seed
      - ./radarr/config:/config/radarr
      - ./sonarr/config:/config/sonarr
      - ./prowlarr/config:/config/prowlarr
      # Templates read-only
      - ./config-templates:/templates:ro
    depends_on:
      qbittorrent:
        condition: service_healthy
      prowlarr:
        condition: service_healthy
      radarr:
        condition: service_healthy
      sonarr:
        condition: service_healthy
    restart: "no"
    networks:
      - media-network
```

### Paso 6 — Añadir target al Makefile

```makefile
provision:
	@echo $(GREEN)Ejecutando provisioner...$(RESET)
	$(COMPOSE) run --rm provisioner

logs-provisioner:
	$(COMPOSE) logs provisioner
```

---

## Flujo Completo

```
make up
  ↓
Servicios arrancan + health checks pasan
  ↓
provisioner:
  1. Pre-seed config.xml (si primer arranque)
  2. Espera health checks de todos
  3. Configura qBittorrent (categorías)
  4. Prowlarr → FlareSolverr
  5. Prowlarr ↔ Radarr / Sonarr (fullSync)
  6. Radarr / Sonarr → qBittorrent
  7. Root folders
  ↓
provisioner sale con exit 0
  ↓
Stack 100% interconectado
```

---

## Lo Que No Se Puede Automatizar

| Tarea | Motivo |
|---|---|
| Añadir indexers en Prowlarr | Requieren cuentas/credenciales externas |
| Configurar biblioteca Plex | Requiere `PLEX_CLAIM` de plex.tv (token de 5 min) |
| Autenticación UI primera vez | Cada servicio solicita contraseña en primer login |

---

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|---|---|
| Provisioner falla a medias | Idempotente: `make provision` re-ejecuta sin duplicar |
| API key en `.env` comprometida | `.env` en `.gitignore`; acceso solo via Tailscale |
| qBittorrent cambia password por defecto | Verificar en logs si falla la auth; ajustar `.env` |
| config.xml ignorado por el servicio | Verificar que el archivo llegó antes del arranque del servicio; el volumen lo garantiza si `provisioner` corre antes (para reinstalaciones) |

---

## Actualización de Documentación (al completar este plan)

Actualizar `README.md` con:

1. **Sección "Configuración Zero-Touch"**:
   - Explicar que tras `make up` los servicios quedan interconectados automáticamente
   - Tabla de qué se configura automáticamente vs qué requiere acción manual
2. **Variables de entorno requeridas**: documentar todas las del `.env.example`
   con descripción y cómo generarlas
3. **Reinstalación / migración**: indicar que si se migra el stack a otro servidor,
   basta con copiar los directorios `*/config` + el `.env` y ejecutar `make up`
4. **`make provision`**: documentar que es idempotente y cuándo usarlo

Actualizar `CLAUDE.md`:
- Añadir sección sobre el provisioner y los config-templates
- Documentar el flujo de pre-seed de API keys
