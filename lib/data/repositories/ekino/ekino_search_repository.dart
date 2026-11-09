import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/ekino/ekino_dio_factory.dart';
import 'package:purevideo/data/repositories/search_repository.dart';
import 'package:purevideo/di/injection_container.dart';

class EkinoSearchRepository extends SearchRepository {
  final AuthRepository _authRepository =
      getIt<Map<SupportedService, AuthRepository>>()[SupportedService.ekino]!;
  Dio? _dio;

  EkinoSearchRepository() {
    _authRepository.authStream.listen(_onAuthChanged);
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.ekino) {
      _dio = EkinoDioFactory.getDio(auth.account);
      _dio!.options.headers['User-Agent'] = WebViewService.cleanUserAgent;
    }
  }

  Future<void> _prepareDio() async {
    await WebViewService.ensureCleanUserAgent();
    if (_dio == null) {
      final account = _authRepository.getAccount();
      _dio = EkinoDioFactory.getDio(account);
    }
    _dio!.options.headers['User-Agent'] = WebViewService.cleanUserAgent;
  }

  String _cleanTitle(String raw) {
    var t = raw.replaceAll('\u00a0', ' ').trim();
    if (t.contains(' / ')) {
      final first = t.split(' / ').first.trim();
      if (first.isNotEmpty) {
        t = first;
      }
    }
    t = t.replaceFirst(
      RegExp(
        r'\s*-\s*(?:HD|CAM|4K|FHD|AI|PL|Lektor|Dubbing|Napisy)(?:\s+.*)?$',
        caseSensitive: false,
      ),
      '',
    );
    return t.trim();
  }

  @override
  Future<List<ServiceMovieModel>> searchMovies(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }
    await _prepareDio();
    final response = await _dio!.get(
      '/search/qf/',
      queryParameters: {'q': query.trim()},
    );
    final document = html.parse(response.data);
    final moviesList = <ServiceMovieModel>[];
    final seriesList = <ServiceMovieModel>[];

    for (final movieElement in document.querySelectorAll('.movies-list-item')) {
      final coverElement = movieElement.querySelector('.cover-list a');
      if (coverElement == null) continue;
      final rawUrl = (coverElement.attributes['href'] ?? '').trim();
      if (rawUrl.isEmpty) continue;
      final isSeries = rawUrl.contains('/serie/');
      final url = (isSeries && !rawUrl.endsWith('/')) ? '$rawUrl/' : rawUrl;

      final imageUrl =
          (coverElement.querySelector('img')?.attributes['src'] ?? '')
              .trim()
              .replaceAll('/static/thumb/', '/static/normal/');
      final titleElement =
          movieElement.querySelector('.opis-list .title a') ??
              movieElement.querySelector('.title a');
      if (titleElement == null) continue;
      final title = titleElement.text.trim();
      if (title.isEmpty) continue;
      final cleanTitle = _cleanTitle(title);

      String fullImageUrl = imageUrl;
      if (imageUrl.startsWith('//')) {
        fullImageUrl = 'https:$imageUrl';
      } else if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
        fullImageUrl = 'https://ekino.ws$imageUrl';
      }

      final model = ServiceMovieModel(
        service: SupportedService.ekino,
        title: cleanTitle,
        imageUrl: fullImageUrl,
        url: url,
        category: isSeries ? 'Seriale' : 'Filmy',
      );
      if (isSeries) {
        seriesList.add(model);
      } else {
        moviesList.add(model);
      }
    }

    final qLower = query.trim().toLowerCase();
    int score(ServiceMovieModel m) {
      final t = m.title.toLowerCase();
      if (t == qLower) return 0;
      if (t.startsWith(qLower)) return 1;
      if (t.contains(qLower)) return 2;
      return 3;
    }

    seriesList.sort((a, b) => score(a).compareTo(score(b)));
    moviesList.sort((a, b) => score(a).compareTo(score(b)));

    final combined = <ServiceMovieModel>[];
    final maxLen = seriesList.length > moviesList.length
        ? seriesList.length
        : moviesList.length;
    for (int i = 0; i < maxLen; i++) {
      if (i < seriesList.length) combined.add(seriesList[i]);
      if (i < moviesList.length) combined.add(moviesList[i]);
    }
    combined.sort((a, b) => score(a).compareTo(score(b)));
    return combined;
  }
}
