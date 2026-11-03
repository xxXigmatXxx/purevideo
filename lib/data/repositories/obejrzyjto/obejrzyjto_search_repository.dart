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

  @override
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    await _prepareDio();

    final response =
        await _dio!.get('/search/${Uri.encodeComponent(query.trim())}');

    final bootstrapData = extractBootstrapData(response.data);
    final results =
        bootstrapData?['loaders']?['searchPage']?['results'] as List?;

    if (results == null || results.isEmpty) {
      return [];
    }

    final futures = results.take(12).map((movieData) async {
      if (movieData is! Map) return null;

      final title = (movieData['name'] as String?)?.trim();
      final imageUrl = (movieData['poster'] as String?)?.trim();

      if (title == null ||
          title.isEmpty ||
          imageUrl == null ||
          imageUrl.isEmpty) {
        return null;
      }

      try {
        final detailsResponse = await _dio!
            .get('/titles/${movieData['id']}/${generateSlug(title)}')
            .timeout(const Duration(seconds: 6));

        final detailsBootstrapData =
            extractBootstrapData(detailsResponse.data);
        if (detailsBootstrapData == null) return null;

        final titleObj =
            detailsBootstrapData['loaders']?['titlePage']?['title'];
        if (titleObj is! Map) return null;

        final isSeries = titleObj['is_series']?.toString() == 'true';
        final primaryVideoId = titleObj['primary_video']?['id'] as int?;
        if (primaryVideoId == null) return null;

        return ServiceMovieModel(
          service: SupportedService.obejrzyjto,
          title: title,
          imageUrl: imageUrl,
          url: '/watch/$primaryVideoId',
          category: isSeries ? 'Seriale' : 'Filmy',
        );
      } catch (_) {
        return null;
      }
    }).toList();

    final resolved = await Future.wait(futures);
    return resolved.whereType<ServiceMovieModel>().toList();
  }
}
