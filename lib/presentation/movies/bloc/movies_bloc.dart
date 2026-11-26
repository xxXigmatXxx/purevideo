import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_auth_repository.dart';
import 'package:purevideo/data/repositories/docchi/docchi_auth_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/movies/bloc/movies_event.dart';
import 'package:purevideo/presentation/movies/bloc/movies_state.dart';

class MoviesBloc extends Bloc<MoviesEvent, MoviesState> {
  final Map<SupportedService, MovieRepository> _repositories = getIt();
  final Map<SupportedService, AuthRepository> _authRepositories = getIt();
  final SettingsService _settingsService = getIt<SettingsService>();
  final ExtraSourcesService _extraSourcesService = getIt<ExtraSourcesService>();
  StreamSubscription<void>? _extraSub;
  final List<MovieModel> _movies = [];
  final List<StreamSubscription<AuthModel>> _authSubscriptions = [];
  bool _isRefreshing = false;
  bool _pendingRefresh = false;

  MoviesBloc() : super(MoviesInitial()) {
    on<LoadMoviesRequested>(_onLoadMoviesRequested);
    _setupAuthListeners();
    _extraSub = _extraSourcesService.changesStream.listen((_) {
      add(LoadMoviesRequested());
    });
  }

  void _setupAuthListeners() {
    for (final authRepo in _authRepositories.values) {
      final subscription = authRepo.authStream.listen((auth) {
        add(LoadMoviesRequested());
      });
      _authSubscriptions.add(subscription);
    }
  }

  @override
  Future<void> close() {
    _extraSub?.cancel();
    for (final subscription in _authSubscriptions) {
      subscription.cancel();
    }
    return super.close();
  }

  bool _areMovieListsEqual(List<MovieModel> a, List<MovieModel> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final sa = a[i].services;
      final sb = b[i].services;
      if (sa.length != sb.length) return false;
      for (int j = 0; j < sa.length; j++) {
        if (sa[j].service != sb[j].service ||
            sa[j].url != sb[j].url ||
            sa[j].category != sb[j].category ||
            sa[j].imageUrl != sb[j].imageUrl) {
          return false;
        }
      }
    }
    return true;
  }

  List<MovieModel> _filterForLoggedServices(
      List<MovieModel> input, Set<SupportedService> loggedServices) {
    final result = <MovieModel>[];
    for (final m in input) {
      final validServices = m.services
          .where((s) =>
              loggedServices.contains(s.service) &&
              !_settingsService.isUrlLinkless(s.url) &&
              s.url.trim().isNotEmpty &&
              s.title.trim().isNotEmpty &&
              s.title != 'Brak danych')
          .toList();
      if (validServices.isNotEmpty) {
        result.add(MovieModel(services: validServices));
      }
    }
    return result;
  }

  Future<void> _onLoadMoviesRequested(
    LoadMoviesRequested event,
    Emitter<MoviesState> emit,
  ) async {
    if (_isRefreshing) {
      _pendingRefresh = true;
      return;
    }
    _isRefreshing = true;
    try {
      for (final repo in _authRepositories.values) {
        if (repo is DocchiAuthRepository) await repo.ensureInitialized();
        if (repo is BajeczkiAuthRepository) await repo.ensureInitialized();
      }
      final loggedServices = _authRepositories.entries
          .where((entry) =>
              entry.value.getAccount() != null &&
              _settingsService.isServiceEnabled(entry.key))
          .map((entry) => entry.key)
          .toSet();

      if (loggedServices.isEmpty) {
        emit(const MoviesError('Zaloguj się aby zobaczyć filmy'));
        return;
      }

      final merge = getIt<MergeService>();

      // 1. Immediately emit cached movies if available so startup is instant!
      final cached = _filterForLoggedServices(
        _settingsService.getCachedHomeMovies(),
        loggedServices,
      );
      if (cached.isNotEmpty) {
        merge.replaceAll(cached);
        _movies
          ..clear()
          ..addAll(cached);
        emit(MoviesLoaded(List<MovieModel>.from(_movies)));
      } else if (state is! MoviesLoaded) {
        emit(MoviesLoading());
      }

      // 2. Refresh from logged-in services in parallel
      final loadErrors = <String>[];
      final loggedServiceEntries = _repositories.entries
          .where((entry) => loggedServices.contains(entry.key))
          .toList();

      if (loggedServiceEntries.isNotEmpty) {
        final movieFutures = loggedServiceEntries.map((entry) async {
          try {
            return await entry.value
                .getMovies()
                .timeout(const Duration(seconds: 65));
          } catch (e) {
            debugPrint('Failed to load movies from ${entry.key}: $e');
            loadErrors.add('${entry.key.displayName}: $e');
            return <ServiceMovieModel>[];
          }
        }).toList();

        final results = await Future.wait(
          movieFutures,
          eagerError: false,
        ).then((res) => res.whereType<List<ServiceMovieModel>>().toList());

        final hasAnyFresh = results.any((list) => list.isNotEmpty);
        if (hasAnyFresh) {
          final freshMerged = <MovieModel>[];
          for (final movieList in results) {
            final cleanList = movieList
                .where((s) => !_settingsService.isUrlLinkless(s.url))
                .toList();
            await merge.addFromServiceTemp(cleanList, freshMerged);
          }

          final filteredFresh =
              _filterForLoggedServices(freshMerged, loggedServices);

          if (filteredFresh.isNotEmpty) {
            final unchanged =
                state is MoviesLoaded && _areMovieListsEqual(_movies, filteredFresh);
            merge.replaceAll(filteredFresh);
            _movies
              ..clear()
              ..addAll(filteredFresh);
            _settingsService.setCachedHomeMovies(_movies);
            if (!unchanged) {
              emit(MoviesLoaded(List<MovieModel>.from(_movies)));
            }
            return;
          }
        }
      }

      if (_movies.isEmpty) {
        emit(MoviesError(loadErrors.isNotEmpty
            ? 'Nie udało się załadować filmów:\n${loadErrors.join('\n')}'
            : 'Brak dostępnych filmów'));
      } else if (state is! MoviesLoaded) {
        emit(MoviesLoaded(List<MovieModel>.from(_movies)));
      }
    } catch (e) {
      if (_movies.isEmpty) {
        emit(MoviesError(e.toString()));
      }
    } finally {
      _isRefreshing = false;
      if (_pendingRefresh && !isClosed) {
        _pendingRefresh = false;
        add(LoadMoviesRequested());
      }
    }
  }
}
