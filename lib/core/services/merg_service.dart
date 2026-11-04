import 'package:flutter/material.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:diacritic/diacritic.dart';

class MergeService {
  final List<MovieModel> _movies = [];
  static final _nonWordRegex = RegExp(r'[^\w\s]');
  static final _spacesRegex = RegExp(r'\s+');

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

  Future<void> addFromService(List<ServiceMovieModel> movies) async {
    if (movies.isEmpty) return;
    for (final movie in movies) {
      final normalizedTitle = _normalizeTitle(movie.title);

      final existingMovieIndex = _movies.indexWhere(
        (existingMovie) =>
            _normalizeTitle(existingMovie.services.first.title) ==
            normalizedTitle,
      );

      if (existingMovieIndex != -1) {
        final existingMovie = _movies[existingMovieIndex];
        final existingSvcIdx = existingMovie.services.indexWhere(
          (service) => service.service == movie.service,
        );

        if (existingSvcIdx == -1) {
          final updatedServices = [...existingMovie.services, movie];
          _movies[existingMovieIndex] = MovieModel(services: updatedServices);
        } else {
          final oldSvc = existingMovie.services[existingSvcIdx];
          final mergedCat = _mergeCategoryStrings(oldSvc.category, movie.category);
          if (mergedCat != oldSvc.category) {
            final updatedServices = List<ServiceMovieModel>.from(existingMovie.services);
            updatedServices[existingSvcIdx] = ServiceMovieModel(
              service: oldSvc.service,
              url: oldSvc.url,
              title: oldSvc.title,
              imageUrl: oldSvc.imageUrl,
              category: mergedCat,
            );
            _movies[existingMovieIndex] = MovieModel(services: updatedServices);
          }
        }
      } else {
        _movies.add(MovieModel(services: [movie]));
      }
    }
  }

  Future<List<MovieModel>> addFromServiceTemp(
      List<ServiceMovieModel> toAdd, List<MovieModel> existingMovies) async {
    if (toAdd.isEmpty) return [];
    for (final movie in toAdd) {
      final normalizedTitle = _normalizeTitle(movie.title);

      final existingMovieIndex = existingMovies.indexWhere(
        (existingMovie) =>
            _normalizeTitle(existingMovie.services.first.title) ==
            normalizedTitle,
      );

      if (existingMovieIndex != -1) {
        final existingMovie = existingMovies[existingMovieIndex];
        final existingSvcIdx = existingMovie.services.indexWhere(
          (service) => service.service == movie.service,
        );

        if (existingSvcIdx == -1) {
          final updatedServices = [...existingMovie.services, movie];
          existingMovies[existingMovieIndex] =
              MovieModel(services: updatedServices);
        } else {
          final oldSvc = existingMovie.services[existingSvcIdx];
          final mergedCat = _mergeCategoryStrings(oldSvc.category, movie.category);
          if (mergedCat != oldSvc.category) {
            final updatedServices =
                List<ServiceMovieModel>.from(existingMovie.services);
            updatedServices[existingSvcIdx] = ServiceMovieModel(
              service: oldSvc.service,
              url: oldSvc.url,
              title: oldSvc.title,
              imageUrl: oldSvc.imageUrl,
              category: mergedCat,
            );
            existingMovies[existingMovieIndex] =
                MovieModel(services: updatedServices);
          }
        }
      } else {
        existingMovies.add(MovieModel(services: [movie]));
      }
    }
    return existingMovies;
  }

  List<MovieModel> get getMovies => _movies;

  String _normalizeTitle(String title) {
    return removeDiacritics(title
        .toLowerCase()
        .trim()
        .replaceAll(_nonWordRegex, '')
        .replaceAll(_spacesRegex, ' ')
        .replaceAll(' ', '')
        .trim());
  }
}
