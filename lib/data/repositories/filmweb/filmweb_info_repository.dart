import 'package:dio/dio.dart';
import 'package:purevideo/data/models/filmweb_model.dart';
import 'package:purevideo/data/repositories/filmweb/filmweb_dio_factory.dart';

class FilmwebInfoRepository {
  final Dio _dio = FilmwebDioFactory.getDio();

  FilmwebInfoRepository();

  Future<FilmwebPreviewModel?> searchTopPreview(String query,
      {bool? isSeries}) async {
    final response = await _dio.get('api/v1/search', queryParameters: {
      'query': query.toLowerCase(),
      'pageSize': 3,
      'groupType': 'web',
    });
    if (response.statusCode != 200) return null;
    final List<dynamic> results = response.data['searchHits'] ?? [];
    for (final r in results) {
      if (r['id'] == null) continue;
      final type = r['type']?.toString() ?? '';
      final matchesType = isSeries == null
          ? (type == 'serial' || type == 'film')
          : type == (isSeries ? 'serial' : 'film');
      if (matchesType) {
        final id = int.tryParse(r['id'].toString());
        if (id != null && id > 0) {
          return await getPreview(id);
        }
      }
    }
    return null;
  }

  Future<List<FilmwebPreviewModel>> searchMovie(String query,
      {bool? isSeries}) async {
    final response = await _dio.get('api/v1/search', queryParameters: {
      'query': query.toLowerCase(),
      'pageSize': 25,
      'groupType': 'web'
    });
    if (response.statusCode == 200) {
      final List<dynamic> results = response.data['searchHits'] ?? [];
      final search = results
          .where((r) =>
              r['id'] != null &&
              (isSeries == null
                  ? ['serial', 'film'].contains(r['type'])
                  : r['type'] == (isSeries ? 'serial' : 'film')))
          .map((item) => FilmwebSearchResultModel.fromJson(item))
          .toList();

      return await Future.wait(search.map((result) => getPreview(result.id)));
    } else {
      throw Exception('Failed to load search results');
    }
  }

  Future<FilmwebPreviewModel> getPreview(int filmwebId) async {
    final response = await _dio.get('api/v1/film/$filmwebId/preview');
    if (response.statusCode == 200) {
      final preview = FilmwebPreviewModel.fromJson(response.data, filmwebId);
      return preview;
    } else {
      throw Exception('Failed to load preview');
    }
  }

  // Future<MovieDetailsModel> getMovieDetails(MovieModel movie) async {
  //   final response = await _dio.get('api/v1/film/$filmwebId/details');
  //   if (response.statusCode == 200) {
  //     return details;
  //   } else {
  //     throw Exception('Failed to load movie details');
  //   }
  // }

  Future<FilmwebRatingModel> getRating(int filmwebId) async {
    final response = await _dio.get('api/v1/film/$filmwebId/ratings');
    if (response.statusCode == 200) {
      final rating = FilmwebRatingModel.fromJson(response.data);
      return rating;
    } else {
      throw Exception('Failed to load rating');
    }
  }
}
