import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/movies/bloc/movies_event.dart';
import 'package:purevideo/presentation/movies/bloc/movies_state.dart';

class MoviesBloc extends Bloc<MoviesEvent, MoviesState> {
  final Map<SupportedService, MovieRepository> _repositories = getIt();
  final Map<SupportedService, AuthRepository> _authRepositories = getIt();
  final List<MovieModel> _movies = [];
  final List<StreamSubscription<AuthModel>> _authSubscriptions = [];

  MoviesBloc() : super(MoviesInitial()) {
    on<LoadMoviesRequested>(_onLoadMoviesRequested);
    _setupAuthListeners();
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
    for (final subscription in _authSubscriptions) {
      subscription.cancel();
    }
    return super.close();
  }

  Future<void> _onLoadMoviesRequested(
    LoadMoviesRequested event,
    Emitter<MoviesState> emit,
  ) async {
    if (state is MoviesLoading) return;
    try {
      emit(MoviesLoading());
      _movies.clear();

      bool hasLoggedInUser = false;
      for (final entry in _authRepositories.entries) {
        final account = entry.value.getAccount();
        if (account != null) {
          hasLoggedInUser = true;
          break;
        }
      }

      if (!hasLoggedInUser) {
        emit(const MoviesError('Zaloguj się aby zobaczyć filmy'));
        return;
      }

      final merge = getIt<MergeService>();

      // Fetch movies from all logged-in services in parallel instead of sequentially
      final loggedServiceEntries = _repositories.entries
          .where((entry) => _authRepositories[entry.key]?.getAccount() != null)
          .toList();

      if (loggedServiceEntries.isNotEmpty) {
        final movieFutures = loggedServiceEntries
            .map((entry) async {
              // One slow/blocked service (e.g. Cloudflare) must not break the
              // others or leave the home screen loading forever.
              try {
                return await entry.value
                    .getMovies()
                    .timeout(const Duration(seconds: 45));
              } catch (e) {
                debugPrint('Failed to load movies from ${entry.key}: $e');
                return <ServiceMovieModel>[];
              }
            })
            .toList();

        // Wait for all API calls to complete in parallel, but continue even if one fails
        final results = await Future.wait(
          movieFutures,
          eagerError: false,
        ).then((results) =>
            results.whereType<List<ServiceMovieModel>>().toList());

        // Add all fetched movies to merge service
        for (final movieList in results) {
          await merge.addFromService(movieList);
        }
      }

      final loggedServices = _authRepositories.entries
          .where((entry) => entry.value.getAccount() != null)
          .map((entry) => entry.key)
          .toSet();

      _movies.addAll(getIt<MergeService>().getMovies.where((m) {
        final movieServices = m.services
            .map((s) => s.service)
            .toSet();
        return movieServices.intersection(loggedServices).isNotEmpty;
      }));

      if (_movies.isEmpty) {
        emit(const MoviesError('Brak dostępnych filmów'));
      } else {
        emit(MoviesLoaded(_movies));
      }
    } catch (e) {
      emit(MoviesError(e.toString()));
    }
  }
}
