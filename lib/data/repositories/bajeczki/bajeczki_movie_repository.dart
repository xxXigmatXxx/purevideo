import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';

class BajeczkiMovieRepository implements MovieRepository {
  static const int moviesCategoryId = 1924; // ► Filmy
  static const Set<int> _ignoredCategoryIds = {
    1, // Bez kategorii
    moviesCategoryId,
    6947, // Artykuł
    6954, // Filmy (empty parent)
  };

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://bajeczki.org/wp-json/wp/v2',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      'Referer': 'https://bajeczki.org/',
      'Accept': 'application/json',
    },
  ));

  static String decodeHtmlText(String raw) {
    if (raw.isEmpty) return '';
    try {
      return (html.parseFragment(raw).text ?? raw)
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    } catch (_) {
      return raw.trim();
    }
  }

  static String extractLanguageFromTitle(String rawTitle) {
    final lower = rawTitle.toLowerCase();
    if (lower.contains('dubbing')) return 'Dubbing PL';
    if (lower.contains('lektor')) return 'Lektor PL';
    if (lower.contains('napisy') || lower.contains('plsub')) return 'Napisy PL';
    return 'PL';
  }

  static String cleanDisplayTitle(String rawTitle) {
    var t = decodeHtmlText(rawTitle);
    // Remove bracketed audio tags like [Lektor PL], [Dubbing PL], [PLSUB]
    t = t
        .replaceAll(
          RegExp(
            r'\[(?:lektor|dubbing|napisy|pl|plsub|hd|fhd|cam)[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+PLSUB\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.contains(' / ')) {
      t = t.split(' / ').first.trim();
    }
    if (t.contains(' – ')) {
      final first = t.split(' – ').first.trim();
      if (first.length >= 3) t = first;
    }
    return t;
  }

  static String extractFeaturedPoster(Map post) {
    try {
      final embedded = post['_embedded'];
      if (embedded is Map) {
        final media = embedded['wp:featuredmedia'];
        if (media is List && media.isNotEmpty && media.first is Map) {
          final src = (media.first['source_url'] ?? '').toString().trim();
          if (src.startsWith('http') && !src.contains('thumbnail-default')) {
            return src;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  static List<HostLink> extractEmbedLinks(
    String contentHtml, {
    String lang = 'PL',
  }) {
    if (contentHtml.trim().isEmpty) return const [];
    final out = <HostLink>[];
    final seen = <String>{};

    void addUrl(String rawUrl) {
      var u = rawUrl.trim();
      if (u.startsWith('//')) u = 'https:$u';
      if (!u.startsWith('http')) return;
      final lower = u.toLowerCase();
      if (lower.contains('bajeczki.org') ||
          lower.contains('youtube.com') ||
          lower.contains('youtu.be') ||
          lower.contains('highperform') ||
          lower.contains('doubleclick') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.js') ||
          lower.endsWith('.css')) {
        return;
      }
      if (!seen.add(u)) return;
      out.add(HostLink(url: u, lang: lang, quality: 'HD'));
    }

    final iframeMatches = RegExp(
      r'''<iframe[^>]+(?:src|data-src)=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(contentHtml);
    for (final m in iframeMatches) {
      addUrl(m.group(1) ?? '');
    }

    final sourceMatches = RegExp(
      r'''<source[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(contentHtml);
    for (final m in sourceMatches) {
      addUrl(m.group(1) ?? '');
    }

    if (out.isEmpty) {
      final rawUrls = RegExp(
        r'''https?://(?:ebd\.cda\.pl|goodstream\.vip|voe\.sx|dood\.|lulustream\.|vidmoly\.|streamtape\.|mixdrop\.)[^\s"'<>]+''',
        caseSensitive: false,
      ).allMatches(contentHtml);
      for (final m in rawUrls) {
        addUrl(m.group(0) ?? '');
      }
    }

    return out;
  }

  static int? parseEpisodeNumber(String title, int fallbackIndex) {
    final m1 = RegExp(r'S\d+E(\d+)', caseSensitive: false).firstMatch(title);
    if (m1 != null) return int.tryParse(m1.group(1)!);
    final m2 = RegExp(
      r'(?:^|\s)(?:E|Odcinek|Odc\.?)\s*0*(\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    if (m2 != null) return int.tryParse(m2.group(1)!);
    return fallbackIndex;
  }

  @override
  Future<List<ServiceMovieModel>> getMovies() async {
    final results = <ServiceMovieModel>[];

    final moviesFuture = _dio
        .get('/posts', queryParameters: {
          'categories': moviesCategoryId,
          'per_page': 35,
          '_embed': 1,
        })
        .then((r) => r.data)
        .catchError((_) => null);

    final recentPostsFuture = _dio
        .get('/posts', queryParameters: {
          'per_page': 50,
          '_embed': 1,
        })
        .then((r) => r.data)
        .catchError((_) => null);

    final catsFuture = _dio
        .get('/categories', queryParameters: {
          'per_page': 60,
          'orderby': 'id',
          'order': 'desc',
        })
        .then((r) => r.data)
        .catchError((_) => null);

    final moviesData = await moviesFuture;
    final recentData = await recentPostsFuture;
    final catsData = await catsFuture;

    final catMap = <int, Map<String, dynamic>>{};
    if (catsData is List) {
      for (final c in catsData) {
        if (c is Map) {
          final id = c['id'];
          if (id is int) catMap[id] = Map<String, dynamic>.from(c);
        }
      }
    }

    // 1. Series discovered from recent verified posts (guaranteed playable embeds + posters)
    final seenCatIds = <int>{};
    if (recentData is List) {
      for (final item in recentData) {
        if (item is! Map) continue;
        final titleRaw = (item['title']?['rendered'] ?? '').toString();
        if (titleRaw.toLowerCase().contains('zwiastun')) continue;
        final content = (item['content']?['rendered'] ?? '').toString();
        if (extractEmbedLinks(content).isEmpty) continue;

        final cats = (item['categories'] as List?)?.whereType<int>() ?? const [];
        for (final cid in cats) {
          if (_ignoredCategoryIds.contains(cid) || !seenCatIds.add(cid)) {
            continue;
          }
          final catInfo = catMap[cid];
          final catName = decodeHtmlText((catInfo?['name'] ?? '').toString());
          final catSlug = (catInfo?['slug'] ?? '').toString().toLowerCase();
          if (catName.isEmpty ||
              catSlug.contains('zwiastun') ||
              catSlug.contains('artykul')) {
            continue;
          }
          final poster = extractFeaturedPoster(item);
          if (poster.isEmpty) continue;
          results.add(ServiceMovieModel(
            service: SupportedService.bajeczki,
            url: '/bajeczki/series/$cid',
            title: catName,
            imageUrl: poster,
            category: 'Bajki dla dzieci|Seriale',
          ));
          break;
        }
      }
    }

    // 2. Full feature movies from ► Filmy (cat 1924)
    if (moviesData is List) {
      for (final item in moviesData) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id == null) continue;
        final rawTitle = (item['title']?['rendered'] ?? '').toString();
        final title = cleanDisplayTitle(rawTitle);
        final content = (item['content']?['rendered'] ?? '').toString();
        if (title.isEmpty || extractEmbedLinks(content).isEmpty) continue;
        final poster = extractFeaturedPoster(item);
        results.add(ServiceMovieModel(
          service: SupportedService.bajeczki,
          url: '/bajeczki/movie/$id',
          title: title,
          imageUrl: poster,
          category: 'Familijne',
        ));
      }
    }

    return results;
  }

  @override
  Future<ServiceMovieDetailsModel> getMovieDetails(String url) async {
    final parts = url.split('/').where((e) => e.isNotEmpty).toList();
    final isSeries = url.contains('/bajeczki/series/');
    final id = parts.last;

    if (!isSeries) {
      final resp = await _dio.get('/posts/$id', queryParameters: {'_embed': 1});
      final data = resp.data as Map;
      final rawTitle = (data['title']?['rendered'] ?? '').toString();
      final title = cleanDisplayTitle(rawTitle);
      final lang = extractLanguageFromTitle(rawTitle);
      final contentHtml = (data['content']?['rendered'] ?? '').toString();
      final links = extractEmbedLinks(contentHtml, lang: lang);
      final excerpt =
          decodeHtmlText((data['excerpt']?['rendered'] ?? '').toString());
      final poster = extractFeaturedPoster(data);

      return ServiceMovieDetailsModel(
        service: SupportedService.bajeczki,
        url: url,
        title: title.isEmpty ? 'Film' : title,
        description: excerpt,
        imageUrl: poster,
        isSeries: false,
        videoUrls: links,
      );
    }

    final catRespFuture = _dio.get('/categories/$id').catchError((_) => Response(
          requestOptions: RequestOptions(),
          data: <String, dynamic>{},
        ));
    final postsRespFuture = _dio.get('/posts', queryParameters: {
      'categories': id,
      'per_page': 100,
      'orderby': 'date',
      'order': 'asc',
      '_embed': 1,
    });

    final catResp = await catRespFuture;
    final postsResp = await postsRespFuture;

    String seriesTitle = 'Serial';
    String seriesDesc = '';
    if (catResp.data is Map) {
      final c = catResp.data as Map;
      final n = decodeHtmlText((c['name'] ?? '').toString());
      if (n.isNotEmpty) seriesTitle = n;
      seriesDesc = decodeHtmlText((c['description'] ?? '').toString());
    }

    String poster = '';
    final episodes = <EpisodeModel>[];
    if (postsResp.data is List) {
      final posts = (postsResp.data as List).whereType<Map>().toList();
      int idx = 1;
      for (final p in posts) {
        final contentHtml = (p['content']?['rendered'] ?? '').toString();
        final rawTitle = (p['title']?['rendered'] ?? '').toString();
        final lang = extractLanguageFromTitle(rawTitle);
        final links = extractEmbedLinks(contentHtml, lang: lang);
        if (links.isEmpty) continue;

        if (poster.isEmpty) {
          poster = extractFeaturedPoster(p);
        }

        final epTitle = decodeHtmlText(rawTitle);
        final epNum = parseEpisodeNumber(epTitle, idx) ?? idx;
        final pid = p['id'];
        episodes.add(EpisodeModel(
          number: epNum,
          title: epTitle.isEmpty ? 'Odcinek $epNum' : epTitle,
          url: '/bajeczki/post/$pid',
          videoUrls: links,
        ));
        idx++;
      }
    }

    episodes.sort((a, b) => a.number.compareTo(b.number));

    return ServiceMovieDetailsModel(
      service: SupportedService.bajeczki,
      url: url,
      title: seriesTitle,
      description: seriesDesc,
      imageUrl: poster,
      isSeries: true,
      seasons: episodes.isEmpty
          ? const []
          : [SeasonModel(number: 1, episodes: episodes)],
    );
  }

  @override
  Future<EpisodeModel> getEpisodeHosts(EpisodeModel episode) async {
    if (episode.videoUrls != null && episode.videoUrls!.isNotEmpty) {
      return episode;
    }
    final postId = episode.url.split('/').where((e) => e.isNotEmpty).last;
    try {
      final resp = await _dio.get('/posts/$postId');
      if (resp.data is Map) {
        final p = resp.data as Map;
        final rawTitle = (p['title']?['rendered'] ?? '').toString();
        final contentHtml = (p['content']?['rendered'] ?? '').toString();
        final links = extractEmbedLinks(
          contentHtml,
          lang: extractLanguageFromTitle(rawTitle),
        );
        return episode.copyWith(videoUrls: links);
      }
    } catch (e) {
      debugPrint('Bajeczki episode hosts error ($postId): $e');
    }
    return episode;
  }
}
