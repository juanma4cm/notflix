#!/bin/bash
# seed.sh — Pre-siembra config.xml en los servicios Arr antes del primer arranque.
# Se ejecuta via "make up" ANTES de "docker compose up -d", por eso puede escribir
# los archivos antes de que los servicios los lean.
# Es idempotente: no sobreescribe si el archivo ya existe.
set -euo pipefail

log() { echo "[seeder] $*"; }

seed_config() {
  local service=$1 dest=$2
  if [ ! -f "$dest/config.xml" ]; then
    mkdir -p "$dest"
    log "Sembrando config.xml para $service..."
    envsubst < "/templates/$service/config.xml" > "$dest/config.xml"
    log "  → $dest/config.xml creado."
  else
    log "config.xml de $service ya existe. Skipping."
  fi
}

seed_config "radarr"   "/config/radarr"
seed_config "sonarr"   "/config/sonarr"
seed_config "prowlarr" "/config/prowlarr"


# Generar dnsmasq.conf desde template (siempre — la IP puede cambiar)
if [ -f "/dnsmasq/dnsmasq.conf.template" ]; then
  log "Generando dnsmasq.conf con TAILSCALE_IP=${TAILSCALE_IP}..."
  envsubst < "/dnsmasq/dnsmasq.conf.template" > "/dnsmasq/dnsmasq.conf"
  log "  → /dnsmasq/dnsmasq.conf generado."
else
  log "WARN: /dnsmasq/dnsmasq.conf.template no encontrado. Skipping."
fi

log "Seed completado."
