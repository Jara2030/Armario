import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../data/database.dart';
import '../providers.dart';

/// Miniatura de una prenda (o un icono si aún no tiene foto).
class ItemThumb extends ConsumerWidget {
  final Item item;
  const ItemThumb(this.item, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final version = ref.watch(
        photoVersionsProvider.select((v) => v.value?[item.id]));
    final bytes = version == null
        ? null
        : ref.watch(thumbProvider((item.id, version))).value;
    if (bytes == null) {
      final first = item.colors.isEmpty ? null : colorOf(item.colors.first);
      return Container(
        color: first?.color.withValues(alpha: 0.25) ??
            scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (_, c) => Icon(typeOf(item.type).icon,
              size: (c.biggest.shortestSide * 0.4).clamp(16, 64),
              color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      width: double.infinity,
      height: double.infinity,
    );
  }
}

String itemTitle(Item i) => i.name.isNotEmpty ? i.name : typeOf(i.type).label;

/// Tarjeta de la galería: la foto manda; encima, el nombre y el estado.
class ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String? footnote;
  const ItemCard(
    this.item, {
    super.key,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = statusOf(item.status);
    final unavailable = item.status != statusAvailable;
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: unavailable ? 0.55 : 1, child: ItemThumb(item)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xB3000000)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      itemTitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    if (footnote != null)
                      Text(
                        footnote!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            if (unavailable)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.icon, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(status.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            if (item.location.isNotEmpty && !selected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.home, size: 13, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(houseShort(item.location),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            if (selected)
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.28),
                  border: Border.all(color: scheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.topRight,
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.check, size: 18, color: scheme.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

SliverGridDelegate itemGridDelegate(double width) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: width >= 800 ? 220 : 200,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3 / 4,
    );

/// Punto de color (con borde, para que el blanco se vea).
class ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  const ColorDot(this.color, {super.key, this.size = 16});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        ),
      );
}

/// Grupo de chips de selección múltiple.
class ChipGroup extends StatelessWidget {
  final String title;
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Widget? Function(String key)? avatar;
  final bool single;

  /// En modo [single], volver a tocar la opción elegida la desmarca.
  final bool allowNone;
  const ChipGroup({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.avatar,
    this.single = false,
    this.allowNone = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in options.entries)
              FilterChip(
                label: Text(e.value),
                avatar: selected.contains(e.key) ? null : avatar?.call(e.key),
                selected: selected.contains(e.key),
                onSelected: (on) {
                  if (single) {
                    onChanged(allowNone && !on ? <String>{} : {e.key});
                    return;
                  }
                  final next = {...selected};
                  on ? next.add(e.key) : next.remove(e.key);
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

final typeLabels = {for (final t in garmentTypes) t.key: t.label};
final colorLabels = {for (final c in colorOptions) c.key: c.label};
final statusLabels = {for (final s in statusOptions) s.key: s.label};
const houseFilterLabels = {'mama': 'Mamá', 'papa': 'Papá', '': 'Sin casa'};

Widget? colorAvatar(String key) {
  final c = colorOf(key);
  return c == null ? null : ColorDot(c.color);
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(message), behavior: SnackBarBehavior.floating));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.action});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Menú rápido para cambiar el estado de una prenda (pulsación larga).
Future<void> showStatusSheet(
    BuildContext context, WidgetRef ref, Item item) async {
  final picked = await showModalBottomSheet<String>(
    isScrollControlled: true,
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
       child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(itemTitle(item),
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: const Text('Cambiar estado o casa'),
          ),
          for (final s in statusOptions)
            ListTile(
              leading: Icon(s.icon, color: s.color),
              title: Text(s.label),
              trailing: item.status == s.key ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, s.key),
            ),
          const Divider(),
          for (final h in houses.entries)
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text('Está en ${h.value.toLowerCase()}'),
              trailing: item.location == h.key ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, 'casa:${h.key}'),
            ),
          const SizedBox(height: 8),
        ],
       ),
      ),
    ),
  );
  if (picked == null) return;
  final db = ref.read(dbProvider);
  if (picked.startsWith('casa:')) {
    final house = picked.substring(5);
    if (house != item.location) await db.setLocation([item.id], house);
  } else if (picked != item.status) {
    await db.setStatus([item.id], picked);
  }
}
