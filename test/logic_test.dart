import 'package:armario/core/suggest.dart';
import 'package:armario/data/database.dart';
import 'package:armario/providers.dart';
import 'package:flutter_test/flutter_test.dart';

Item item(String id, String type,
        {String name = '',
        List<String> colors = const [],
        List<String> seasons = const [],
        List<String> occasions = const [],
        String status = 'disponible',
        String brand = ''}) =>
    Item(
        id: id,
        name: name,
        type: type,
        colors: colors,
        seasons: seasons,
        occasions: occasions,
        brand: brand,
        notes: '',
        status: status,
        photoVersion: null,
        photoDirty: false,
        createdAt: 0,
        updatedAt: 0,
        deleted: false,
        dirty: false);

void main() {
  final items = [
    item('1', 'camiseta', colors: ['azul'], seasons: ['verano'], occasions: ['casual']),
    item('2', 'pantalon', name: 'Vaqueros', colors: ['vaquero'], brand: "Levi's"),
    item('3', 'abrigo', colors: ['negro'], seasons: ['invierno'], status: 'sucia'),
    item('4', 'zapatos', colors: ['blanco', 'azul'], occasions: ['deporte']),
    item('5', 'abrigo', colors: ['gris'], seasons: ['invierno']),
    item('6', 'jersey', seasons: ['invierno', 'otono']),
    item('7', 'pantalon_corto', seasons: ['verano']),
  ];
  List<String> ids(ItemFilter f) =>
      items.where(f.matches).map((i) => i.id).toList();

  test('filtros combinables', () {
    expect(ids(const ItemFilter(colors: {'azul'})), ['1', '4']);
    expect(ids(const ItemFilter(colors: {'azul'}, types: {'zapatos'})), ['4']);
    expect(ids(const ItemFilter(statuses: {'sucia'})), ['3']);
    expect(ids(const ItemFilter(types: {'abrigo'}, statuses: {'disponible'})),
        ['5']);
    expect(const ItemFilter(colors: {'azul'}, types: {'a', 'b'}).activeCount, 3);
  });

  test('búsqueda sin tildes ni mayúsculas', () {
    expect(ids(const ItemFilter(query: 'PANTALON')), ['2', '7']);
    expect(ids(const ItemFilter(query: 'levi')), ['2']);
    expect(ids(const ItemFilter(query: 'abrigo gris')), ['5']);
    expect(ids(const ItemFilter(query: 'otoño')), ['6']);
  });

  test('sugerencia: solo disponibles y acorde a la temperatura', () {
    for (var seed = 0; seed < 20; seed++) {
      final cold = suggestOutfit(items, {}, tMax: 5, seed: seed);
      expect(cold.map((i) => i.id), containsAll(['6', '2', '5', '4']));
      expect(cold.any((i) => i.status != 'disponible'), false);
      final hot = suggestOutfit(items, {}, tMax: 30, seed: seed);
      expect(hot.map((i) => i.id), contains('1'));
      expect(hot.any((i) => i.type == 'abrigo'), false);
    }
    expect(suggestOutfit(const [], {}, tMax: 20), isEmpty);
  });
}
