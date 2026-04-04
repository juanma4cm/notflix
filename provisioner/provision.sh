#!/bin/bash
# provision.sh — Configura e interconecta los servicios del stack via API.
# Corre como contenedor one-shot DESPUÉS de que los servicios están healthy.
# Es idempotente: comprueba si cada recurso ya existe antes de crearlo.
set -euo pipefail

RADARR_URL="http://radarr:7878"
SONARR_URL="http://sonarr:8989"
PROWLARR_URL="http://prowlarr:9696"
QBIT_URL="http://qbittorrent:8080"

# ─── Utilidades ───────────────────────────────────────────────────────────────

log() { echo "[provisioner] $(date '+%H:%M:%S') $*"; }

wait_for() {
  local name=$1 url=$2
  log "Esperando a $name..."
  for i in $(seq 1 60); do
    if curl -sf "$url" > /dev/null 2>&1; then
      log "$name listo."
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

already_exists() { [ "$(echo "$1" | jq 'length')" -gt "0" ]; }

# ─── Esperar a que todos los servicios estén listos ───────────────────────────

wait_for "qBittorrent" "$QBIT_URL"
wait_for "Prowlarr"    "$PROWLARR_URL/api/v1/health?apikey=$PROWLARR_API_KEY"
wait_for "Radarr"      "$RADARR_URL/api/v3/health?apikey=$RADARR_API_KEY"
wait_for "Sonarr"      "$SONARR_URL/api/v3/health?apikey=$SONARR_API_KEY"

# ─── qBittorrent ──────────────────────────────────────────────────────────────

log "Configurando qBittorrent..."

QBIT_COOKIE=$(curl -sf -c - \
  -H "Referer: $QBIT_URL" \
  --data "username=${QBIT_USER}&password=${QBIT_PASS}" \
  "$QBIT_URL/api/v2/auth/login" | grep SID | awk '{print "SID="$NF}') || true

if [ -n "$QBIT_COOKIE" ]; then
  curl -sf -b "$QBIT_COOKIE" -H "Referer: $QBIT_URL" \
    --data "json=$(jq -n '{
      "save_path": "/downloads",
      "temp_path_enabled": true,
      "temp_path": "/downloads/incomplete"
    }')" \
    "$QBIT_URL/api/v2/app/setPreferences" > /dev/null || true

  curl -sf -b "$QBIT_COOKIE" -H "Referer: $QBIT_URL" \
    --data "category=movies&savePath=/downloads/movies" \
    "$QBIT_URL/api/v2/torrents/createCategory" > /dev/null || true

  curl -sf -b "$QBIT_COOKIE" -H "Referer: $QBIT_URL" \
    --data "category=tv&savePath=/downloads/tv" \
    "$QBIT_URL/api/v2/torrents/createCategory" > /dev/null || true

  log "qBittorrent configurado (categorías movies/tv)."
else
  log "WARN: Auth en qBittorrent fallida. En primer arranque, qBittorrent genera una"
  log "      contraseña temporal. Ejecuta 'make logs-qbit', cámbiala a \$QBIT_PASS"
  log "      en la WebUI y luego vuelve a ejecutar 'make provision'."
fi

# ─── Usuario admin en Arr ─────────────────────────────────────────────────────
# Estrategia:
#   1. Intentar POST sin auth (solo funciona cuando no existe ningún usuario).
#   2. Si falla, consultar la lista de usuarios vía API key y hacer PUT para
#      actualizar la contraseña al valor de ARR_PASS.
# Idempotente: siempre deja el usuario admin con la contraseña del .env.

ensure_arr_user() {
  local name=$1 url=$2 api=$3 apikey=$4
  local user="${ARR_USER:-admin}" pass="${ARR_PASS:-admin}"
  log "Configurando usuario $user en $name..."

  # Intento 1: creación sin auth (fresh install, tabla Users vacía)
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url$api" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$user\",\"password\":\"$pass\",\"confirmPassword\":\"$pass\"}")
  if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
    log "  → Usuario $user creado en $name."
    return
  fi

  # Intento 2: actualizar contraseña vía API key (usuario ya existe)
  USER_ID=$(curl -sf -H "X-Api-Key: $apikey" "$url$api" | jq -r '.[0].id // empty')
  if [ -n "$USER_ID" ]; then
    curl -sf -X PUT -H "X-Api-Key: $apikey" -H "Content-Type: application/json" \
      "$url$api/$USER_ID" \
      -d "{\"id\":$USER_ID,\"username\":\"$user\",\"password\":\"$pass\",\"confirmPassword\":\"$pass\"}" \
      > /dev/null \
      && log "  → Contraseña de $user actualizada en $name." \
      || log "  WARN: No se pudo actualizar contraseña en $name."
  else
    log "  WARN: No se encontró usuario en $name."
  fi
}

ensure_arr_user "Prowlarr" "$PROWLARR_URL" "/api/v1/user" "$PROWLARR_API_KEY"
ensure_arr_user "Radarr"   "$RADARR_URL"   "/api/v3/user" "$RADARR_API_KEY"
ensure_arr_user "Sonarr"   "$SONARR_URL"   "/api/v3/user" "$SONARR_API_KEY"

# ─── Prowlarr → FlareSolverr ──────────────────────────────────────────────────

log "Configurando FlareSolverr en Prowlarr..."

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
    }' > /dev/null
  log "FlareSolverr añadido a Prowlarr."
else
  log "FlareSolverr ya existe en Prowlarr. Skipping."
fi

# ─── Prowlarr → Radarr ────────────────────────────────────────────────────────

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
    }" > /dev/null
  log "Radarr conectado a Prowlarr."
else
  log "Radarr ya conectado a Prowlarr. Skipping."
fi

# ─── Prowlarr → Sonarr ────────────────────────────────────────────────────────

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
    }" > /dev/null
  log "Sonarr conectado a Prowlarr."
else
  log "Sonarr ya conectado a Prowlarr. Skipping."
fi

# ─── Radarr → qBittorrent ─────────────────────────────────────────────────────

log "Añadiendo qBittorrent como download client en Radarr..."

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
        {\"name\": \"host\",          \"value\": \"qbittorrent\"},
        {\"name\": \"port\",          \"value\": 8080},
        {\"name\": \"username\",      \"value\": \"$QBIT_USER\"},
        {\"name\": \"password\",      \"value\": \"$QBIT_PASS\"},
        {\"name\": \"movieCategory\", \"value\": \"movies\"}
      ]
    }" > /dev/null
  log "qBittorrent añadido a Radarr."
else
  log "qBittorrent ya existe en Radarr. Skipping."
fi

# ─── Sonarr → qBittorrent ─────────────────────────────────────────────────────

log "Añadiendo qBittorrent como download client en Sonarr..."

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
    }" > /dev/null
  log "qBittorrent añadido a Sonarr."
else
  log "qBittorrent ya existe en Sonarr. Skipping."
fi

# ─── Root folders ─────────────────────────────────────────────────────────────

EXISTING=$(radarr_api "rootfolder" | jq '[.[] | select(.path == "/movies")]')
if ! already_exists "$EXISTING"; then
  radarr_api "rootfolder" -X POST -H "Content-Type: application/json" \
    -d '{"path": "/movies"}' > /dev/null
  log "Root folder /movies añadido a Radarr."
fi

EXISTING=$(sonarr_api "rootfolder" | jq '[.[] | select(.path == "/tv")]')
if ! already_exists "$EXISTING"; then
  sonarr_api "rootfolder" -X POST -H "Content-Type: application/json" \
    -d '{"path": "/tv"}' > /dev/null
  log "Root folder /tv añadido a Sonarr."
fi

# ─── Notificaciones ntfy ──────────────────────────────────────────────────────

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
        {"name": "method", "value": 1}
      ]
    }' > /dev/null
  log "ntfy añadido a Radarr."
else
  log "ntfy ya existe en Radarr. Skipping."
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
        {"name": "method", "value": 1}
      ]
    }' > /dev/null
  log "ntfy añadido a Sonarr."
else
  log "ntfy ya existe en Sonarr. Skipping."
fi

# ─── Resumen ──────────────────────────────────────────────────────────────────

log "=== Provisioning completado ==="
log "  OK Prowlarr → FlareSolverr"
log "  OK Prowlarr ↔ Radarr (fullSync)"
log "  OK Prowlarr ↔ Sonarr (fullSync)"
log "  OK Radarr → qBittorrent + root folder /movies"
log "  OK Sonarr  → qBittorrent + root folder /tv"
log "  OK Radarr → ntfy (webhook)"
log "  OK Sonarr  → ntfy (webhook)"
log ""
log "Pendiente manual:"
log "  • qBittorrent: cambiar contraseña temporal y ejecutar 'make provision' (si falló la auth)"
log "  • Prowlarr: añadir indexers (requieren credenciales externas)"
log "  • Plex: configurar biblioteca (requiere PLEX_CLAIM token)"
