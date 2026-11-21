import 'package:flutter/material.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

class ExtraSourcesScreen extends StatefulWidget {
  const ExtraSourcesScreen({super.key});

  @override
  State<ExtraSourcesScreen> createState() => _ExtraSourcesScreenState();
}

class _ExtraSourcesScreenState extends State<ExtraSourcesScreen> {
  final SettingsService _settings = getIt<SettingsService>();
  final ExtraSourcesService _extraSources = getIt<ExtraSourcesService>();

  bool _isSyncing = false;
  bool _hasOwnerCreds = false;
  String? _ownerLogin;

  @override
  void initState() {
    super.initState();
    _loadOwnerStatus();
    _syncNow(silent: true);
  }

  Future<void> _loadOwnerStatus() async {
    final has = await _extraSources.hasVerifiedOwnerCredentials();
    final login = await _extraSources.getVerifiedOwnerLogin();
    if (mounted) {
      setState(() {
        _hasOwnerCreds = has;
        _ownerLogin = login;
      });
    }
  }

  Future<void> _syncNow({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    final ok = await _extraSources.syncRemoteSources(force: true);
    if (!mounted) return;
    setState(() => _isSyncing = false);
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Zsynchronizowano listę źródeł z chmury.'
              : 'Nie udało się pobrać listy źródeł z chmury.'),
        ),
      );
    }
  }

  Future<String?> _promptPinOrVerifyOwner() async {
    final hasCreds = await _extraSources.hasVerifiedOwnerCredentials();
    if (!mounted) return null;

    if (hasCreds) {
      final pinCtrl = TextEditingController();
      return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Zatwierdzenie właściciela'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wpisz PIN właściciela${_ownerLogin != null ? ' ($_ownerLogin)' : ''}, aby zatwierdzić publikację zmian dla wszystkich użytkowników:',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Kod PIN właściciela',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(pinCtrl.text.trim()),
              child: const Text('Zatwierdź'),
            ),
          ],
        ),
      );
    }

    final tokenCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String? errText;
    bool busy = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Weryfikacja właściciela'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aby publikować źródła dla wszystkich użytkowników aplikacji, potwierdź że jesteś właścicielem repozytorium (xxXigmatXxx). Token zostanie zapisany zaszyfrowany wyłącznie na tym urządzeniu.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Token GitHub (PAT z uprawnieniem Contents)',
                    hintText: 'ghp_... lub github_pat_...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ustaw swój PIN administratora (4–8 znaków)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errText!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDlgState(() {
                        busy = true;
                        errText = null;
                      });
                      final err =
                          await _extraSources.verifyAndSaveOwnerCredentials(
                        githubToken: tokenCtrl.text,
                        pin: pinCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setDlgState(() {
                          busy = false;
                          errText = err;
                        });
                      } else {
                        await _loadOwnerStatus();
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop(pinCtrl.text.trim());
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Zweryfikuj i zapisz'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSourceDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final logoCtrl = TextEditingController();
    var selectedType = ExtraSourceType.wordpress;
    var selectedCategory = 'Popularne filmy';
    String? errMsg;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Dodaj nowe źródło'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa źródła',
                    hintText: 'np. FilmyOnline',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Adres strony (URL)',
                    hintText: 'https://przyklad.pl',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExtraSourceType>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Typ źródła',
                    border: OutlineInputBorder(),
                  ),
                  items: ExtraSourceType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedType = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Kategoria główna',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Popularne filmy',
                    'Popularne seriale',
                    'Bajki dla dzieci',
                    'Familijne',
                    'Anime',
                  ]
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedCategory = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: logoCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL (opcjonalnie)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errMsg!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Anuluj'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      var url = urlCtrl.text.trim();
                      if (url.endsWith('/')) {
                        url = url.substring(0, url.length - 1);
                      }
                      if (name.isEmpty || !url.startsWith('http')) {
                        setDlgState(() =>
                            errMsg = 'Podaj nazwę oraz pełny adres https://...');
                        return;
                      }
                      setDlgState(() {
                        busy = true;
                        errMsg = null;
                      });
                      final err = await _extraSources.validateSourceUrl(url);
                      if (err != null) {
                        setDlgState(() {
                          busy = false;
                          errMsg = err;
                        });
                        return;
                      }
                      final id =
                          'local_${DateTime.now().millisecondsSinceEpoch}';
                      await _extraSources.addLocalSource(ExtraSourceConfig(
                        id: id,
                        name: name,
                        baseUrl: url,
                        type: selectedType,
                        category: selectedCategory,
                        logoUrl: logoCtrl.text.trim(),
                      ));
                      if (!_settings.extraSourcesEnabled) {
                        _settings.setExtraSourcesEnabled(true);
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
              child: const Text('Tylko u mnie'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      var url = urlCtrl.text.trim();
                      if (url.endsWith('/')) {
                        url = url.substring(0, url.length - 1);
                      }
                      if (name.isEmpty || !url.startsWith('http')) {
                        setDlgState(() =>
                            errMsg = 'Podaj nazwę oraz pełny adres https://...');
                        return;
                      }
                      final pin = await _promptPinOrVerifyOwner();
                      if (pin == null || pin.isEmpty) return;

                      setDlgState(() {
                        busy = true;
                        errMsg = null;
                      });
                      final cleanId = name
                          .toLowerCase()
                          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                          .replaceAll(RegExp(r'^_+|_+$'), '');
                      final id =
                          '${cleanId.isEmpty ? 'src' : cleanId}_${DateTime.now().millisecondsSinceEpoch % 10000}';
                      final err = await _extraSources.publishGlobalSourcesChange(
                        addSource: ExtraSourceConfig(
                          id: id,
                          name: name,
                          baseUrl: url,
                          type: selectedType,
                          category: selectedCategory,
                          logoUrl: logoCtrl.text.trim(),
                          isRemote: true,
                        ),
                        pin: pin,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setDlgState(() {
                          busy = false;
                          errMsg = err;
                        });
                      } else {
                        if (!_settings.extraSourcesEnabled) {
                          _settings.setExtraSourcesEnabled(true);
                        }
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Opublikowano źródło "$name" dla wszystkich użytkowników!'),
                          ),
                        );
                      }
                    },
              child: const Text('Dla wszystkich'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeGlobalSource(ExtraSourceConfig src) async {
    final pin = await _promptPinOrVerifyOwner();
    if (pin == null || pin.isEmpty) return;
    final err = await _extraSources.publishGlobalSourcesChange(
      removeId: src.id,
      pin: pin,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Usunięto globalne źródło "${src.name}".'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Źródła dodatkowe'),
        actions: [
          IconButton(
            tooltip: 'Odśwież z chmury',
            onPressed: _isSyncing ? null : () => _syncNow(silent: false),
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Dodaj źródło',
            onPressed: _showAddSourceDialog,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SettingsListenable(
        builder: (context, _, __) {
          final masterEnabled = _settings.extraSourcesEnabled;
          final remoteSources = _extraSources.getRemoteSources();
          final localSources = _extraSources.getLocalSources();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  value: masterEnabled,
                  title: const Text(
                    'Włącz źródła dodatkowe',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Po włączeniu aktywuje dodatkowe katalogi oraz źródła zaktualizowane z chmury.',
                  ),
                  secondary: const Icon(Icons.extension_outlined),
                  onChanged: (val) {
                    _settings.setExtraSourcesEnabled(val);
                    _extraSources.notifyChanged();
                    if (val) {
                      _syncNow(silent: true);
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Wbudowane źródła dodatkowe',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _settings.isBuiltinExtraEnabled(
                          SupportedService.bajeczki),
                      title: Text(SupportedService.bajeczki.displayName),
                      subtitle: const Text('Filmy (Lektor/Dubbing PL), bajki i seriale'),
                      onChanged: masterEnabled
                          ? (val) {
                              _settings.setBuiltinExtraEnabled(
                                  SupportedService.bajeczki, val);
                              _extraSources.notifyChanged();
                            }
                          : null,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _settings
                          .isBuiltinExtraEnabled(SupportedService.docchi),
                      title: Text(SupportedService.docchi.displayName),
                      subtitle: const Text('Seriale i filmy anime (napisy PL)'),
                      onChanged: masterEnabled
                          ? (val) {
                              _settings.setBuiltinExtraEnabled(
                                  SupportedService.docchi, val);
                              _extraSources.notifyChanged();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Źródła z chmury (dla wszystkich)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showAddSourceDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Dodaj'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: remoteSources.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.cloud_done_outlined),
                        title: Text('Brak dodatkowych źródeł w chmurze'),
                        subtitle: Text(
                          'Źródła dodane przez właściciela pojawią się tutaj automatycznie u wszystkich użytkowników.',
                        ),
                      )
                    : Column(
                        children: remoteSources
                            .map((s) => ListTile(
                                  leading: const Icon(Icons.public),
                                  title: Text(s.name),
                                  subtitle: Text(
                                      '${s.baseUrl}\n${s.type.displayName} • ${s.category}'),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _removeGlobalSource(s),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              if (localSources.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Źródła lokalne (tylko to urządzenie)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                Card(
                  color: colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: localSources
                        .map((s) => ListTile(
                              leading: const Icon(Icons.smartphone),
                              title: Text(s.name),
                              subtitle: Text(
                                  '${s.baseUrl}\n${s.type.displayName} • ${s.category}'),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _extraSources.removeLocalSource(s.id),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Card(
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: Icon(
                    _hasOwnerCreds ? Icons.verified_user : Icons.lock_outline,
                    color: _hasOwnerCreds ? Colors.greenAccent : null,
                  ),
                  title: Text(_hasOwnerCreds
                      ? 'Weryfikacja właściciela aktywna (${_ownerLogin ?? 'xxXigmatXxx'})'
                      : 'Weryfikacja właściciela nieaktywna'),
                  subtitle: Text(_hasOwnerCreds
                      ? 'Możesz publikować nowe źródła dla wszystkich użytkowników za pomocą PIN-u.'
                      : 'Wymagana tylko do globalnej publikacji nowych źródeł dla wszystkich użytkowników.'),
                  trailing: _hasOwnerCreds
                      ? TextButton(
                          onPressed: () async {
                            await _extraSources.clearOwnerVerification();
                            await _loadOwnerStatus();
                          },
                          child: const Text('Resetuj'),
                        )
                      : TvFocusable(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            await _promptPinOrVerifyOwner();
                            await _loadOwnerStatus();
                          },
                          child: TextButton(
                            onPressed: () async {
                              await _promptPinOrVerifyOwner();
                              await _loadOwnerStatus();
                            },
                            child: const Text('Zweryfikuj'),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
