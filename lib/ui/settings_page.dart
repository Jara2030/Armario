import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/catalog.dart';
import '../data/backup.dart';
import '../providers.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(t,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                Text('Ajustes', style: theme.textTheme.headlineSmall),
                title('Apariencia'),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('Sistema')),
                    ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Claro')),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Oscuro')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) =>
                      ref.read(settingsProvider.notifier).setTheme(s.first),
                ),
                title('Tiempo'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.location_city),
                    title: Text(settings.hasCity
                        ? settings.city
                        : 'Elegir ciudad'),
                    subtitle: const Text(
                        'Para sugerir ropa según el tiempo (Open-Meteo, gratis)'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog(
                        context: context, builder: (_) => const _CityDialog()),
                  ),
                ),
                title('Sincronización entre dispositivos'),
                const _SyncSection(),
                title('Copia de seguridad'),
                const _BackupSection(),
                const SizedBox(height: 24),
                Text(
                  'Armario · tus datos se guardan siempre en este dispositivo y la app funciona sin internet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ ciudad

class _CityDialog extends ConsumerStatefulWidget {
  const _CityDialog();
  @override
  ConsumerState<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends ConsumerState<_CityDialog> {
  final _ctrl = TextEditingController();
  List<CityResult>? _results;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_ctrl.text.trim().length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await searchCity(_ctrl.text);
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo buscar. ¿Hay internet?');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tu ciudad'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'p. ej. Madrid',
                suffixIcon: IconButton(
                    onPressed: _search, icon: const Icon(Icons.search)),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_results != null && _results!.isEmpty)
              const Text('Sin resultados.'),
            if (_results != null)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in _results!)
                      ListTile(
                        title: Text(r.label),
                        onTap: () async {
                          await ref
                              .read(settingsProvider.notifier)
                              .setCity(r.label, r.lat, r.lon);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

// ----------------------------------------------------------- sincronización

class _SyncSection extends ConsumerStatefulWidget {
  const _SyncSection();
  @override
  ConsumerState<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<_SyncSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login({bool create = false}) async {
    if (_email.text.trim().isEmpty || _password.text.length < 6) {
      toast(context, 'Escribe tu email y una contraseña de 6 caracteres o más.');
      return;
    }
    setState(() => _busy = true);
    final error = await ref
        .read(syncProvider.notifier)
        .signIn(_email.text, _password.text, create: create);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      toast(context, error);
    } else {
      _password.clear();
    }
  }

  String _when(DateTime? d) {
    if (d == null) return 'todavía nunca';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora mismo';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return agoLabel(dayKey(d));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sync = ref.watch(syncProvider);
    final settings = ref.watch(settingsProvider);
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final controller = ref.read(syncProvider.notifier);

    final serverTile = ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: const Text('Servidor (Supabase)'),
      subtitle: Text(settings.hasServer
          ? settings.supabaseUrl
          : 'Sin configurar: la app funciona solo en este dispositivo'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog(
          context: context, builder: (_) => const _ServerDialog()),
    );

    final children = <Widget>[serverTile];
    switch (sync.phase) {
      case SyncPhase.off:
        break;
      case SyncPhase.signedOut:
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sync.message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(sync.message!,
                      style: TextStyle(color: scheme.error)),
                ),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: Text(_busy ? 'Conectando…' : 'Iniciar sesión'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _login(create: true),
                child: const Text('Es la primera vez: crear mi cuenta'),
              ),
            ],
          ),
        ));
      case SyncPhase.idle:
      case SyncPhase.syncing:
      case SyncPhase.error:
        final isError = sync.phase == SyncPhase.error;
        final syncing = sync.phase == SyncPhase.syncing;
        children.addAll([
          ListTile(
            leading: Icon(
              isError
                  ? Icons.cloud_off
                  : syncing
                      ? Icons.cloud_sync
                      : Icons.cloud_done,
              color: isError ? scheme.error : scheme.primary,
            ),
            title: Text(syncing
                ? 'Sincronizando…'
                : isError
                    ? 'Sin conexión con el servidor'
                    : pending > 0
                        ? '$pending cambios pendientes de subir'
                        : 'Todo sincronizado'),
            subtitle: Text([
              if (sync.email != null) sync.email!,
              'Última sincronización: ${_when(sync.lastOk)}',
              if (isError && sync.message != null) sync.message!,
            ].join('\n')),
            isThreeLine: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: syncing ? null : controller.syncNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizar ahora'),
                ),
                OutlinedButton(
                  onPressed: syncing ? null : controller.fullResync,
                  child: const Text('Resincronizar todo'),
                ),
                TextButton(
                  onPressed: controller.signOut,
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ]);
    }
    return Card(child: Column(children: children));
  }
}

class _ServerDialog extends ConsumerStatefulWidget {
  const _ServerDialog();
  @override
  ConsumerState<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends ConsumerState<_ServerDialog> {
  late final _url =
      TextEditingController(text: ref.read(settingsProvider).supabaseUrl);
  late final _key =
      TextEditingController(text: ref.read(settingsProvider).supabaseKey);

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (url.isNotEmpty && !url.startsWith('https://')) {
      toast(context, 'La URL debe empezar por https://');
      return;
    }
    await ref.read(settingsProvider.notifier).setServer(url, _key.text);
    await ref.read(syncProvider.notifier).init();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Servidor de sincronización'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Copia estos dos datos de tu proyecto de Supabase (Project Settings → API). El README explica cómo crearlo gratis. Déjalos vacíos para usar la app solo en este dispositivo.'),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Project URL',
                  hintText: 'https://xxxxxxxx.supabase.co'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              autocorrect: false,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                  labelText: 'Clave pública (anon / publishable)'),
            ),
            const SizedBox(height: 8),
            Text(
              'Nunca pegues aquí la clave "service_role" / "secret".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

// ------------------------------------------------------- copia de seguridad

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();
  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = await BackupService(ref.read(dbProvider)).export();
      final name = 'armario-${dayKey(DateTime.now())}.zip';
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: 'Guardar copia de seguridad',
      );
      if (mounted && saved != null) {
        toast(context,
            'Copia guardada (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
      }
    } catch (e) {
      if (mounted) toast(context, 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        dialogTitle: 'Elegir copia de seguridad',
      );
      if (file == null || !mounted) return;
      setState(() => _busy = true);
      final r = await BackupService(ref.read(dbProvider))
          .import(await file.readAsBytes());
      if (mounted) {
        toast(context,
            'Importado: ${r.items} prendas, ${r.outfits} conjuntos, ${r.wearLogs} usos');
      }
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'No se pudo importar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Exportar copia completa'),
            subtitle:
                const Text('Un archivo .zip con todos los datos y las fotos'),
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Importar copia'),
            subtitle: const Text(
                'Añade lo que falte; no borra nada de lo que ya tienes'),
            enabled: !_busy,
            onTap: _import,
          ),
        ],
      ),
    );
  }
}
