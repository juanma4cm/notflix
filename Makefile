COMPOSE    = docker compose
BACKUP_DIR ?= ./backups

GREEN  := \033[0;32m
YELLOW := \033[0;33m
RESET  := \033[0m

.PHONY: create-folders up down restart status provision recyclarr backup backup-full \
        logs logs-plex logs-qbit logs-radarr logs-sonarr \
        logs-prowlarr logs-flare logs-caddy logs-provisioner \
        logs-overseerr logs-ntfy logs-diun \
        help

create-folders:
	mkdir -p {plex,qbittorrent,radarr,sonarr,prowlarr,overseerr}/config
	mkdir -p plex/transcode
	mkdir -p downloads/{movies,tv,incomplete}
	mkdir -p dnsmasq recyclarr ntfy/data diun/data

up:
	@printf "$(GREEN)Sembrando configuraciones iniciales...$(RESET)\n"
	$(COMPOSE) run --rm --no-deps provisioner /seed.sh
	@printf "$(GREEN)Levantando todos los servicios...$(RESET)\n"
	$(COMPOSE) up -d

down:
	@printf "$(YELLOW)Deteniendo todos los servicios...$(RESET)\n"
	$(COMPOSE) down

restart:
	@printf "$(YELLOW)Reiniciando todos los servicios...$(RESET)\n"
	$(COMPOSE) restart

status:
	$(COMPOSE) ps

provision:
	@printf "$(GREEN)Ejecutando provisioner...$(RESET)\n"
	$(COMPOSE) run --rm provisioner

recyclarr:
	@printf "$(GREEN)Sincronizando perfiles de calidad con TRaSH-Guides...$(RESET)\n"
	$(COMPOSE) run --rm recyclarr sync

recyclarr-list:
	$(COMPOSE) run --rm recyclarr list custom-formats radarr

backup:
	@printf "$(GREEN)Creando backup de configuraciones...$(RESET)\n"
	@mkdir -p $(BACKUP_DIR)
	@tar -czf $(BACKUP_DIR)/notflix-backup-$$(date +%Y%m%d-%H%M%S).tar.gz \
	  radarr/config sonarr/config prowlarr/config \
	  qbittorrent/config overseerr/config recyclarr \
	  dnsmasq ntfy/server.yml diun/diun.yml \
	  Caddyfile docker-compose.yml .env.example
	@printf "$(GREEN)Backup guardado en $(BACKUP_DIR)/$(RESET)\n"
	@ls -lh $(BACKUP_DIR)/ | tail -5

backup-full: backup
	@tar -czf $(BACKUP_DIR)/notflix-env-$$(date +%Y%m%d-%H%M%S).tar.gz .env
	@printf "$(YELLOW)AVISO: backup-env contiene credenciales. Guardar en lugar seguro.$(RESET)\n"

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

logs-provisioner:
	$(COMPOSE) logs provisioner

logs-overseerr:
	$(COMPOSE) logs -f overseerr

logs-ntfy:
	$(COMPOSE) logs -f ntfy

logs-diun:
	$(COMPOSE) logs -f diun

help:
	@printf "Comandos disponibles:\n"
	@printf "  make create-folders  - Crea la estructura de directorios\n"
	@printf "  make up              - Siembra configs, levanta servicios y ejecuta provisioner\n"
	@printf "  make down            - Detiene todos los servicios\n"
	@printf "  make restart         - Reinicia todos los servicios\n"
	@printf "  make status          - Estado de los contenedores\n"
	@printf "  make provision       - Re-ejecuta el provisioner (idempotente)\n"
	@printf "  make recyclarr       - Sincroniza quality profiles con TRaSH-Guides\n"
	@printf "  make backup          - Backup de configuraciones (sin .env)\n"
	@printf "  make backup-full     - Backup completo incluyendo .env (contiene credenciales)\n"
	@printf "  make logs            - Logs de todos los servicios\n"
	@printf "  make logs-<servicio> - Logs individuales: plex, qbit, radarr, sonarr,\n"
	@printf "                         prowlarr, flare, caddy, provisioner,\n"
	@printf "                         overseerr, ntfy, diun\n"
