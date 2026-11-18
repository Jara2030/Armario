import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../data/database.dart';
import '../data/photo_processor.dart';
import '../providers.dart';
import 'widgets.dart';

/// Alta y edición de una prenda.
class ItemFormPage extends ConsumerStatefulWidget {
  final Item? existing;
  const ItemFormPage({super.key, this.existing});
  @override
  ConsumerState<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends ConsumerState<ItemFormPage> {
  // Una prenda nueva se crea en la casa en la que estás ahora.
  late final ItemDraft _d = widget.existing == null
      ? ItemDraft(location: ref.read(settingsProvider).house)
      : ItemDraft.from(widget.existing!);
  late final _name = TextEditingController(text: _d.name);
  late final _brand = TextEditingController(text: _d.brand);
  late final _notes = TextEditingController(text: _d.notes);
  ProcessedPhoto? _photo;
  bool _busy = false;
  bool _saving = false;

  bool get _hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      // En el móvil el propio sistema ya reduce la foto, lo que acelera
      // mucho el procesado posterior.
      final file = await ImagePicker().pickImage(
          source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
      if (file == null) return;
      setState(() => _busy = true);
      final processed = await processPhoto(await file.readAsBytes());
      if (!mounted) return;
      if (processed == null) {
        toast(context, 'No se pudo leer esa imagen.');
      } else {
        setState(() => _photo = processed);
      }
    } catch (e) {
      if (mounted) toast(context, 'No se pudo obtener la foto: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePhoto() async {
    if (!_hasCamera) return _pick(ImageSource.gallery);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Hacer foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  Future<void> _save() async {
    if (_saving || _busy) return;
    setState(() => _saving = true);
    _d
      ..name = _name.text.trim()
      ..brand = _brand.text.trim()
      ..notes = _notes.text.trim();
    try {
      await ref
          .read(dbProvider)
          .saveItem(_d, id: widget.existing?.id, photo: _photo);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, 'No se pudo guardar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar prenda' : 'Nueva prenda'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving || _busy ? null : _save,
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Material(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _busy ? null : _choosePhoto,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_photo != null)
                          Image.memory(_photo!.full, fit: BoxFit.cover)
                        else if (editing &&
                            widget.existing!.photoVersion != null)
                          ItemThumb(widget.existing!)
                        else
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  size: 44, color: scheme.primary),
                              const SizedBox(height: 8),
                              Text(_hasCamera
                                  ? 'Añadir foto'
                                  : 'Elegir una foto'),
                            ],
                          ),
                        if (_busy)
                          Container(
                            color: Colors.black45,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(),
                          ),
                        if (_photo != null ||
                            (editing && widget.existing!.photoVersion != null))
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: IgnorePointer(
                              child: CircleAvatar(
                                backgroundColor: scheme.surface,
                                child: Icon(Icons.edit,
                                    size: 20, color: scheme.onSurface),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ChipGroup(
            title: 'Tipo',
            options: typeLabels,
            selected: {_d.type},
            single: true,
            onChanged: (s) => setState(() => _d.type = s.first),
          ),
          ChipGroup(
            title: 'Casa',
            options: houses,
            selected: _d.location.isEmpty ? const {} : {_d.location},
            single: true,
            allowNone: true,
            onChanged: (s) =>
                setState(() => _d.location = s.isEmpty ? '' : s.first),
          ),
          ChipGroup(
            title: 'Colores',
            options: colorLabels,
            selected: _d.colors.toSet(),
            avatar: colorAvatar,
            onChanged: (s) => setState(() => _d.colors = s.toList()),
          ),
          ChipGroup(
            title: 'Temporada',
            options: seasons,
            selected: _d.seasons.toSet(),
            onChanged: (s) => setState(() => _d.seasons = s.toList()),
          ),
          ChipGroup(
            title: 'Ocasión',
            options: occasions,
            selected: _d.occasions.toSet(),
            onChanged: (s) => setState(() => _d.occasions = s.toList()),
          ),
          ChipGroup(
            title: 'Estado',
            options: statusLabels,
            selected: {_d.status},
            single: true,
            onChanged: (s) => setState(() => _d.status = s.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Nombre (opcional)',
                hintText: 'p. ej. Camisa de lino azul'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _brand,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Marca (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),
        ],
      ),
    );
  }
}
