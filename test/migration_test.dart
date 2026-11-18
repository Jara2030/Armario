import 'package:armario/data/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Quien ya tenía la app instalada tiene la base de datos de la versión 1
/// (sin la columna "location"). Al actualizar no debe perder nada.
void main() {
  test('migración v1 -> v2 conserva las prendas y añade la casa', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE items (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL, colors TEXT NOT NULL, seasons TEXT NOT NULL,
        occasions TEXT NOT NULL, brand TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'disponible', photo_version INTEGER NULL,
        photo_dirty INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1);
      CREATE TABLE photos (id TEXT NOT NULL PRIMARY KEY, version INTEGER NOT NULL,
        full BLOB NOT NULL, thumb BLOB NOT NULL);
      CREATE TABLE outfits (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '', item_ids TEXT NOT NULL, created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1);
      CREATE TABLE wear_logs (id TEXT NOT NULL PRIMARY KEY, item_id TEXT NOT NULL,
        outfit_id TEXT NULL, worn_on TEXT NOT NULL, created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1);
      CREATE TABLE meta ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO items (id, name, type, colors, seasons, occasions, created_at, updated_at)
        VALUES ('x', 'Camisa vieja', 'camisa', '["azul"]', '[]', '[]', 1, 1);
      PRAGMA user_version = 1;
    ''');
    final db = AppDatabase(NativeDatabase.opened(raw));
    final item = (await db.watchItems().first).single;
    expect(item.name, 'Camisa vieja');
    expect(item.location, '');
    await db.setLocation(['x'], 'mama');
    expect((await db.getItem('x'))!.location, 'mama');
    await db.close();
  });
}
