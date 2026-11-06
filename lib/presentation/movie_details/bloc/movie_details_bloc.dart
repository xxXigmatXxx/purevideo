import 'dart:async';
import 'package:diacritic/diacritic.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/movie_details/bloc/movie_details_event.dart';
import 'package:purevideo/presentation/movie_details/bloc/movie_details_state.dart';

class MovieDetailsBloc extends Bloc<MovieDetailsEvent, MovieDetailsState> {
  final Map<SupportedService, MovieRepository> _movieRepositories = getIt();
  final Map<SupportedService, SearchRepository> _searchRepositories = getIt();
  final Map<SupportedService, AuthRepository> _authRepositories = getIt();
  final VideoSourceRepository _videoSourceRepository = getIt();
  final MergeService _mergeService = getIt();
  final WatchedService _watchedService = getIt();

  static final _nonWordRegex = RegExp(r'[^\w\s]');
  static final _spacesRegex = RegExp(r'\s+');

  MovieDetailsBloc() : super(const MovieDetailsState()) {
    on<LoadMovieDetails>(_onLoadMovieDetails);
    on<LoadFilmwebMovieDetails>(_onLoadFilmwebMovieDetails);
    on<ScrapeVideoUrls>(_onScrapeVideoUrls);
    on<SelectSeason>(_onSelectSeason);
    on<UpdateWatchedStatus>(_onUpdateWatchedStatus);
  }

  String _normTitle(String title) {
    return removeDiacritics(title
        .toLowerCase()
        .trim()
        .replaceAll(_nonWordRegex, '')
        .replaceAll(_spacesRegex, '')
        .trim());
  }

  Future<void> _onLoadFilmwebMovieDetails(
      LoadFilmwebMovieDetails event, Emitter<MovieDetailsState> emit) async {
    try {
      bool hasLoggedInUser = false;
      for (final entry in _authRepositories.entries) {
        final account = entry.value.getAccount();
        if (account != null) {
          hasLoggedInUser = true;
          break;
        }
      }

      if (!hasLoggedInUser) {
        emit(state.copyWith(
          errorMessage: 'Nie jesteś zalogowany do żadnego serwisu',
        ));
        return;
      }

      final results = <MovieModel>[];
      final loggedServiceEntries = _searchRepositories.entries
          .where((entry) => _authRepositories[entry.key]?.getAccount() != null)
          .toList();

      if (loggedServiceEntries.isNotEmpty) {
        final searchFutures =
            loggedServiceEntries.map((loggedServiceEntry) async {
          final q1 = event.movie.title.trim().isNotEmpty
              ? event.movie.title.trim()
              : event.movie.originalTitle.trim();
          var r = await loggedServiceEntry.value
              .searchMovies(q1)
              .timeout(const Duration(seconds: 7), onTimeout: () => []);
          if (r.isEmpty &&
              event.movie.originalTitle.trim().isNotEmpty &&
              event.movie.originalTitle.trim() != q1) {
            try {
              r = await loggedServiceEntry.value
                  .searchMovies(event.movie.originalTitle.trim())
                  .timeout(const Duration(seconds: 7), onTimeout: () => []);
            } catch (_) {}
          }
          return r;
        }).toList();

        final searchLists = await Future.wait(searchFutures);

        for (final result in searchLists) {
          await _mergeService.addFromServiceTemp(result, results);
        }

        if (results.isEmpty) {
          emit(state.copyWith(
            errorMessage:
                'Nie znaleziono wideo dla: ${event.movie.title.isNotEmpty ? event.movie.title : event.movie.originalTitle}.',
            isLoaded: true,
          ));
          return;
        }

        add(LoadMovieDetails(movie: results.first));
      } else {
        emit(state.copyWith(
          errorMessage: 'Nie jesteś zalogowany do żadnego serwisu',
        ));
        return;
      }
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Nie udało się załadować szczegółów filmu: $e',
      ));
    }
  }

  Future<void> _onLoadMovieDetails(
      LoadMovieDetails event, Emitter<MovieDetailsState> emit) async {
    try {
      final candidateServices =
          List<ServiceMovieModel>.from(event.movie.services);
      final existingTypes = candidateServices.map((s) => s.service).toSet();
      final baseTitle = event.movie.title.trim();
      final normBase = _normTitle(baseTitle);

      // Cross-search other logged-in services (e.g. Ekino <-> Obejrzyj.to) so every movie gets all available sources
      if (baseTitle.isNotEmpty && normBase.isNotEmpty) {
        final missingSearchEntries = _searchRepositories.entries
            .where((entry) =>
                !existingTypes.contains(entry.key) &&
                _authRepositories[entry.key]?.getAccount() != null)
            .toList();

        if (missingSearchEntries.isNotEmpty) {
          final extraLists = await Future.wait(
            missingSearchEntries.map((entry) async {
              try {
                return await entry.value
                    .searchMovies(baseTitle)
                    .timeout(const Duration(seconds: 5), onTimeout: () => []);
              } catch (_) {
                return <ServiceMovieModel>[];
              }
            }),
          );
          for (final list in extraLists) {
            for (final item in list) {
              if (_normTitle(item.title) == normBase &&
                  !candidateServices.any((s) => s.service == item.service)) {
                candidateServices.add(item);
                break;
              }
            }
          }
        }
      }

      final services = <ServiceMovieDetailsModel>[];
      final detailsFutures = <Future<ServiceMovieDetailsModel?>>[];

      for (final serivceMovie in candidateServices) {
        final authRepository = _authRepositories[serivceMovie.service];
        if (authRepository == null) {
          continue;
        }

        final account = authRepository.getAccount();
        if (account == null) {
          if (candidateServices.length == 1) {
            return emit(state.copyWith(
              errorMessage:
                  'Nie jesteś zalogowany do ${serivceMovie.service.displayName}',
            ));
          }
          continue;
        }

        final movieRepository = _movieRepositories[serivceMovie.service];
        if (movieRepository == null) {
          continue;
        }

        detailsFutures.add(() async {
          try {
            final details =
                await movieRepository.getMovieDetails(serivceMovie.url);
            final fixedTitle = (details.title.trim().isEmpty ||
                    details.title.trim() == 'Brak tytułu')
                ? serivceMovie.title
                : details.title;
            final fixedImg = details.imageUrl.trim().isEmpty
                ? serivceMovie.imageUrl
                : details.imageUrl;
            return details.copyWith(
              title: fixedTitle,
              imageUrl: fixedImg,
            );
          } catch (e) {
            debugPrint(
                'Error loading details from ${serivceMovie.service}: $e');
            if (candidateServices.length == 1) rethrow;
            return null;
          }
        }());
      }

      services.addAll((await Future.wait(detailsFutures))
          .whereType<ServiceMovieDetailsModel>());

      if (services.isEmpty) {
        throw Exception('Nie udało się pobrać szczegółów z żadnego serwisu');
      }

      final MovieDetailsModel movie = MovieDetailsModel(services: services);

      try {
        FirebaseAnalytics.instance
            .logSelectContent(contentType: 'video', itemId: movie.title);
      } catch (_) {}

      final watched = _watchedService.getByMovie(movie);

      emit(state.copyWith(watched: watched));

      if (movie.isSeries) {
        final lastWatchedSeason = watched?.lastWatchedEpisode?.season;
        int selectedSeasonIndex = 0;
        if (lastWatchedSeason != null && movie.seasons != null) {
          final idx = movie.seasons!
              .indexWhere((s) => s.number == lastWatchedSeason.number);
          if (idx >= 0) selectedSeasonIndex = idx;
        }

        emit(state.copyWith(
          movie: movie,
          selectedSeasonIndex: selectedSeasonIndex,
          isLoaded: true,
        ));
      } else {
        emit(state.copyWith(movie: movie));
      }

      if (!movie.isSeries) {
        add(ScrapeVideoUrls(movie: movie));
      }
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Nie udało się załadować szczegółów filmu: $e',
      ));
    }
  }

  Future<void> _onScrapeVideoUrls(
      ScrapeVideoUrls event, Emitter<MovieDetailsState> emit) async {
    try {
      if (!event.movie.isSeries) {
        final updatedMovie = await _videoSourceRepository
            .scrapeVideoUrls(event.movie)
            .timeout(const Duration(seconds: 28), onTimeout: () => event.movie);
        emit(state.copyWith(movie: updatedMovie, isLoaded: true));
      }
    } catch (e) {
      emit(state.copyWith(
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onSelectSeason(
      SelectSeason event, Emitter<MovieDetailsState> emit) async {
    emit(state.copyWith(
      selectedSeasonIndex: event.seasonIndex,
    ));
  }

  Future<void> _onUpdateWatchedStatus(
      UpdateWatchedStatus event, Emitter<MovieDetailsState> emit) async {
    emit(state.copyWith(watched: event.watched));
  }
}
