import 'dart:collection';

import 'package:diacritic/diacritic.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:purevideo/data/models/movie_model.dart';

class MergeService {
  final List<MovieModel> _movies = [];
  static final _nonWordRegex = RegExp(r'[^\w\s]');
  static final _spacesRegex = RegExp(r'\s+');
  static final _yearSuffixRegex = RegExp(r'\s*\((?:19|20)\d{2}\)\s*$');
  static final _tagSuffixRegex = RegExp(
    r'\s*-\s*(?:HD|CAM|4K|FHD|AI|PL|Dubbing|Lektor|Napisy)(?:\s+.*)?$',
    caseSensitive: false,
  );
  static final LinkedHashMap<String, String> _normCache = LinkedHashMap();
  static const int _maxNormCache = 1200;

  void clear() {
    _movies.clear();
  }

  void replaceAll(List<MovieModel> movies) {
    _movies
      ..clear()
      ..addAll(movies);
  }

  String? _mergeCategoryStrings(String? a, String? b) {
    if (b == null || b.trim().isEmpty) return a;
    if (a == null || a.trim().isEmpty) return b;
    final parts = <String>{};
    for (final p in a.split('|')) {
      final t = p.trim();
      if (t.isNotEmpty) parts.add(t);
    }
    for (final p in b.split('|')) {
      final t = p.trim();
      if (t.isNotEmpty) parts.add(t);
    }
    return parts.isEmpty ? null : parts.join('|');
  }

  String _movieKey(String normalizedTitle, bool isSeries) =>
      '$normalizedTitle|${isSeries ? 1 : 0}';

  void _mergeIntoList(List<ServiceMovieModel> movies, List<MovieModel> target) {
    // Build O(1) lookup index instead of O(N^2) indexWhere + normalizeTitle per pair
    final indexByKey = <String, int>{};
    for (int i = 0; i < target.length; i++) {
      final existing = target[i];
      if (existing.services.isEmpty) continue;
      final norm = normalizeTitle(existing.services.first.title);
      if (norm.isEmpty) continue;
      final isSeries = existing.services.any(_isSeriesEntry);
      indexByKey.putIfAbsent(_movieKey(norm, isSeries), () => i);
    }

    for (final movie in movies) {
      final normalizedTitle = normalizeTitle(movie.title);
      if (normalizedTitle.isEmpty) continue;
      final isMovieSeries = _isSeriesEntry(movie);
      final key = _movieKey(normalizedTitle, isMovieSeries);
      final existingMovieIndex = indexByKey[key];

      if (existingMovieIndex != null) {
        final existingMovie = target[existingMovieIndex];
        final existingSvcIdx = existingMovie.services.indexWhere(
          (service) => service.service == movie.service,
        );
        if (existingSvcIdx == -1) {
          final updatedServices = [...existingMovie.services, movie];
          target[existingMovieIndex] = MovieModel(services: updatedServices);
        } else {
          final oldSvc = existingMovie.services[existingSvcIdx];
          final mergedCat =
              _mergeCategoryStrings(oldSvc.category, movie.category);
          final betterImg =
              (oldSvc.imageUrl.trim().isEmpty && movie.imageUrl.trim().isNotEmpty)
                  ? movie.imageUrl
                  : oldSvc.imageUrl;
          final updatedServices =
              List<ServiceMovieModel>.from(existingMovie.services);
          if (mergedCat != oldSvc.category || betterImg != oldSvc.imageUrl) {
            updatedServices[existingSvcIdx] = ServiceMovieModel(
              service: oldSvc.service,
              url: oldSvc.url,
              title: oldSvc.title,
              imageUrl: betterImg,
              category: mergedCat,
            );
          }
          final sameServiceCount = updatedServices
              .where((s) => s.service == movie.service)
              .length;
          final alreadyHasUrl =
              updatedServices.any((s) => s.url == movie.url);
          if (!alreadyHasUrl && sameServiceCount < 3) {
            updatedServices.add(movie);
          }
          target[existingMovieIndex] = MovieModel(services: updatedServices);
        }
      } else {
        indexByKey[key] = target.length;
        target.add(MovieModel(services: [movie]));
      }
    }
  }

  Future<void> addFromService(List<ServiceMovieModel> movies) async {
    if (movies.isEmpty) return;
    _mergeIntoList(movies, _movies);
  }

  Future<List<MovieModel>> addFromServiceTemp(
      List<ServiceMovieModel> toAdd, List<MovieModel> existingMovies) async {
    if (toAdd.isEmpty) return existingMovies;
    _mergeIntoList(toAdd, existingMovies);
    return existingMovies;
  }

  List<MovieModel> get getMovies => _movies;

  bool _isSeriesEntry(ServiceMovieModel m) {
    final u = m.url.toLowerCase();
    final c = (m.category ?? '').toLowerCase();
    return u.contains('/serie/') ||
        u.contains('/s/') ||
        u.contains('serial') ||
        c.contains('serial');
  }

  static String normalizeTitle(String title) {
    final cached = _normCache[title];
    if (cached != null) return cached;

    var t = title;
    if (t.contains('&')) {
      try {
        t = html_parser.parseFragment(t).text ?? t;
      } catch (_) {}
    }
    t = t.replaceAll('\u00a0', ' ').trim();
    if (t.contains(' / ')) {
      final first = t.split(' / ').first.trim();
      if (first.isNotEmpty) t = first;
    }
    t = t.replaceAll(_tagSuffixRegex, '').replaceAll(_yearSuffixRegex, '').trim();
    final result = removeDiacritics(t
        .toLowerCase()
        .replaceAll(_nonWordRegex, '')
        .replaceAll(_spacesRegex, ' ')
        .replaceAll(' ', '')
        .trim());

    _normCache[title] = result;
    if (_normCache.length > _maxNormCache) {
      _normCache.remove(_normCache.keys.first);
    }
    return result;
  }
}
