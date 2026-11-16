import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../data/database.dart';
import '../providers.dart';
import 'item_form_page.dart';
import 'shell.dart';
import 'widgets.dart';

class ItemDetailPage extends ConsumerWidget {
  final String id;
  const ItemDetailPage(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider).value ?? const <Item>[];
    final item = items.where((i) => i.id == id).firstOrNull;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
            icon: Icons.delete_outline, title: 'Esta prenda ya no existe'),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final photo = _Photo(item);
    final info = _Info(item);
    return Scaffold(
      appBar: AppBar(
        title: Text(itemTitle(item)),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openPage(context, ItemFormPage(existing: item)),
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, item),
          ),
        ],
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 10, 20),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: photo),
                    )),
                Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(10, 4, 20, 20),
                        child: info)),
              ],
            )
          : ListView(
              children: [
                AspectRatio(aspectRatio: 4 / 5, child: photo),
                Padding(padding: const EdgeInsets.all(16), child: info),
              ],
            ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar esta prenda?'),
        content: Text(
            'Se borrará "${itemTitle(item)}" con su foto y su historial de uso. No se puede deshacer.'),
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
    await ref.read(dbProvider).deleteItem(item.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _Photo extends ConsumerWidget {
  final Item item;
  const _Photo(this.item);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version =
        ref.watch(photoVersionsProvider.select((v) => v.value?[item.id]));
    final bytes = version == null
        ? null
        : ref.watch(fullPhotoProvider((item.id, version))).value;
    if (bytes == null) return ItemThumb(item);
    return InteractiveViewer(
      maxScale: 4,
      child: Image.memory(bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity),
    );
  }
}

class _Info extends ConsumerWidget {
  final Item item;
  const _Info(this.item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.read(dbProvider);
    final logs = (ref.watch(wearLogsProvider).value ?? const <WearLog>[])
        .where((l) => l.itemId == item.id)
        .toList();
    final today = dayKey(DateTime.now());
    final wornToday = logs.any((l) => l.wornOn == today);
    final lastWorn = logs.isEmpty ? null : logs.first.wornOn;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              child,
            ],
          ),
        );

    Widget tags(Iterable<Widget> chips) =>
        Wrap(spacing: 8, runSpacing: 6, children: chips.toList());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(itemTitle(item), style: theme.textTheme.headlineSmall),
        Text(
          [typeOf(item.type).label, if (item.brand.isNotEmpty) item.brand]
              .join(' · '),
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: wornToday
              ? OutlinedButton.icon(
                  onPressed: () => db.unmarkWorn(item.id),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Puesta hoy · deshacer'),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    await db.markWorn([item.id]);
                    if (context.mounted) toast(context, 'Apuntado: usada hoy');
                  },
                  icon: const Icon(Icons.today),
                  label: const Text('Me lo he puesto hoy'),
                ),
        ),
        section(
          'Estado',
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in statusOptions)
                ChoiceChip(
                  avatar: item.status == s.key
                      ? null
                      : Icon(s.icon, size: 18, color: s.color),
                  label: Text(s.label),
                  selected: item.status == s.key,
                  onSelected: (_) => db.setStatus([item.id], s.key),
                ),
            ],
          ),
        ),
        if (item.colors.isNotEmpty)
          section(
              'Colores',
              tags(item.colors.map((c) {
                final o = colorOf(c);
                return Chip(
                    avatar: o == null ? null : ColorDot(o.color),
                    label: Text(o?.label ?? c));
              }))),
        if (item.seasons.isNotEmpty)
          section('Temporada',
              tags(item.seasons.map((s) => Chip(label: Text(seasons[s] ?? s))))),
        if (item.occasions.isNotEmpty)
          section(
              'Ocasión',
              tags(item.occasions
                  .map((o) => Chip(label: Text(occasions[o] ?? o))))),
        if (item.notes.isNotEmpty) section('Notas', Text(item.notes)),
        section(
          'Uso',
          Text(logs.isEmpty
              ? 'Todavía no la has marcado como usada.'
              : 'Usada ${logs.length} ${logs.length == 1 ? 'vez' : 'veces'} · última: ${agoLabel(lastWorn)}'),
        ),
      ],
    );
  }
}
