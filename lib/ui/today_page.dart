import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../core/suggest.dart';
import '../data/database.dart';
import '../providers.dart';
import 'item_detail_page.dart';
import 'shell.dart';
import 'widgets.dart';

/// "¿Qué puedo ponerme hoy?": solo prendas disponibles, una sugerencia según
/// el tiempo y lo que lleva más tiempo sin usarse.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});
  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  String? _occasion;
  int _seed = DateTime.now().day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final house = ref.watch(settingsProvider.select((s) => s.house));
    final everything = ref.watch(itemsProvider).value ?? const <Item>[];
    // Solo la ropa de la casa en la que estoy (y la que no tiene casa
    // indicada, por si acaso).
    final all = house.isEmpty
        ? everything
        : everything
            .where((i) => i.location == house || i.location.isEmpty)
            .toList();
    final lastWorn = ref.watch(lastWornProvider);
    final weather = ref.watch(weatherProvider).value;
    final width = MediaQuery.sizeOf(context).width;

    final available = all.where((i) {
      if (i.status != statusAvailable) return false;
      if (_occasion != null &&
          i.occasions.isNotEmpty &&
          !i.occasions.contains(_occasion)) {
        return false;
      }
      return true;
    }).toList();
    final unavailable = all.length - all.where((i) => i.status == statusAvailable).length;

    // Sin datos del tiempo se asume un día templado.
    final suggestion = suggestOutfit(all, lastWorn,
        tMax: weather?.tMax ?? 20,
        rainy: weather?.rainy ?? false,
        occasion: _occasion,
        seed: _seed);

    final forgotten = [...available]
      ..sort((a, b) => (lastWorn[a.id] ?? '').compareTo(lastWorn[b.id] ?? ''));
    final today = dayKey(DateTime.now());
    final forgottenTop =
        forgotten.where((i) => lastWorn[i.id] != today).take(12).toList();

    Widget header(String text, {String? trailing}) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
            child: Row(
              children: [
                Expanded(
                    child: Text(text, style: theme.textTheme.titleMedium)),
                if (trailing != null)
                  Text(trailing,
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('¿Qué me pongo hoy?',
                    style: theme.textTheme.headlineSmall),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: 'mama',
                        icon: Icon(Icons.home_outlined),
                        label: Text('Mamá')),
                    ButtonSegment(
                        value: 'papa',
                        icon: Icon(Icons.home_outlined),
                        label: Text('Papá')),
                    ButtonSegment(value: '', label: Text('Todo')),
                  ],
                  selected: {house},
                  onSelectionChanged: (s) =>
                      ref.read(settingsProvider.notifier).setHouse(s.first),
                ),
              ),
            ),
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
                        label: const Text('Cualquiera'),
                        selected: _occasion == null,
                        onSelected: (_) => setState(() => _occasion = null),
                      ),
                    ),
                    for (final o in occasions.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(o.value),
                          selected: _occasion == o.key,
                          onSelected: (_) =>
                              setState(() => _occasion = o.key),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: everything.isNotEmpty
                      ? 'No tienes ropa apuntada en esta casa'
                      : 'Aún no hay prendas',
                  subtitle: everything.isNotEmpty
                      ? 'Indica la casa de cada prenda al editarla, o elige "Todo".'
                      : 'Cuando añadas ropa en "Armario", aquí verás qué tienes disponible y una sugerencia para hoy.',
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _SuggestionCard(
                    weather: weather,
                    items: suggestion,
                    onAnother: () => setState(() => _seed++),
                  ),
                ),
              ),
              if (forgottenTop.length >= 3) ...[
                header('Llevas tiempo sin ponerte'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: forgottenTop.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final item = forgottenTop[i];
                        return SizedBox(
                          width: 140,
                          child: ItemCard(
                            item,
                            footnote: agoLabel(lastWorn[item.id]),
                            onTap: () =>
                                openPage(context, ItemDetailPage(item.id)),
                            onLongPress: () =>
                                showStatusSheet(context, ref, item),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              header('Disponible ahora',
                  trailing: unavailable == 0
                      ? '${available.length}'
                      : '${available.length} · $unavailable no disponibles'),
              if (available.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'No hay nada disponible con este filtro. ¿Toca poner una lavadora?',
                        textAlign: TextAlign.center),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                  sliver: SliverGrid.builder(
                    gridDelegate: itemGridDelegate(width),
                    itemCount: available.length,
                    itemBuilder: (context, i) {
                      final item = available[i];
                      return ItemCard(
                        item,
                        key: ValueKey(item.id),
                        onTap: () =>
                            openPage(context, ItemDetailPage(item.id)),
                        onLongPress: () => showStatusSheet(context, ref, item),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final Weather? weather;
  final List<Item> items;
  final VoidCallback onAnother;
  const _SuggestionCard(
      {required this.weather, required this.items, required this.onAnother});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final w = weather;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(w?.icon ?? Icons.auto_awesome,
                    color: scheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    w != null
                        ? '${settings.city.split(',').first} · ${w.description}, '
                            '${w.tMin.round()}°–${w.tMax.round()}°'
                            '${w.rainy ? ' · lluvia ${w.rainProb}%' : ''}'
                        : settings.hasCity
                            ? 'Sugerencia (sin datos del tiempo ahora mismo)'
                            : 'Sugerencia · pon tu ciudad en Ajustes para tener en cuenta el tiempo',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text('No hay suficientes prendas disponibles para proponer algo.',
                  style: TextStyle(color: scheme.onPrimaryContainer))
            else ...[
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => SizedBox(
                    width: 112,
                    child: ItemCard(
                      items[i],
                      onTap: () =>
                          openPage(context, ItemDetailPage(items[i].id)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await ref
                          .read(dbProvider)
                          .markWorn(items.map((i) => i.id));
                      if (context.mounted) {
                        toast(context, 'Apuntado: te lo has puesto hoy');
                      }
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Me pongo esto'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onAnother,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Otra'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await ref.read(dbProvider).saveOutfit(
                          name: 'Conjunto del ${dayKey(DateTime.now())}',
                          notes: '',
                          itemIds: items.map((i) => i.id).toList());
                      if (context.mounted) {
                        toast(context, 'Guardado en Conjuntos');
                      }
                    },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
