import 'package:dio/dio.dart';
import 'package:purevideo/core/services/settings_service.dart';
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
  final SettingsService _settingsService = getIt<SettingsService>();

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

  bool _isTrailerOrYoutube(dynamic video) {
    if (video is! Map) return true;
    final src = (video['src'] ?? '').toString().toLowerCase().trim();
    if (src.isEmpty ||
        src.contains('youtube.com') ||
        src.contains('youtu.be')) {
      return true;
    }
    final cat = (video['category'] ?? '').toString().toLowerCase().trim();
    if (cat == 'trailer' || cat == 'teaser' || cat == 'clip') {
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
    if (videoUrls.isEmpty) {
      throw Exception('Ten odcinek nie posiada jeszcze linków wideo.');
    }

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

    if (seasons.isEmpty) {
      _settingsService.markUrlLinkless(movie.url);
      throw Exception('Ten serial nie posiada jeszcze dostępnych odcinków.');
    }

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
      _settingsService.markUrlLinkless(url);
      throw Exception('Brak danych o tytule.');
    }

    final details =
        (watchPageData['title'] as Map<String, dynamic>?) ?? watchPageData;
    final isSeries = details['is_series']?.toString() == 'true';

    final combinedVideos = <dynamic>[];
    if (watchPageData['video'] is Map) {
      combinedVideos.add(watchPageData['video']);
    }
    if (watchPageData['alternative_videos'] is List) {
      combinedVideos.addAll(watchPageData['alternative_videos'] as List);
    }
    if (details['videos'] is List) {
      combinedVideos.addAll(details['videos'] as List);
    }

    final videoUrls = _extractVideoUrls(combinedVideos);

    if (!isSeries && videoUrls.isEmpty) {
      _settingsService.markUrlLinkless(url);
      throw Exception('Ten film nie posiada jeszcze aktywnych linków wideo.');
    }

    _settingsService.markUrlVerified(url);
    final movieModel = _buildMovieDetails(url, details, videoUrls);

    if (movieModel.isSeries) {
      final movieId = details['id'] as int?;
      if (movieId == null) {
        _settingsService.markUrlLinkless(url);
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
      if (_isTrailerOrYoutube(video)) continue;

      final rawUrl = (video['src'] as String?)?.trim();
      if (rawUrl == null || rawUrl.isEmpty) {
        continue;
      }

      final cleanUrl = rawUrl.replaceAll('?autoplay=1', '').trim();
      if (!seenUrls.add(cleanUrl)) continue;

      final rawQuality = (video['quality'] as String?)?.trim();
      final rawLang = (video['language'] as String?)?.trim();

      final quality =
          (rawQuality != null && rawQuality.isNotEmpty) ? rawQuality.toUpperCase() : 'HD';
      final lang =
          (rawLang != null && rawLang.isNotEmpty) ? rawLang.toUpperCase() : 'PL';

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

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    await _prepareDio();

    final response = await _dio!.get('/');
    final bootstrapData = extractBootstrapData(response.data);

    return bootstrapData != null
        ? _parseMoviesFromData(bootstrapData)
        : <ServiceMovieModel>[];
  }

  List<ServiceMovieModel> _parseMoviesFromData(Map<String, dynamic> data) {
    final loaders = data['loaders']?['channelPage']?['channel']?['content']
        ?['data'] as List?;
    if (loaders == null) return <ServiceMovieModel>[];

    return loaders
        .expand((loader) => _parseMoviesFromLoader(loader))
        .whereType<ServiceMovieModel>()
        .toList();
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
            ?.map((movieData) => _parseMovie(movieData, loaderName)) ??
        [];
  }

  ServiceMovieModel? _parseMovie(Map<String, dynamic> data, String? category) {
    final name = (data['name'] as String?)?.trim();
    final poster = (data['poster'] as String?)?.trim();
    final primaryVideo = data['primary_video'];

    if (name == null ||
        name.isEmpty ||
        poster == null ||
        poster.isEmpty ||
        primaryVideo is! Map) {
      return null;
    }

    final primaryVideoId = primaryVideo['id'];
    if (primaryVideoId == null) return null;

    final isSeries = data['is_series']?.toString() == 'true';

    // Filter out items where primary_video is only a trailer or YouTube link
    if (_isTrailerOrYoutube(primaryVideo)) {
      if (!isSeries) {
        return null;
      }
      final seasonsCount = (data['seasons_count'] as int?) ?? 1;
      if (seasonsCount <= 0) {
        return null;
      }
    }

    final watchUrl = '/watch/$primaryVideoId';
    if (_settingsService.isUrlLinkless(watchUrl)) {
      return null;
    }

    return ServiceMovieModel(
      service: SupportedService.obejrzyjto,
      title: name,
      imageUrl: poster,
      url: watchUrl,
      category: category ?? '',
    );
  }
}
