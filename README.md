# 🎬 Notflix - Media Server Stack

Un stack completo de Docker para gestionar tu servidor multimedia personal. Incluye Plex, Radarr, Sonarr y herramientas complementarias, optimizado para Apple Silicon.

## 📋 Servicios Incluidos

### 🎥 Plex Media Server

- Servidor de streaming multimedia personal
- Interfaz tipo Netflix
- Organización automática de tu biblioteca

### 🎬 Radarr

- Gestión automatizada de películas
- Monitorización de nuevos lanzamientos
- Organización automática de archivos

### 📺 Sonarr

- Gestión automatizada de series de TV
- Seguimiento de episodios
- Descarga automática de nuevos episodios

### 🔍 Prowlarr

- Gestor centralizado de indexadores
- Integración con Radarr y Sonarr
- Búsqueda unificada

### ⚡ FlareSolverr

- Bypass de protecciones Cloudflare
- Soporte para indexadores protegidos
- Resolución automática de captchas

### 🌊 qBittorrent

- Cliente torrent con interfaz web
- Gestión de descargas
- Integración con Radarr/Sonarr

## 🚀 Inicio Rápido

### Prerrequisitos

- Docker Desktop para Mac (Apple Silicon)
- Git
- Make

### Instalación

1. Clona el repositorio:

```bash
git clone https://github.com/tu-usuario/media-server-stack.git
cd media-server-stack
```

2. Crea la estructura de directorios necesaria:

```bash
make create-folders
```

3. Inicia los servicios:

```bash
make up
```

## 📁 Estructura de Directorios Recomendada

```bash
notflix/
├── custom-format-español.json
├── docker-compose.yml
├── Makefile
├── README.md
├── plex/
│   ├── config/
│   └── transcode/
├── qbittorrent/
│   └── config/
├── radarr/
│   └── config/
├── sonarr/
│   └── config/
├── prowlarr/
│   └── config/
└── downloads/
    ├── movies/     # Carpeta final para películas
    ├── tv/         # Carpeta final para series
    └── incomplete/ # Carpeta temporal para descargas en proceso
```

## 🛠 Comandos Make Disponibles

| Comando | Descripción |
|---------|-------------|
| `make create-folders` | Crea la estructura de directorios necesaria |
| `make up` | Inicia todos los servicios |
| `make down` | Detiene todos los servicios |
| `make restart` | Reinicia todos los servicios |
| `make status` | Muestra el estado de los servicios |
| `make logs` | Muestra logs de todos los servicios |
| `make logs-plex` | Muestra logs de Plex |
| `make logs-qbit` | Muestra logs de qBittorrent |
| `make logs-radarr` | Muestra logs de Radarr |
| `make logs-sonarr` | Muestra logs de Sonarr |
| `make logs-prowlarr` | Muestra logs de Prowlarr |
| `make logs-flare` | Muestra logs de FlareSolverr |

## ⚙️ Configuración Recomendada

### qBittorrent

- Ruta de descarga: `/downloads/incomplete`
- Mover archivos completados a: `/downloads`
- Crear subcarpetas para torrents: No

### Radarr

- Carpeta de películas: `/movies`
- Carpeta de descargas: `/downloads`
- Media Management:
  - Renombrado de archivos: Activado
  - Mover archivos: Activado
  - Eliminar archivos: Activado después de importar

### Sonarr

- Carpeta de series: `/tv`
- Carpeta de descargas: `/downloads`
- Media Management:
  - Renombrado de episodios: Activado
  - Crear carpeta por temporada: Activado
  - Eliminar archivos: Activado después de importar

### Plex

- Biblioteca de películas: `/movies`
- Biblioteca de TV: `/tv`
- Escaneo automático: Activado

## 🔧 Guía de Configuración Paso a Paso

### 1️⃣ qBittorrent

- Accede a [http://localhost:8080](http://localhost:8080)
- Credenciales por defecto: usuario `admin` y contraseña `la contraseña que se genera la primera vez que se levanta el contenedor`
- Configuración inicial:
  1. WebUI > Password: la primera vez que se levanta el contenedor, se genera una contraseña aleatoria y se muestra en los logs.

  ```bash
  make logs-qbit
  ```

  ```bash
  qbittorrent  | The WebUI administrator password was not set. A temporary password is provided for this session: XXXXXX
  ```

  2. Tools > WebUI > Change password: Cambiar la contraseña o bien bypass de cliente en localhost:8080
  3. Tools > Options > Downloads
  4. Default Save Path: `/downloads`
  5. Keep incomplete torrents in: `/downloads/incomplete`
  6. Deshabilitar "Create subfolder for torrents"
  7. Save

- Documentación:
  - [https://hub.docker.com/r/linuxserver/qbittorrent](https://hub.docker.com/r/linuxserver/qbittorrent)
  - [https://wiki.archlinux.org/title/QBittorrent](https://wiki.archlinux.org/title/QBittorrent)

### 2️⃣ Prowlarr

- Accede a [http://localhost:9696](http://localhost:9696)
- Configuración inicial:
  1. Authentication Method: Elige un método, recomendado: Basic Authentication
  2. Authentication > Enable authentication
  3. Authentication > Username
  4. Authentication > Password
  5. Configura FlareSolverr como `http://flaresolverr:8191/`:
      - [https://trash-guides.info/Prowlarr/prowlarr-setup-flaresolverr/](https://trash-guides.info/Prowlarr/prowlarr-setup-flaresolverr/)

  6. Añade indexadores (trackers)
     - Añadir indexadores: recomendados los de privacy public y contengan tags de movies y tv
  7. Settings > Apps
     - Añade Radarr y Sonarr:
       - Accede para obtener el API Key a cada uno, en Settings > General > API Key
     - Hosts:
       - `http://prowlarr:9696`
       - `http://radarr:7878`
       - `http://sonarr:8989`

### 3️⃣ Radarr

- Accede a [http://localhost:7878](http://localhost:7878)
- Configuración inicial:
  1. Settings > Media Management
     - Movies Folder: `/movies`
     - Activar "Movie Naming"
  2. Settings > Download Clients
     - Añade qBittorrent
     - Host: qbittorrent
     - Puerto: 8080
     - Incluye el usuario y contraseña de qBittorrent
  3. Settings > General
     - Añade Prowlarr como indexador

### 4️⃣ Sonarr

- Accede a [http://localhost:8989](http://localhost:8989)
- Configuración similar a Radarr:
  1. Settings > Media Management
     - TV Folder: `/tv`
     - Activar "Episode Naming"
  2. Settings > Download Clients
     - Añade qBittorrent (igual que en Radarr)
  3. Settings > General
     - Añade Prowlarr como indexador

> **Nota**: custom-format-español.json es un custom format tanto para Radarr y Sonarr, se encuentra en la raiz del proyecto.
Ir a Settings > Custom Formats > Add Custom Format > Import Custom Format > Seleccionar el contenido del archivo custom-format-español.json > Import

### 5️⃣ Plex

- Accede a [http://localhost:32400/web](http://localhost:32400/web)
- Configuración de bibliotecas:
  1. Añade biblioteca Movies: `/movies`
  2. Añade biblioteca TV Shows: `/tv`
  3. Activa "Scan my library automatically"

## ⚙️ Notas Importantes

- Optimizado para Apple Silicon (ARM64)
- PUID=501 y PGID=20 (valores por defecto en macOS)
- Carpeta `downloads` compartida entre qBittorrent, Radarr y Sonarr
- Carpetas de medios (`Movies` y `TV`) compartidas entre Plex y Radarr/Sonarr

## 🔒 Seguridad

Recuerda cambiar las credenciales por defecto de qBittorrent después de la primera instalación.

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor, abre un issue o un pull request.

## 📝 Licencia

Este proyecto está bajo la Licencia MIT. Ver el archivo `LICENSE` para más detalles.
