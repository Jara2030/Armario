import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/catalog.dart';
import 'data/database.dart';
import 'data/sync/remote_store.dart';
import 'data/sync/sync_engine.dart';

// Valores por defecto al compilar (opcionales):
//   flutter build ... --dart-define-from-file=config.json
// Si no se dan, se pueden escribir en Ajustes dentro de la app.
const _envUrl = String.fromEnvironment('SUPABASE_URL');
const _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

final dbProvider =
    Provider<AppDatabase>((_) => throw UnimplementedError('db'));
final prefsProvider =
    Provider<SharedPreferences>((_) => throw UnimplementedError('prefs'));

// ------------------------------------------------------------------- datos

final itemsProvider =
    StreamProvider<List<Item>>((ref) => ref.watch(dbProvider).watchItems());
final outfitsProvider =
    StreamProvider<List<Outfit>>((ref) => ref.watch(dbProvider).watchOutfits());
final wearLogsProvider = StreamProvider<List<WearLog>>(
    (ref) => ref.watch(dbProvider).watchWearLogs());
final pendingCountProvider =
    StreamProvider<int>((ref) => ref.watch(dbProvider).watchPendingCount());

/// id de prenda -> último día que se usó (AAAA-MM-DD).
final lastWornProvider = Provider<Map<String, String>>((ref) {
  final logs = ref.watch(wearLogsProvider).value ?? const [];
  final map = <String, String>{};
  for (final l in logs) {
    final prev = map[l.itemId];
    if (prev == null || l.wornOn.compareTo(prev) > 0) map[l.itemId] = l.wornOn;
  }
  return map;
});

/// id de prenda -> número de usos.
final wearCountProvider = Provider<Map<String, int>>((ref) {
  final logs = ref.watch(wearLogsProvider).value ?? const [];
  final map = <String, int>{};
  for (final l in logs) {
    map[l.itemId] = (map[l.itemId] ?? 0) + 1;
  }
  return map;
});

final photoVersionsProvider = StreamProvider<Map<String, int>>(
    (ref) => ref.watch(dbProvider).watchPhotoVersions());

/// Miniatura por (id, versión local): al cambiar la foto cambia la clave.
final thumbProvider = FutureProvider.family<Uint8List?, (String, int)>(
    (ref, key) => ref.watch(dbProvider).thumbOf(key.$1));

final fullPhotoProvider =
    FutureProvider.autoDispose.family<Uint8List?, (String, int)>(
        (ref, key) => ref.watch(dbProvider).fullOf(key.$1));

// ------------------------------------------------------------------ filtros

enum ItemSort { recent, forgotten, mostWorn }

class ItemFilter {
  final String query;
  final Set<String> types, colors, seasons, occasions, statuses;
  final ItemSort sort;
  const ItemFilter({
    this.query = '',
    this.types = const {},
    this.colors = const {},
    this.seasons = const {},
    this.occasions = const {},
    this.statuses = const {},
    this.sort = ItemSort.recent,
  });

  int get activeCount =>
      types.length +
      colors.length +
      seasons.length +
      occasions.length +
      statuses.length;

  ItemFilter copyWith({
    String? query,
    Set<String>? types,
    Set<String>? colors,
    Set<String>? seasons,
    Set<String>? occasions,
    Set<String>? statuses,
    ItemSort? sort,
  }) =>
      ItemFilter(
        query: query ?? this.query,
        types: types ?? this.types,
        colors: colors ?? this.colors,
        seasons: seasons ?? this.seasons,
        occasions: occasions ?? this.occasions,
        statuses: statuses ?? this.statuses,
        sort: sort ?? this.sort,
      );

  /// Dentro de un mismo grupo basta con coincidir en una opción (O);
  /// entre grupos distintos tienen que cumplirse todos (Y).
  bool matches(Item i) {
    if (types.isNotEmpty && !types.contains(i.type)) return false;
    if (statuses.isNotEmpty && !statuses.contains(i.status)) return false;
    if (colors.isNotEmpty && !i.colors.any(colors.contains)) return false;
    if (seasons.isNotEmpty && !i.seasons.any(seasons.contains)) return false;
    if (occasions.isNotEmpty && !i.occasions.any(occasions.contains)) {
      return false;
    }
    final q = _norm(query);
    if (q.isNotEmpty) {
      final text = _norm([
        i.name,
        i.brand,
        i.notes,
        typeOf(i.type).label,
        ...i.colors.map((c) => colorOf(c)?.label ?? c),
        ...i.seasons.map((s) => _seasonLabels[s] ?? s),
        ...i.occasions.map((o) => _occasionLabels[o] ?? o),
        statusOf(i.status).label,
      ].join(' '));
      for (final word in q.split(' ')) {
        if (!text.contains(word)) return false;
      }
    }
    return true;
  }
}

const _seasonLabels = seasons;
const _occasionLabels = occasions;

/// Minúsculas y sin tildes, para que "pantalon" encuentre "Pantalón".
String _norm(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

class FilterNotifier extends Notifier<ItemFilter> {
  @override
  ItemFilter build() => const ItemFilter();
  void set(ItemFilter f) => state = f;
  void clear() => state = ItemFilter(query: state.query, sort: state.sort);
}

final filterProvider =
    NotifierProvider<FilterNotifier, ItemFilter>(FilterNotifier.new);

final filteredItemsProvider = Provider<List<Item>>((ref) {
  final items = ref.watch(itemsProvider).value ?? const <Item>[];
  final f = ref.watch(filterProvider);
  final out = items.where(f.matches).toList();
  switch (f.sort) {
    case ItemSort.recent:
      break;
    case ItemSort.forgotten:
      final last = ref.watch(lastWornProvider);
      out.sort((a, b) => (last[a.id] ?? '').compareTo(last[b.id] ?? ''));
    case ItemSort.mostWorn:
      final count = ref.watch(wearCountProvider);
      out.sort((a, b) => (count[b.id] ?? 0).compareTo(count[a.id] ?? 0));
  }
  return out;
});

// ------------------------------------------------------------------ ajustes

class AppSettings {
  final ThemeMode themeMode;
  final String city;
  final double? lat, lon;
  final String supabaseUrl, supabaseKey;
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.city = '',
    this.lat,
    this.lon,
    this.supabaseUrl = '',
    this.supabaseKey = '',
  });
  bool get hasServer => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  bool get hasCity => lat != null && lon != null;
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final p = ref.watch(prefsProvider);
    final url = p.getString('supabase_url') ?? '';
    final key = p.getString('supabase_key') ?? '';
    return AppSettings(
      themeMode: ThemeMode.values[p.getInt('theme') ?? 0],
      city: p.getString('city') ?? '',
      lat: p.getDouble('lat'),
      lon: p.getDouble('lon'),
      supabaseUrl: url.isNotEmpty ? url : _envUrl,
      supabaseKey: key.isNotEmpty ? key : _envKey,
    );
  }

  Future<void> setTheme(ThemeMode m) async {
    await _p.setInt('theme', m.index);
    ref.invalidateSelf();
  }

  Future<void> setCity(String name, double lat, double lon) async {
    await _p.setString('city', name);
    await _p.setDouble('lat', lat);
    await _p.setDouble('lon', lon);
    await _p.remove('weather_cache');
    ref.invalidateSelf();
  }

  Future<void> setServer(String url, String key) async {
    await _p.setString('supabase_url', url.trim());
    await _p.setString('supabase_key', key.trim());
    ref.invalidateSelf();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ------------------------------------------------------------ sincronización

enum SyncPhase {
  /// Sin servidor configurado: la app funciona solo en local.
  off,

  /// Servidor configurado pero sin iniciar sesión.
  signedOut,
  idle,
  syncing,

  /// El último intento falló (sin red, proyecto pausado…). Se reintentará.
  error,
}

class SyncState {
  final SyncPhase phase;
  final String? email;
  final String? message;
  final DateTime? lastOk;
  const SyncState(this.phase, {this.email, this.message, this.lastOk});
}

class SyncController extends Notifier<SyncState> {
  SupabaseClient? _client;
  Timer? _periodic, _debounce;
  bool _running = false, _again = false;

  SharedPreferences get _p => ref.read(prefsProvider);
  AppDatabase get _db => ref.read(dbProvider);

  DateTime? get _lastOk {
    final ms = _p.getInt('last_sync_ok');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  SyncState build() {
    ref.onDispose(() {
      _periodic?.cancel();
      _debounce?.cancel();
    });
    // Cada cambio local programa una sincronización unos segundos después.
    ref.listen(pendingCountProvider, (_, next) {
      if ((next.value ?? 0) > 0) _schedule();
    });
    return const SyncState(SyncPhase.off);
  }

  /// Conecta con Supabase con la configuración actual. Nunca lanza: si
  /// algo falla la app sigue funcionando en local.
  Future<void> init() async {
    final s = ref.read(settingsProvider);
    _periodic?.cancel();
    try {
      if (Supabase.instance.isInitialized) {
        await Supabase.instance.dispose();
      }
    } catch (_) {}
    _client = null;
    if (!s.hasServer) {
      state = const SyncState(SyncPhase.off);
      return;
    }
    try {
      await Supabase.initialize(
          url: s.supabaseUrl, publishableKey: s.supabaseKey, debug: false);
      _client = Supabase.instance.client;
    } catch (e) {
      state = SyncState(SyncPhase.error,
          message: 'Configuración del servidor no válida: $e');
      return;
    }
    _periodic =
        Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    _refreshIdle();
    unawaited(syncNow());
  }

  void _refreshIdle({String? message}) {
    final user = _client?.auth.currentUser;
    if (_client == null) {
      state = const SyncState(SyncPhase.off);
    } else if (user == null) {
      state = SyncState(SyncPhase.signedOut, message: message);
    } else {
      state = SyncState(SyncPhase.idle,
          email: user.email, lastOk: _lastOk, message: message);
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), syncNow);
  }

  /// Devuelve null si va bien, o un mensaje de error para mostrar.
  Future<String?> signIn(String email, String password,
      {bool create = false}) async {
    final c = _client;
    if (c == null) return 'Primero configura el servidor.';
    try {
      if (create) {
        final r = await c.auth.signUp(email: email.trim(), password: password);
        if (r.session == null) {
          return 'Cuenta creada. Supabase te ha enviado un correo: confírmalo '
              'y luego inicia sesión.';
        }
      } else {
        await c.auth.signInWithPassword(
            email: email.trim(), password: password);
      }
      // Si es otra cuenta (o la primera vez), se vuelve a subir/bajar todo.
      final uid = c.auth.currentUser?.id;
      if (uid != null && await _db.getMeta('sync_user') != uid) {
        await _db.resetSyncState();
        await _db.setMeta('sync_user', uid);
      }
      _refreshIdle();
      unawaited(syncNow());
      return null;
    } catch (e) {
      return describeError(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _client?.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    _refreshIdle();
  }

  /// Vuelve a subir y bajar absolutamente todo.
  Future<void> fullResync() async {
    final uid = _client?.auth.currentUser?.id;
    await _db.resetSyncState();
    if (uid != null) await _db.setMeta('sync_user', uid);
    await syncNow();
  }

  Future<void> syncNow() async {
    final c = _client;
    if (c == null || c.auth.currentUser == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final email = c.auth.currentUser?.email;
    state = SyncState(SyncPhase.syncing, email: email, lastOk: _lastOk);
    try {
      await SyncEngine(_db, SupabaseRemoteStore(c)).run();
      await _p.setInt('last_sync_ok', nowMs());
      _refreshIdle();
    } catch (e) {
      // Sin red, proyecto pausado, tablas sin crear… Nada se pierde: los
      // cambios siguen marcados como pendientes y se reintenta más tarde.
      if (c.auth.currentUser == null) {
        _refreshIdle(message: 'La sesión ha caducado. Vuelve a iniciar sesión.');
      } else {
        state = SyncState(SyncPhase.error,
            email: email, lastOk: _lastOk, message: describeError(e));
      }
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }
}

final syncProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

String describeError(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Email o contraseña incorrectos.';
    if (m.contains('not confirmed')) {
      return 'Falta confirmar el email (mira tu correo).';
    }
    if (e.statusCode == null) {
      return 'No se pudo contactar con el servidor. ¿Hay internet? ¿Está el '
          'proyecto de Supabase pausado?';
    }
    return e.message;
  }
  if (e is PostgrestException) {
    if (e.code == '42P01' || e.code == 'PGRST205') {
      return 'Faltan las tablas en Supabase: ejecuta supabase/schema.sql '
          '(ver README).';
    }
    return 'Error del servidor: ${e.message}';
  }
  if (e is StorageException) {
    return 'Error al guardar fotos en el servidor: ${e.message}';
  }
  return 'Sin conexión con el servidor (sin internet o proyecto de Supabase '
      'pausado). Tus datos están guardados en este dispositivo y se '
      'sincronizarán cuando vuelva.';
}

// ------------------------------------------------------------------- tiempo

class Weather {
  final double tMax, tMin;
  final double? tNow;
  final int rainProb;
  final int code;
  final DateTime fetchedAt;
  const Weather({
    required this.tMax,
    required this.tMin,
    required this.tNow,
    required this.rainProb,
    required this.code,
    required this.fetchedAt,
  });

  bool get rainy => rainProb >= 50;

  String get description {
    if (code == 0) return 'Despejado';
    if (code <= 2) return 'Poco nuboso';
    if (code == 3) return 'Nublado';
    if (code <= 48) return 'Niebla';
    if (code <= 57) return 'Llovizna';
    if (code <= 67) return 'Lluvia';
    if (code <= 77) return 'Nieve';
    if (code <= 82) return 'Chubascos';
    if (code <= 86) return 'Nieve';
    return 'Tormenta';
  }

  IconData get icon {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 2) return Icons.wb_cloudy;
    if (code <= 48) return Icons.cloud;
    if (code <= 67) return Icons.umbrella;
    if (code <= 77) return Icons.ac_unit;
    if (code <= 82) return Icons.umbrella;
    if (code <= 86) return Icons.ac_unit;
    return Icons.thunderstorm;
  }

  Map<String, dynamic> toJson() => {
        'tMax': tMax,
        'tMin': tMin,
        'tNow': tNow,
        'rain': rainProb,
        'code': code,
        'at': fetchedAt.millisecondsSinceEpoch,
      };

  factory Weather.fromJson(Map<String, dynamic> j) => Weather(
        tMax: (j['tMax'] as num).toDouble(),
        tMin: (j['tMin'] as num).toDouble(),
        tNow: (j['tNow'] as num?)?.toDouble(),
        rainProb: (j['rain'] as num).toInt(),
        code: (j['code'] as num).toInt(),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

/// Tiempo de hoy con Open-Meteo (gratis, sin clave). Guarda el último
/// resultado para no depender de internet; devuelve null si no hay ciudad o
/// no se puede obtener y no hay nada guardado de hoy.
final weatherProvider = FutureProvider<Weather?>((ref) async {
  final s = ref.watch(settingsProvider);
  if (!s.hasCity) return null;
  final p = ref.watch(prefsProvider);
  Weather? cached;
  final raw = p.getString('weather_cache');
  if (raw != null) {
    try {
      cached = Weather.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }
  final now = DateTime.now();
  final sameDay =
      cached != null && dayKey(cached.fetchedAt) == dayKey(now);
  if (sameDay && now.difference(cached.fetchedAt).inMinutes < 60) {
    return cached;
  }
  try {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${s.lat}',
      'longitude': '${s.lon}',
      'current': 'temperature_2m,weather_code',
      'daily':
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;
    final c = j['current'] as Map<String, dynamic>?;
    final w = Weather(
      tMax: ((d['temperature_2m_max'] as List).first as num).toDouble(),
      tMin: ((d['temperature_2m_min'] as List).first as num).toDouble(),
      tNow: (c?['temperature_2m'] as num?)?.toDouble(),
      rainProb:
          ((d['precipitation_probability_max'] as List).first as num?)
                  ?.toInt() ??
              0,
      code: ((c?['weather_code'] ?? (d['weather_code'] as List).first) as num)
          .toInt(),
      fetchedAt: now,
    );
    await p.setString('weather_cache', jsonEncode(w.toJson()));
    return w;
  } catch (_) {
    return sameDay ? cached : null;
  }
});

class CityResult {
  final String label;
  final double lat, lon;
  const CityResult(this.label, this.lat, this.lon);
}

Future<List<CityResult>> searchCity(String name) async {
  final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
      {'name': name.trim(), 'count': '6', 'language': 'es'});
  final res = await http.get(uri).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final results = (jsonDecode(res.body) as Map)['results'] as List? ?? [];
  return [
    for (final r in results)
      CityResult(
        [r['name'], r['admin1'], r['country']]
            .where((e) => e != null && '$e'.isNotEmpty)
            .join(', '),
        (r['latitude'] as num).toDouble(),
        (r['longitude'] as num).toDouble(),
      )
  ];
}
