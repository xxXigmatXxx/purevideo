import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';

class SettingsService {
  static const String _isDeveloperModeKey = 'isDeveloperMode';
  static const String _isDebugVisibleKey = 'isDebugVisible';
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _isSystemBrightnessKey = 'isSystemBrightness';
  static const String _myListKey = 'myListJson';
  static const String _cachedHomeMoviesKey = 'cachedHomeMoviesJson_v7';
  static const String _linklessUrlsKey = 'linklessUrlsJson_v1';
  static const String _verifiedUrlsKey = 'verifiedUrlsJson_v1';
  static const String _uiStyleKey = 'uiStyle'; // 'netflix' or 'original'
  static const String _appIconKey = 'appIcon'; // 'default' or 'netflix'

  static const MethodChannel _iconChannel = MethodChannel('purevideo/app_icon');

  late final Box box;

  Future<void> init() async {
    try {
      box = await Hive.openBox('settings');
    } catch (e) {
      await Hive.deleteBoxFromDisk('settings');
      box = await Hive.openBox('settings');
    }
    try {
      await box.delete(_linklessUrlsKey);
      await box.delete(_verifiedUrlsKey);
    } catch (_) {}
  }

  bool isUrlLinkless(String url) => false;

  bool isUrlVerified(String url) => true;

  void markUrlVerified(String url) {}

  void markUrlLinkless(String url) {}

  List<MovieModel> getCachedHomeMovies() {
    try {
      final raw = box.get(_cachedHomeMoviesKey) as String?;
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((item) {
            final services = ((item['services'] as List?) ?? [])
                .map((s) {
                  final sName = s['service']?.toString() ?? '';
                  
                  final url = s['url']?.toString().trim() ?? '';
                  final title = s['title']?.toString().trim() ?? '';
                  final imageUrl = s['imageUrl']?.toString().trim() ?? '';
                  if (url.isEmpty ||
                      title.isEmpty ||
                      title == 'Brak danych') {
                    return null;
                  }
                  return ServiceMovieModel(
                    service: SupportedService.values.firstWhere(
                      (e) => e.name == sName,
                      orElse: () => SupportedService.filman,
                    ),
                    url: url,
                    title: title,
                    imageUrl: imageUrl,
                    category: s['category']?.toString(),
                  );
                })
                .whereType<ServiceMovieModel>()
                .toList();
            return services.isEmpty ? null : MovieModel(services: services);
          })
          .whereType<MovieModel>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  void setCachedHomeMovies(List<MovieModel> movies) {
    try {
      final encoded = jsonEncode(movies
          .map((m) => {
                'services': m.services
                    
                    .map((s) => {
                          'service': s.service.name,
                          'url': s.url,
                          'title': s.title,
                          'imageUrl': s.imageUrl,
                          'category': s.category,
                        })
                    .toList(),
              })
          .where((m) => (m['services'] as List).isNotEmpty)
          .toList());
      box.put(_cachedHomeMoviesKey, encoded);
    } catch (_) {}
  }

  String get uiStyle => (box.get(_uiStyleKey) as String?) ?? 'netflix';

  bool get isNetflixStyle => uiStyle == 'netflix';

  void setUiStyle(String style) {
    box.put(_uiStyleKey, style);
  }

  String get appIcon {
    final val = (box.get(_appIconKey) as String?) ?? 'default';
    if (val != 'default' && val != 'netflix') return 'default';
    return val;
  }

  Future<void> setAppIcon(String iconKey) async {
    final normalized = (iconKey == 'netflix') ? 'netflix' : 'default';
    await box.put(_appIconKey, normalized);
    try {
      await _iconChannel.invokeMethod('setIcon', {'icon': normalized});
    } catch (e) {
      debugPrint('Failed to change launcher icon: $e');
    }
  }

  List<MovieModel> getMyList() {
    try {
      final raw = box.get(_myListKey) as String?;
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((item) {
            final services = ((item['services'] as List?) ?? [])
                .map((s) {
                  final sName = s['service']?.toString() ?? '';
                  
                  return ServiceMovieModel(
                    service: SupportedService.values.firstWhere(
                      (e) => e.name == sName,
                      orElse: () => SupportedService.filman,
                    ),
                    url: s['url']?.toString() ?? '',
                    title: s['title']?.toString() ?? '',
                    imageUrl: s['imageUrl']?.toString() ?? '',
                    category: s['category']?.toString(),
                  );
                })
                .whereType<ServiceMovieModel>()
                .toList();
            return services.isEmpty ? null : MovieModel(services: services);
          })
          .whereType<MovieModel>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool isInMyList(MovieModel movie) {
    final urls = movie.services.map((s) => s.url).toSet();
    return getMyList().any(
      (m) =>
          m.services.any((s) => urls.contains(s.url)) || m.title == movie.title,
    );
  }

  void toggleMyList(MovieModel movie) {
    final current = getMyList();
    final urls = movie.services.map((s) => s.url).toSet();
    final idx = current.indexWhere(
      (m) =>
          m.services.any((s) => urls.contains(s.url)) || m.title == movie.title,
    );
    if (idx != -1) {
      current.removeAt(idx);
    } else {
      current.insert(0, movie);
    }
    final encoded = jsonEncode(current
        .map((m) => {
              'services': m.services
                  .map((s) => {
                        'service': s.service.name,
                        'url': s.url,
                        'title': s.title,
                        'imageUrl': s.imageUrl,
                        'category': s.category,
                      })
                  .toList(),
            })
        .toList());
    box.put(_myListKey, encoded);
  }

  bool get isDeveloperMode =>
      bool.parse(box.get(_isDeveloperModeKey) ?? 'false');

  void setDeveloperMode(bool value) {
    box.put(_isDeveloperModeKey, value.toString());
  }

  bool get isDebugVisible => bool.parse(box.get(_isDebugVisibleKey) ?? 'false');

  void setDebugVisible(bool value) {
    box.put(_isDebugVisibleKey, value.toString());
  }

  bool get isDarkMode => bool.parse(box.get(_isDarkModeKey) ?? 'true');

  void setDarkMode(bool value) {
    box.put(_isDarkModeKey, value.toString());
  }

  bool get isSystemBrightness =>
      bool.parse(box.get(_isSystemBrightnessKey) ?? 'false');

  void setSystemBrightness(bool value) {
    box.put(_isSystemBrightnessKey, value.toString());
  }

  ThemeMode get theme {
    if (isNetflixStyle) {
      return ThemeMode.dark;
    }
    if (isSystemBrightness) {
      return ThemeMode.system;
    } else if (isDarkMode) {
      return ThemeMode.dark;
    } else {
      return ThemeMode.light;
    }
  }
}
