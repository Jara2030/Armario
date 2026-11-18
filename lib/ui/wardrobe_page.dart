import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../providers.dart';
import 'item_detail_page.dart';
import 'item_form_page.dart';
import 'shell.dart';
import 'widgets.dart';

class WardrobePage extends ConsumerStatefulWidget {
  const WardrobePage({super.key});
  @override
  ConsumerState<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends ConsumerState<WardrobePage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(itemsProvider);
    final items = ref.watch(filteredItemsProvider);
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    final lastWorn = ref.watch(lastWornProvider);
    final counts = ref.watch(wearCountProvider);
    final total = all.value?.length ?? 0;
    final width = MediaQuery.sizeOf(context).width;

    String? footnote(String id) => switch (filter.sort) {
          ItemSort.recent => null,
          ItemSort.forgotten => 'Usada: ${agoLabel(lastWorn[id])}',
          ItemSort.mostWorn => '${counts[id] ?? 0} usos',
        };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openPage(context, const ItemFormPage()),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Añadir'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (q) => notifier.set(filter.copyWith(query: q)),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Buscar en mi armario',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        suffixIcon: filter.query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  notifier.set(filter.copyWith(query: ''));
                                },
                              ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Filtros',
                    onPressed: () => _openFilters(context),
                    icon: Badge(
                      isLabelVisible: filter.activeCount > 0,
                      label: Text('${filter.activeCount}'),
                      child: const Icon(Icons.tune),
                    ),
                  ),
                  PopupMenuButton<ItemSort>(
                    tooltip: 'Ordenar',
                    icon: const Icon(Icons.sort),
                    initialValue: filter.sort,
                    onSelected: (s) => notifier.set(filter.copyWith(sort: s)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: ItemSort.recent,
                          child: Text('Añadidas recientemente')),
                      PopupMenuItem(
                          value: ItemSort.forgotten,
                          child: Text('Más tiempo sin usar')),
                      PopupMenuItem(
                          value: ItemSort.mostWorn,
                          child: Text('Más usadas')),
                    ],
                  ),
                ],
              ),
            ),
            if (filter.activeCount > 0)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Quitar filtros'),
                      onPressed: notifier.clear,
                    ),
                    ..._activeChips(filter, notifier),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  items.length == total
                      ? '$total prendas'
                      : '${items.length} de $total prendas',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: all.isLoading && !all.hasValue
                  ? const Center(child: CircularProgressIndicator())
                  : total == 0
                      ? EmptyState(
                          icon: Icons.checkroom,
                          title: 'Tu armario está vacío',
                          subtitle:
                              'Añade tu primera prenda con una foto. Tarda unos segundos.',
                          action: FilledButton.icon(
                            onPressed: () =>
                                openPage(context, const ItemFormPage()),
                            icon: const Icon(Icons.add),
                            label: const Text('Añadir prenda'),
                          ),
                        )
                      : items.isEmpty
                          ? EmptyState(
                              icon: Icons.search_off,
                              title: 'Nada coincide',
                              subtitle:
                                  'Prueba con otra búsqueda o quita algún filtro.',
                              action: OutlinedButton(
                                onPressed: () {
                                  _search.clear();
                                  notifier.set(const ItemFilter());
                                },
                                child: const Text('Ver todo'),
                              ),
                            )
                          : GridView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 96),
                              gridDelegate: itemGridDelegate(width),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                return ItemCard(
                                  item,
                                  key: ValueKey(item.id),
                                  footnote: footnote(item.id),
                                  onTap: () => openPage(
                                      context, ItemDetailPage(item.id)),
                                  onLongPress: () =>
                                      showStatusSheet(context, ref, item),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _activeChips(ItemFilter f, FilterNotifier n) {
    Widget chip(String label, VoidCallback remove) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: InputChip(label: Text(label), onDeleted: remove),
        );
    Set<String> without(Set<String> s, String k) => {...s}..remove(k);
    return [
      for (final k in f.statuses)
        chip(statusOf(k).label,
            () => n.set(f.copyWith(statuses: without(f.statuses, k)))),
      for (final k in f.locations)
        chip(houseFilterLabels[k] ?? k,
            () => n.set(f.copyWith(locations: without(f.locations, k)))),
      for (final k in f.types)
        chip(typeOf(k).label,
            () => n.set(f.copyWith(types: without(f.types, k)))),
      for (final k in f.colors)
        chip(colorOf(k)?.label ?? k,
            () => n.set(f.copyWith(colors: without(f.colors, k)))),
      for (final k in f.seasons)
        chip(seasons[k] ?? k,
            () => n.set(f.copyWith(seasons: without(f.seasons, k)))),
      for (final k in f.occasions)
        chip(occasions[k] ?? k,
            () => n.set(f.copyWith(occasions: without(f.occasions, k)))),
    ];
  }

  void _openFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(filterProvider);
    final n = ref.read(filterProvider.notifier);
    final count = ref.watch(filteredItemsProvider).length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
                ChipGroup(
                  title: 'Estado',
                  options: statusLabels,
                  selected: f.statuses,
                  onChanged: (s) => n.set(f.copyWith(statuses: s)),
                ),
                ChipGroup(
                  title: 'Casa',
                  options: houseFilterLabels,
                  selected: f.locations,
                  onChanged: (s) => n.set(f.copyWith(locations: s)),
                ),
                ChipGroup(
                  title: 'Tipo',
                  options: typeLabels,
                  selected: f.types,
                  onChanged: (s) => n.set(f.copyWith(types: s)),
                ),
                ChipGroup(
                  title: 'Color',
                  options: colorLabels,
                  selected: f.colors,
                  avatar: colorAvatar,
                  onChanged: (s) => n.set(f.copyWith(colors: s)),
                ),
                ChipGroup(
                  title: 'Temporada',
                  options: seasons,
                  selected: f.seasons,
                  onChanged: (s) => n.set(f.copyWith(seasons: s)),
                ),
                ChipGroup(
                  title: 'Ocasión',
                  options: occasions,
                  selected: f.occasions,
                  onChanged: (s) => n.set(f.copyWith(occasions: s)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                TextButton(
                    onPressed: f.activeCount == 0 ? null : n.clear,
                    child: const Text('Quitar todos')),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Ver $count prendas'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
