COMPOSE = docker compose

GREEN  := \033[0;32m
YELLOW := \033[0;33m
RESET  := \033[0m

.PHONY: create-folders up down restart status logs \
        logs-plex logs-qbit logs-radarr logs-sonarr logs-prowlarr logs-flare logs-caddy \
        help

create-folders:
	mkdir -p {plex,qbittorrent,radarr,sonarr,prowlarr}/config
	mkdir -p plex/transcode
	mkdir -p downloads/{movies,tv,incomplete}
	mkdir -p dnsmasq

up:
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
	@printf "Comandos disponibles:\n"
	@printf "  make create-folders  - Crea la estructura de directorios\n"
	@printf "  make up              - Inicia todos los servicios\n"
	@printf "  make down            - Detiene todos los servicios\n"
	@printf "  make restart         - Reinicia todos los servicios\n"
	@printf "  make status          - Estado de los contenedores\n"
	@printf "  make logs            - Logs de todos los servicios\n"
	@printf "  make logs-<servicio> - Logs de un servicio específico\n"
