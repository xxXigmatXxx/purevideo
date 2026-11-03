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
        final hasService = existingMovie.services.any(
          (service) => service.service == movie.service,
        );

        if (!hasService) {
          final updatedServices = [...existingMovie.services, movie];
          _movies[existingMovieIndex] = MovieModel(services: updatedServices);
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
      debugPrint('Normalized Title: $normalizedTitle');

      final existingMovieIndex = existingMovies.indexWhere(
        (existingMovie) =>
            _normalizeTitle(existingMovie.services.first.title) ==
            normalizedTitle,
      );

      if (existingMovieIndex != -1) {
        final existingMovie = existingMovies[existingMovieIndex];
        final hasService = existingMovie.services.any(
          (service) => service.service == movie.service,
        );

        if (!hasService) {
          final updatedServices = [...existingMovie.services, movie];
          existingMovies[existingMovieIndex] =
              MovieModel(services: updatedServices);
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
