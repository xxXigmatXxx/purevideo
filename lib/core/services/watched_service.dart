import 'dart:async';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';

class WatchedService {
  late final Box<WatchedMovieModel> box;
  final StreamController<List<WatchedMovieModel>> _watchedController =
      StreamController<List<WatchedMovieModel>>.broadcast();

  final Map<String, WatchedMovieModel> _urlCache = {};

  bool _initialized = false;
  List<WatchedMovieModel> _cachedList = [];

  Stream<List<WatchedMovieModel>> get watchedStream => _getInitializedStream();

  Stream<List<WatchedMovieModel>> _getInitializedStream() {
    if (_initialized) {
      return Stream<List<WatchedMovieModel>>.multi((controller) {
        controller.add(_cachedList);

        final subscription = _watchedController.stream.listen(
          (data) => controller.add(data),
          onError: (error) => controller.addError(error),
          onDone: () => controller.close(),
        );

        controller.onCancel = subscription.cancel;
      });
    }
    return _watchedController.stream;
  }

  Future<void> init() async {
    try {
      box = await Hive.openBox<WatchedMovieModel>('watched');
    } catch (e) {
      await Hive.deleteBoxFromDisk('watched');
      box = await Hive.openBox<WatchedMovieModel>('watched');
    }
    await _cleanupInvalidEntries();
    _rebuildCache();
    _cachedList = getAll();
    _notifyListeners();
    _initialized = true;
  }

  Future<void> _cleanupInvalidEntries() async {
    try {
      final keysToDelete = <dynamic>[];
      final entriesToUpdate = <dynamic, WatchedMovieModel>{};

      for (final entry in box.toMap().entries) {
        final w = entry.value;
        final validServices = w.movie.services
            .where((s) =>
                
                s.url.trim().isNotEmpty &&
                s.title.trim().isNotEmpty &&
                s.title.trim() != 'Brak tytułu' &&
                s.title.trim() != 'Brak danych')
            .toList();

        if (validServices.isEmpty) {
          keysToDelete.add(entry.key);
        } else if (validServices.length != w.movie.services.length ||
            w.movie.filmwebInfo != null ||
            w.movie.directUrls != null) {
          entriesToUpdate[entry.key] = w.copyWith(
            movie: _sanitizeMovie(w.movie),
          );
        }
      }

      for (final k in keysToDelete) {
        await box.delete(k);
      }
      for (final e in entriesToUpdate.entries) {
        await box.put(e.key, e.value);
      }
    } catch (e) {
      debugPrint('Error cleaning watched box: $e');
    }
  }

  MovieDetailsModel _sanitizeMovie(MovieDetailsModel movie) {
    final fallbackTitle = movie.filmwebInfo?.title.trim() ?? '';
    final fallbackPoster = movie.filmwebInfo?.posterUrl.trim() ?? '';

    final sanitizedServices = movie.services
        .where((s) =>
             s.url.trim().isNotEmpty)
        .map((s) {
          final cleanTitle =
              (s.title.trim().isEmpty || s.title.trim() == 'Brak tytułu') &&
                      fallbackTitle.isNotEmpty
                  ? fallbackTitle
                  : s.title.trim();
          final cleanImage =
              s.imageUrl.trim().isEmpty && fallbackPoster.isNotEmpty
                  ? fallbackPoster
                  : s.imageUrl.trim();
          final cleanSeasons = s.seasons
              ?.map((season) => SeasonModel(
                    number: season.number,
                    episodes: season.episodes
                        .map((ep) => EpisodeModel(
                              title: ep.title,
                              number: ep.number,
                              url: ep.url,
                              videoUrls: ep.videoUrls,
                              directUrls: null,
                            ))
                        .toList(),
                  ))
              .toList();
          return ServiceMovieDetailsModel(
            service: s.service,
            url: s.url.trim(),
            title: cleanTitle,
            description: s.description,
            imageUrl: cleanImage,
            isSeries: s.isSeries,
            videoUrls: s.videoUrls,
            seasons: cleanSeasons,
          );
        })
        .toList();

    return MovieDetailsModel(
      services: sanitizedServices,
      filmwebInfo: null,
      directUrls: null,
    );
  }

  void _rebuildCache() {
    _urlCache.clear();
    for (final watched in box.values) {
      for (final service in watched.movie.services) {
        _urlCache[service.url] = watched;
      }
    }
  }

  void _removeFromCache(MovieDetailsModel movie) {
    for (final service in movie.services) {
      _urlCache.remove(service.url);
    }
  }

  void _addToCache(WatchedMovieModel watched) {
    for (final service in watched.movie.services) {
      _urlCache[service.url] = watched;
    }
  }

  void _notifyListeners() {
    _cachedList = getAll();
    _watchedController.add(_cachedList);
  }

  void dispose() {
    _watchedController.close();
  }

  List<WatchedMovieModel> getAll() {
    return box.values
        .where((w) =>
            w.movie.services.isNotEmpty &&
            w.movie.services.first.url.trim().isNotEmpty &&
            w.movie.services.first.title.trim().isNotEmpty)
        .toList();
  }

  WatchedMovieModel? getByMovie(MovieDetailsModel movie) {
    final movieServiceUrls =
        movie.services.map((service) => service.url.trim()).toSet();

    for (final url in movieServiceUrls) {
      if (_urlCache.containsKey(url)) {
        return _urlCache[url];
      }
    }

    return box.values.firstWhereOrNull((boxElement) {
      final boxServiceUrls =
          boxElement.movie.services.map((service) => service.url.trim()).toSet();
      return movieServiceUrls.intersection(boxServiceUrls).isNotEmpty ||
          boxElement.movie.title.toLowerCase().trim() ==
              movie.title.toLowerCase().trim();
    });
  }

  dynamic getKeyByMovie(MovieDetailsModel movie) {
    final movieServiceUrls =
        movie.services.map((service) => service.url.trim()).toSet();
    for (final entry in box.toMap().entries) {
      final boxUrls = entry.value.movie.services
          .map((service) => service.url.trim())
          .toSet();
      if (movieServiceUrls.intersection(boxUrls).isNotEmpty ||
          entry.value.movie.title.toLowerCase().trim() ==
              movie.title.toLowerCase().trim()) {
        return entry.key;
      }
    }
    return null;
  }

  WatchedEpisodeModel? getByEpisode(
      MovieDetailsModel movie, EpisodeModel episode) {
    final watchedMovie = getByMovie(movie);
    return watchedMovie?.getEpisodeByUrl(episode.url);
  }

  void removeMovie(MovieDetailsModel movie) {
    try {
      final existingKey = getKeyByMovie(movie);
      if (existingKey != null) {
        final oldMovie = box.get(existingKey);
        if (oldMovie != null) {
          _removeFromCache(oldMovie.movie);
        }
        box.delete(existingKey);
        _notifyListeners();
      }
    } catch (e) {
      debugPrint('Error removing watched movie: $e');
    }
  }

  void watchMovie(MovieDetailsModel movie, int watchedTime) {
    try {
      final cleanMovie = _sanitizeMovie(movie);
      if (cleanMovie.services.isEmpty) return;

      final existing = getByMovie(cleanMovie);
      final effectiveTime = watchedTime > 0
          ? watchedTime
          : max(existing?.watchedTime ?? 0, 120);

      final existingKey = getKeyByMovie(cleanMovie);
      if (existingKey != null) {
        final oldMovie = box.get(existingKey);
        if (oldMovie != null) {
          _removeFromCache(oldMovie.movie);
        }
        box.delete(existingKey);
      }

      final watchedMovie = WatchedMovieModel(
        movie: cleanMovie,
        watchedTime: effectiveTime,
        watchedAt: DateTime.now(),
        episodes: existing?.episodes != null
            ? List<WatchedSeasonEpisode>.from(existing!.episodes!)
            : null,
      );
      box.add(watchedMovie);
      _addToCache(watchedMovie);
      _notifyListeners();
    } catch (e) {
      debugPrint('Error in watchMovie: $e');
    }
  }

  void watchEpisode(
    MovieDetailsModel movie,
    SeasonModel season,
    EpisodeModel episode,
    int watchedTime,
  ) {
    try {
      final cleanMovie = _sanitizeMovie(movie);
      if (cleanMovie.services.isEmpty) return;

      final cleanEpisode = EpisodeModel(
        title: episode.title,
        number: episode.number,
        url: episode.url,
        videoUrls: episode.videoUrls,
        directUrls: null,
      );
      final cleanSeason = SeasonModel(
        number: season.number,
        episodes: season.episodes
            .map((ep) => EpisodeModel(
                  title: ep.title,
                  number: ep.number,
                  url: ep.url,
                  videoUrls: ep.videoUrls,
                  directUrls: null,
                ))
            .toList(),
      );

      final existing = getByMovie(cleanMovie);
      final prevEp = existing?.getEpisodeByUrl(cleanEpisode.url);
      final effectiveTime = watchedTime > 0
          ? watchedTime
          : max(prevEp?.watchedTime ?? 0, 60);

      final existingEpisodes = <WatchedSeasonEpisode>[
        ...(existing?.episodes ?? const <WatchedSeasonEpisode>[]),
      ]..removeWhere((e) =>
          e.watchedEpisode.episode.url == cleanEpisode.url ||
          (e.season.number == cleanSeason.number &&
              e.watchedEpisode.episode.number == cleanEpisode.number));

      final watchedEpisode = WatchedEpisodeModel(
        episode: cleanEpisode,
        watchedTime: effectiveTime,
        watchedAt: DateTime.now(),
      );

      existingEpisodes.add(
        WatchedSeasonEpisode(
          season: cleanSeason,
          watchedEpisode: watchedEpisode,
        ),
      );

      final watchedMovie = WatchedMovieModel(
        movie: cleanMovie,
        watchedTime: effectiveTime,
        watchedAt: DateTime.now(),
        episodes: existingEpisodes,
      );

      final existingKey = getKeyByMovie(cleanMovie);
      if (existingKey != null) {
        final oldMovie = box.get(existingKey);
        if (oldMovie != null) {
          _removeFromCache(oldMovie.movie);
        }
        box.delete(existingKey);
      }

      box.add(watchedMovie);
      _addToCache(watchedMovie);
      _notifyListeners();
    } catch (e) {
      debugPrint('Error in watchEpisode: $e');
    }
  }
}
