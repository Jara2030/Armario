# PROGRESS · Armario

Documento de traspaso. Quien continúe (otra sesión u otro modelo) debe poder
retomar el trabajo leyendo solo esto. **Mantenerlo siempre actualizado.**

Última actualización: 2026-11-16

## Requisitos que no se pueden romper

- **100 % gratis.** Nada de servicios con tarjeta ni "gratis hasta X" sin
  avisar antes al usuario y proponer alternativa gratuita.
- Trabajar **en español** con el usuario, que no es experto: explicar los
  comandos.
- App **nativa** en Android y Windows; iPhone por .ipa sin firmar (Sideloadly /
  SideStore) y PWA en GitHub Pages como plan B.
- **Offline-first**: la app nunca depende del servidor para funcionar.
- **Nunca** subir secretos al repo (ver `.gitignore`: `config.json`, `*.jks`).

## Estado actual

| Fase | Estado |
|---|---|
| 1. MVP (prendas, fotos, filtros, estados, "hoy", copia de seguridad) | Hecho y probado en navegador |
| 2. Workflows de GitHub Actions (APK, Windows, .ipa, PWA) | **Hecho**: APK, Windows y .ipa compilan en CI y se publican en Releases → `latest`. Solo falla el job de Pages hasta que el usuario lo active |
| 3. Sincronización con Supabase + login | Código hecho y probado contra un servidor falso; **sin probar contra un Supabase real** |
| 4. iOS (.ipa sin firmar + PWA) | El .ipa se genera en CI; pendiente de probar en un iPhone real |
| 5. Extras (conjuntos, historial, sugerencia por tiempo, modo oscuro) | Hecho |
| 6. README en español | Hecho |

### Qué se ha verificado de verdad

- `flutter analyze`: sin avisos. `flutter test`: 14 tests en verde
  (`test/sync_test.dart`, `test/logic_test.dart`).
- Compilación web (`flutter build web`) y recorrido real en Chromium con
  Playwright: añadir prenda con foto (se comprime), editar, galería, búsqueda,
  filtros, cambio de estado, "me lo he puesto hoy", pantalla Hoy con
  sugerencia, guardar conjunto, ajustes, modo oscuro, exportar e importar
  copia de seguridad, y layout de escritorio (1360 px).

### Qué NO se ha verificado todavía

- Las apps compiladas de Android, Windows e iPhone **no se han ejecutado en
  un dispositivo real** (solo se sabe que compilan en GitHub Actions). La
  misma app sí se ha probado a fondo en su versión web.
- Sincronización contra un proyecto real de Supabase (`supabase/schema.sql`
  está validado sintácticamente con un parser de PostgreSQL, pero no ejecutado).
- Cámara en Android / iPhone y selector de archivos en Windows.
- Open-Meteo solo se ha probado sin ciudad configurada (la lógica de la
  sugerencia tiene tests; la llamada HTTP no).

## Casa (mamá / papá)

Pedido por el usuario (vive en dos casas). Columna `items.location`
('mama', 'papa' o ''), esquema local v2 con migración (`test/migration_test.dart`)
y `alter table ... add column if not exists location` en `supabase/schema.sql`.
Se elige en el formulario (por defecto, la casa actual), se cambia en el
detalle o con pulsación larga, se filtra en Armario, y en "Hoy" un selector
Mamá / Papá / Todo (guardado en preferencias) limita lo disponible y la
sugerencia a esa casa (más lo que no tiene casa indicada).

## Próximo paso exacto

1. El usuario instala el APK y el .zip de Windows desde Releases y cuenta
   qué tal van; corregir lo que salga.
2. El usuario debe (ver README): activar GitHub Pages (Source: GitHub
   Actions), añadir el secreto `ANDROID_KEYSTORE_BASE64`, crear el proyecto de
   Supabase, ejecutar `supabase/schema.sql` y crear su usuario.
3. Probar la sincronización real entre dos dispositivos y corregir lo que salga.
4. Probar en el móvil: cámara, rendimiento de la compresión de fotos, uso con
   una mano.

## Ideas pendientes (no pedidas, no hacer sin preguntar)

- Borrar del servidor las lápidas (`deleted = true`) antiguas.
- Recorte / eliminación de fondo de las fotos.
- Estadísticas (coste por uso, prendas más usadas).
- Ubicación automática para el tiempo (ahora se elige ciudad a mano para no
  pedir permisos).

## Arquitectura

- **Flutter 3.50 / Dart 3.14.** OJO: en esta versión Material ya no viene
  dentro de `flutter`; se importa de `package:material_ui/material_ui.dart`.
- **Estado:** Riverpod 3 (sin generación de código). Todo en
  `lib/providers.dart`.
- **Base de datos local:** drift (SQLite). En web usa `web/sqlite3.wasm` y
  `web/drift_worker.js` (descargados de las releases de drift/sqlite3; hay
  que actualizarlos si se suben esas dependencias).
- **Navegación:** `Navigator` simple + `openPage()` (en pantallas anchas abre
  las pantallas secundarias como diálogo centrado). No se usa go_router.
- **Layout adaptativo:** < 800 px barra inferior; ≥ 800 px `NavigationRail`.

### Estructura

```
lib/
  main.dart                 arranque, tema claro/oscuro
  providers.dart            estado: datos, filtros, ajustes, sync, tiempo
  core/catalog.dart         tipos, colores, temporadas, ocasiones, estados
  core/suggest.dart         sugerencia de conjunto según temperatura
  data/database.dart        tablas drift + operaciones (database.g.dart es generado)
  data/photo_processor.dart compresión de fotos
  data/backup.dart          exportar / importar .zip
  data/sync/remote_store.dart  interfaz del servidor + implementación Supabase
  data/sync/sync_engine.dart   motor de sincronización
  ui/                       shell, armario, detalle, formulario, hoy, conjuntos, ajustes
supabase/schema.sql         tablas, RLS, disparadores y bucket
.github/workflows/build.yml compila todo y publica
test/                       tests de sincronización, copia, compresión y lógica
```

Tras cambiar tablas en `database.dart`: `dart run build_runner build` y subir
`database.g.dart` (se versiona a propósito, para que CI no lo regenere). Si
cambia el esquema hay que subir `schemaVersion` y escribir la migración.

### Modelo de datos

Tablas sincronizadas (local y Supabase, mismos nombres de columna):

- `items`: id (UUID), name, type, colors[], seasons[], occasions[], brand,
  notes, status, photo_version, created_at, updated_at, deleted.
- `outfits`: id, name, notes, item_ids[], created_at, updated_at, deleted.
- `wear_logs`: id, item_id, outfit_id?, worn_on (AAAA-MM-DD), created_at,
  updated_at, deleted.

Solo locales: columnas `dirty` y `photo_dirty`; tabla `photos` (id de prenda,
version, full, thumb) y tabla `meta` (cursores de sync). Solo en servidor:
`user_id` y `server_updated_at`.

Las fechas son enteros en milisegundos. Las listas son JSON (texto en local,
`jsonb` en Supabase).

### Decisiones tomadas (y por qué)

- **Fotos dentro de SQLite (BLOB)** en vez de archivos: el mismo código vale
  para Android, Windows, iOS y web (que no tiene sistema de archivos). Con
  ~200 KB por foto y unos cientos de prendas es asumible.
- **Compresión con `package:image` (Dart puro)**: lado mayor 1280 px, JPEG
  bajando calidad hasta ≤ 250 KB, más miniatura de 400 px. Funciona en todas
  las plataformas (flutter_image_compress no soporta Windows).
- **Sincronización propia** (no PowerSync ni similares, para no depender de
  otro servicio): `updated_at` del dispositivo + "gana el último cambio",
  borrado lógico, `dirty` para lo pendiente de subir y cursor por tabla sobre
  `server_updated_at`. Las fotos se suben antes que las filas. Un disparador
  en Postgres descarta escrituras más antiguas que lo guardado.
- **Servidor caído o pausado:** cualquier error de red deja todo como
  pendiente y se reintenta (al abrir la app, al volver a primer plano, 4 s
  después de cada cambio y cada 5 min). La interfaz nunca espera al servidor.
- **Configuración de Supabase en Ajustes** (URL + clave pública), además de
  `--dart-define`. Así las compilaciones públicas de GitHub no llevan nada
  dentro. La clave "anon/publishable" es pública por diseño; la protección
  real es RLS + login.
- **Conjuntos con `item_ids` como lista** en vez de tabla intermedia: menos
  tablas que sincronizar.
- **Ciudad manual** para el tiempo (geocodificación de Open-Meteo): evita
  permisos de ubicación.
- **CI con Java 21:** con Java 17 falla `lintVitalAnalyzeRelease` de
  image_picker_android (`List.removeLast`).
- **Firma del APK:** si existe `android/app/armario.jks` se usa; si no, clave
  de depuración. En CI sale del secreto `ANDROID_KEYSTORE_BASE64`
  (contraseña y alias: `armario`).
- **Fuente Roboto incluida** en `assets/fonts` y `--no-web-resources-cdn`
  para que la PWA funcione sin internet.

### Problemas conocidos

- Con el modo de accesibilidad de Flutter web activado (lectores de
  pantalla), el navegador puede bloquear la apertura del selector de fotos.
  Solo afecta a la PWA con tecnologías de asistencia.
- En iPhone, Safari puede borrar los datos de una web que no se abre en
  7 días si NO está añadida a la pantalla de inicio. Instalada como PWA no
  debería ocurrir; aun así, usar sincronización o copias de seguridad.
