import 'package:dio/dio.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_movie_repository.dart';
import 'package:purevideo/data/repositories/search_repository.dart';

class BajeczkiSearchRepository implements SearchRepository {
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

  @override
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final postsFuture = _dio
        .get('/posts', queryParameters: {
          'search': q,
          'per_page': 25,
          '_embed': 1,
        })
        .then((r) => r.data)
        .catchError((_) => null);

    final catsFuture = _dio
        .get('/categories', queryParameters: {
          'search': q,
          'per_page': 12,
        })
        .then((r) => r.data)
        .catchError((_) => null);

    final postsData = await postsFuture;
    final catsData = await catsFuture;

    final out = <ServiceMovieModel>[];
    final seenKeys = <String>{};
    final seenUrls = <String>{};

    // 1. Matching series categories (check first post has playable embed + not trailer)
    if (catsData is List) {
      final catChecks = catsData.whereType<Map>().take(6).map((c) async {
        final cid = c['id'];
        final count = (c['count'] as num?)?.toInt() ?? 0;
        final slug = (c['slug'] ?? '').toString().toLowerCase();
        if (cid is! int ||
            count <= 0 ||
            cid == BajeczkiMovieRepository.moviesCategoryId ||
            cid == BajeczkiMovieRepository.trailerCategoryId ||
            cid == 6947 ||
            cid == 6954 ||
            slug.contains('zwiastun') ||
            slug.contains('trailer')) {
          return null;
        }
        final name =
            BajeczkiMovieRepository.decodeHtmlText((c['name'] ?? '').toString());
        if (name.isEmpty || BajeczkiMovieRepository.isTrailerOrPromo(name)) {
          return null;
        }

        try {
          final pResp = await _dio.get('/posts', queryParameters: {
            'categories': cid,
            'per_page': 2,
            '_embed': 1,
          });
          if (pResp.data is List && (pResp.data as List).isNotEmpty) {
            for (final p in (pResp.data as List).whereType<Map>()) {
              final content = (p['content']?['rendered'] ?? '').toString();
              if (BajeczkiMovieRepository.extractEmbedLinks(content)
                  .isNotEmpty) {
                final poster = BajeczkiMovieRepository.extractFeaturedPoster(p);
                return ServiceMovieModel(
                  service: SupportedService.bajeczki,
                  url: '/bajeczki/series/$cid',
                  title: name,
                  imageUrl: poster,
                  category: 'Bajki dla dzieci|Seriale',
                );
              }
            }
          }
        } catch (_) {}
        return null;
      });
      final resolvedCats = await Future.wait(catChecks);
      for (final m in resolvedCats.whereType<ServiceMovieModel>()) {
        final key = 's:${m.title.toLowerCase()}';
        if (seenUrls.add(m.url) && seenKeys.add(key)) out.add(m);
      }
    }

    // 2. Only full movies (cat 1924) from post search; avoid leaking individual episode posts as movies
    if (postsData is List) {
      for (final item in postsData) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id == null) continue;
        final cats =
            (item['categories'] as List?)?.whereType<int>().toList() ?? const <int>[];
        if (!cats.contains(BajeczkiMovieRepository.moviesCategoryId)) continue;

        final rawTitle = (item['title']?['rendered'] ?? '').toString();
        if (BajeczkiMovieRepository.isTrailerOrPromo(rawTitle, cats)) continue;

        final content = (item['content']?['rendered'] ?? '').toString();
        if (BajeczkiMovieRepository.extractEmbedLinks(content).isEmpty) {
          continue;
        }

        final title = BajeczkiMovieRepository.cleanDisplayTitle(rawTitle);
        if (title.isEmpty) continue;
        final poster = BajeczkiMovieRepository.extractFeaturedPoster(item);
        final url = '/bajeczki/movie/$id';
        final key = 'm:${title.toLowerCase()}';
        if (seenUrls.add(url) && seenKeys.add(key)) {
          out.add(ServiceMovieModel(
            service: SupportedService.bajeczki,
            url: url,
            title: title,
            imageUrl: poster,
            category: 'Familijne',
          ));
        }
      }
    }

    return out;
  }
}
