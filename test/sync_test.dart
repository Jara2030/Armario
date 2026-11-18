import 'package:armario/data/backup.dart';
import 'package:armario/data/database.dart';
import 'package:armario/data/photo_processor.dart';
import 'package:armario/data/sync/remote_store.dart';
import 'package:armario/data/sync/sync_engine.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Servidor falso en memoria que imita lo que hace Supabase: guarda filas
/// por id, pone `server_updated_at` y descarta escrituras más antiguas.
class FakeRemote implements RemoteStore {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  final photos = <String, ({Uint8List full, Uint8List thumb})>{};
  bool offline = false;
  var _clock = DateTime.utc(2026, 1, 1);

  void _check() {
    if (offline) throw Exception('servidor no disponible');
  }

  @override
  Future<List<Map<String, dynamic>>> pull(
      String table, String? since, int offset, int limit) async {
    _check();
    final rows = (tables[table] ?? {}).values.where((r) {
      if (since == null) return true;
      return DateTime.parse(r['server_updated_at'] as String)
          .isAfter(DateTime.parse(since));
    }).toList()
      ..sort((a, b) {
        final c = (a['server_updated_at'] as String)
            .compareTo(b['server_updated_at'] as String);
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    return rows.skip(offset).take(limit).map((r) => {...r}).toList();
  }

  @override
  Future<void> push(String table, List<Map<String, dynamic>> rows) async {
    _check();
    final t = tables.putIfAbsent(table, () => {});
    _clock = _clock.add(const Duration(seconds: 1));
    for (final r in rows) {
      final old = t[r['id']];
      if (old != null &&
          (old['updated_at'] as int) > (r['updated_at'] as int)) {
        continue;
      }
      t[r['id'] as String] = {
        ...r,
        'server_updated_at': _clock.toIso8601String()
      };
    }
  }

  @override
  Future<void> uploadPhoto(
      String itemId, Uint8List full, Uint8List thumb) async {
    _check();
    photos[itemId] = (full: full, thumb: thumb);
  }

  @override
  Future<({Uint8List full, Uint8List thumb})?> downloadPhoto(
      String itemId) async {
    _check();
    return photos[itemId];
  }

  @override
  Future<void> deletePhoto(String itemId) async {
    _check();
    photos.remove(itemId);
  }
}

AppDatabase memDb() => AppDatabase(NativeDatabase.memory());

ProcessedPhoto fakePhoto(int seed) => ProcessedPhoto(
    Uint8List.fromList(List.filled(100, seed)),
    Uint8List.fromList(List.filled(10, seed)));

Future<void> tick() => Future.delayed(const Duration(milliseconds: 3));

void main() {
  late AppDatabase a, b;
  late FakeRemote remote;
  late SyncEngine sa, sb;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    a = memDb();
    b = memDb();
    remote = FakeRemote();
    sa = SyncEngine(a, remote);
    sb = SyncEngine(b, remote);
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<List<Item>> live(AppDatabase d) => d.watchItems().first;

  test('una prenda con foto viaja de un dispositivo a otro', () async {
    final id = await a.saveItem(
        ItemDraft(name: 'Camisa azul', type: 'camisa', colors: ['azul']),
        photo: fakePhoto(1));
    await sa.run();
    await sb.run();
    final items = await live(b);
    expect(items.single.name, 'Camisa azul');
    expect(items.single.colors, ['azul']);
    expect((await b.fullOf(id))!.first, 1);
    expect((await a.getItem(id))!.dirty, false);
    expect((await a.getItem(id))!.photoDirty, false);
    expect(await a.watchPendingCount().first, 0);
  });

  test('la casa viaja con la sincronización y la copia', () async {
    final id = await a.saveItem(ItemDraft(type: 'camisa', location: 'mama'));
    await sa.run();
    await sb.run();
    expect((await b.getItem(id))!.location, 'mama');
    await tick();
    await b.setLocation([id], 'papa');
    await sb.run();
    await sa.run();
    expect((await a.getItem(id))!.location, 'papa');
    final c = memDb();
    await BackupService(c).import(await BackupService(a).export());
    expect((await c.getItem(id))!.location, 'papa');
    await c.close();
  });

  test('gana la modificación más reciente', () async {
    final id = await a.saveItem(ItemDraft(name: 'v1', type: 'camisa'));
    await sa.run();
    await sb.run();
    await tick();
    await a.saveItem(ItemDraft(name: 'desde A', type: 'camisa'), id: id);
    await tick();
    await b.saveItem(ItemDraft(name: 'desde B', type: 'camisa'), id: id);
    await sa.run();
    await sb.run();
    await sa.run();
    expect((await a.getItem(id))!.name, 'desde B');
    expect((await b.getItem(id))!.name, 'desde B');
  });

  test('un cambio antiguo no pisa uno nuevo ya subido', () async {
    final id = await a.saveItem(ItemDraft(name: 'v1', type: 'camisa'));
    await sa.run();
    await sb.run();
    await tick();
    await b.saveItem(ItemDraft(name: 'viejo (B)', type: 'camisa'), id: id);
    await tick();
    await a.saveItem(ItemDraft(name: 'nuevo (A)', type: 'camisa'), id: id);
    await sa.run();
    await sb.run(); // B baja el de A, que es más nuevo
    await sa.run();
    expect((await a.getItem(id))!.name, 'nuevo (A)');
    expect((await b.getItem(id))!.name, 'nuevo (A)');
  });

  test('los borrados se propagan y eliminan la foto', () async {
    final id = await a.saveItem(ItemDraft(type: 'camisa'), photo: fakePhoto(2));
    await sa.run();
    await sb.run();
    expect(await live(b), hasLength(1));
    await tick();
    await a.deleteItem(id);
    await sa.run();
    await sb.run();
    expect(await live(b), isEmpty);
    expect(await b.fullOf(id), isNull);
    expect(remote.photos, isEmpty);
  });

  test('servidor caído: no se rompe y sincroniza al volver', () async {
    remote.offline = true;
    final id = await a.saveItem(ItemDraft(name: 'offline', type: 'camisa'),
        photo: fakePhoto(3));
    await expectLater(sa.run(), throwsException);
    expect((await a.getItem(id))!.dirty, true);
    expect((await live(a)).single.name, 'offline');
    remote.offline = false;
    await sa.run();
    await sb.run();
    expect((await live(b)).single.name, 'offline');
    expect(await b.thumbOf(id), isNotNull);
  });

  test('cambiar la foto en un dispositivo la actualiza en el otro', () async {
    final id = await a.saveItem(ItemDraft(type: 'camisa'), photo: fakePhoto(4));
    await sa.run();
    await sb.run();
    await tick();
    await b.saveItem(ItemDraft(type: 'camisa'), id: id, photo: fakePhoto(5));
    await sb.run();
    await sa.run();
    expect((await a.fullOf(id))!.first, 5);
  });

  test('conjuntos e historial de uso se sincronizan', () async {
    final i1 = await a.saveItem(ItemDraft(type: 'camisa'));
    final i2 = await a.saveItem(ItemDraft(type: 'pantalon'));
    final o = await a.saveOutfit(name: 'Lunes', notes: '', itemIds: [i1, i2]);
    await a.markWorn([i1, i2], outfitId: o);
    await a.markWorn([i1]); // no duplica
    await sa.run();
    await sb.run();
    expect((await b.watchOutfits().first).single.itemIds, [i1, i2]);
    expect(await b.watchWearLogs().first, hasLength(2));
    // Borrar una prenda la quita del conjunto.
    await tick();
    await b.deleteItem(i1);
    await sb.run();
    await sa.run();
    expect((await a.watchOutfits().first).single.itemIds, [i2]);
    expect(await a.watchWearLogs().first, hasLength(1));
  });

  test('muchas filas: paginación sin perder ninguna', () async {
    await a.batch((batch) {
      for (var i = 0; i < 1203; i++) {
        batch.insert(
            a.items,
            ItemsCompanion.insert(
                id: 'id-${i.toString().padLeft(5, '0')}',
                type: 'camisa',
                colors: [],
                seasons: [],
                occasions: [],
                createdAt: i,
                updatedAt: i));
      }
    });
    await sa.run();
    await sb.run();
    expect(await live(b), hasLength(1203));
    // Segunda pasada: nada nuevo que aplicar.
    final stats = await sb.run();
    expect(stats.pulled, 0);
    expect(stats.pushed, 0);
  });

  test('resetSyncState vuelve a subir todo a un servidor vacío', () async {
    final id = await a.saveItem(ItemDraft(type: 'camisa'), photo: fakePhoto(6));
    await sa.run();
    final nuevo = FakeRemote();
    await a.resetSyncState();
    await SyncEngine(a, nuevo).run();
    expect(nuevo.tables['items']!.keys, [id]);
    expect(nuevo.photos.keys, [id]);
  });

  test('copia de seguridad: exportar e importar en una base vacía', () async {
    final id = await a.saveItem(
        ItemDraft(name: 'Abrigo', type: 'abrigo', seasons: ['invierno']),
        photo: fakePhoto(7));
    final o = await a.saveOutfit(name: 'Frío', notes: 'n', itemIds: [id]);
    await a.markWorn([id], outfitId: o);
    final zip = await BackupService(a).export();
    final r = await BackupService(b).import(zip);
    expect([r.items, r.outfits, r.wearLogs], [1, 1, 1]);
    final item = (await live(b)).single;
    expect(item.name, 'Abrigo');
    expect(item.seasons, ['invierno']);
    expect(item.dirty && item.photoDirty, true);
    expect((await b.fullOf(id))!.first, 7);
    // Importar dos veces no duplica.
    final again = await BackupService(b).import(zip);
    expect([again.items, again.outfits, again.wearLogs], [0, 0, 0]);
    expect(() => BackupService(b).import(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });

  test('las fotos se comprimen por debajo del objetivo', () async {
    // Imagen 3000x2000 con ruido (lo más difícil de comprimir).
    final image = img.Image(width: 3000, height: 2000);
    var s = 1;
    for (final p in image) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      p
        ..r = (p.x ~/ 12) + (s % 40)
        ..g = (p.y ~/ 8) + (s % 40)
        ..b = 120 + (s % 40);
    }
    final original = img.encodeJpg(image, quality: 95);
    final out = await processPhoto(original);
    final full = img.decodeJpg(out!.full)!;
    expect(full.width, 1280);
    expect(out.full.length, lessThanOrEqualTo(targetBytes));
    expect(out.thumb.length, lessThan(60 * 1024));
    expect(img.decodeJpg(out.thumb)!.width, thumbSide);
  });
}
