import 'package:dio/dio.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_dio_factory.dart';
import 'package:purevideo/data/repositories/obejrzyjto/obejrzyjto_utils.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/di/injection_container.dart';

class ObejrzyjtoSearchRepository extends SearchRepository {
  final AuthRepository _authRepository = getIt<
      Map<SupportedService, AuthRepository>>()[SupportedService.obejrzyjto]!;

  Dio? _dio;

  ObejrzyjtoSearchRepository() {
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
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    await _prepareDio();

    final response = await _dio!.get(
      '/api/v1/search/${Uri.encodeComponent(query.trim())}',
      queryParameters: {'limit': 12},
      options: Options(headers: {
        'Referer': 'https://www.obejrzyj.to/',
      }),
    );

    if (response.data is! Map || response.data['results'] == null) {
      return [];
    }

    final List<dynamic> searchResults = response.data['results'];

    final futures = searchResults.map((movieData) async {
      if (movieData is! Map) return null;
      final modelType = movieData['model_type']?.toString();
      if (modelType != null && modelType != 'title') return null;
      if (movieData['is_series'] == null) return null;

      final isSeries = movieData['is_series']?.toString() == 'true';
      if (!isSeries && movieData['videos_updated_at'] == null) {
        return null;
      }

      final title = (movieData['name'] as String?)?.trim();
      final imageUrl = (movieData['poster'] as String?)?.trim();
      final titleId = movieData['id'];

      if (title == null ||
          title.isEmpty ||
          imageUrl == null ||
          imageUrl.isEmpty ||
          titleId == null) {
        return null;
      }

      try {
        final slug = generateSlug(title);
        final detailsResponse = await _dio!
            .get('/titles/$titleId/$slug')
            .timeout(const Duration(seconds: 6));

        final detailsBootstrapData =
            extractBootstrapData(detailsResponse.data);
        if (detailsBootstrapData == null) return null;

        final titleObj =
            detailsBootstrapData['loaders']?['titlePage']?['title'];
        if (titleObj is! Map) return null;

        final primaryVideo = titleObj['primary_video'];
        final videosList = (titleObj['videos'] as List?) ?? const [];

        if (!isSeries) {
          int? targetVideoId;
          if (primaryVideo is Map &&
              primaryVideo['id'] != null &&
              !_isTrailerVideo(primaryVideo)) {
            targetVideoId = primaryVideo['id'] as int?;
          }
          if (targetVideoId == null) {
            for (final v in videosList) {
              if (v is Map && v['id'] != null && !_isTrailerVideo(v)) {
                targetVideoId = v['id'] as int?;
                if (targetVideoId != null) break;
              }
            }
          }
          if (targetVideoId == null) return null;

          return ServiceMovieModel(
            service: SupportedService.obejrzyjto,
            title: title,
            imageUrl: imageUrl,
            url: '/watch/$targetVideoId',
            category: 'Filmy',
          );
        } else {
          final seasonsCount = (titleObj['seasons_count'] as int?) ?? 0;
          final primaryVideoId =
              (primaryVideo is Map) ? (primaryVideo['id'] as int?) : null;
          if (seasonsCount <= 0 && primaryVideoId == null) {
            return null;
          }
          final targetUrl = primaryVideoId != null
              ? '/watch/$primaryVideoId'
              : '/titles/$titleId/$slug';

          return ServiceMovieModel(
            service: SupportedService.obejrzyjto,
            title: title,
            imageUrl: imageUrl,
            url: targetUrl,
            category: 'Seriale',
          );
        }
      } catch (_) {
        return null;
      }
    }).toList();

    final resolved = await Future.wait(futures);
    return resolved.whereType<ServiceMovieModel>().toList();
  }
}
