import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import 'outfits_page.dart';
import 'settings_page.dart';
import 'today_page.dart';
import 'wardrobe_page.dart';

const wideBreakpoint = 800.0;

/// Abre una pantalla secundaria. En pantallas anchas se muestra como un
/// panel centrado en lugar de ocupar toda la ventana.
Future<T?> openPage<T>(BuildContext context, Widget page,
    {double maxWidth = 980}) {
  final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
  if (!wide) {
    return Navigator.of(context)
        .push<T>(MaterialPageRoute(builder: (_) => page));
  }
  return showDialog<T>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 860),
        child: page,
      ),
    ),
  );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _index = 0;
  late final AppLifecycleListener _lifecycle;

  static const _destinations = [
    (Icons.checkroom_outlined, Icons.checkroom, 'Armario'),
    (Icons.wb_sunny_outlined, Icons.wb_sunny, 'Hoy'),
    (Icons.style_outlined, Icons.style, 'Conjuntos'),
    (Icons.settings_outlined, Icons.settings, 'Ajustes'),
  ];

  @override
  void initState() {
    super.initState();
    // Arranca la sincronización sin bloquear la interfaz.
    Future.microtask(() => ref.read(syncProvider.notifier).init());
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(syncProvider.notifier).syncNow(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= wideBreakpoint;
    final body = IndexedStack(
      index: _index,
      children: const [
        WardrobePage(),
        TodayPage(),
        OutfitsPage(),
        SettingsPage(),
      ],
    );
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: width >= 1200,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: width >= 1200
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: _SyncDot(),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.$1),
                      selectedIcon: Icon(d.$2),
                      label: Text(d.$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$1),
              selectedIcon: Icon(d.$2),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}

/// Indicador discreto del estado de la sincronización.
class _SyncDot extends ConsumerWidget {
  const _SyncDot();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncProvider);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, tip) = switch (s.phase) {
      SyncPhase.off => (Icons.cloud_off, scheme.outline, 'Solo en este dispositivo'),
      SyncPhase.signedOut => (Icons.cloud_off, scheme.outline, 'Sin iniciar sesión'),
      SyncPhase.idle => (Icons.cloud_done, scheme.primary, 'Sincronizado'),
      SyncPhase.syncing => (Icons.cloud_sync, scheme.primary, 'Sincronizando…'),
      SyncPhase.error => (Icons.cloud_off, scheme.error, s.message ?? 'Sin conexión'),
    };
    return Tooltip(message: tip, child: Icon(icon, color: color));
  }
}
