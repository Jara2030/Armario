import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Lo mínimo que el motor de sincronización necesita del servidor. Es una
/// interfaz para poder probar el motor con un servidor falso en los tests.
abstract class RemoteStore {
  /// Filas de [table] con server_updated_at > [since] (o todas si es null),
  /// ordenadas por (server_updated_at, id), paginadas.
  Future<List<Map<String, dynamic>>> pull(
      String table, String? since, int offset, int limit);

  /// Inserta o actualiza filas (por id).
  Future<void> push(String table, List<Map<String, dynamic>> rows);

  Future<void> uploadPhoto(String itemId, Uint8List full, Uint8List thumb);

  /// null si la foto no existe (todavía) en el servidor.
  Future<({Uint8List full, Uint8List thumb})?> downloadPhoto(String itemId);

  Future<void> deletePhoto(String itemId);
}

class SupabaseRemoteStore implements RemoteStore {
  final SupabaseClient client;
  SupabaseRemoteStore(this.client);

  static const bucket = 'photos';
  static const _timeout = Duration(seconds: 40);

  String get _uid {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sesión no iniciada');
    return user.id;
  }

  String _full(String id) => '$_uid/$id.jpg';
  String _thumb(String id) => '$_uid/${id}_t.jpg';

  @override
  Future<List<Map<String, dynamic>>> pull(
      String table, String? since, int offset, int limit) async {
    var q = client.from(table).select();
    if (since != null) q = q.gt('server_updated_at', since);
    final rows = await q
        .order('server_updated_at', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + limit - 1)
        .timeout(_timeout);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> push(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await client.from(table).upsert(rows, onConflict: 'id').timeout(_timeout);
  }

  @override
  Future<void> uploadPhoto(
      String itemId, Uint8List full, Uint8List thumb) async {
    const opts = FileOptions(upsert: true, contentType: 'image/jpeg');
    final storage = client.storage.from(bucket);
    await storage
        .uploadBinary(_full(itemId), full, fileOptions: opts)
        .timeout(_timeout);
    await storage
        .uploadBinary(_thumb(itemId), thumb, fileOptions: opts)
        .timeout(_timeout);
  }

  @override
  Future<({Uint8List full, Uint8List thumb})?> downloadPhoto(
      String itemId) async {
    final storage = client.storage.from(bucket);
    try {
      final full = await storage.download(_full(itemId)).timeout(_timeout);
      final thumb = await storage.download(_thumb(itemId)).timeout(_timeout);
      return (full: full, thumb: thumb);
    } on StorageException catch (e) {
      // Supabase responde 400/404 cuando el objeto no existe.
      final code = e.statusCode;
      if (code == '404' || code == '400') return null;
      rethrow;
    }
  }

  @override
  Future<void> deletePhoto(String itemId) async {
    await client.storage
        .from(bucket)
        .remove([_full(itemId), _thumb(itemId)]).timeout(_timeout);
  }
}
