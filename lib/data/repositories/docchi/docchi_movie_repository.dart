import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';

class DocchiMovieRepository implements MovieRepository {
  static const String _apiBase = 'https://api.docchi.pl/v1';
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://docchi.pl/',
    'Origin': 'https://docchi.pl',
    'Accept': 'application/json',
  };

  static List<Map<String, dynamic>>? _cachedSeriesList;
  static DateTime? _cacheTime;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _apiBase,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    headers: _headers,
  ));

  static Future<List<Map<String, dynamic>>> getSeriesCatalog(Dio dio) async {
    final now = DateTime.now();
    if (_cachedSeriesList != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!).inMinutes < 20) {
      return _cachedSeriesList!;
    }
    final resp = await dio.get('/series/list');
    if (resp.data is List) {
      final list = (resp.data as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) =>
              e['adult_content']?.toString().toLowerCase() != 'true' &&
              (e['slug']?.toString().trim().isNotEmpty ?? false))
          .toList();
      _cachedSeriesList = list;
      _cacheTime = now;
      return list;
    }
    return const [];
  }

  static String _pickDisplayTitle(Map item) {
    final en = (item['title_en'] ?? '').toString().trim();
    final main = (item['title'] ?? '').toString().trim();
    return en.isNotEmpty ? en : main;
  }

  static String _normalizeCover(dynamic raw) {
    var u = (raw ?? '').toString().trim();
    if (u.startsWith('//')) u = 'https:$u';
    return u;
  }

  static int _hostPriority(String hosting) {
    final h = hosting.toLowerCase();
    if (h.contains('cda')) return 0;
    if (h.contains('byse') || h.contains('filemoon')) return 1;
    if (h.contains('vidara')) return 2;
    if (h.contains('lulustream') || h.contains('luluvdo')) return 3;
    if (h.contains('earnvids') || h.contains('vidhide') || h.contains('filelions')) {
      return 4;
    }
    if (h.contains('dood') || h.contains('playmogo')) return 5;
    if (h.contains('mp4upload')) return 6;
    if (h.contains('ok')) return 7;
    if (h.contains('vidmoly')) return 8;
    if (h.contains('streamtape')) return 9;
    return 15;
  }

  static List<HostLink> _parseEpisodePlayers(dynamic data) {
    if (data is! List) return const [];
    final sorted = data.whereType<Map>().toList()
      ..sort((a, b) => _hostPriority((a['player_hosting'] ?? '').toString())
          .compareTo(_hostPriority((b['player_hosting'] ?? '').toString())));

    final out = <HostLink>[];
    final seenUrls = <String>{};
    for (final item in sorted) {
      var playerUrl = (item['player'] ?? '').toString().trim();
      if (playerUrl.isEmpty || !playerUrl.startsWith('http')) continue;
      if (!seenUrls.add(playerUrl)) continue;

      final hosting = (item['player_hosting'] ?? '').toString().trim();
      final hLower = hosting.toLowerCase();
      // Skip hostings without extractable embed streams
      if (hLower.contains('mega') ||
          hLower.contains('google drive') ||
          hLower.contains('gdrive') ||
          hLower.contains('lycoris')) {
        continue;
      }

      final translator = (item['translator_title'] ?? '').toString().trim();
      final langLabel = translator.isNotEmpty && hosting.isNotEmpty
          ? 'Napisy PL • $translator ($hosting)'
          : (hosting.isNotEmpty ? 'Napisy PL ($hosting)' : 'Napisy PL');

      out.add(HostLink(
        url: playerUrl,
        lang: langLabel,
        quality: 'HD',
      ));
    }
    return out;
  }

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    final results = <ServiceMovieModel>[];
    final seenSlugs = <String>{};

    final latestFuture = _dio
        .get('/episodes/latest')
        .then((r) => r.data)
        .catchError((_) => null);
    final catalogFuture =
        getSeriesCatalog(_dio).catchError((_) => <Map<String, dynamic>>[]);

    final latestData = await latestFuture;
    final catalog = await catalogFuture;

    // 1. Latest anime episodes deduplicated by series
    if (latestData is List) {
      for (final item in latestData) {
        if (item is! Map) continue;
        final slug = (item['anime_id'] ?? '').toString().trim();
        final title = _pickDisplayTitle(item);
        final cover = _normalizeCover(item['cover']);
        if (slug.isEmpty || title.isEmpty || !seenSlugs.add(slug)) continue;
        results.add(ServiceMovieModel(
          service: SupportedService.docchi,
          url: '/docchi/series/$slug',
          title: title,
          imageUrl: cover,
          category: 'Anime|Seriale',
        ));
        if (results.length >= 28) break;
      }
    }

    // 2. Popular / recent anime series & anime movies from catalog
    if (catalog.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(catalog)
        ..sort((a, b) {
          final ya = int.tryParse((a['season_year'] ?? '').toString()) ?? 0;
          final yb = int.tryParse((b['season_year'] ?? '').toString()) ?? 0;
          return yb.compareTo(ya);
        });

      int movieAdded = 0;
      int seriesAdded = 0;
      for (final item in sorted) {
        final slug = (item['slug'] ?? '').toString().trim();
        final title = _pickDisplayTitle(item);
        final cover = _normalizeCover(item['cover']);
        if (slug.isEmpty || title.isEmpty || cover.isEmpty) continue;
        if (!seenSlugs.add(slug)) continue;

        final sType = (item['series_type'] ?? '').toString().toUpperCase();
        final epCount = int.tryParse((item['episodes'] ?? '').toString()) ?? 0;
        final isMovie = sType == 'MOVIE' && epCount <= 1;

        if (isMovie && movieAdded < 18) {
          movieAdded++;
          results.add(ServiceMovieModel(
            service: SupportedService.docchi,
            url: '/docchi/movie/$slug',
            title: title,
            imageUrl: cover,
            category: 'Anime',
          ));
        } else if (!isMovie && seriesAdded < 14) {
          seriesAdded++;
          results.add(ServiceMovieModel(
            service: SupportedService.docchi,
            url: '/docchi/series/$slug',
            title: title,
            imageUrl: cover,
            category: 'Anime|Seriale',
          ));
        }
        if (movieAdded >= 18 && seriesAdded >= 14) break;
      }
    }

    return results;
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    final isExplicitMovie = url.contains('/docchi/movie/');
    final slug = url.split('/').where((e) => e.isNotEmpty).last;

    final seriesFuture =
        _dio.get('/series/find/$slug').then((r) => r.data).catchError((_) => null);
    final countFuture = _dio
        .get('/episodes/count/$slug')
        .then((r) => r.data)
        .catchError((_) => null);

    final seriesData = await seriesFuture;
    final countData = await countFuture;

    String title = slug.replaceAll('-', ' ');
    String description = '';
    String imageUrl = '';
    int totalEpisodes = 0;
    String seriesType = '';

    if (seriesData is Map) {
      title = _pickDisplayTitle(seriesData);
      description = (seriesData['description'] ?? '').toString().trim();
      imageUrl = _normalizeCover(seriesData['cover']);
      totalEpisodes =
          int.tryParse((seriesData['episodes'] ?? '').toString()) ?? 0;
      seriesType = (seriesData['series_type'] ?? '').toString().toUpperCase();
    }

    final availableEps = <int>[];
    if (countData is List) {
      for (final e in countData) {
        if (e is Map) {
          final num = int.tryParse(
              (e['anime_episode_number'] ?? '').toString());
          if (num != null && num > 0 && !availableEps.contains(num)) {
            availableEps.add(num);
          }
        }
      }
      availableEps.sort();
    }

    if (availableEps.isEmpty && totalEpisodes > 0) {
      for (int i = 1; i <= totalEpisodes; i++) {
        availableEps.add(i);
      }
    }
    if (availableEps.isEmpty) {
      availableEps.add(1);
    }

    final treatAsMovie =
        (isExplicitMovie || seriesType == 'MOVIE') && availableEps.length <= 1;

    if (treatAsMovie) {
      final epNum = availableEps.first;
      List<HostLink> links = const [];
      try {
        final epResp = await _dio.get('/episodes/find/$slug/$epNum');
        links = _parseEpisodePlayers(epResp.data);
      } catch (e) {
        debugPrint('Docchi movie hosts error ($slug): $e');
      }
      return ServiceMovieDetailsModel(
        service: SupportedService.docchi,
        url: url,
        title: title,
        description: description,
        imageUrl: imageUrl,
        isSeries: false,
        videoUrls: links,
      );
    }

    final episodes = availableEps
        .map((epNum) => EpisodeModel(
              number: epNum,
              title: 'Odcinek $epNum',
              url: '/docchi/ep/$slug/$epNum',
              videoUrls: const [],
            ))
        .toList();

    return ServiceMovieDetailsModel(
      service: SupportedService.docchi,
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      isSeries: true,
      seasons: [SeasonModel(number: 1, episodes: episodes)],
    );
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    final parts = episode.url.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length < 4) return episode;
    final slug = parts[parts.length - 2];
    final epNum = parts.last;

    try {
      final resp = await _dio.get('/episodes/find/$slug/$epNum');
      final links = _parseEpisodePlayers(resp.data);
      return episode.copyWith(videoUrls: links);
    } catch (e) {
      debugPrint('Docchi episode hosts error ($slug/$epNum): $e');
      return episode;
    }
  }
}
