import 'package:dio/dio.dart';

class FilmwebDioFactory {
  static Dio getDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://www.filmweb.pl/',
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        },
      ),
    );
    return dio;
  }
}
