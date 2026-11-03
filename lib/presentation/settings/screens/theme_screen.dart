import 'package:flutter/material.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/di/injection_container.dart';
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
    IconData? icon,
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
      child: icon != null
          ? Icon(icon, color: fg, size: 20)
          : Text(
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 4),
        Radio<String>(
          value: value,
          groupValue: groupValue,
          activeColor: const Color(0xFFE50914),
          onChanged: (val) {
            if (val != null) {
              _selectAppIcon(val, displayName);
            }
          },
        ),
      ],
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
                      trailing: Radio<String>(
                        value: 'netflix',
                        groupValue: currentStyle,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _settingsService.setUiStyle(val);
                            });
                          }
                        },
                      ),
                    ),
                    SettingsItem(
                      icon: Icons.grid_view_rounded,
                      title: 'Oryginalny (PureVideo)',
                      subtitle:
                          'Klasyczny fioletowy wygląd Material 3 z siatką filmów',
                      onTap: () {
                        setState(() {
                          _settingsService.setUiStyle('original');
                        });
                      },
                      trailing: Radio<String>(
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
                        trailing: Switch(
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
                      SettingsItem(
                        icon: Icons.brightness_auto_outlined,
                        title: 'Tryb systemowy',
                        subtitle: 'Dopasuj jasność do ustawień telefonu',
                        onTap: () {
                          setState(() {
                            _settingsService.setSystemBrightness(
                              !_settingsService.isSystemBrightness,
                            );
                          });
                        },
                        trailing: Switch(
                          value: _settingsService.isSystemBrightness,
                          onChanged: (value) {
                            setState(() {
                              _settingsService.setSystemBrightness(value);
                            });
                          },
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
                      title: 'Oryginalna (PureVideo)',
                      subtitle: 'Domyślna ikona i nazwa „PureVideo”',
                      onTap: () => _selectAppIcon('default', 'PureVideo'),
                      trailing: _buildIconRadio(
                        value: 'default',
                        groupValue: currentIcon,
                        displayName: 'PureVideo',
                        badge: _buildIconBadge(
                          bg: const Color(0xFF4A148C),
                          fg: Colors.white,
                          letter: 'P',
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
                          fg: const Color(0xFFE50914),
                          letter: 'N',
                        ),
                      ),
                    ),
                    SettingsItem(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Obejrzyj.to',
                      subtitle:
                          'Ikona odtwarzacza oraz nazwa aplikacji „Obejrzyj.to”',
                      onTap: () => _selectAppIcon('obejrzyjto', 'Obejrzyj.to'),
                      trailing: _buildIconRadio(
                        value: 'obejrzyjto',
                        groupValue: currentIcon,
                        displayName: 'Obejrzyj.to',
                        badge: _buildIconBadge(
                          bg: const Color(0xFF10131A),
                          fg: const Color(0xFFE50914),
                          letter: 'O',
                          icon: Icons.play_circle_fill,
                        ),
                      ),
                    ),
                    SettingsItem(
                      icon: Icons.local_movies_outlined,
                      title: 'Filman.cc',
                      subtitle:
                          'Niebieskie logo „F” oraz nazwa aplikacji „Filman.cc”',
                      onTap: () => _selectAppIcon('filman', 'Filman.cc'),
                      trailing: _buildIconRadio(
                        value: 'filman',
                        groupValue: currentIcon,
                        displayName: 'Filman.cc',
                        badge: _buildIconBadge(
                          bg: const Color(0xFF0B192C),
                          fg: const Color(0xFF1E88E5),
                          letter: 'F',
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
