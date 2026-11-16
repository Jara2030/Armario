import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../data/database.dart';
import '../providers.dart';
import 'shell.dart';
import 'widgets.dart';

class OutfitsPage extends ConsumerWidget {
  const OutfitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final outfits = ref.watch(outfitsProvider).value ?? const <Outfit>[];
    final items = {
      for (final i in ref.watch(itemsProvider).value ?? const <Item>[]) i.id: i
    };
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openPage(context, const OutfitFormPage()),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo conjunto'),
      ),
      body: SafeArea(
        bottom: false,
        child: outfits.isEmpty
            ? const EmptyState(
                icon: Icons.style_outlined,
                title: 'Sin conjuntos todavía',
                subtitle:
                    'Combina prendas y guarda tus conjuntos favoritos para decidir más rápido.',
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Text('Conjuntos',
                          style: theme.textTheme.headlineSmall),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 420,
                        mainAxisExtent: 210,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemCount: outfits.length,
                      itemBuilder: (context, i) {
                        final o = outfits[i];
                        final own = [
                          for (final id in o.itemIds)
                            if (items[id] != null) items[id]!
                        ];
                        final ready = own.isNotEmpty &&
                            own.every((e) => e.status == statusAvailable);
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => openPage(
                                context, OutfitFormPage(existing: o)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          o.name.isEmpty
                                              ? 'Conjunto sin nombre'
                                              : o.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                      ),
                                      if (!ready && own.isNotEmpty)
                                        Tooltip(
                                          message:
                                              'Alguna prenda no está disponible',
                                          child: Icon(
                                              Icons.local_laundry_service,
                                              size: 20,
                                              color: theme.colorScheme.outline),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        for (final item in own.take(4))
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 6),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Opacity(
                                                  opacity: item.status ==
                                                          statusAvailable
                                                      ? 1
                                                      : 0.45,
                                                  child: ItemThumb(item),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (own.length > 4)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(left: 4),
                                            child: Text('+${own.length - 4}'),
                                          ),
                                        if (own.isEmpty)
                                          const Text('Sin prendas'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Crear / editar un conjunto: nombre y selección de prendas.
class OutfitFormPage extends ConsumerStatefulWidget {
  final Outfit? existing;
  const OutfitFormPage({super.key, this.existing});
  @override
  ConsumerState<OutfitFormPage> createState() => _OutfitFormPageState();
}

class _OutfitFormPageState extends ConsumerState<OutfitFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late final List<String> _selected = [...?widget.existing?.itemIds];
  String? _type;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      toast(context, 'Elige al menos una prenda.');
      return;
    }
    await ref.read(dbProvider).saveOutfit(
        id: widget.existing?.id,
        name: _name.text.trim(),
        notes: _notes.text.trim(),
        itemIds: _selected);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar este conjunto?'),
        content: const Text('Las prendas no se borran, solo el conjunto.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteOutfit(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(itemsProvider).value ?? const <Item>[];
    final known = all.map((e) => e.id).toSet();
    _selected.removeWhere((id) => !known.contains(id));
    final shown = _type == null
        ? all
        : all.where((i) => i.type == _type).toList();
    final usedTypes = {
      for (final t in garmentTypes)
        if (all.any((i) => i.type == t.key)) t.key: t.label
    };
    final editing = widget.existing != null;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Conjunto' : 'Nuevo conjunto'),
        actions: [
          if (editing)
            IconButton(
                tooltip: 'Borrar',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child:
                FilledButton(onPressed: _save, child: const Text('Guardar')),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Nombre', hintText: 'p. ej. Oficina lunes'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        const InputDecoration(labelText: 'Notas (opcional)'),
                  ),
                  if (editing) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _selected.isEmpty
                            ? null
                            : () async {
                                await ref.read(dbProvider).markWorn(_selected,
                                    outfitId: widget.existing!.id);
                                if (context.mounted) {
                                  toast(context,
                                      'Apuntado: te lo has puesto hoy');
                                }
                              },
                        icon: const Icon(Icons.today),
                        label: const Text('Me lo he puesto hoy'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                      'Prendas del conjunto (${_selected.length} elegidas)',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          if (usedTypes.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: const Text('Todo'),
                          selected: _type == null,
                          onSelected: (_) => setState(() => _type = null)),
                    ),
                    for (final t in usedTypes.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                            label: Text(t.value),
                            selected: _type == t.key,
                            onSelected: (_) => setState(() => _type = t.key)),
                      ),
                  ],
                ),
              ),
            ),
          if (all.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                  icon: Icons.checkroom,
                  title: 'Primero añade prendas a tu armario'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 32),
              sliver: SliverGrid.builder(
                gridDelegate: itemGridDelegate(width),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final item = shown[i];
                  final on = _selected.contains(item.id);
                  return ItemCard(
                    item,
                    key: ValueKey(item.id),
                    selected: on,
                    onTap: () => setState(() =>
                        on ? _selected.remove(item.id) : _selected.add(item.id)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
