import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'database.dart';

/// Reduce y comprime una foto antes de guardarla / subirla.
///
/// Objetivo: lado mayor 1280 px y ~150-250 KB en JPEG, más una miniatura de
/// 400 px para la galería. Usa `package:image` (Dart puro), así funciona
/// igual en Android, Windows, iOS y web. Se ejecuta fuera del hilo de la
/// interfaz donde la plataforma lo permite.
Future<ProcessedPhoto?> processPhoto(Uint8List original) async {
  final out = await compute(_process, original);
  if (out == null) return null;
  return ProcessedPhoto(out[0], out[1]);
}

const maxSide = 1280;
const thumbSide = 400;
const targetBytes = 250 * 1024;

List<Uint8List>? _process(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // Aplica la rotación EXIF (las fotos del móvil suelen venir "tumbadas").
  var image = img.bakeOrientation(decoded);
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image,
            height: maxSide, interpolation: img.Interpolation.average);
  }
  // Baja la calidad poco a poco hasta entrar en el objetivo de tamaño.
  Uint8List full = img.encodeJpg(image, quality: 82);
  for (final q in [74, 66, 58, 50]) {
    if (full.length <= targetBytes) break;
    full = img.encodeJpg(image, quality: q);
  }
  final small = image.width >= image.height
      ? img.copyResize(image,
          width: thumbSide, interpolation: img.Interpolation.average)
      : img.copyResize(image,
          height: thumbSide, interpolation: img.Interpolation.average);
  final thumb = img.encodeJpg(small, quality: 72);
  return [full, thumb];
}
