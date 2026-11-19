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

  void clear() {
    _movies.clear();
  }

  void replaceAll(List<MovieModel> movies) {
    _movies
      ..clear()
      ..addAll(movies);
  }

  String? _mergeCategoryStrings(String? a, String? b) {
    final parts = <String>{};
    if (a != null && a.trim().isNotEmpty) {
      for (final p in a.split('|')) {
        if (p.trim().isNotEmpty) parts.add(p.trim());
      }
    }
    if (b != null && b.trim().isNotEmpty) {
      for (final p in b.split('|')) {
        if (p.trim().isNotEmpty) parts.add(p.trim());
      }
    }
    return parts.isEmpty ? null : parts.join('|');
  }

  void _mergeIntoList(List<ServiceMovieModel> movies, List<MovieModel> target) {
    for (final movie in movies) {
      final normalizedTitle = normalizeTitle(movie.title);
      if (normalizedTitle.isEmpty) continue;
      final isMovieSeries = _isSeriesEntry(movie);
      final existingMovieIndex = target.indexWhere(
        (existingMovie) =>
            normalizeTitle(existingMovie.services.first.title) ==
                normalizedTitle &&
            existingMovie.services.any(_isSeriesEntry) == isMovieSeries,
      );

      if (existingMovieIndex != -1) {
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
    if (toAdd.isEmpty) return [];
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
    return removeDiacritics(t
        .toLowerCase()
        .replaceAll(_nonWordRegex, '')
        .replaceAll(_spacesRegex, ' ')
        .replaceAll(' ', '')
        .trim());
  }
}
