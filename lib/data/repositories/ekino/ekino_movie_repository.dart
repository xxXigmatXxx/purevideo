import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Cookie;
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/ekino/ekino_dio_factory.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

class _EkinoTabCandidate {
  final String hostName;
  final String hostId;
  final String language;
  final String quality;
  final int priority;

  const _EkinoTabCandidate({
    required this.hostName,
    required this.hostId,
    required this.language,
    required this.quality,
    required this.priority,
  });
}

class EkinoMovieRepository implements MovieRepository {
  final AuthRepository _authRepository =
      getIt<Map<SupportedService, AuthRepository>>()[SupportedService.ekino]!;
  Dio? _dio;
  final Map<String, String> _sessionCookies = {};

  static const Set<String> _deadHosts = {
    'upzone',
    'hqq',
    'flashx',
    'bit',
    'rload',
    'clip',
    'playerbox',
    'openload',
    'vidtodo',
    'streamango',
    'vshare',
  };

  EkinoMovieRepository() {
    _authRepository.authStream.listen(_onAuthChanged);
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.ekino) {
      _dio = EkinoDioFactory.getDio(auth.account);
      _applySessionCookiesToDio();
    }
  }

  String _cleanTitle(String rawTitle) {
    var t = rawTitle.replaceAll('\u00a0', ' ').trim();
    if (t.contains(' / ')) {
      t = t.split(' / ').first.trim();
    }
    t = t
        .replaceAll(
          RegExp(
            r'\s*-\s*(?:HD|CAM|4K|FHD|AI|PL|Dubbing|Lektor|Napisy)(?:\s+.*)?$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return t.isEmpty ? rawTitle.trim() : t;
  }

  String _normalizeImageUrl(String raw) {
    var u = raw.trim().replaceAll('/static/thumb/', '/static/normal/');
    if (u.isEmpty) return '';
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return '${SupportedService.ekino.baseUrl}$u';
    return u;
  }

  void _applySessionCookiesToDio() {
    if (_dio == null) return;
    _dio!.options.headers['User-Agent'] = WebViewService.cleanUserAgent;
    if (_sessionCookies.isEmpty) return;
    final existing = (_dio!.options.headers['Cookie']?.toString() ?? '').trim();
    final map = <String, String>{};
    if (existing.isNotEmpty) {
      for (final part in existing.split(';')) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          final k = part.substring(0, idx).trim();
          final v = part.substring(idx + 1).trim();
          if (k.isNotEmpty && v.isNotEmpty && v != 'deleted') {
            map[k] = v;
          }
        }
      }
    }
    map.addAll(_sessionCookies);
    _dio!.options.headers['Cookie'] =
        map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> _syncCookiesFromWebView() async {
    try {
      final cm = CookieManager.instance();
      final cookies = await cm.getCookies(url: WebUri('https://ekino.ws'));
      for (final c in cookies) {
        if (c.name.isNotEmpty &&
            c.value.isNotEmpty &&
            c.value != 'deleted') {
          _sessionCookies[c.name] = c.value;
        }
      }
      _applySessionCookiesToDio();
    } catch (_) {}
  }

  void _saveSetCookiesFromResponse(Response response) {
    try {
      final setCookies = response.headers['set-cookie'];
      if (setCookies == null || setCookies.isEmpty) return;
      for (final sc in setCookies) {
        final lower = sc.toLowerCase();
        final firstPart = sc.split(';').first.trim();
        final idx = firstPart.indexOf('=');
        if (idx > 0) {
          final name = firstPart.substring(0, idx).trim();
          final value = firstPart.substring(idx + 1).trim();
          if (value == 'deleted' ||
              lower.contains('max-age=0') ||
              lower.contains('1970')) {
            _sessionCookies.remove(name);
            continue;
          }
          if (name == 'PHPSESSID' && _sessionCookies.containsKey('PHPSESSID')) {
            continue;
          }
          if (name.isNotEmpty && value.isNotEmpty) {
            _sessionCookies[name] = value;
          }
        }
      }
      _applySessionCookiesToDio();
    } catch (_) {}
  }

  Future<void> _prepareDio() async {
    _dio ??= EkinoDioFactory.getDio(
      _authRepository.getAccount(),
    );
    _dio!.options.headers['User-Agent'] = WebViewService.cleanUserAgent;
    _applySessionCookiesToDio();
  }

  int _hostPriority(String host) {
    final h = host.toLowerCase().trim();
    if (h == 'voe') return 1;
    if (h == 'shvid') return 2;
    if (h == 'wrzucaj' || h == 'vidoza') return 3;
    if (h == 'file1' || h == 'vmoly') return 4;
    if (h == 'dood') return 5;
    if (h == 'mix') return 6;
    if (h == 'player') return 7;
    return 8;
  }

  Future<List<HostLink>> _extractHostLinksFromDocument(
      dom.Document document) async {
    final videoUrls = <HostLink>[];

    final tabPanes =
        document.querySelectorAll('.tab-content .tab-pane[role="tabpanel"]');
    final playerTabs = document.querySelectorAll('#myTab li');

    final candidates = <_EkinoTabCandidate>[];

    for (int i = 0; i < tabPanes.length && i < playerTabs.length; i++) {
      final tabPane = tabPanes[i];
      final playerTab = playerTabs[i];

      final tabId = tabPane.attributes['id'] ?? '';
      if (tabId.isEmpty || tabId == 'premium' || tabId == 'rek') continue;

      final onclickLink = tabPane.querySelector('a[onclick]');
      if (onclickLink == null) continue;

      final onclick = onclickLink.attributes['onclick'] ?? '';
      if (onclick.isEmpty) continue;

      final onclickMatch = RegExp(
        r"ShowPlayer\s*\(\s*'([^']+)'\s*,\s*'([^']+)'\s*\)",
      ).firstMatch(onclick);
      if (onclickMatch == null) continue;

      final hostName = (onclickMatch.group(1) ?? '').trim();
      final hostId = (onclickMatch.group(2) ?? '').trim();
      if (hostName.isEmpty || hostId.isEmpty) continue;

      final lowerHost = hostName.toLowerCase();
      if (_deadHosts.any((dead) => lowerHost.contains(dead))) continue;

      final languageIcon = playerTab.querySelector('i.glyphicon');
      final language = languageIcon?.attributes['title']?.trim() ?? 'PL';

      final qualityIcon = playerTab.querySelector('img');
      final quality = qualityIcon?.attributes['title']?.trim() ?? 'HD';

      candidates.add(_EkinoTabCandidate(
        hostName: hostName,
        hostId: hostId,
        language: language,
        quality: quality,
        priority: _hostPriority(lowerHost),
      ));
    }

    candidates.sort((a, b) => a.priority.compareTo(b.priority));

    bool turnstileAttempted = false;
    bool turnstileCancelled = false;
    int gatesQueried = 0;

    for (final cand in candidates) {
      if (turnstileCancelled) break;
      if (videoUrls.length >= 2 || gatesQueried >= 2) break;
      gatesQueried++;

      final gateUrl = '/watch/f/${cand.hostName}/${cand.hostId}';
      String? videoUrl;

      try {
        final gateResp = await _dio!.get(gateUrl);
        _saveSetCookiesFromResponse(gateResp);
        final gateDoc = html.parse(gateResp.data);
        videoUrl = gateDoc.querySelector('a.buttonprch')?.attributes['href'] ??
            gateDoc.querySelector('a[href*="play.ekino"]')?.attributes['href'];

        if ((videoUrl == null || videoUrl.isEmpty) &&
            !turnstileAttempted &&
            videoUrls.isEmpty) {
          turnstileAttempted = true;
          _sessionCookies.remove('PHPSESSID');
          final elem = await getIt<WebViewService>().waitForDomElement(
            '${SupportedService.ekino.baseUrl}$gateUrl',
            'a.buttonprch',
          );
          await _syncCookiesFromWebView();
          videoUrl = elem?.attributes['href'];
          if (videoUrl == null || videoUrl.isEmpty) {
            turnstileCancelled = true;
            break;
          }
        }

        if (videoUrl != null && videoUrl.startsWith('//')) {
          videoUrl = 'https:$videoUrl';
        }
        if (videoUrl != null &&
            (videoUrl.contains('ekino.link') ||
                videoUrl.contains('play.ekino') ||
                videoUrl.contains('ekino-tv'))) {
          final cookieHdr = _dio!.options.headers['Cookie']?.toString() ?? '';
          final linkResp = await Dio(BaseOptions(
            headers: {
              'User-Agent': WebViewService.cleanUserAgent,
              'Referer': '${SupportedService.ekino.baseUrl}$gateUrl',
              if (cookieHdr.isNotEmpty) 'Cookie': cookieHdr,
            },
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
            validateStatus: (_) => true,
          )).get(videoUrl);
          final linkDoc = html.parse(linkResp.data);
          var ifr = linkDoc.querySelector('iframe')?.attributes['src']?.trim();
          if (ifr != null && ifr.startsWith('//')) ifr = 'https:$ifr';
          if (ifr != null && ifr.startsWith('http')) {
            videoUrl = ifr;
          }
        }
      } catch (e) {
        debugPrint('Ekino gate extraction error: $e');
      }

      if (videoUrl == null ||
          videoUrl.isEmpty ||
          videoUrl.contains('upzone.cc') ||
          videoUrl.contains('ekino.link') ||
          videoUrl.contains('play.ekino')) {
        continue;
      }

      videoUrls.add(HostLink(
        url: videoUrl,
        lang: cand.language,
        quality: cand.quality,
      ));
    }

    return videoUrls;
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    await _prepareDio();
    final episodeResponse = await _dio!.get(episode.url);
    _saveSetCookiesFromResponse(episodeResponse);
    final document = html.parse(episodeResponse.data);
    final videoUrls = await _extractHostLinksFromDocument(document);

    return episode.copyWith(
      videoUrls: videoUrls,
    );
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    await _prepareDio();

    final response = await _dio!.get(url);
    _saveSetCookiesFromResponse(response);
    final document = html.parse(response.data);

    final titleElement = document.querySelector('h1.title');
    final title = titleElement?.text.trim() ?? 'Brak tytułu';
    final cleanTitle = _cleanTitle(title);

    final descriptionElement = document.querySelector('.descriptionMovie');
    String description = descriptionElement?.text.trim() ?? '';

    final lines = description.split('\n');
    final cleanLines = <String>[];
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('Edit:')) {
        cleanLines.add(trimmedLine);
      }
    }
    description = cleanLines.join('\n');

    final posterElement = document.querySelector('.moviePoster');
    final imageUrl =
        _normalizeImageUrl(posterElement?.attributes['src'] ?? '');

    final isSeries = document.querySelector('#list-series') != null;

    if (isSeries) {
      final seasons = <SeasonModel>[];
      final seriesContainer = document.querySelector('#list-series');

      if (seriesContainer != null) {
        final children = seriesContainer.children;
        for (int i = 0; i < children.length; i += 2) {
          final seasonElement = children[i];
          if (seasonElement.localName != 'p') continue;

          final seasonName = seasonElement.text.trim();
          if (i + 1 >= children.length) continue;

          final episodesList = children[i + 1];
          if (episodesList.localName != 'ul' ||
              !episodesList.classes.contains('list-series')) {
            continue;
          }

          final seasonNumberMatch =
              RegExp(r'Sezon (\d+)').firstMatch(seasonName);
          final seasonNumber = seasonNumberMatch != null
              ? int.tryParse(seasonNumberMatch.group(1) ?? '0') ?? 0
              : 0;

          final episodes = <EpisodeModel>[];

          for (final episodeItem in episodesList.children) {
            final episodeLink = episodeItem.querySelector('a');
            if (episodeLink == null) continue;

            final episodeUrl = episodeLink.attributes['href'] ?? '';
            if (episodeUrl.isEmpty) continue;

            final episodeTitle = episodeLink.text.trim();
            final episodeNumberDiv = episodeItem.querySelector('div');
            final episodeNumber = episodeNumberDiv != null
                ? int.tryParse(episodeNumberDiv.text.trim()) ?? 0
                : 0;

            episodes.add(EpisodeModel(
              title: episodeTitle,
              number: episodeNumber,
              url: episodeUrl,
              videoUrls: [],
            ));
          }

          seasons.add(SeasonModel(
            number: seasonNumber,
            episodes: episodes.reversed.toList(),
          ));
        }
      }

      return ServiceMovieDetailsModel(
        service: SupportedService.ekino,
        url: url,
        title: cleanTitle,
        description: description,
        imageUrl: imageUrl,
        isSeries: true,
        seasons: seasons.reversed.toList(),
      );
    }

    final videoUrls = await _extractHostLinksFromDocument(document);
    debugPrint('Extracted Ekino video URLs: $videoUrls');

    return ServiceMovieDetailsModel(
      service: SupportedService.ekino,
      url: url,
      title: cleanTitle,
      description: description,
      imageUrl: imageUrl,
      isSeries: false,
      videoUrls: videoUrls,
    );
  }

  Future<List<ServiceMovieModel>> _fetchCategoryPage(
      String path, String categoryLabel) async {
    try {
      final resp =
          await _dio!.get(path).timeout(const Duration(seconds: 12));
      _saveSetCookiesFromResponse(resp);
      final doc = html.parse(resp.data);
      final list = <ServiceMovieModel>[];
      for (final movieElement in doc.querySelectorAll('.movies-list-item')) {
        final coverElement = movieElement.querySelector('.cover-list a');
        if (coverElement == null) continue;
        final url = (coverElement.attributes['href'] ?? '').trim();
        if (url.isEmpty) continue;
        final rawImg =
            coverElement.querySelector('img')?.attributes['src'] ?? '';
        final imageUrl = _normalizeImageUrl(rawImg);
        final titleElement = movieElement.querySelector('.opis-list .title a');
        if (titleElement == null) continue;
        final cleanTitle = _cleanTitle(titleElement.text);
        if (cleanTitle.isEmpty || imageUrl.isEmpty) continue;
        list.add(ServiceMovieModel(
          service: SupportedService.ekino,
          title: cleanTitle,
          imageUrl: imageUrl,
          url: url,
          category: categoryLabel,
        ));
      }
      return list;
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
              await _dio!.get('/').timeout(const Duration(seconds: 12));
          _saveSetCookiesFromResponse(response);
          final document = html.parse(response.data);
          final movies = <ServiceMovieModel>[];
          final movieSections = document.querySelectorAll('.mostPopular');

          for (final section in movieSections) {
            final categoryElement = section.querySelector('h4');
            if (categoryElement == null) continue;

            final subCategoryElement = section.querySelector('span');
            String category =
                categoryElement.text.replaceAll('!', '').trim();
            if (subCategoryElement != null && category == 'Najpopularniejsze') {
              category += ' ${subCategoryElement.text.trim()}';
            }

            final movieList = section.querySelector('ul.list');
            if (movieList == null) continue;

            for (final item in movieList.children) {
              final leftScope = item.querySelector('.scope_left');
              if (leftScope == null) continue;

              final link = leftScope.querySelector('a');
              if (link == null) continue;

              final url = (link.attributes['href'] ?? '').trim();
              if (url.isEmpty) continue;

              final img = link.querySelector('img');
              if (img == null) continue;

              final imageUrl =
                  _normalizeImageUrl(img.attributes['src'] ?? '');
              final rawTitle = img.attributes['alt']?.trim() ?? '';
              final cleanTitle = _cleanTitle(rawTitle);

              if (cleanTitle.isEmpty || imageUrl.isEmpty) continue;

              movies.add(ServiceMovieModel(
                service: SupportedService.ekino,
                title: cleanTitle,
                imageUrl: imageUrl,
                url: url,
                category: category,
              ));
            }
          }
          return movies;
        } catch (_) {
          return <ServiceMovieModel>[];
        }
      }(),
      _fetchCategoryPage('/movie/cat/kategoria[2,5]', 'Bajki dla dzieci'),
      _fetchCategoryPage('/movie/cat/kategoria[12]', 'Familijne'),
      _fetchCategoryPage('/movie/cat/kategoria[1]', 'Akcja'),
      _fetchCategoryPage('/movie/cat/kategoria[17]', 'Komedia'),
      _fetchCategoryPage('/movie/cat/kategoria[15]', 'Horror'),
      _fetchCategoryPage('/movie/cat/kategoria[31]', 'Thriller'),
      _fetchCategoryPage('/movie/cat/kategoria[28]', 'Sci-Fi'),
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
    ];
  }
}
