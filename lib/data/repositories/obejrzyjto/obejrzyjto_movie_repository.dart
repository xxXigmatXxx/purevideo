import 'package:dio/dio.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_dio_factory.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_utils.dart';
import 'package:purevideo/di/injection_container.dart';

class ObejrzyjtoMovieRepository implements MovieRepository {
  final AuthRepository _authRepository = getIt<
      Map<SupportedService, AuthRepository>>()[SupportedService.obejrzyjto]!;

  Dio? _dio;

  ObejrzyjtoMovieRepository() {
    _authRepository.authStream.listen(_onAuthChanged);
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.obejrzyjto) {
      _dio = ObejrzyjtoDioFactory.getDio(auth.account);
    }
  }

  Future<void> _prepareDio() async {
    _dio ??= ObejrzyjtoDioFactory.getDio(
      _authRepository.getAccount(),
    );
  }

  bool _isTrailerVideo(dynamic video) {
    if (video is! Map) return true;
    final cat = (video['category'] ?? '').toString().toLowerCase().trim();
    if (cat == 'trailer' || cat == 'teaser' || cat == 'clip') {
      return true;
    }
    final name = (video['name'] ?? '').toString().toLowerCase().trim();
    if (name.contains('zwiastun') ||
        name.contains('trailer') ||
        name.contains('youtube')) {
      return true;
    }
    final src = (video['src'] ?? '').toString().toLowerCase().trim();
    if (src.isNotEmpty &&
        (src.contains('youtube.com') || src.contains('youtu.be'))) {
      return true;
    }
    return false;
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    await _prepareDio();

    final episodeResponse = await _dio!.get(episode.url);

    final bootstrapData = extractBootstrapData(episodeResponse.data);
    if (bootstrapData == null) {
      throw Exception(
          'Nie udało się pobrać danych bootstrap z odpowiedzi serwera.');
    }

    final loaders = bootstrapData['loaders'] as Map<String, dynamic>?;
    final watchPageData = loaders?['episodePage'] ?? loaders?['watchPage'];

    final combinedVideos = <dynamic>[];
    final episodeData = watchPageData?['episode'];
    if (episodeData is Map && episodeData['videos'] is List) {
      combinedVideos.addAll(episodeData['videos'] as List);
    }
    if (watchPageData is Map) {
      if (watchPageData['video'] is Map) {
        combinedVideos.add(watchPageData['video']);
      }
      if (watchPageData['alternative_videos'] is List) {
        combinedVideos.addAll(watchPageData['alternative_videos'] as List);
      }
    }

    final videoUrls = _extractVideoUrls(combinedVideos);

    return episode.copyWith(
      videoUrls: videoUrls,
    );
  }

  Future<ServiceMovieDetailsModel> scrapeSeasons(
      ServiceMovieDetailsModel movie, int movieId) async {
    await _prepareDio();

    final response = await _dio!.get('/api/v1/titles/$movieId/seasons',
        options: Options(headers: {
          'Referer': 'https://www.obejrzyj.to/',
        }));

    if (response.data['pagination']?['data'] == null) {
      throw Exception('Nie udało się pobrać danych z odpowiedzi serwera.');
    }

    final List data = response.data['pagination']['data'];
    final seasonCount = data.length;

    final seasonFutures = List.generate(seasonCount, (idx) async {
      final i = idx + 1;
      try {
        final seasonResponse =
            await _dio!.get('/api/v1/titles/$movieId/seasons/$i/episodes',
                queryParameters: {
                  'perPage': 999,
                  'excludeDescription': true,
                  'query': '',
                  'orderBy': 'episode_number',
                  'orderDir': 'asc',
                  'page': 1,
                },
                options: Options(headers: {
                  'Referer': 'https://www.obejrzyj.to/',
                }));

        final List episodesData =
            (seasonResponse.data['pagination']?['data'] as List?) ?? [];

        final List<EpisodeModel> episodes = [];

        for (var j = 1; j <= episodesData.length; j++) {
          final episodeData = episodesData[j - 1];
          final name = episodeData['name'] as String?;

          if (name == null || name.isEmpty) {
            continue;
          }

          final epNum = (episodeData['episode_number'] as int?) ?? j;

          episodes.add(EpisodeModel(
            title: name,
            number: epNum,
            url:
                '/titles/$movieId/${generateSlug(movie.title)}/season/$i/episode/$epNum',
            videoUrls: [],
          ));
        }

        if (episodes.isEmpty) return null;
        return SeasonModel(number: i, episodes: episodes);
      } catch (_) {
        return null;
      }
    });

    final seasons =
        (await Future.wait(seasonFutures)).whereType<SeasonModel>().toList();

    return movie.copyWith(
      seasons: seasons,
    );
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    await _prepareDio();

    final response = await _dio!.get(url);

    final bootstrapData = extractBootstrapData(response.data);
    if (bootstrapData == null) {
      throw Exception(
          'Nie udało się pobrać danych bootstrap z odpowiedzi serwera.');
    }

    final loaders = bootstrapData['loaders'] as Map<String, dynamic>?;
    final watchPageData = loaders?['watchPage'] ?? loaders?['titlePage'];
    if (watchPageData == null) {
      throw Exception('Brak danych o tytule.');
    }

    final details =
        (watchPageData['title'] as Map<String, dynamic>?) ?? watchPageData;

    final combinedVideos = <dynamic>[];
    if (watchPageData['alternative_videos'] is List) {
      combinedVideos.addAll(watchPageData['alternative_videos'] as List);
    }
    if (watchPageData['video'] is Map) {
      combinedVideos.add(watchPageData['video']);
    }
    if (details['videos'] is List) {
      combinedVideos.addAll(details['videos'] as List);
    }

    final videoUrls = _extractVideoUrls(combinedVideos);

    final movieModel = _buildMovieDetails(url, details, videoUrls);

    if (movieModel.isSeries) {
      final movieId = details['id'] as int?;
      if (movieId == null) {
        throw Exception('Brak ID serialu w danych serwera.');
      }

      final series = await scrapeSeasons(
        movieModel,
        movieId,
      );

      return series;
    }

    return movieModel;
  }

  List<HostLink> _extractVideoUrls(List videoData) {
    final videoUrls = <HostLink>[];
    final seenUrls = <String>{};

    for (final video in videoData) {
      if (video is! Map) continue;
      if (_isTrailerVideo(video)) continue;
      final rawUrl = (video['src'] as String?)?.trim();
      if (rawUrl == null || rawUrl.isEmpty) {
        continue;
      }

      final cleanUrl = rawUrl.replaceAll('?autoplay=1', '').trim();
      if (!seenUrls.add(cleanUrl)) continue;

      final rawQuality = (video['quality'] as String?)?.trim();
      final rawLangType = (video['language_type'] as String?)?.trim().toLowerCase();
      final rawLang = (video['language'] as String?)?.trim();

      final quality = (rawQuality != null && rawQuality.isNotEmpty)
          ? rawQuality.toUpperCase()
          : 'HD';
      String lang = (rawLang != null && rawLang.isNotEmpty)
          ? rawLang.toUpperCase()
          : 'PL';
      if (rawLangType != null && rawLangType.isNotEmpty) {
        if (rawLangType.contains('lektor') && rawLangType.contains('napisy')) {
          lang = 'Lektor/Napisy';
        } else if (rawLangType.contains('lektor')) {
          lang = 'Lektor PL';
        } else if (rawLangType.contains('dubbing')) {
          lang = 'Dubbing PL';
        } else if (rawLangType.contains('napisy')) {
          lang = 'Napisy PL';
        }
      }

      videoUrls.add(HostLink(
        url: cleanUrl,
        quality: quality,
        lang: lang,
      ));
    }

    return videoUrls;
  }

  ServiceMovieDetailsModel _buildMovieDetails(
      String url, Map<String, dynamic> details, List<HostLink> videoUrls) {
    final title = (details['name'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      throw Exception('Brak tytułu filmu w danych serwera.');
    }

    final rawDesc = (details['description'] as String?)?.trim();
    final description = (rawDesc != null && rawDesc.isNotEmpty)
        ? rawDesc
        : 'Brak opisu dla tego tytułu.';

    return ServiceMovieDetailsModel(
      service: SupportedService.obejrzyjto,
      url: url,
      title: title,
      description: description,
      imageUrl: (details['poster'] as String?)?.trim() ?? '',
      isSeries: details['is_series']?.toString() == 'true',
      videoUrls: videoUrls,
    );
  }

  bool _isAdultCert(Map<String, dynamic> data) {
    final cert = (data['certification'] ?? '').toString().toLowerCase().trim();
    return cert == 'ma' || cert == 'r' || cert == '18' || cert == 'nc-17';
  }

  String _enrichCategoryWithGenres(
      Map<String, dynamic> data, String? baseCategory) {
    final cats = <String>{};
    if (baseCategory != null && baseCategory.trim().isNotEmpty) {
      cats.add(baseCategory.trim());
    }
    final isAdult = _isAdultCert(data);
    final genres = data['genres'];
    if (genres is List) {
      for (final g in genres) {
        if (g is Map) {
          final gName = (g['name'] ?? '').toString().toLowerCase().trim();
          if (gName == 'animacja' && !isAdult) {
            cats.add('Bajki dla dzieci');
          } else if (gName == 'familijny' && !isAdult) {
            cats.add('Familijne');
          } else if (gName == 'akcja') {
            cats.add('Akcja');
          } else if (gName == 'komedia') {
            cats.add('Komedia');
          } else if (gName == 'horror') {
            cats.add('Horror');
          } else if (gName == 'thriller') {
            cats.add('Thriller');
          } else if (gName.contains('sci-fi') || gName.contains('scifi')) {
            cats.add('Sci-Fi');
          } else if (gName == 'dramat') {
            cats.add('Dramat');
          }
        }
      }
    }
    return cats.join('|');
  }

  Future<List<ServiceMovieModel>> _fetchGenreChannel(
      String path, String categoryLabel,
      {bool filterAdult = false}) async {
    try {
      final resp =
          await _dio!.get(path).timeout(const Duration(seconds: 14));
      final bootstrapData = extractBootstrapData(resp.data);
      if (bootstrapData == null) return [];
      final items = bootstrapData['loaders']?['channelPage']?['channel']
          ?['content']?['data'];
      if (items is! List) return [];
      return items
          .whereType<Map<String, dynamic>>()
          .where((m) => !filterAdult || !_isAdultCert(m))
          .map((m) => _parseMovie(m, categoryLabel))
          .whereType<ServiceMovieModel>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    await _prepareDio();

    final results = await Future.wait([
      () async {
        try {
          final response =
              await _dio!.get('/').timeout(const Duration(seconds: 14));
          final bootstrapData = extractBootstrapData(response.data);
          if (bootstrapData == null) return <ServiceMovieModel>[];
          final channelData = bootstrapData['loaders']?['channelPage']
              ?['channel']?['content']?['data'];
          if (channelData is! List) return <ServiceMovieModel>[];
          return channelData
              .whereType<Map<String, dynamic>>()
              .expand(_parseMoviesFromLoader)
              .whereType<ServiceMovieModel>()
              .toList();
        } catch (_) {
          return <ServiceMovieModel>[];
        }
      }(),
      _fetchGenreChannel('/genre/animacja', 'Bajki dla dzieci',
          filterAdult: true),
      _fetchGenreChannel('/genre/familijny', 'Familijne', filterAdult: true),
      _fetchGenreChannel('/movies', 'Popularne filmy'),
      _fetchGenreChannel('/movies?page=2', 'Popularne filmy'),
      _fetchGenreChannel('/series', 'Popularne seriale'),
      _fetchGenreChannel('/genre/akcja', 'Akcja'),
      _fetchGenreChannel('/genre/komedia', 'Komedia'),
      _fetchGenreChannel('/genre/horror', 'Horror'),
      _fetchGenreChannel('/genre/thriller', 'Thriller'),
      _fetchGenreChannel('/genre/sci-fi', 'Sci-Fi'),
      _fetchGenreChannel('/genre/dramat', 'Dramat'),
    ]);

    return [
      ...results[1],
      ...results[2],
      ...results[0],
      ...results[3],
      ...results[4],
      ...results[5],
      ...results[6],
      ...results[7],
      ...results[8],
      ...results[9],
      ...results[10],
      ...results[11],
    ];
  }

  Iterable<ServiceMovieModel?> _parseMoviesFromLoader(
      Map<String, dynamic> loader) {
    final loaderName = (loader['name'] as String?)?.trim();
    final lowerName = (loaderName ?? '').toLowerCase();
    if (lowerName.contains('wkrótce') ||
        lowerName.contains('wkrotce') ||
        lowerName.contains('zapowied') ||
        lowerName.contains('upcoming')) {
      return const [];
    }
    final contentData = loader['content']?['data'] as List?;

    return contentData
            ?.whereType<Map<String, dynamic>>()
            .map((movieData) => _parseMovie(movieData, loaderName)) ??
        [];
  }

  ServiceMovieModel? _parseMovie(Map<String, dynamic> data, String? category) {
    final name = (data['name'] as String?)?.trim();
    final poster = (data['poster'] as String?)?.trim();

    if (name == null || name.isEmpty || poster == null || poster.isEmpty) {
      return null;
    }

    final isSeries = data['is_series']?.toString() == 'true';
    final primaryVideo = data['primary_video'];

    if (!isSeries) {
      if (primaryVideo is! Map || primaryVideo['id'] == null) {
        return null;
      }
      if (_isTrailerVideo(primaryVideo)) {
        return null;
      }
      return ServiceMovieModel(
        service: SupportedService.obejrzyjto,
        title: name,
        imageUrl: poster,
        url: '/watch/${primaryVideo['id']}',
        category: _enrichCategoryWithGenres(data, category),
      );
    } else {
      final epRangeSize = (data['episode_range_size'] as int?) ?? 1;
      if (epRangeSize <= 0) return null;

      final primaryVideoId =
          (primaryVideo is Map) ? primaryVideo['id'] : null;
      final latestEpVideoId =
          (data['latest_episode_video'] is Map)
              ? data['latest_episode_video']['id']
              : null;
      final titleId = data['id'];

      String? targetUrl;
      if (primaryVideoId != null) {
        targetUrl = '/watch/$primaryVideoId';
      } else if (latestEpVideoId != null) {
        targetUrl = '/watch/$latestEpVideoId';
      } else if (titleId != null) {
        targetUrl = '/titles/$titleId/${generateSlug(name)}';
      }
      if (targetUrl == null) return null;

      return ServiceMovieModel(
        service: SupportedService.obejrzyjto,
        title: name,
        imageUrl: poster,
        url: targetUrl,
        category: _enrichCategoryWithGenres(data, category ?? 'Seriale'),
      );
    }
  }
}
