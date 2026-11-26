import 'package:flutter/material.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/purevideo_logo.dart';
import 'package:purevideo/presentation/settings/widgets/settings_item.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';
import 'package:purevideo/presentation/settings/widgets/settings_section.dart';

class ThemeScreen extends StatefulWidget {
  const ThemeScreen({super.key});

  @override
  State<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends State<ThemeScreen> {
  final SettingsService _settingsService = getIt<SettingsService>();

  Future<void> _selectAppIcon(String key, String displayName) async {
    await _settingsService.setAppIcon(key);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Zmieniono ikonę i nazwę aplikacji na: $displayName (zmiana na ekranie głównym może potrwać kilka sekund)',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildIconBadge({
    required Color bg,
    required Color fg,
    required String letter,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 20,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildIconRadio({
    required String value,
    required String groupValue,
    required String displayName,
    required Widget badge,
  }) {
    return ExcludeFocus(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge,
          const SizedBox(width: 4),
          Radio<String>(
            value: value,
            groupValue: groupValue,
            activeColor: kPureVideoRed,
            onChanged: (val) {
              if (val != null) {
                _selectAppIcon(val, displayName);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motywy'),
        centerTitle: true,
      ),
      body: SettingsListenable(
        builder: (context, box, _) {
          final currentStyle = _settingsService.uiStyle;
          final currentIcon = _settingsService.appIcon;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsSection(
                  title: 'Styl interfejsu',
                  items: [
                    SettingsItem(
                      icon: Icons.movie_filter_outlined,
                      title: 'Netflix (PureVideo)',
                      subtitle:
                          'Ciemny motyw kinowy z dużym banerem polecanych, kategoriami i sekcją „Ostatnio oglądane”',
                      onTap: () {
                        setState(() {
                          _settingsService.setUiStyle('netflix');
                        });
                      },
                      trailing: ExcludeFocus(
                        child: Radio<String>(
                          value: 'netflix',
                          groupValue: currentStyle,
                          activeColor: kPureVideoRed,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _settingsService.setUiStyle(val);
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    SettingsItem(
                      icon: Icons.grid_view_rounded,
                      title: 'Oryginalny (PureVideo)',
                      subtitle:
                          'Klasyczny widok siatki filmów z szybkim dostępem',
                      onTap: () {
                        setState(() {
                          _settingsService.setUiStyle('original');
                        });
                      },
                      trailing: ExcludeFocus(
                        child: Radio<String>(
                          value: 'original',
                          groupValue: currentStyle,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _settingsService.setUiStyle(val);
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                if (currentStyle == 'original') ...[
                  const SizedBox(height: 20),
                  SettingsSection(
                    title: 'Jasność motywu oryginalnego',
                    items: [
                      SettingsItem(
                        icon: Icons.dark_mode_outlined,
                        title: 'Tryb ciemny',
                        subtitle: 'Włącz lub wyłącz tryb ciemny',
                        onTap: () {
                          if (_settingsService.isSystemBrightness) return;
                          setState(() {
                            _settingsService.setDarkMode(
                              !_settingsService.isDarkMode,
                            );
                          });
                        },
                        trailing: ExcludeFocus(
                          child: Switch(
                            value: _settingsService.isDarkMode,
                            activeColor: _settingsService.isSystemBrightness
                                ? Colors.grey
                                : null,
                            onChanged: (value) {
                              if (_settingsService.isSystemBrightness) return;
                              setState(() {
                                _settingsService.setDarkMode(value);
                              });
                            },
                          ),
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.brightness_auto_outlined,
                        title: 'Tryb systemowy',
                        subtitle: 'Dopasuj jasność do ustawień urządzenia',
                        onTap: () {
                          setState(() {
                            _settingsService.setSystemBrightness(
                              !_settingsService.isSystemBrightness,
                            );
                          });
                        },
                        trailing: ExcludeFocus(
                          child: Switch(
                            value: _settingsService.isSystemBrightness,
                            onChanged: (value) {
                              setState(() {
                                _settingsService.setSystemBrightness(value);
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                SettingsSection(
                  title: 'Ikona i nazwa aplikacji',
                  items: [
                    SettingsItem(
                      icon: Icons.apps_rounded,
                      title: 'PureVideo (Spójna ikona)',
                      subtitle:
                          'Domyślna ikona P▶, baner TV i nazwa „PureVideo”',
                      onTap: () => _selectAppIcon('default', 'PureVideo'),
                      trailing: _buildIconRadio(
                        value: 'default',
                        groupValue: currentIcon,
                        displayName: 'PureVideo',
                        badge: const PureVideoMark(
                          size: 36,
                          withDarkTile: true,
                        ),
                      ),
                    ),
                    SettingsItem(
                      icon: Icons.tv_rounded,
                      title: 'Netflix',
                      subtitle:
                          'Czerwone logo „N” oraz nazwa aplikacji „Netflix”',
                      onTap: () => _selectAppIcon('netflix', 'Netflix'),
                      trailing: _buildIconRadio(
                        value: 'netflix',
                        groupValue: currentIcon,
                        displayName: 'Netflix',
                        badge: _buildIconBadge(
                          bg: const Color(0xFF000000),
                          fg: kPureVideoRed,
                          letter: 'N',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
