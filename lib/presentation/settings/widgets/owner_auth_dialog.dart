import 'package:flutter/material.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/di/injection_container.dart';

class OwnerAuthGate {
  static Future<String?> authorizeEntry(
    BuildContext context, {
    bool forceSetup = false,
  }) async {
    final extraSources = getIt<ExtraSourcesService>();
    final hasOwner =
        !forceSetup && await extraSources.hasVerifiedOwnerCredentials();
    if (!context.mounted) return null;

    if (!hasOwner) {
      return _showSetupOwnerDialog(context, extraSources);
    }

    final pinCtrl = TextEditingController();
    String? errText;
    bool busy = false;
    bool requestReset = false;

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined, size: 22),
              SizedBox(width: 8),
              Expanded(child: Text('Zatwierdzenie administratora')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aby wejść do zakładki Źródła dodatkowe i Panelu Admina, podaj swój PIN administratora.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                onSubmitted: (_) async {
                  if (busy) return;
                  setDlgState(() {
                    busy = true;
                    errText = null;
                  });
                  final ok = await extraSources.verifyPin(pinCtrl.text);
                  if (!ctx.mounted) return;
                  if (ok) {
                    final clean = pinCtrl.text.trim();
                    extraSources.unlockAdminSession(clean);
                    Navigator.of(ctx).pop(clean);
                  } else {
                    setDlgState(() {
                      busy = false;
                      errText = 'Nieprawidłowy PIN administratora.';
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'PIN administratora',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errText!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          requestReset = true;
                          Navigator.of(ctx).pop();
                        },
                  child: const Text('Zresetuj / podaj nowy token GitHub'),
                ),
              ),
            ],
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
                      final ok = await extraSources.verifyPin(pinCtrl.text);
                      if (!ctx.mounted) return;
                      if (ok) {
                        final clean = pinCtrl.text.trim();
                        extraSources.unlockAdminSession(clean);
                        Navigator.of(ctx).pop(clean);
                      } else {
                        setDlgState(() {
                          busy = false;
                          errText = 'Nieprawidłowy PIN administratora.';
                        });
                      }
                    },
              child: const Text('Odblokuj'),
            ),
          ],
        ),
      ),
    );

    if (requestReset && context.mounted) {
      return _showSetupOwnerDialog(context, extraSources);
    }
    return pin;
  }

  static Future<String?> _showSetupOwnerDialog(
    BuildContext context,
    ExtraSourcesService extraSources,
  ) async {
    final tokenCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String? errText;
    bool busy = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 22),
              SizedBox(width: 8),
              Expanded(child: Text('Zatwierdź tryb administratora')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dostęp do zakładki Źródła dodatkowe wymaga weryfikacji konta właściciela repozytorium GitHub (${ExtraSourcesService.repoOwner}) oraz ustawienia PIN-u (4–8 znaków).',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'GitHub Token (PAT)',
                    hintText: 'ghp_... lub github_pat_...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ustaw PIN (4–8 znaków)',
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
                          await extraSources.verifyAndSaveOwnerCredentials(
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
                        final clean = pinCtrl.text.trim();
                        extraSources.unlockAdminSession(clean);
                        Navigator.of(ctx).pop(clean);
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Zweryfikuj i wejdź'),
            ),
          ],
        ),
      ),
    );
  }
}
