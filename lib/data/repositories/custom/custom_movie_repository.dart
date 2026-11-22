import 'package:diacritic/diacritic.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_movie_repository.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/di/injection_container.dart';

class CustomMovieRepository implements MovieRepository {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': WebViewService.cleanUserAgent,
    },
  ));

  static String encodeCustomUrl(String sourceId, String targetUrl) =>
      'custom://$sourceId|$targetUrl';

  static String encodeMediaUrl(ExtraMediaEntry entry) =>
      entry.isSeries ? 'custom://media_serial|${entry.id}' : 'custom://media_film|${entry.id}';

  static (String kindOrId, String payload)? parseCustomUrl(String url) {
    if (!url.startsWith('custom://')) return null;
    final rest = url.substring('custom://'.length);
    final sep = rest.indexOf('|');
    if (sep <= 0) return null;
    return (rest.substring(0, sep), rest.substring(sep + 1));
  }

  static String resolveUrl(String baseUrl, String raw) {
    final u = raw.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return '$baseUrl$u';
    return '$baseUrl/$u';
  }

  static List<HostLink> extractGenericHtmlEmbeds(String body, String baseUrl) {
    final doc = html.parse(body);
    final links = <HostLink>[];
    final seen = <String>{};

    void addEmbed(String raw) {
      var u = raw.trim();
      if (u.startsWith('//')) u = 'https:$u';
      if (u.startsWith('/')) u = '$baseUrl$u';
      if (!u.startsWith('http')) return;
      final lower = u.toLowerCase();
      if (lower.contains('youtube.com') ||
          lower.contains('youtu.be') ||
          lower.contains('facebook.com') ||
          lower.contains('doubleclick') ||
          lower.contains('googletagmanager') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.css') ||
          lower.endsWith('.js')) {
        return;
      }
      if (!seen.add(u)) return;
      links.add(HostLink(url: u, lang: 'PL', quality: 'HD'));
    }

    for (final ifr in doc.querySelectorAll('iframe')) {
      final src = ifr.attributes['src'] ?? ifr.attributes['data-src'] ?? '';
      if (src.isNotEmpty) addEmbed(src);
    }
    for (final srcTag in doc.querySelectorAll('source')) {
      final src = srcTag.attributes['src'] ?? '';
      if (src.isNotEmpty) addEmbed(src);
    }

    if (links.isEmpty) {
      final rx = RegExp(
        r'''https?://(?:ebd\.cda\.pl|(?:www\.)?cda\.pl/video/|vider\.(?:info|pl)/|goodstream\.vip|voe\.sx|dood\.|lulustream\.|vidmoly\.|vidara\.|streamtape\.|mixdrop\.|mp4upload\.|ok\.ru)[^\s"'<>]+''',
        caseSensitive: false,
      );
      for (final m in rx.allMatches(body)) {
        addEmbed(m.group(0) ?? '');
      }
    }
    return links;
  }

  static List<ServiceMovieModel> parseHtmlCards(
    String htmlBody,
    ExtraSourceConfig src, {
    int limit = 30,
  }) {
    final doc = html.parse(htmlBody);
    final out = <ServiceMovieModel>[];
    final seenUrls = <String>{};

    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (href.isEmpty ||
          href == '#' ||
          href.startsWith('javascript:') ||
          href.contains('/tag/') ||
          href.contains('/page/') ||
          href.contains('/login') ||
          href.contains('/rejestracja') ||
          href.contains('zwiastun')) {
        continue;
      }
      final img = a.querySelector('img');
      if (img == null) continue;
      final rawImg = img.attributes['data-src'] ??
          img.attributes['data-lazy-src'] ??
          img.attributes['src'] ??
          '';
      final imgUrl = resolveUrl(src.baseUrl, rawImg);
      if (imgUrl.isEmpty ||
          imgUrl.contains('logo') ||
          imgUrl.contains('avatar') ||
          imgUrl.startsWith('data:')) {
        continue;
      }

      var title = (a.attributes['title'] ?? img.attributes['alt'] ?? a.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty || title.length < 2 || title.length > 120) continue;
      if (title.toLowerCase().contains('zwiastun')) continue;

      final fullUrl = resolveUrl(src.baseUrl, href);
      if (!fullUrl.startsWith('http') || !seenUrls.add(fullUrl)) continue;

      out.add(ServiceMovieModel(
        service: SupportedService.custom,
        url: encodeCustomUrl(src.id, fullUrl),
        title: title,
        imageUrl: imgUrl,
        category: src.category.isNotEmpty ? src.category : src.name,
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  Future<List<ServiceMovieModel>> _loadFromSource(ExtraSourceConfig src) async {
    try {
      switch (src.type) {
        case ExtraSourceType.wordpress:
          final resp = await _dio.get(
            '${src.baseUrl}/wp-json/wp/v2/posts',
            queryParameters: {'per_page': 24, '_embed': 1},
            options: Options(headers: {'Referer': '${src.baseUrl}/'}),
          );
          if (resp.data is! List) return const [];
          final out = <ServiceMovieModel>[];
          for (final item in (resp.data as List).whereType<Map>()) {
            final id = item['id'];
            if (id == null) continue;
            final rawTitle = (item['title']?['rendered'] ?? '').toString();
            if (BajeczkiMovieRepository.isTrailerOrPromo(rawTitle)) continue;
            final content = (item['content']?['rendered'] ?? '').toString();
            if (BajeczkiMovieRepository.extractEmbedLinks(content).isEmpty) {
              continue;
            }
            final title = BajeczkiMovieRepository.cleanDisplayTitle(rawTitle);
            final poster = BajeczkiMovieRepository.extractFeaturedPoster(item);
            if (title.isEmpty) continue;
            out.add(ServiceMovieModel(
              service: SupportedService.custom,
              url: encodeCustomUrl(
                  src.id, '${src.baseUrl}/wp-json/wp/v2/posts/$id'),
              title: title,
              imageUrl: poster,
              category: src.category.isNotEmpty ? src.category : src.name,
            ));
          }
          return out;

        case ExtraSourceType.ekinoMirror:
          final resp = await _dio.get<String>(
            '${src.baseUrl}/',
            options: Options(headers: {'Referer': '${src.baseUrl}/'}),
          );
          final doc = html.parse(resp.data ?? '');
          final out = <ServiceMovieModel>[];
          final seen = <String>{};
          for (final a in doc.querySelectorAll('a[href]')) {
            final href = (a.attributes['href'] ?? '').trim();
            if (!href.contains('/movie/show/') &&
                !href.contains('/serie/show/')) {
              continue;
            }
            final full = resolveUrl(src.baseUrl, href);
            if (!seen.add(full)) continue;
            final img = a.querySelector('img');
            final rawImg =
                img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
            final imgUrl = resolveUrl(src.baseUrl, rawImg)
                .replaceAll('/static/thumb/', '/static/normal/');
            var title =
                (a.attributes['title'] ?? img?.attributes['alt'] ?? a.text)
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
            if (title.contains(' / ')) title = title.split(' / ').first.trim();
            if (title.isEmpty) continue;
            out.add(ServiceMovieModel(
              service: SupportedService.custom,
              url: encodeCustomUrl(src.id, full),
              title: title,
              imageUrl: imgUrl,
              category: href.contains('/serie/')
                  ? 'Popularne seriale'
                  : (src.category.isNotEmpty ? src.category : 'Popularne filmy'),
            ));
            if (out.length >= 25) break;
          }
          return out;

        case ExtraSourceType.htmlAuto:
          final resp = await _dio.get<String>(
            '${src.baseUrl}/',
            options: Options(headers: {'Referer': '${src.baseUrl}/'}),
          );
          return parseHtmlCards(resp.data ?? '', src, limit: 25);
      }
    } catch (e) {
      debugPrint('Custom source load failed (${src.name}): $e');
      return const [];
    }
  }

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    final extra = getIt<ExtraSourcesService>();
    final out = <ServiceMovieModel>[];

    // 1. Curated Films & Series (added via CDA / Vider.info)
    for (final media in extra.getAllActiveCustomMedia()) {
      final defaultCat =
          media.isSeries ? 'Popularne seriale' : 'Popularne filmy';
      final cat = media.category.isNotEmpty
          ? (media.isSeries && !media.category.toLowerCase().contains('serial')
              ? '${media.category}|Popularne seriale'
              : media.category)
          : defaultCat;
      out.add(ServiceMovieModel(
        service: SupportedService.custom,
        url: encodeMediaUrl(media),
        title: media.title,
        imageUrl: media.posterUrl,
        category: '$cat|Źródła dodatkowe',
      ));
    }

    // 2. Optional website sources
    final sources = extra.getAllActiveCustomSources();
    if (sources.isNotEmpty) {
      final lists = await Future.wait(
        sources.map((s) => _loadFromSource(s)
            .timeout(const Duration(seconds: 12), onTimeout: () => const [])),
      );
      out.addAll(lists.expand((e) => e));
    }
    return out;
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    final parsed = parseCustomUrl(url);
    if (parsed == null) {
      throw Exception('Nieprawidłowy adres dodatkowego źródła');
    }
    final kindOrId = parsed.$1;
    final targetUrl = parsed.$2;
    final extra = getIt<ExtraSourcesService>();

    if (kindOrId == 'media_film' ||
        kindOrId == 'media_serial' ||
        kindOrId == 'media') {
      final media = extra.findMediaById(targetUrl);
      if (media == null) {
        throw Exception('Nie znaleziono dodanej pozycji w źródłach dodatkowych');
      }
      if (!media.isSeries) {
        return ServiceMovieDetailsModel(
          service: SupportedService.custom,
          url: url,
          title: media.title,
          description: media.description,
          imageUrl: media.posterUrl,
          isSeries: false,
          videoUrls: media.links
              .map((l) => HostLink(url: l.url, lang: l.lang, quality: l.quality))
              .toList(),
        );
      }
      final seasons = media.seasons
          .map((s) => SeasonModel(
                number: s.number,
                episodes: s.episodes
                    .map((ep) => EpisodeModel(
                          title: ep.title.isNotEmpty
                              ? ep.title
                              : 'Odcinek ${ep.number}',
                          number: ep.number,
                          url: 'custom://episode|${media.id}|${s.number}|${ep.number}',
                          videoUrls: ep.links
                              .map((l) => HostLink(
                                    url: l.url,
                                    lang: l.lang,
                                    quality: l.quality,
                                  ))
                              .toList(),
                        ))
                    .toList(),
              ))
          .toList();
      return ServiceMovieDetailsModel(
        service: SupportedService.custom,
        url: url,
        title: media.title,
        description: media.description,
        imageUrl: media.posterUrl,
        isSeries: true,
        seasons: seasons,
      );
    }

    final src = extra.findById(kindOrId);
    final baseUrl = src?.baseUrl ?? Uri.tryParse(targetUrl)?.origin ?? '';

    if (src?.type == ExtraSourceType.wordpress &&
        targetUrl.contains('/wp-json/wp/v2/posts/')) {
      final resp = await _dio.get(
        '$targetUrl?_embed=1',
        options: Options(headers: {'Referer': '$baseUrl/'}),
      );
      if (resp.data is! Map) {
        throw Exception('Błąd pobierania danych wpisu');
      }
      final post = resp.data as Map;
      final title = BajeczkiMovieRepository.cleanDisplayTitle(
          (post['title']?['rendered'] ?? '').toString());
      final content = (post['content']?['rendered'] ?? '').toString();
      final desc = html
          .parse(post['excerpt']?['rendered']?.toString() ?? content)
          .body!
          .text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final poster = BajeczkiMovieRepository.extractFeaturedPoster(post);
      final links = BajeczkiMovieRepository.extractEmbedLinks(content);
      return ServiceMovieDetailsModel(
        service: SupportedService.custom,
        url: url,
        title: title.isEmpty ? 'Wideo' : title,
        description: desc,
        imageUrl: poster,
        isSeries: false,
        videoUrls: links,
      );
    }

    final resp = await _dio.get<String>(
      targetUrl,
      options: Options(headers: {'Referer': '$baseUrl/'}),
    );
    final body = resp.data ?? '';
    final doc = html.parse(body);
    var title = doc
            .querySelector('meta[property="og:title"]')
            ?.attributes['content'] ??
        doc.querySelector('h1')?.text ??
        doc.querySelector('title')?.text ??
        'Wideo';
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final desc = doc
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'] ??
        doc.querySelector('meta[name="description"]')?.attributes['content'] ??
        '';
    final img = resolveUrl(
      baseUrl,
      doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
          '',
    );

    if (src?.type == ExtraSourceType.ekinoMirror &&
        targetUrl.contains('/movie/show/')) {
      final matches = RegExp(
        r"ShowPlayer\s*\(\s*'([^']+)'\s*,\s*'([^']+)'\s*\)",
      ).allMatches(body);
      final hostLinks = <HostLink>[];
      final seenGates = <String>{};
      for (final m in matches) {
        final h = (m.group(1) ?? '').trim();
        final id = (m.group(2) ?? '').trim();
        if (h.isEmpty || id.isEmpty || h.toLowerCase() == 'upzone') continue;
        final gate = '$baseUrl/watch/f/$h/$id';
        if (!seenGates.add(gate)) continue;
        try {
          final gResp = await _dio.get<String>(
            gate,
            options: Options(headers: {'Referer': targetUrl}),
          );
          final gDoc = html.parse(gResp.data ?? '');
          final href = gDoc
                  .querySelector('a.buttonprch')
                  ?.attributes['href'] ??
              gDoc.querySelector('a[href*="play.ekino"]')?.attributes['href'];
          if (href != null && href.isNotEmpty) {
            hostLinks.add(HostLink(
              url: resolveUrl(baseUrl, href),
              lang: 'PL',
              quality: 'HD',
            ));
          }
        } catch (_) {}
      }
      return ServiceMovieDetailsModel(
        service: SupportedService.custom,
        url: url,
        title: title,
        description: desc,
        imageUrl: img,
        isSeries: false,
        videoUrls: hostLinks,
      );
    }

    final links = extractGenericHtmlEmbeds(body, baseUrl);
    return ServiceMovieDetailsModel(
      service: SupportedService.custom,
      url: url,
      title: title,
      description: desc,
      imageUrl: img,
      isSeries: false,
      videoUrls: links,
    );
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    if (episode.videoUrls != null && episode.videoUrls!.isNotEmpty) {
      return episode;
    }
    if (episode.url.startsWith('custom://episode|')) {
      final parts = episode.url.split('|');
      if (parts.length >= 4) {
        final mediaId = parts[1];
        final seasonNum = int.tryParse(parts[2]) ?? 1;
        final epNum = int.tryParse(parts[3]) ?? 1;
        final media = getIt<ExtraSourcesService>().findMediaById(mediaId);
        if (media != null) {
          for (final s in media.seasons) {
            if (s.number == seasonNum) {
              for (final e in s.episodes) {
                if (e.number == epNum) {
                  return episode.copyWith(
                    videoUrls: e.links
                        .map((l) => HostLink(
                              url: l.url,
                              lang: l.lang,
                              quality: l.quality,
                            ))
                        .toList(),
                  );
                }
              }
            }
          }
        }
      }
      return episode;
    }
    final parsed = parseCustomUrl(episode.url);
    if (parsed == null) return episode;
    try {
      final resp = await _dio.get<String>(parsed.$2);
      final origin = Uri.tryParse(parsed.$2)?.origin ?? '';
      final links = extractGenericHtmlEmbeds(resp.data ?? '', origin);
      return episode.copyWith(videoUrls: links);
    } catch (_) {
      return episode;
    }
  }
}
