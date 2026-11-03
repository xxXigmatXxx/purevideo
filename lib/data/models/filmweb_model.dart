class FilmwebSearchResultModel {
  final int id;
  final String type;
  final String? matchedTitle;
  final String? matchedName;
  final String? matchedLang;

  FilmwebSearchResultModel({
    required this.id,
    required this.type,
    this.matchedTitle,
    this.matchedName,
    this.matchedLang,
  });

  factory FilmwebSearchResultModel.fromJson(Map<String, dynamic> json) {
    return FilmwebSearchResultModel(
      id: json['id'] ?? 0,
      type: json['type'] ?? '',
      matchedTitle: json['matchedTitle'],
      matchedName: json['matchedName'],
      matchedLang: json['matchedLang'],
    );
  }

  @override
  String toString() {
    return 'FilmwebSearchResultModel(id: $id, type: $type, matchedTitle: $matchedTitle, matchedName: $matchedName, matchedLang: $matchedLang)';
  }
}

class FilmwebRatingModel {
  final String count;
  final String rate;

  FilmwebRatingModel({
    required this.count,
    required this.rate,
  });

  factory FilmwebRatingModel.fromJson(Map<String, dynamic> json) {
    return FilmwebRatingModel(
      count: json['count']?.toString() ?? '-',
      rate: json['rate']?.toString() ?? '-',
    );
  }
}

class FilmwebPreviewModel {
  final int id;
  final int year;
  final String plot;
  final String posterUrl;
  final String title;
  final String originalTitle;

  FilmwebPreviewModel({
    required this.id,
    required this.year,
    required this.plot,
    required this.title,
    required this.posterUrl,
    required this.originalTitle,
  });

  factory FilmwebPreviewModel.fromJson(
      Map<String, dynamic> json, int filmwebId) {
    return FilmwebPreviewModel(
      id: filmwebId,
      year: json['year'] ?? 0,
      plot: json['plot']?['synopsis'] ?? '',
      title: (json['title'] is Map ? (json['title']['title'] ?? '') : (json['title']?.toString() ?? '')).toString().trim().isNotEmpty ? (json['title'] is Map ? (json['title']['title'] ?? '') : (json['title']?.toString() ?? '')).toString().trim() : ((json['originalTitle'] is Map ? (json['originalTitle']['title'] ?? '') : (json['originalTitle']?.toString() ?? '')).toString().trim().isNotEmpty ? (json['originalTitle'] is Map ? (json['originalTitle']['title'] ?? '') : (json['originalTitle']?.toString() ?? '')).toString().trim() : 'Film'),
      posterUrl: json['poster']?['path'] != null
          ? 'https://fwcdn.pl/fpo${json['poster']['path']}'
              .replaceAll('\$.jpg', '10.webp')
          : '',
      originalTitle: json['originalTitle']?['title'] ?? '',
    );
  }

  @override
  String toString() {
    return 'FilmwebPreviewModel(year: $year, plot: $plot, posterUrl: $posterUrl, title: $title, originalTitle: $originalTitle)';
  }
}
