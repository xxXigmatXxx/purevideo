import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
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
    }
  }

  Future<void> _prepareDio() async {
    if (_dio == null) {
      final account = _authRepository.getAccount();
      _dio = EkinoDioFactory.getDio(account);
    }
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
    if (query.isEmpty) {
      return [];
    }

    await _prepareDio();

    final response = await _dio!.get(
      '/search/qf/',
      queryParameters: {'q': query},
    );

    final document = html.parse(response.data);
    final movies = <ServiceMovieModel>[];

    document.querySelectorAll('.movies-list-item').forEach((movieElement) {
      final coverElement = movieElement.querySelector('.cover-list a');
      if (coverElement == null) return;

      final url = coverElement.attributes['href'] ?? '';
      if (url.isEmpty) return;

      final imageUrl =
          (coverElement.querySelector('img')?.attributes['src'] ?? '')
              .replaceAll('/static/thumb/', '/static/normal/');

      final titleElement = movieElement.querySelector('.opis-list .title a');
      if (titleElement == null) return;

      final title = titleElement.text.trim();
      if (title.isEmpty) return;

      final cleanTitle = _cleanTitle(title);

      String fullImageUrl = imageUrl;
      if (imageUrl.startsWith('//')) {
        fullImageUrl = 'https:$imageUrl';
      } else if (imageUrl.isNotEmpty && imageUrl.startsWith('/')) {
        fullImageUrl = 'https://ekino.ws$imageUrl';
      }

      movies.add(ServiceMovieModel(
        service: SupportedService.ekino,
        title: cleanTitle,
        imageUrl: fullImageUrl,
        url: url,
      ));
    });

    return movies;
  }
}
