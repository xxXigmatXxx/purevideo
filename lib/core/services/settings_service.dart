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
  static const String _cachedHomeMoviesKey = 'cachedHomeMoviesJson_v2';
  static const String _linklessUrlsKey = 'linklessUrlsJson_v1';
  static const String _verifiedUrlsKey = 'verifiedUrlsJson_v1';
  static const String _uiStyleKey = 'uiStyle'; // 'netflix' or 'original'
  static const String _appIconKey = 'appIcon'; // 'default' or 'netflix'

  static const MethodChannel _iconChannel = MethodChannel('purevideo/app_icon');

  late final Box box;
  final Set<String> _linklessUrls = {};
  final Set<String> _verifiedUrls = {};

  Future<void> init() async {
    try {
      box = await Hive.openBox('settings');
    } catch (e) {
      await Hive.deleteBoxFromDisk('settings');
      box = await Hive.openBox('settings');
    }
    _loadUrlCaches();
  }

  void _loadUrlCaches() {
    try {
      final rawLinkless = box.get(_linklessUrlsKey) as String?;
      if (rawLinkless != null && rawLinkless.isNotEmpty) {
        final list = (jsonDecode(rawLinkless) as List).map((e) => e.toString());
        _linklessUrls.addAll(list);
      }
    } catch (_) {}
    try {
      final rawVerified = box.get(_verifiedUrlsKey) as String?;
      if (rawVerified != null && rawVerified.isNotEmpty) {
        final list = (jsonDecode(rawVerified) as List).map((e) => e.toString());
        _verifiedUrls.addAll(list);
      }
    } catch (_) {}
  }

  bool isUrlLinkless(String url) => _linklessUrls.contains(url.trim());

  bool isUrlVerified(String url) => _verifiedUrls.contains(url.trim());

  void markUrlVerified(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;
    if (_verifiedUrls.add(clean)) {
      _linklessUrls.remove(clean);
      try {
        box.put(_verifiedUrlsKey, jsonEncode(_verifiedUrls.take(1500).toList()));
      } catch (_) {}
    }
  }

  void markUrlLinkless(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;
    if (_linklessUrls.add(clean)) {
      _verifiedUrls.remove(clean);
      try {
        box.put(_linklessUrlsKey, jsonEncode(_linklessUrls.take(1500).toList()));
      } catch (_) {}
      // Also remove from cached home movies immediately
      final cached = getCachedHomeMovies();
      if (cached.isNotEmpty) {
        final filtered = cached
            .map((m) {
              final validServices = m.services
                  .where((s) => !_linklessUrls.contains(s.url.trim()))
                  .toList();
              return validServices.isEmpty
                  ? null
                  : MovieModel(services: validServices);
            })
            .whereType<MovieModel>()
            .toList();
        if (filtered.length != cached.length) {
          setCachedHomeMovies(filtered);
        }
      }
    }
  }

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
                  if (sName == 'ekino') return null;
                  final url = s['url']?.toString().trim() ?? '';
                  final title = s['title']?.toString().trim() ?? '';
                  final imageUrl = s['imageUrl']?.toString().trim() ?? '';
                  if (url.isEmpty ||
                      title.isEmpty ||
                      title == 'Brak danych' ||
                      _linklessUrls.contains(url)) {
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
                    .where((s) =>
                        s.service != SupportedService.ekino &&
                        !_linklessUrls.contains(s.url.trim()))
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
                  if (sName == 'ekino') return null;
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
