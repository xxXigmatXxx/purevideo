import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/app_update_service.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/core/utils/tv_nav_controller.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/settings/widgets/app_update_dialog.dart';
import 'package:purevideo/presentation/settings/widgets/owner_auth_dialog.dart';
import 'package:purevideo/presentation/settings/widgets/settings_item.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';
import 'package:purevideo/presentation/settings/widgets/settings_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = getIt();

  @override
  Widget build(BuildContext context) {
    final isWide = DeviceUtils.isWideLayout(context);
    return Scaffold(
      backgroundColor: isWide ? const Color(0xFF0A0A0D) : null,
      appBar: isWide
          ? null
          : AppBar(title: const Text('Ustawienia'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 48 : 16,
          vertical: isWide ? 18 : 16,
        ),
        children: [
          SettingsSection(
            title: 'Konta',
            items: [
              SettingsItem(
                focusNode: TvNavController.instance.settingsFirstNode,
                icon: Icons.person_outline,
                title: 'Zarządzanie kontami',
                subtitle: 'Dodaj lub usuń konta serwisów',
                onTap: () => context.pushNamed('accounts'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsListenable(
            builder: (context, _, __) {
              return SettingsSection(
                title: 'Źródła',
                items: [
                  SettingsItem(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Źródła dodatkowe',
                    subtitle: _settingsService.extraSourcesEnabled
                        ? 'Włączone • dotknij, aby wejść (wymaga zatwierdzenia admina)'
                        : 'Wyłączone • dotknij, aby wejść (wymaga zatwierdzenia admina)',
                    onTap: () async {
                      final pin = await OwnerAuthGate.authorizeEntry(context);
                      if (pin == null || pin.isEmpty || !context.mounted) {
                        return;
                      }
                      await context.pushNamed('extra_sources');
                    },
                    trailing: ExcludeFocus(
                      child: Switch(
                        value: _settingsService.extraSourcesEnabled,
                        onChanged: (value) {
                          _settingsService.setExtraSourcesEnabled(value);
                          getIt<ExtraSourcesService>().notifyChanged();
                          if (value) {
                            getIt<ExtraSourcesService>().syncRemoteSources();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          SettingsSection(
            title: 'Aplikacja',
            items: [
              SettingsItem(
                icon: Icons.palette_outlined,
                title: 'Motywy',
                subtitle:
                    'Styl interfejsu (Netflix / Oryginalny) oraz ikona i nazwa aplikacji',
                onTap: () {
                  context.pushNamed('theme');
                },
              ),
              SettingsItem(
                icon: Icons.system_update_alt,
                title: 'Aktualizacje',
                subtitle: getIt<AppUpdateService>().availableUpdate.value != null
                    ? 'Dostępna nowa wersja: v${getIt<AppUpdateService>().availableUpdate.value!.version}'
                    : 'Sprawdź dostępność nowej wersji aplikacji',
                onTap: () async {
                  final upd = await getIt<AppUpdateService>()
                      .checkForUpdates(force: true);
                  if (!context.mounted) return;
                  if (upd != null) {
                    await AppUpdateDialog.show(context, upd);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Masz już najnowszą wersję aplikacji.'),
                      ),
                    );
                  }
                },
              ),
              SettingsItem(
                icon: Icons.info_outline,
                title: 'O aplikacji',
                subtitle: 'Informacje o wersji',
                onTap: () {
                  context.pushNamed('about');
                },
              ),
            ],
          ),
          SettingsListenable(
            builder: (context, value, child) {
              if (_settingsService.isDeveloperMode == false) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  const SizedBox(height: 24),
                  SettingsSection(
                    title: 'Opcje deweloperskie',
                    items: [
                      SettingsItem(
                        icon: Icons.bug_report_outlined,
                        title: 'Debugowanie',
                        subtitle: 'Pokaż debugowanie filmów i seriali',
                        onTap: () {
                          setState(() {
                            _settingsService.setDebugVisible(
                                !_settingsService.isDebugVisible);
                          });
                        },
                        trailing: ExcludeFocus(
                          child: Switch(
                            value: _settingsService.isDebugVisible,
                            onChanged: (value) {
                              setState(() {
                                _settingsService.setDebugVisible(value);
                              });
                            },
                          ),
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.developer_mode,
                        title: 'Tryb deweloperski',
                        subtitle: 'Wyłącz tryb deweloperski',
                        onTap: () {
                          setState(() {
                            _settingsService.setDeveloperMode(false);
                          });
                        },
                        trailing: Icon(
                          Icons.close,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          )
        ],
      ),
    );
  }
}
