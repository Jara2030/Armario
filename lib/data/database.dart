import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/catalog.dart';

part 'database.g.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();
  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).map((e) => e.toString()).toList();
  @override
  String toSql(List<String> value) => jsonEncode(value);
}

// Todas las tablas sincronizadas comparten: id (UUID), created_at/updated_at
// (milisegundos desde epoch), deleted (borrado lógico) y dirty (pendiente de
// subir al servidor; solo local).

class Items extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get type => text()();
  TextColumn get colors => text().map(const StringListConverter())();
  TextColumn get seasons => text().map(const StringListConverter())();
  TextColumn get occasions => text().map(const StringListConverter())();
  TextColumn get brand => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('disponible'))();

  /// Versión de la foto (ms). null = sin foto.
  IntColumn get photoVersion => integer().nullable()();

  /// La foto local aún no se ha subido al servidor (solo local).
  BoolColumn get photoDirty => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Fotos guardadas dentro de la propia base de datos (solo local). Así el
/// mismo código funciona en Android, Windows, iOS y web sin sistema de archivos.
class Photos extends Table {
  TextColumn get id => text()(); // = id de la prenda
  IntColumn get version => integer()();
  BlobColumn get full => blob()();
  BlobColumn get thumb => blob()();

  @override
  Set<Column> get primaryKey => {id};
}

class Outfits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get itemIds => text().map(const StringListConverter())();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class WearLogs extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text()();
  TextColumn get outfitId => text().nullable()();
  TextColumn get wornOn => text()(); // AAAA-MM-DD
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Clave/valor local (cursores de sincronización, etc.).
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Datos de una prenda al crearla o editarla.
class ItemDraft {
  String name;
  String type;
  List<String> colors;
  List<String> seasons;
  List<String> occasions;
  String brand;
  String notes;
  String status;
  ItemDraft({
    this.name = '',
    this.type = 'camiseta',
    List<String>? colors,
    List<String>? seasons,
    List<String>? occasions,
    this.brand = '',
    this.notes = '',
    this.status = statusAvailable,
  })  : colors = colors ?? [],
        seasons = seasons ?? [],
        occasions = occasions ?? [];

  factory ItemDraft.from(Item i) => ItemDraft(
        name: i.name,
        type: i.type,
        colors: [...i.colors],
        seasons: [...i.seasons],
        occasions: [...i.occasions],
        brand: i.brand,
        notes: i.notes,
        status: i.status,
      );
}

class ProcessedPhoto {
  final Uint8List full;
  final Uint8List thumb;
  const ProcessedPhoto(this.full, this.thumb);
}

@DriftDatabase(tables: [Items, Photos, Outfits, WearLogs, Meta])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.open()
      : super(driftDatabase(
          name: 'armario',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ));

  @override
  int get schemaVersion => 1;

  // ---------------------------------------------------------------- prendas

  Stream<List<Item>> watchItems() => (select(items)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Stream<Item?> watchItem(String id) =>
      (select(items)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Item?> getItem(String id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Crea (id == null) o actualiza una prenda. Devuelve su id.
  Future<String> saveItem(ItemDraft d, {String? id, ProcessedPhoto? photo}) {
    return transaction(() async {
      final now = nowMs();
      final itemId = id ?? newId();
      if (id == null) {
        await into(items).insert(ItemsCompanion.insert(
          id: itemId,
          name: Value(d.name),
          type: d.type,
          colors: d.colors,
          seasons: d.seasons,
          occasions: d.occasions,
          brand: Value(d.brand),
          notes: Value(d.notes),
          status: Value(d.status),
          photoVersion: Value(photo == null ? null : now),
          photoDirty: Value(photo != null),
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        await (update(items)..where((t) => t.id.equals(itemId)))
            .write(ItemsCompanion(
          name: Value(d.name),
          type: Value(d.type),
          colors: Value(d.colors),
          seasons: Value(d.seasons),
          occasions: Value(d.occasions),
          brand: Value(d.brand),
          notes: Value(d.notes),
          status: Value(d.status),
          photoVersion: photo == null ? const Value.absent() : Value(now),
          photoDirty: photo == null ? const Value.absent() : const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
      }
      if (photo != null) {
        await into(photos).insertOnConflictUpdate(PhotosCompanion.insert(
          id: itemId,
          version: now,
          full: photo.full,
          thumb: photo.thumb,
        ));
      }
      return itemId;
    });
  }

  Future<void> setStatus(Iterable<String> ids, String status) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (update(items)..where((t) => t.id.isIn(list))).write(ItemsCompanion(
      status: Value(status),
      updatedAt: Value(nowMs()),
      dirty: const Value(true),
    ));
  }

  /// Borrado lógico: la fila queda como lápida para que el borrado se
  /// propague a los demás dispositivos. La foto local se elimina ya.
  Future<void> deleteItem(String id) => transaction(() async {
        final now = nowMs();
        await (update(items)..where((t) => t.id.equals(id)))
            .write(ItemsCompanion(
          deleted: const Value(true),
          photoDirty: const Value(false),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
        await (delete(photos)..where((t) => t.id.equals(id))).go();
        // Sus registros de uso dejan de tener sentido.
        await (update(wearLogs)..where((t) => t.itemId.equals(id)))
            .write(WearLogsCompanion(
          deleted: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
        // Y se quita de los conjuntos que la usaban.
        final using = await (select(outfits)
              ..where((t) => t.deleted.equals(false)))
            .get();
        for (final o in using.where((o) => o.itemIds.contains(id))) {
          await (update(outfits)..where((t) => t.id.equals(o.id)))
              .write(OutfitsCompanion(
            itemIds: Value(o.itemIds.where((e) => e != id).toList()),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
        }
      });

  // ------------------------------------------------------------------ fotos

  Future<Uint8List?> thumbOf(String id) async {
    final q = selectOnly(photos)
      ..addColumns([photos.thumb])
      ..where(photos.id.equals(id));
    return (await q.getSingleOrNull())?.read(photos.thumb);
  }

  Future<Uint8List?> fullOf(String id) async {
    final q = selectOnly(photos)
      ..addColumns([photos.full])
      ..where(photos.id.equals(id));
    return (await q.getSingleOrNull())?.read(photos.full);
  }

  /// id de prenda -> versión de la foto que hay guardada en este dispositivo.
  Stream<Map<String, int>> watchPhotoVersions() {
    final q = selectOnly(photos)..addColumns([photos.id, photos.version]);
    return q.watch().map((rows) => {
          for (final r in rows) r.read(photos.id)!: r.read(photos.version)!,
        });
  }

  // -------------------------------------------------------------- conjuntos

  Stream<List<Outfit>> watchOutfits() => (select(outfits)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<String> saveOutfit({
    String? id,
    required String name,
    required String notes,
    required List<String> itemIds,
  }) async {
    final now = nowMs();
    final outfitId = id ?? newId();
    if (id == null) {
      await into(outfits).insert(OutfitsCompanion.insert(
        id: outfitId,
        name: Value(name),
        notes: Value(notes),
        itemIds: itemIds,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      await (update(outfits)..where((t) => t.id.equals(outfitId)))
          .write(OutfitsCompanion(
        name: Value(name),
        notes: Value(notes),
        itemIds: Value(itemIds),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
    }
    return outfitId;
  }

  Future<void> deleteOutfit(String id) =>
      (update(outfits)..where((t) => t.id.equals(id))).write(OutfitsCompanion(
        deleted: const Value(true),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ));

  // --------------------------------------------------------- historial de uso

  /// Marca prendas como usadas un día (por defecto hoy). No duplica si ya
  /// había registro de esa prenda ese día.
  Future<void> markWorn(Iterable<String> itemIds,
      {String? outfitId, DateTime? day}) {
    final key = dayKey(day ?? DateTime.now());
    return transaction(() async {
      final existing = await (select(wearLogs)
            ..where((t) => t.wornOn.equals(key) & t.deleted.equals(false)))
          .get();
      final already = existing.map((e) => e.itemId).toSet();
      final now = nowMs();
      for (final itemId in itemIds.toSet()) {
        if (already.contains(itemId)) continue;
        await into(wearLogs).insert(WearLogsCompanion.insert(
          id: newId(),
          itemId: itemId,
          outfitId: Value(outfitId),
          wornOn: key,
          createdAt: now,
          updatedAt: now,
        ));
      }
    });
  }

  Future<void> unmarkWorn(String itemId, {DateTime? day}) {
    final key = dayKey(day ?? DateTime.now());
    return (update(wearLogs)
          ..where((t) =>
              t.itemId.equals(itemId) &
              t.wornOn.equals(key) &
              t.deleted.equals(false)))
        .write(WearLogsCompanion(
      deleted: const Value(true),
      updatedAt: Value(nowMs()),
      dirty: const Value(true),
    ));
  }

  Stream<List<WearLog>> watchWearLogs() => (select(wearLogs)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.wornOn)]))
      .watch();

  // ------------------------------------------------------------------- meta

  Future<String?> getMeta(String key) async =>
      (await (select(meta)..where((t) => t.key.equals(key))).getSingleOrNull())
          ?.value;

  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await (delete(meta)..where((t) => t.key.equals(key))).go();
    } else {
      await into(meta)
          .insertOnConflictUpdate(MetaCompanion.insert(key: key, value: value));
    }
  }

  /// Hay cambios locales pendientes de subir.
  Stream<int> watchPendingCount() => customSelect(
        'SELECT (SELECT COUNT(*) FROM items WHERE dirty OR photo_dirty) + '
        '(SELECT COUNT(*) FROM outfits WHERE dirty) + '
        '(SELECT COUNT(*) FROM wear_logs WHERE dirty) AS c',
        readsFrom: {items, outfits, wearLogs},
      ).watchSingle().map((r) => r.read<int>('c'));

  /// Marca todo como pendiente y olvida los cursores: la próxima
  /// sincronización vuelve a subir y bajar todo (p. ej. al cambiar de
  /// proyecto de Supabase).
  Future<void> resetSyncState() => transaction(() async {
        await customUpdate('UPDATE items SET dirty = 1', updates: {items});
        await customUpdate(
            'UPDATE items SET photo_dirty = 1 WHERE deleted = 0 AND '
            'id IN (SELECT id FROM photos)',
            updates: {items});
        await customUpdate('UPDATE outfits SET dirty = 1', updates: {outfits});
        await customUpdate('UPDATE wear_logs SET dirty = 1',
            updates: {wearLogs});
        await delete(meta).go();
      });
}
