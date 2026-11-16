import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import 'database.dart';

/// Copia de seguridad completa en un único archivo .zip:
///   data.json            -> prendas, conjuntos e historial
///   `photos/<id>.jpg`    -> foto de cada prenda
///   `photos/<id>_t.jpg`  -> miniatura
/// El formato es JSON + JPEG normales, legibles sin esta app.
class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  static const formatVersion = 1;

  Future<Uint8List> export() async {
    final items = await (db.select(db.items)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final outfits = await (db.select(db.outfits)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final logs = await (db.select(db.wearLogs)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final data = {
      'app': 'armario',
      'format': formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'items': [
        for (final i in items)
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
            'photo_version': i.photoVersion,
            'created_at': i.createdAt,
            'updated_at': i.updatedAt,
          }
      ],
      'outfits': [
        for (final o in outfits)
          {
            'id': o.id,
            'name': o.name,
            'notes': o.notes,
            'item_ids': o.itemIds,
            'created_at': o.createdAt,
            'updated_at': o.updatedAt,
          }
      ],
      'wear_logs': [
        for (final w in logs)
          {
            'id': w.id,
            'item_id': w.itemId,
            'outfit_id': w.outfitId,
            'worn_on': w.wornOn,
            'created_at': w.createdAt,
            'updated_at': w.updatedAt,
          }
      ],
    };
    final archive = Archive();
    final json = utf8.encode(const JsonEncoder.withIndent(' ').convert(data));
    archive.addFile(ArchiveFile.bytes('data.json', json));
    for (final i in items) {
      final p = await (db.select(db.photos)..where((t) => t.id.equals(i.id)))
          .getSingleOrNull();
      if (p == null) continue;
      // Los JPEG ya están comprimidos: se guardan tal cual.
      archive.addFile(ArchiveFile.noCompress('photos/${i.id}.jpg', p.full.length, p.full));
      archive.addFile(ArchiveFile.noCompress('photos/${i.id}_t.jpg', p.thumb.length, p.thumb));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Importa una copia fusionándola con lo que haya: para cada elemento gana
  /// la versión modificada más recientemente. No borra nada que no esté en la
  /// copia. Todo lo importado queda pendiente de sincronizar.
  Future<ImportResult> import(Uint8List zipBytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const FormatException('El archivo no es un .zip válido.');
    }
    final dataFile = archive.findFile('data.json');
    if (dataFile == null) {
      throw const FormatException(
          'El archivo no es una copia de seguridad de Armario.');
    }
    final data = jsonDecode(utf8.decode(dataFile.content)) as Map;
    if (data['app'] != 'armario') {
      throw const FormatException(
          'El archivo no es una copia de seguridad de Armario.');
    }
    final result = ImportResult();
    List<String> list(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];

    await db.transaction(() async {
      for (final r in (data['items'] as List? ?? const [])) {
        final id = r['id'] as String;
        final updated = (r['updated_at'] as num).toInt();
        final local = await db.getItem(id);
        if (local != null && local.updatedAt >= updated && !local.deleted) {
          continue;
        }
        final full = archive.findFile('photos/$id.jpg')?.content;
        final thumb = archive.findFile('photos/${id}_t.jpg')?.content;
        final hasPhoto = full != null && thumb != null;
        final version = hasPhoto
            ? ((r['photo_version'] as num?)?.toInt() ?? updated)
            : null;
        // Si "resucita" una prenda borrada, se le da fecha nueva para que la
        // restauración gane al borrado al sincronizar.
        final stamp = (local != null && local.deleted)
            ? DateTime.now().millisecondsSinceEpoch
            : updated;
        await db.into(db.items).insertOnConflictUpdate(ItemsCompanion.insert(
              id: id,
              name: Value((r['name'] ?? '') as String),
              type: (r['type'] ?? 'otro') as String,
              colors: list(r['colors']),
              seasons: list(r['seasons']),
              occasions: list(r['occasions']),
              brand: Value((r['brand'] ?? '') as String),
              notes: Value((r['notes'] ?? '') as String),
              status: Value((r['status'] ?? 'disponible') as String),
              photoVersion: Value(version),
              photoDirty: Value(hasPhoto),
              createdAt: (r['created_at'] as num).toInt(),
              updatedAt: stamp,
              deleted: const Value(false),
              dirty: const Value(true),
            ));
        if (hasPhoto) {
          await db.into(db.photos).insertOnConflictUpdate(
              PhotosCompanion.insert(
                  id: id,
                  version: version!,
                  full: Uint8List.fromList(full),
                  thumb: Uint8List.fromList(thumb)));
        }
        result.items++;
      }
      for (final r in (data['outfits'] as List? ?? const [])) {
        final id = r['id'] as String;
        final updated = (r['updated_at'] as num).toInt();
        final local = await (db.select(db.outfits)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (local != null && local.updatedAt >= updated && !local.deleted) {
          continue;
        }
        await db
            .into(db.outfits)
            .insertOnConflictUpdate(OutfitsCompanion.insert(
              id: id,
              name: Value((r['name'] ?? '') as String),
              notes: Value((r['notes'] ?? '') as String),
              itemIds: list(r['item_ids']),
              createdAt: (r['created_at'] as num).toInt(),
              updatedAt: (local != null && local.deleted)
                  ? DateTime.now().millisecondsSinceEpoch
                  : updated,
              deleted: const Value(false),
              dirty: const Value(true),
            ));
        result.outfits++;
      }
      for (final r in (data['wear_logs'] as List? ?? const [])) {
        final id = r['id'] as String;
        final exists = await (db.select(db.wearLogs)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (exists != null) continue;
        await db.into(db.wearLogs).insert(WearLogsCompanion.insert(
              id: id,
              itemId: r['item_id'] as String,
              outfitId: Value(r['outfit_id'] as String?),
              wornOn: r['worn_on'] as String,
              createdAt: (r['created_at'] as num).toInt(),
              updatedAt: (r['updated_at'] as num).toInt(),
            ));
        result.wearLogs++;
      }
    });
    return result;
  }
}

class ImportResult {
  int items = 0;
  int outfits = 0;
  int wearLogs = 0;
}
