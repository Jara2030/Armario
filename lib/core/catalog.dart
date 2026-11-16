import 'package:material_ui/material_ui.dart';

/// Catálogos fijos de la app. Las claves (String) son las que se guardan en la
/// base de datos y se sincronizan; las etiquetas son solo para mostrar.

enum Category { top, bottom, full, outer, shoes, accessory, other }

class GarmentType {
  final String key;
  final String label;
  final IconData icon;
  final Category category;
  const GarmentType(this.key, this.label, this.icon, this.category);
}

const garmentTypes = <GarmentType>[
  GarmentType('camiseta', 'Camiseta', Icons.checkroom, Category.top),
  GarmentType('camisa', 'Camisa', Icons.checkroom, Category.top),
  GarmentType('jersey', 'Jersey', Icons.checkroom, Category.top),
  GarmentType('sudadera', 'Sudadera', Icons.checkroom, Category.top),
  GarmentType('pantalon', 'Pantalón', Icons.straighten, Category.bottom),
  GarmentType('pantalon_corto', 'Pantalón corto', Icons.straighten,
      Category.bottom),
  GarmentType('falda', 'Falda', Icons.straighten, Category.bottom),
  GarmentType('vestido', 'Vestido', Icons.checkroom, Category.full),
  GarmentType('chaqueta', 'Chaqueta', Icons.layers, Category.outer),
  GarmentType('abrigo', 'Abrigo', Icons.layers, Category.outer),
  GarmentType('zapatos', 'Zapatos', Icons.hiking, Category.shoes),
  GarmentType('accesorio', 'Accesorio', Icons.watch, Category.accessory),
  GarmentType('otro', 'Otro', Icons.category, Category.other),
];

GarmentType typeOf(String key) => garmentTypes.firstWhere(
      (t) => t.key == key,
      orElse: () => garmentTypes.last,
    );

class ColorOption {
  final String key;
  final String label;
  final Color color;
  const ColorOption(this.key, this.label, this.color);
}

const colorOptions = <ColorOption>[
  ColorOption('negro', 'Negro', Color(0xFF1B1B1B)),
  ColorOption('blanco', 'Blanco', Color(0xFFFFFFFF)),
  ColorOption('gris', 'Gris', Color(0xFF9E9E9E)),
  ColorOption('azul', 'Azul', Color(0xFF2979FF)),
  ColorOption('marino', 'Azul marino', Color(0xFF1A237E)),
  ColorOption('vaquero', 'Vaquero', Color(0xFF5C7FA8)),
  ColorOption('rojo', 'Rojo', Color(0xFFD32F2F)),
  ColorOption('verde', 'Verde', Color(0xFF388E3C)),
  ColorOption('amarillo', 'Amarillo', Color(0xFFFDD835)),
  ColorOption('naranja', 'Naranja', Color(0xFFF57C00)),
  ColorOption('rosa', 'Rosa', Color(0xFFF48FB1)),
  ColorOption('morado', 'Morado', Color(0xFF7B1FA2)),
  ColorOption('marron', 'Marrón', Color(0xFF6D4C41)),
  ColorOption('beige', 'Beige', Color(0xFFD7C4A3)),
];

ColorOption? colorOf(String key) {
  for (final c in colorOptions) {
    if (c.key == key) return c;
  }
  return null;
}

const seasons = <String, String>{
  'primavera': 'Primavera',
  'verano': 'Verano',
  'otono': 'Otoño',
  'invierno': 'Invierno',
};

const occasions = <String, String>{
  'casual': 'Casual',
  'trabajo': 'Trabajo',
  'deporte': 'Deporte',
  'formal': 'Formal',
};

class StatusOption {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const StatusOption(this.key, this.label, this.icon, this.color);
}

const statusAvailable = 'disponible';

const statusOptions = <StatusOption>[
  StatusOption(
      'disponible', 'Disponible', Icons.check_circle, Color(0xFF2E7D32)),
  StatusOption(
      'sucia', 'Sucia', Icons.local_laundry_service, Color(0xFF8D6E63)),
  StatusOption('prestada', 'Prestada', Icons.swap_horiz, Color(0xFF1565C0)),
  StatusOption('reparacion', 'En reparación', Icons.build, Color(0xFFEF6C00)),
];

StatusOption statusOf(String key) => statusOptions.firstWhere(
      (s) => s.key == key,
      orElse: () => statusOptions.first,
    );

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Fecha local en formato AAAA-MM-DD.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "hoy", "ayer", "hace 12 días"… a partir de una fecha AAAA-MM-DD.
String agoLabel(String? day) {
  if (day == null) return 'nunca';
  final d = DateTime.tryParse(day);
  if (d == null) return day;
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day).difference(d).inDays;
  if (diff <= 0) return 'hoy';
  if (diff == 1) return 'ayer';
  if (diff < 60) return 'hace $diff días';
  final months = (diff / 30).round();
  if (months < 24) return 'hace $months meses';
  return 'hace ${(diff / 365).round()} años';
}
