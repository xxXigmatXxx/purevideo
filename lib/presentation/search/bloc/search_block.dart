import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/presentation/search/bloc/search_event.dart';
import 'package:purevideo/presentation/search/bloc/search_state.dart';
import 'package:purevideo/di/injection_container.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final Map<SupportedService, AuthRepository> _authRepositories = getIt();
  final Map<SupportedService, SearchRepository> _searchRepositories = getIt();
  final SettingsService _settingsService = getIt<SettingsService>();

  SearchBloc() : super(const SearchInitial()) {
    on<SearchRequested>(_onSearchRequested);
    on<SearchCleared>(_onSearchCleared);
  }

  Future<void> _onSearchRequested(
    SearchRequested event,
    Emitter<SearchState> emit,
  ) async {
    final q = event.query.trim();
    if (q.isEmpty) {
      emit(const SearchInitial());
      return;
    }

    emit(const SearchLoading());

    try {
      final loggedServiceEntries = _searchRepositories.entries
          .where((entry) => _authRepositories[entry.key]?.getAccount() != null)
          .toList();

      if (loggedServiceEntries.isEmpty) {
        emit(const SearchError('Zaloguj się w Ustawieniach aby wyszukiwać filmy'));
        return;
      }

      final merge = getIt<MergeService>();
      final results = <MovieModel>[];

      final searchFutures = loggedServiceEntries.map((entry) async {
        try {
          return await entry.value
              .searchMovies(q)
              .timeout(const Duration(seconds: 18));
        } catch (e) {
          debugPrint('Search error on ${entry.key}: $e');
          return <ServiceMovieModel>[];
        }
      }).toList();

      final searchLists = await Future.wait(searchFutures, eagerError: false);
      for (final list in searchLists) {
        final clean = list
            .where((s) =>
                !_settingsService.isUrlLinkless(s.url) &&
                s.url.trim().isNotEmpty &&
                s.title.trim().isNotEmpty)
            .toList();
        await merge.addFromServiceTemp(clean, results);
      }

      emit(SearchLoaded(results));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  Future<void> _onSearchCleared(
    SearchCleared event,
    Emitter<SearchState> emit,
  ) async {
    emit(const SearchInitial());
  }
}
