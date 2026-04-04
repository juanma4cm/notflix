# Plan 04 — Configuración manual post-provisioning

Pasos que requieren interacción manual (credenciales externas, OAuth, apps móviles).
Ejecutar en orden tras completar `make provision` con éxito.

---

## Paso 1 — Prowlarr: añadir indexers

**URL:** http://prowlarr.notflix.internal

1. Settings → Indexers → Add Indexer
2. Buscar y añadir los indexers deseados (ej: Jackett, 1337x, RARBG, etc.)
3. Cada indexer requiere credenciales propias (cuenta externa)
4. Tras añadir indexers, Prowlarr los sincroniza automáticamente con Radarr y Sonarr (fullSync ya configurado)

**Verificar:** Radarr → Settings → Indexers debe mostrar los indexers sincronizados desde Prowlarr.

---

## Paso 2 — Plex: configurar bibliotecas

**URL:** http://plex.notflix.internal

1. Acceder y completar el wizard inicial
2. Añadir biblioteca de películas:
   - Library Type: Movies
   - Add folder: `/movies`
3. Añadir biblioteca de series:
   - Library Type: TV Shows
   - Add folder: `/tv`
4. Settings → Remote Access → Custom server access URLs:
   - Añadir `http://plex.notflix.internal`

> Los directorios `/movies` y `/tv` dentro del contenedor apuntan a `/mnt/media/movies` y `/mnt/media/tv` via symlinks del host.

---

## Paso 3 — Overseerr: conectar con Plex

**URL:** http://overseerr.notflix.internal

1. Login con cuenta Plex (OAuth)
2. En el wizard, seleccionar el servidor Plex detectado en la red (`plex-server` en `media-network`)
3. Añadir Radarr:
   - URL: `http://radarr:7878`
   - API Key: valor de `RADARR_API_KEY` en `.env`
   - Quality Profile: elegir el deseado
   - Root Folder: `/movies`
4. Añadir Sonarr:
   - URL: `http://sonarr:8989`
   - API Key: valor de `SONARR_API_KEY` en `.env`
   - Quality Profile: elegir el deseado
   - Root Folder: `/tv`
5. Test → Save

---

## Paso 4 — ntfy: suscribirse desde el móvil

**Requisito:** App ntfy instalada en el móvil + Tailscale activo en el dispositivo.

Suscribirse a estos tópicos desde la app ntfy:
- `http://ntfy.notflix.internal/notflix-movies` — notificaciones de películas (Radarr)
- `http://ntfy.notflix.internal/notflix-series` — notificaciones de series (Sonarr)
- `http://ntfy.notflix.internal/notflix-updates` — actualizaciones de imágenes Docker (Diun, cada lunes)

> El servidor ntfy no requiere autenticación. Solo es accesible dentro de la red Tailscale.

---

## Paso 5 — Recyclarr: sincronizar quality profiles (opcional)

Sincroniza perfiles de calidad y custom formats desde TRaSH-Guides:

```bash
make recyclarr
```

Revisa `recyclarr/recyclarr.yml` para ajustar los perfiles antes de sincronizar.
Para importar el perfil de español: Radarr/Sonarr → Settings → Custom Formats → Import → pegar contenido de `custom-format-español.json`.

---

## Estado

- [ ] Paso 1 — Prowlarr indexers
- [ ] Paso 2 — Plex bibliotecas
- [ ] Paso 3 — Overseerr
- [ ] Paso 4 — ntfy móvil
- [ ] Paso 5 — Recyclarr (opcional)
