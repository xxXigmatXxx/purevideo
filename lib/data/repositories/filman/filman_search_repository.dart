import 'package:dio/dio.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_dio_factory.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:html/parser.dart' as html;

class FilmanSearchRepository extends SearchRepository {
  final AuthRepository _authRepository =
      getIt<Map<SupportedService, AuthRepository>>()[SupportedService.filman]!;
  final SettingsService _settingsService = getIt<SettingsService>();
  Dio? _dio;

  FilmanSearchRepository() {
    _authRepository.authStream.listen(_onAuthChanged);
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.filman) {
      _dio = FilmanDioFactory.getDio(auth.account);
    }
  }

  Future<void> _prepareDio() async {
    if (_dio == null) {
      final account = _authRepository.getAccount();
      _dio = FilmanDioFactory.getDio(account);
    }
  }

  Future<bool> _hasActiveLinks(String url) async {
    if (_settingsService.isUrlLinkless(url)) return false;
    if (_settingsService.isUrlVerified(url)) return true;
    try {
      final resp = await _dio!
          .get(url)
          .timeout(const Duration(seconds: 6));
      final body = resp.data?.toString() ?? '';
      if (body.isEmpty) return false;
      final ok =
          body.contains('data-iframe') || body.contains('episode-list');
      if (ok) {
        _settingsService.markUrlVerified(url);
      } else {
        _settingsService.markUrlLinkless(url);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    await _prepareDio();

    final response = await _dio!.get(
      '/search',
      queryParameters: {'phrase': query.trim()},
    );

    final document = html.parse(response.data);

    final candidates = <ServiceMovieModel>[];

    document
        .querySelectorAll('.col-xs-6.col-sm-3.col-lg-2')
        .forEach((final filmDOM) {
      final poster = filmDOM.querySelector('.poster');
      if (poster == null) return;
      final aTag = poster.querySelector('a');
      final title = (filmDOM.querySelector('.film_title')?.text ??
              aTag?.attributes['title'] ??
              '')
          .trim()
          .split('/')
          .first
          .trim();
      final imgEl = poster.querySelector('img');
      final imageUrl =
          (imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '')
              .trim();
      final link = (aTag?.attributes['href'] ?? '').trim();

      if (title.isEmpty ||
          title == 'Brak danych' ||
          imageUrl.isEmpty ||
          link.isEmpty ||
          link == 'Brak danych' ||
          !link.startsWith('http') ||
          _settingsService.isUrlLinkless(link)) {
        return;
      }
      candidates.add(ServiceMovieModel(
        service: SupportedService.filman,
        title: title,
        imageUrl: imageUrl,
        url: link,
      ));
    });

    final toCheck = candidates.take(14).toList();
    final verified = await Future.wait(
      toCheck.map((m) async {
        final ok = await _hasActiveLinks(m.url);
        return ok ? m : null;
      }),
    );

    return verified.whereType<ServiceMovieModel>().toList();
  }
}
