import 'dart:async';
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
  List<ServiceMovieModel> _pendingEkinoEntries = const [];

  MovieDetailsBloc() : super(const MovieDetailsState()) {
    on<LoadMovieDetails>(_onLoadMovieDetails);
    on<LoadFilmwebMovieDetails>(_onLoadFilmwebMovieDetails);
    on<ScrapeVideoUrls>(_onScrapeVideoUrls);
    on<SelectSeason>(_onSelectSeason);
    on<UpdateWatchedStatus>(_onUpdateWatchedStatus);
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

  Future<ServiceMovieDetailsModel?> _loadFirstValidEkinoDetails(
      List<ServiceMovieModel> ekinoEntries) async {
    final repo = _movieRepositories[SupportedService.ekino];
    if (repo == null || ekinoEntries.isEmpty) return null;
    ServiceMovieDetailsModel? fallbackDetails;
    for (final ekinoMovie in ekinoEntries) {
      try {
        final d = await repo.getMovieDetails(ekinoMovie.url);
        final fixed = d.copyWith(
          title: (d.title.trim().isEmpty || d.title == 'Brak tytułu')
              ? ekinoMovie.title
              : d.title,
          imageUrl: d.imageUrl.trim().isEmpty
              ? ekinoMovie.imageUrl
              : d.imageUrl,
        );
        fallbackDetails ??= fixed;
        if (fixed.isSeries ||
            (fixed.videoUrls != null && fixed.videoUrls!.isNotEmpty)) {
          return fixed;
        }
      } catch (e) {
        debugPrint('Error loading Ekino details (${ekinoMovie.url}): $e');
      }
    }
    return fallbackDetails;
  }

  Future<void> _onLoadMovieDetails(
      LoadMovieDetails event, Emitter<MovieDetailsState> emit) async {
    try {
      final services = <ServiceMovieDetailsModel>[];
      final detailsFutures = <Future<ServiceMovieDetailsModel?>>[];

      final ekinoEntries = event.movie.services
          .where((s) => s.service == SupportedService.ekino)
          .toList();
      final nonEkinoEntries = event.movie.services
          .where((s) => s.service != SupportedService.ekino)
          .toList();
      _pendingEkinoEntries = ekinoEntries;

      for (final serivceMovie in nonEkinoEntries) {
        final authRepository = _authRepositories[serivceMovie.service];
        if (authRepository == null) continue;
        final account = authRepository.getAccount();
        if (account == null) continue;
        final movieRepository = _movieRepositories[serivceMovie.service];
        if (movieRepository == null) continue;

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
            return null;
          }
        }());
      }

      if (detailsFutures.isNotEmpty) {
        services.addAll((await Future.wait(detailsFutures))
            .whereType<ServiceMovieDetailsModel>());
      }

      // Load Ekino if there were no other services or if primary services returned no videoUrls
      final hasAnyUrls = services.any(
          (s) => s.isSeries || (s.videoUrls != null && s.videoUrls!.isNotEmpty));
      if (!hasAnyUrls && ekinoEntries.isNotEmpty) {
        final ekinoDetails = await _loadFirstValidEkinoDetails(ekinoEntries);
        if (ekinoDetails != null) {
          services.add(ekinoDetails);
          _pendingEkinoEntries = const [];
        }
      }

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
        var updatedMovie = await _videoSourceRepository
            .scrapeVideoUrls(event.movie)
            .timeout(const Duration(seconds: 22), onTimeout: () => event.movie);

        // If primary service links failed to resolve and we still have unqueried Ekino entries, fallback to Ekino!
        if ((updatedMovie.directUrls == null ||
                updatedMovie.directUrls!.isEmpty) &&
            _pendingEkinoEntries.isNotEmpty) {
          final ekinoDetails =
              await _loadFirstValidEkinoDetails(_pendingEkinoEntries);
          _pendingEkinoEntries = const [];
          if (ekinoDetails != null &&
              ekinoDetails.videoUrls != null &&
              ekinoDetails.videoUrls!.isNotEmpty) {
            final combinedServices = [
              ...updatedMovie.services,
              ekinoDetails,
            ];
            final withEkino = MovieDetailsModel(
              services: combinedServices,
              filmwebInfo: updatedMovie.filmwebInfo,
            );
            updatedMovie = await _videoSourceRepository
                .scrapeVideoUrls(withEkino)
                .timeout(
                  const Duration(seconds: 22),
                  onTimeout: () => withEkino,
                );
          }
        }

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
