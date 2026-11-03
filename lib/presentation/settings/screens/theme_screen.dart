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
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: fg, size: 22)
          : Text(
              letter,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                height: 1.0,
              ),
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
                    ListTile(
                      leading: _buildIconBadge(
                        bg: const Color(0xFF4A148C),
                        fg: Colors.white,
                        letter: 'P',
                      ),
                      title: const Text(
                        'Oryginalna (PureVideo)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Domyślna ikona i nazwa „PureVideo”',
                      ),
                      trailing: Radio<String>(
                        value: 'default',
                        groupValue: currentIcon,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          if (val != null) {
                            _selectAppIcon(val, 'PureVideo');
                          }
                        },
                      ),
                      onTap: () => _selectAppIcon('default', 'PureVideo'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _buildIconBadge(
                        bg: const Color(0xFF000000),
                        fg: const Color(0xFFE50914),
                        letter: 'N',
                      ),
                      title: const Text(
                        'Netflix',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Czerwone logo „N” oraz nazwa aplikacji „Netflix”',
                      ),
                      trailing: Radio<String>(
                        value: 'netflix',
                        groupValue: currentIcon,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          if (val != null) {
                            _selectAppIcon(val, 'Netflix');
                          }
                        },
                      ),
                      onTap: () => _selectAppIcon('netflix', 'Netflix'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _buildIconBadge(
                        bg: const Color(0xFF10131A),
                        fg: const Color(0xFFE50914),
                        letter: 'O',
                        icon: Icons.play_circle_fill,
                      ),
                      title: const Text(
                        'Obejrzyj.to',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Ikona odtwarzacza oraz nazwa aplikacji „Obejrzyj.to”',
                      ),
                      trailing: Radio<String>(
                        value: 'obejrzyjto',
                        groupValue: currentIcon,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          if (val != null) {
                            _selectAppIcon(val, 'Obejrzyj.to');
                          }
                        },
                      ),
                      onTap: () => _selectAppIcon('obejrzyjto', 'Obejrzyj.to'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _buildIconBadge(
                        bg: const Color(0xFF0B192C),
                        fg: const Color(0xFF1E88E5),
                        letter: 'F',
                      ),
                      title: const Text(
                        'Filman.cc',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Niebieskie logo „F” oraz nazwa aplikacji „Filman.cc”',
                      ),
                      trailing: Radio<String>(
                        value: 'filman',
                        groupValue: currentIcon,
                        activeColor: const Color(0xFFE50914),
                        onChanged: (val) {
                          if (val != null) {
                            _selectAppIcon(val, 'Filman.cc');
                          }
                        },
                      ),
                      onTap: () => _selectAppIcon('filman', 'Filman.cc'),
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
