import 'package:flutter/material.dart';
import 'package:purevideo/core/services/app_update_service.dart';
import 'package:purevideo/di/injection_container.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo update;

  const AppUpdateDialog({super.key, required this.update});

  static Future<void> show(BuildContext context, AppUpdateInfo update) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AppUpdateDialog(update: update),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final AppUpdateService _updateService = getIt<AppUpdateService>();
  bool _downloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorText;
  String? _pendingFilePath;
  bool _needsUnknownSourcesPerm = false;

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0.0;
      _errorText = null;
      _needsUnknownSourcesPerm = false;
      _statusText = 'Łączenie z serwerem...';
    });

    try {
      final (status, path) = await _updateService.downloadAndInstallUpdate(
        widget.update,
        onProgress: (p, txt) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _statusText = txt;
          });
        },
      );
      if (!mounted) return;
      if (status == 'NEED_PERMISSION') {
        setState(() {
          _downloading = false;
          _pendingFilePath = path;
          _needsUnknownSourcesPerm = true;
          _statusText =
              'Wymagane uprawnienie do instalacji aktualizacji z tej aplikacji.';
        });
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _errorText = 'Błąd pobierania lub instalacji: $e';
      });
    }
  }

  Future<void> _retryInstallAfterPermission() async {
    if (_pendingFilePath == null) {
      await _startDownloadAndInstall();
      return;
    }
    try {
      final res = await _updateService.installDownloadedFile(_pendingFilePath!);
      if (!mounted) return;
      if (res == 'NEED_PERMISSION') {
        await _updateService.openInstallPermissionSettings();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Błąd instalacji: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final colorScheme = Theme.of(context).colorScheme;
    final isDev = u.channel == AppUpdateChannel.dev;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update_alt,
            color: isDev ? Colors.amberAccent : const Color(0xFFE50914),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              u.name.isNotEmpty ? u.name : 'Nowa wersja PureVideo',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'v${u.version} (build ${u.buildNumber})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDev ? Colors.amber : Colors.green).withAlpha(35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDev ? 'Deweloperska' : 'Wydanie',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDev ? Colors.amberAccent : Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
            if (u.sourceLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Źródło: ${u.sourceLabel}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withAlpha(170),
                    ),
              ),
            ],
            if (u.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Co nowego:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(u.description),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_needsUnknownSourcesPerm) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withAlpha(110)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Zezwól Androidowi na instalację aktualizacji z tej aplikacji, a następnie kliknij „Zainstaluj ponownie”.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          _updateService.openInstallPermissionSettings(),
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Otwórz uprawnienia instalacji'),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Później'),
        ),
        if (_needsUnknownSourcesPerm)
          FilledButton.icon(
            onPressed: _retryInstallAfterPermission,
            icon: const Icon(Icons.install_mobile),
            label: const Text('Zainstaluj ponownie'),
          )
        else
          FilledButton.icon(
            onPressed: _downloading ? null : _startDownloadAndInstall,
            icon: const Icon(Icons.download),
            label: Text(_downloading ? 'Pobieranie...' : 'Pobierz i aktualizuj'),
          ),
      ],
    );
  }
}
