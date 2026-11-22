import 'package:diacritic/diacritic.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/bajeczki/bajeczki_movie_repository.dart';
import 'package:purevideo/data/repositories/custom/custom_movie_repository.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/di/injection_container.dart';

class CustomSearchRepository implements SearchRepository {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': WebViewService.cleanUserAgent,
    },
  ));

  Future<List<ServiceMovieModel>> _searchInSource(
    ExtraSourceConfig src,
    String query,
  ) async {
    try {
      switch (src.type) {
        case ExtraSourceType.wordpress:
          final resp = await _dio.get(
            '${src.baseUrl}/wp-json/wp/v2/posts',
            queryParameters: {'search': query, 'per_page': 15, '_embed': 1},
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
              url: CustomMovieRepository.encodeCustomUrl(
                  src.id, '${src.baseUrl}/wp-json/wp/v2/posts/$id'),
              title: title,
              imageUrl: poster,
              category: src.category.isNotEmpty ? src.category : src.name,
            ));
          }
          return out;

        case ExtraSourceType.ekinoMirror:
          final resp = await _dio.post<String>(
            '${src.baseUrl}/search/',
            data: {'search_field': query},
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              headers: {'Referer': '${src.baseUrl}/'},
            ),
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
            final full = CustomMovieRepository.resolveUrl(src.baseUrl, href);
            if (!seen.add(full)) continue;
            final img = a.querySelector('img');
            final rawImg =
                img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
            final imgUrl =
                CustomMovieRepository.resolveUrl(src.baseUrl, rawImg)
                    .replaceAll('/static/thumb/', '/static/normal/');
            var title =
                (a.attributes['title'] ?? img?.attributes['alt'] ?? a.text)
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
            if (title.contains(' / ')) title = title.split(' / ').first.trim();
            if (title.isEmpty) continue;
            out.add(ServiceMovieModel(
              service: SupportedService.custom,
              url: CustomMovieRepository.encodeCustomUrl(src.id, full),
              title: title,
              imageUrl: imgUrl,
              category: href.contains('/serie/')
                  ? 'Popularne seriale'
                  : (src.category.isNotEmpty
                      ? src.category
                      : 'Popularne filmy'),
            ));
            if (out.length >= 20) break;
          }
          return out;

        case ExtraSourceType.htmlAuto:
          final q = Uri.encodeQueryComponent(query);
          final resp = await _dio.get<String>(
            '${src.baseUrl}/?s=$q',
            options: Options(headers: {'Referer': '${src.baseUrl}/'}),
          );
          return CustomMovieRepository.parseHtmlCards(
            resp.data ?? '',
            src,
            limit: 15,
          );
      }
    } catch (e) {
      debugPrint('Custom search failed (${src.name}): $e');
      return const [];
    }
  }

  @override
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    final extra = getIt<ExtraSourcesService>();
    final out = <ServiceMovieModel>[];
    final normQ = removeDiacritics(query.toLowerCase().trim());

    // 1. Search curated Movies & Series (CDA / Vider.info)
    if (normQ.isNotEmpty) {
      for (final media in extra.getAllActiveCustomMedia()) {
        final normT = removeDiacritics(media.title.toLowerCase());
        if (normT.contains(normQ)) {
          final defaultCat =
              media.isSeries ? 'Popularne seriale' : 'Popularne filmy';
          final cat = media.category.isNotEmpty
              ? (media.isSeries &&
                      !media.category.toLowerCase().contains('serial')
                  ? '${media.category}|Popularne seriale'
                  : media.category)
              : defaultCat;
          out.add(ServiceMovieModel(
            service: SupportedService.custom,
            url: CustomMovieRepository.encodeMediaUrl(media),
            title: media.title,
            imageUrl: media.posterUrl,
            category: '$cat|Źródła dodatkowe',
          ));
        }
      }
    }

    // 2. Search optional website sources
    final sources = extra.getAllActiveCustomSources();
    if (sources.isNotEmpty) {
      final lists = await Future.wait(
        sources.map((s) => _searchInSource(s, query)
            .timeout(const Duration(seconds: 12), onTimeout: () => const [])),
      );
      out.addAll(lists.expand((e) => e));
    }

    return out;
  }
}
