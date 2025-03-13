# Variables
COMPOSE = docker-compose

# Colores para los mensajes
GREEN := "\033[0;32m"
YELLOW := "\033[0;33m"
RESET := "\033[0m"

# Comandos principales
.PHONY: up down restart status logs

create-folders:
	mkdir -p {plex,qbittorrent,radarr,sonarr,prowlarr}/config
	mkdir -p downloads/{movies,tv,incomplete}

up:
	@echo ${GREEN}Levantando todos los servicios...${RESET}
	$(COMPOSE) up -d

down:
	@echo ${YELLOW}Deteniendo todos los servicios...${RESET}
	$(COMPOSE) down

restart:
	@echo ${YELLOW}Reiniciando todos los servicios...${RESET}
	$(COMPOSE) restart

status:
	@echo ${GREEN}Estado de los contenedores:${RESET}
	$(COMPOSE) ps

# Logs de servicios individuales
.PHONY: logs-plex logs-qbit logs-radarr logs-sonarr logs-prowlarr logs-flare

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

# Ver todos los logs
logs:
	$(COMPOSE) logs -f

# Comandos de ayuda
.PHONY: help
help:
	@echo "Comandos disponibles:"
	@echo "  make up            - Inicia todos los servicios"
	@echo "  make down          - Detiene todos los servicios"
	@echo "  make restart       - Reinicia todos los servicios"
	@echo "  make status        - Muestra el estado de los servicios"
	@echo "  make logs          - Muestra logs de todos los servicios"
	@echo "  make logs-plex     - Muestra logs de Plex"
	@echo "  make logs-qbit     - Muestra logs de qBittorrent"
	@echo "  make logs-radarr   - Muestra logs de Radarr"
	@echo "  make logs-sonarr   - Muestra logs de Sonarr"
	@echo "  make logs-prowlarr - Muestra logs de Prowlarr"
	@echo "  make logs-flare    - Muestra logs de FlareSolverr"
