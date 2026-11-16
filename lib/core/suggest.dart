import 'dart:math';

import '../data/database.dart';
import 'catalog.dart';

/// Temporada que corresponde a la temperatura máxima del día.
String seasonForTemp(double tMax) {
  if (tMax >= 24) return 'verano';
  if (tMax >= 15) {
    final m = DateTime.now().month;
    return (m >= 2 && m <= 7) ? 'primavera' : 'otono';
  }
  return 'invierno';
}

bool _fitsSeason(Item i, double tMax) {
  if (i.seasons.isEmpty) return true;
  if (tMax >= 24) return i.seasons.contains('verano');
  if (tMax >= 15) {
    return i.seasons.contains('primavera') || i.seasons.contains('otono');
  }
  return i.seasons.contains('invierno');
}

/// Propone un conjunto con las prendas disponibles: parte de arriba + parte
/// de abajo (o un vestido), zapatos y, si hace fresco o llueve, algo de
/// abrigo. Prefiere lo que lleva más tiempo sin usarse. [seed] permite pedir
/// "otra" sugerencia distinta.
List<Item> suggestOutfit(
  List<Item> items,
  Map<String, String> lastWorn, {
  required double tMax,
  bool rainy = false,
  String? occasion,
  int seed = 0,
}) {
  final rnd = Random(seed);
  final pool = items.where((i) {
    if (i.status != statusAvailable) return false;
    if (occasion != null &&
        i.occasions.isNotEmpty &&
        !i.occasions.contains(occasion)) {
      return false;
    }
    return true;
  }).toList();

  Item? pick(Category cat, {bool Function(Item)? extra}) {
    var c = pool
        .where((i) => typeOf(i.type).category == cat)
        .where((i) => extra == null || extra(i))
        .toList();
    if (c.isEmpty) return null;
    // Primero las de temporada; si no hay ninguna, cualquiera.
    final seasonal = c.where((i) => _fitsSeason(i, tMax)).toList();
    if (seasonal.isNotEmpty) c = seasonal;
    // Las menos usadas recientemente primero ('' = nunca usada).
    c.sort((a, b) => (lastWorn[a.id] ?? '').compareTo(lastWorn[b.id] ?? ''));
    return c[rnd.nextInt(min(3, c.length))];
  }

  final result = <Item>[];
  final dress = pick(Category.full);
  final top = pick(Category.top);
  final bottom = pick(Category.bottom,
      extra: tMax < 15 ? (i) => i.type != 'pantalon_corto' : null);
  final useDress =
      dress != null && (top == null || bottom == null || rnd.nextInt(4) == 0);
  if (useDress) {
    result.add(dress);
  } else {
    if (top != null) result.add(top);
    if (bottom != null) result.add(bottom);
  }
  if (tMax < 20 || rainy) {
    final outer = pick(Category.outer,
        extra: tMax >= 12 ? (i) => i.type != 'abrigo' : null);
    if (outer != null) result.add(outer);
  }
  final shoes = pick(Category.shoes);
  if (shoes != null) result.add(shoes);
  return result;
}
