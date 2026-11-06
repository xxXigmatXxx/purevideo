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

  void _mergeIntoList(List<ServiceMovieModel> movies, List<MovieModel> target) {
    for (final movie in movies) {
      final normalizedTitle = _normalizeTitle(movie.title);
      final existingMovieIndex = target.indexWhere(
        (existingMovie) =>
            _normalizeTitle(existingMovie.services.first.title) ==
            normalizedTitle,
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
          final updatedServices =
              List<ServiceMovieModel>.from(existingMovie.services);
          if (mergedCat != oldSvc.category) {
            updatedServices[existingSvcIdx] = ServiceMovieModel(
              service: oldSvc.service,
              url: oldSvc.url,
              title: oldSvc.title,
              imageUrl: oldSvc.imageUrl,
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
