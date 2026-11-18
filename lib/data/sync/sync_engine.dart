import 'package:drift/drift.dart';

import '../database.dart';
import 'remote_store.dart';

/// Sincronización local <-> servidor.
///
/// Reglas:
///  * La base local es la fuente de verdad de la interfaz; esto solo copia.
///  * Cada fila lleva `updated_at` (reloj del dispositivo, ms). Si hay
///    conflicto gana la modificación más reciente ("last write wins").
///  * Los borrados son lógicos (`deleted = true`) para poder propagarse.
///  * Lo pendiente de subir se marca con `dirty` (y `photo_dirty`).
///  * Lo que hay que bajar se localiza con un cursor por tabla sobre
///    `server_updated_at`, que pone el servidor (no depende de relojes locales).
///  * Cualquier fallo (sin red, proyecto pausado…) lanza una excepción y no
///    deja nada a medias: todo sigue marcado como pendiente y se reintenta.
class SyncEngine {
  final AppDatabase db;
  final RemoteStore remote;
  SyncEngine(this.db, this.remote);

  static const _page = 500;
  static const _chunk = 100;

  /// Margen que se resta al cursor para no perder filas confirmadas con
  /// retraso en el servidor. Reaplicar filas ya vistas es inofensivo.
  static const _overlap = Duration(seconds: 60);

  Future<SyncStats> run() async {
    final stats = SyncStats();
    final tables = <_TableSync>[_itemsSync(), _outfitsSync(), _wearLogsSync()];
    for (final t in tables) {
      stats.pulled += await _pull(t);
    }
    // Las fotos se suben ANTES que las filas, para que ningún otro
    // dispositivo vea una prenda cuya foto todavía no existe.
    stats.photosUp = await _uploadPhotos();
    for (final t in tables) {
      stats.pushed += await _push(t);
    }
    stats.photosDown = await _downloadPhotos();
    return stats;
  }

  // ------------------------------------------------------------------ bajar

  Future<int> _pull(_TableSync t) async {
    final cursorKey = 'cursor_${t.name}';
    final cursor = await db.getMeta(cursorKey);
    String? since;
    if (cursor != null) {
      final parsed = DateTime.tryParse(cursor);
      since = parsed?.toUtc().subtract(_overlap).toIso8601String();
    }
    var offset = 0;
    var applied = 0;
    String? maxSeen = cursor;
    while (true) {
      final rows = await remote.pull(t.name, since, offset, _page);
      for (final row in rows) {
        if (await _applyRemote(t, row)) applied++;
        final s = row['server_updated_at']?.toString();
        if (s != null && _isAfter(s, maxSeen)) maxSeen = s;
      }
      if (rows.length < _page) break;
      offset += rows.length;
    }
    if (maxSeen != null && maxSeen != cursor) {
      await db.setMeta(cursorKey, maxSeen);
    }
    return applied;
  }

  bool _isAfter(String a, String? b) {
    if (b == null) return true;
    final da = DateTime.tryParse(a), dbb = DateTime.tryParse(b);
    if (da == null || dbb == null) return a.compareTo(b) > 0;
    return da.isAfter(dbb);
  }

  /// Aplica una fila remota si es más nueva que la local. Devuelve true si
  /// cambió algo.
  Future<bool> _applyRemote(_TableSync t, Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdated = (row['updated_at'] as num).toInt();
    final local = await db.customSelect(
      'SELECT dirty, updated_at FROM ${t.name} WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    if (local != null) {
      final localUpdated = local.read<int>('updated_at');
      final localDirty = local.read<bool>('dirty');
      if (localDirty && localUpdated >= remoteUpdated) return false;
      if (!localDirty && localUpdated == remoteUpdated) return false;
    }
    await t.apply(row);
    return true;
  }

  // ------------------------------------------------------------------ subir

  Future<int> _push(_TableSync t) async {
    final rows = await t.dirtyRows();
    for (var i = 0; i < rows.length; i += _chunk) {
      final chunk = rows.sublist(
          i, i + _chunk > rows.length ? rows.length : i + _chunk);
      await remote.push(t.name, chunk);
      await db.transaction(() async {
        for (final r in chunk) {
          // Solo se da por subida si no se ha vuelto a tocar entretanto.
          await db.customUpdate(
            'UPDATE ${t.name} SET dirty = 0 WHERE id = ? AND updated_at = ?',
            variables: [
              Variable.withString(r['id'] as String),
              Variable.withInt(r['updated_at'] as int),
            ],
            updates: {t.table},
          );
        }
      });
    }
    return rows.length;
  }

  // ------------------------------------------------------------------ fotos

  Future<int> _uploadPhotos() async {
    var n = 0;
    final pending = await (db.select(db.items)
          ..where((t) => t.photoDirty.equals(true) & t.deleted.equals(false)))
        .get();
    for (final item in pending) {
      final photo = await (db.select(db.photos)
            ..where((t) => t.id.equals(item.id)))
          .getSingleOrNull();
      if (photo != null) {
        await remote.uploadPhoto(item.id, photo.full, photo.thumb);
        n++;
      }
      await db.customUpdate(
        'UPDATE items SET photo_dirty = 0 WHERE id = ? AND photo_version IS ?',
        variables: [
          Variable.withString(item.id),
          Variable<int>(item.photoVersion),
        ],
        updates: {db.items},
      );
    }
    // Fotos de prendas borradas: se eliminan del servidor (si falla, no pasa
    // nada grave: solo ocupa espacio).
    final tombstones = await (db.select(db.items)
          ..where((t) =>
              t.deleted.equals(true) &
              t.dirty.equals(true) &
              t.photoVersion.isNotNull()))
        .get();
    for (final item in tombstones) {
      try {
        await remote.deletePhoto(item.id);
      } catch (_) {}
    }
    return n;
  }

  Future<int> _downloadPhotos() async {
    var n = 0;
    final rows = await db.customSelect(
      'SELECT i.id AS id, i.photo_version AS v FROM items i '
      'LEFT JOIN photos p ON p.id = i.id '
      'WHERE i.deleted = 0 AND i.photo_dirty = 0 '
      'AND i.photo_version IS NOT NULL '
      'AND (p.id IS NULL OR p.version <> i.photo_version)',
      readsFrom: {db.items, db.photos},
    ).get();
    for (final r in rows) {
      final id = r.read<String>('id');
      final version = r.read<int>('v');
      final photo = await remote.downloadPhoto(id);
      if (photo == null) continue; // aún no subida: se reintenta otro día
      await db.into(db.photos).insertOnConflictUpdate(PhotosCompanion.insert(
            id: id,
            version: version,
            full: photo.full,
            thumb: photo.thumb,
          ));
      n++;
    }
    return n;
  }

  // ----------------------------------------------------- mapeo de cada tabla

  static List<String> _list(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : <String>[];

  _TableSync _itemsSync() => _TableSync(
        name: 'items',
        table: db.items,
        dirtyRows: () async {
          final rows = await (db.select(db.items)
                ..where((t) => t.dirty.equals(true)))
              .get();
          return [
            for (final i in rows)
              {
                'id': i.id,
                'name': i.name,
                'type': i.type,
                'colors': i.colors,
                'seasons': i.seasons,
                'occasions': i.occasions,
                'brand': i.brand,
                'notes': i.notes,
                'status': i.status,
                'location': i.location,
                'photo_version': i.photoVersion,
                'created_at': i.createdAt,
                'updated_at': i.updatedAt,
                'deleted': i.deleted,
              }
          ];
        },
        apply: (r) async {
          final deleted = r['deleted'] == true;
          await db.into(db.items).insertOnConflictUpdate(ItemsCompanion.insert(
                id: r['id'] as String,
                name: Value((r['name'] ?? '') as String),
                type: (r['type'] ?? 'otro') as String,
                colors: _list(r['colors']),
                seasons: _list(r['seasons']),
                occasions: _list(r['occasions']),
                brand: Value((r['brand'] ?? '') as String),
                notes: Value((r['notes'] ?? '') as String),
                status: Value((r['status'] ?? 'disponible') as String),
                location: Value((r['location'] ?? '') as String),
                photoVersion: Value((r['photo_version'] as num?)?.toInt()),
                photoDirty: const Value(false),
                createdAt: (r['created_at'] as num).toInt(),
                updatedAt: (r['updated_at'] as num).toInt(),
                deleted: Value(deleted),
                dirty: const Value(false),
              ));
          if (deleted) {
            await (db.delete(db.photos)
                  ..where((t) => t.id.equals(r['id'] as String)))
                .go();
          }
        },
      );

  _TableSync _outfitsSync() => _TableSync(
        name: 'outfits',
        table: db.outfits,
        dirtyRows: () async {
          final rows = await (db.select(db.outfits)
                ..where((t) => t.dirty.equals(true)))
              .get();
          return [
            for (final o in rows)
              {
                'id': o.id,
                'name': o.name,
                'notes': o.notes,
                'item_ids': o.itemIds,
                'created_at': o.createdAt,
                'updated_at': o.updatedAt,
                'deleted': o.deleted,
              }
          ];
        },
        apply: (r) => db
            .into(db.outfits)
            .insertOnConflictUpdate(OutfitsCompanion.insert(
              id: r['id'] as String,
              name: Value((r['name'] ?? '') as String),
              notes: Value((r['notes'] ?? '') as String),
              itemIds: _list(r['item_ids']),
              createdAt: (r['created_at'] as num).toInt(),
              updatedAt: (r['updated_at'] as num).toInt(),
              deleted: Value(r['deleted'] == true),
              dirty: const Value(false),
            )),
      );

  _TableSync _wearLogsSync() => _TableSync(
        name: 'wear_logs',
        table: db.wearLogs,
        dirtyRows: () async {
          final rows = await (db.select(db.wearLogs)
                ..where((t) => t.dirty.equals(true)))
              .get();
          return [
            for (final w in rows)
              {
                'id': w.id,
                'item_id': w.itemId,
                'outfit_id': w.outfitId,
                'worn_on': w.wornOn,
                'created_at': w.createdAt,
                'updated_at': w.updatedAt,
                'deleted': w.deleted,
              }
          ];
        },
        apply: (r) => db
            .into(db.wearLogs)
            .insertOnConflictUpdate(WearLogsCompanion.insert(
              id: r['id'] as String,
              itemId: r['item_id'] as String,
              outfitId: Value(r['outfit_id'] as String?),
              wornOn: r['worn_on'] as String,
              createdAt: (r['created_at'] as num).toInt(),
              updatedAt: (r['updated_at'] as num).toInt(),
              deleted: Value(r['deleted'] == true),
              dirty: const Value(false),
            )),
      );
}

class SyncStats {
  int pulled = 0;
  int pushed = 0;
  int photosUp = 0;
  int photosDown = 0;
  @override
  String toString() =>
      '↓$pulled ↑$pushed · fotos ↓$photosDown ↑$photosUp';
}

class _TableSync {
  final String name;
  final TableInfo table;
  final Future<List<Map<String, dynamic>>> Function() dirtyRows;
  final Future<void> Function(Map<String, dynamic> row) apply;
  _TableSync({
    required this.name,
    required this.table,
    required this.dirtyRows,
    required this.apply,
  });
}
