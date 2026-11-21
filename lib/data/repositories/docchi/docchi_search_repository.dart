import 'package:diacritic/diacritic.dart';
import 'package:dio/dio.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/docchi/docchi_movie_repository.dart';
import 'package:purevideo/data/repositories/search_repository.dart';

class DocchiSearchRepository implements SearchRepository {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.docchi.pl/v1',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      'Referer': 'https://docchi.pl/',
      'Accept': 'application/json',
    },
  ));

  String _norm(String s) =>
      removeDiacritics(s.toLowerCase()).replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    final q = _norm(query);
    if (q.isEmpty) return const [];
    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();

    final catalog = await DocchiMovieRepository.getSeriesCatalog(_dio);
    final scored = <MapEntry<int, ServiceMovieModel>>[];

    for (final item in catalog) {
      final tMain = (item['title'] ?? '').toString().trim();
      final tEn = (item['title_en'] ?? '').toString().trim();
      final combined = _norm('$tEn $tMain');
      if (combined.isEmpty) continue;

      if (!tokens.every((tok) => combined.contains(tok))) continue;

      final slug = (item['slug'] ?? '').toString().trim();
      var cover = (item['cover'] ?? '').toString().trim();
      if (cover.startsWith('//')) cover = 'https:$cover';
      if (slug.isEmpty) continue;

      final displayTitle = tEn.isNotEmpty ? tEn : tMain;
      final normDisplay = _norm(displayTitle);
      int score = int.tryParse((item['season_year'] ?? '').toString()) ?? 0;
      if (normDisplay == q || _norm(tMain) == q) {
        score += 100000;
      } else if (normDisplay.startsWith(q) || _norm(tMain).startsWith(q)) {
        score += 20000;
      }

      final sType = (item['series_type'] ?? '').toString().toUpperCase();
      final epCount = int.tryParse((item['episodes'] ?? '').toString()) ?? 0;
      final isMovie = sType == 'MOVIE' && epCount <= 1;

      scored.add(MapEntry(
        score,
        ServiceMovieModel(
          service: SupportedService.docchi,
          url: isMovie ? '/docchi/movie/$slug' : '/docchi/series/$slug',
          title: displayTitle,
          imageUrl: cover,
          category: isMovie ? 'Anime' : 'Anime|Seriale',
        ),
      ));
    }

    scored.sort((a, b) => b.key.compareTo(a.key));
    return scored.take(25).map((e) => e.value).toList();
  }
}
