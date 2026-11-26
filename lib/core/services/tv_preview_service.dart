import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/filmweb/filmweb_info_repository.dart';

class TvMoviePreview {
  final int? year;
  final String plot;
  final String originalTitle;

  const TvMoviePreview({
    this.year,
    required this.plot,
    this.originalTitle = '',
  });
}

/// Lightweight debounced + cached Filmweb metadata provider for TV Hero & Expandable Row preview.
class TvPreviewService extends ChangeNotifier {
  final FilmwebInfoRepository _filmwebRepo;

  TvPreviewService(this._filmwebRepo);

  final Map<String, TvMoviePreview> _cache = {};
  final Set<String> _inFlight = {};
  final Set<String> _failed = {};
  Timer? _debounce;

  String _keyFor(MovieModel movie) {
    final norm = MergeService.normalizeTitle(movie.title);
    final isSeries = movie.services.any((s) {
      final cat = (s.category ?? '').toLowerCase();
      final url = s.url.toLowerCase();
      return cat.contains('serial') ||
          url.contains('/s/') ||
          url.contains('/serie/') ||
          url.contains('serial');
    });
    return '$norm|${isSeries ? "s" : "m"}';
  }

  TvMoviePreview? getCached(MovieModel movie) {
    return _cache[_keyFor(movie)];
  }

  void requestPreview(MovieModel movie) {
    final key = _keyFor(movie);
    if (key.startsWith('|') ||
        _cache.containsKey(key) ||
        _inFlight.contains(key) ||
        _failed.contains(key)) {
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _fetchPreview(movie, key);
    });
  }

  Future<void> _fetchPreview(MovieModel movie, String key) async {
    if (_cache.containsKey(key) || _inFlight.contains(key)) return;
    _inFlight.add(key);

    final isSeries = key.endsWith('|s');
    final cleanQuery = movie.title
        .replaceAll(RegExp(r'\(\d{4}\)'), '')
        .replaceAll(RegExp(r'\b(PL|LEKTOR|NAPISY|DUBBING|HD|CAM|4K)\b', caseSensitive: false), '')
        .trim();

    if (cleanQuery.isEmpty) {
      _inFlight.remove(key);
      return;
    }

    try {
      final hits = await _filmwebRepo
          .searchMovie(cleanQuery, isSeries: isSeries)
          .timeout(const Duration(seconds: 4));

      final match = hits.isNotEmpty
          ? hits.firstWhere(
              (h) => h.plot.trim().isNotEmpty,
              orElse: () => hits.first,
            )
          : null;

      if (match != null) {
        _cache[key] = TvMoviePreview(
          year: match.year > 1900 ? match.year : null,
          plot: match.plot.trim(),
          originalTitle: match.originalTitle.trim(),
        );
        if (_cache.length > 150) {
          _cache.remove(_cache.keys.first);
        }
        notifyListeners();
      } else {
        _failed.add(key);
      }
    } catch (_) {
      _failed.add(key);
    } finally {
      _inFlight.remove(key);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
