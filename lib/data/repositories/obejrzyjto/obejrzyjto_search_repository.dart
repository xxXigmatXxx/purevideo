import 'package:dio/dio.dart';
import 'package:purevideo/core/services/settings_service.dart';
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
  final SettingsService _settingsService = getIt<SettingsService>();

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

  bool _isValidStreamVideo(dynamic video) {
    if (video is! Map) return false;
    if (video['id'] == null) return false;
    final src = (video['src'] ?? '').toString().toLowerCase().trim();
    if (src.isEmpty ||
        src.contains('youtube.com') ||
        src.contains('youtu.be')) {
      return false;
    }
    final cat = (video['category'] ?? '').toString().toLowerCase().trim();
    if (cat == 'trailer' || cat == 'teaser' || cat == 'clip') {
      return false;
    }
    return true;
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
        final primaryVideo = titleObj['primary_video'];
        final videosList = (titleObj['videos'] as List?) ?? const [];

        int? targetVideoId;
        if (_isValidStreamVideo(primaryVideo)) {
          targetVideoId = primaryVideo['id'] as int?;
        } else {
          for (final v in videosList) {
            if (_isValidStreamVideo(v)) {
              targetVideoId = v['id'] as int?;
              if (targetVideoId != null) break;
            }
          }
        }

        if (isSeries) {
          final seasonsCount = (titleObj['seasons_count'] as int?) ?? 0;
          final seasonsList = (titleObj['seasons'] as List?) ?? const [];
          if (seasonsCount <= 0 && seasonsList.isEmpty) {
            return null;
          }
          targetVideoId ??= (primaryVideo is Map)
              ? (primaryVideo['id'] as int?)
              : (videosList.isNotEmpty && videosList.first is Map
                  ? videosList.first['id'] as int?
                  : null);
        }

        if (targetVideoId == null) return null;

        final watchUrl = '/watch/$targetVideoId';
        if (_settingsService.isUrlLinkless(watchUrl)) return null;

        _settingsService.markUrlVerified(watchUrl);
        return ServiceMovieModel(
          service: SupportedService.obejrzyjto,
          title: title,
          imageUrl: imageUrl,
          url: watchUrl,
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
