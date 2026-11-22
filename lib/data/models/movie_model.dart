import 'package:hive_flutter/adapters.dart';
import 'package:purevideo/core/services/poster_cache_service.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/filmweb_model.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/di/injection_container.dart';

part 'movie_model.g.dart';

@HiveType(typeId: 6)
class ServiceMovieModel {
  @HiveField(0)
  final SupportedService service;

  @HiveField(1)
  final String url;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final String imageUrl;

  @HiveField(4)
  final String? category;

  const ServiceMovieModel({
    required this.service,
    required this.url,
    required this.title,
    required this.imageUrl,
    this.category,
  });
}

@HiveType(typeId: 0)
class MovieModel {
  @HiveField(0)
  final List<ServiceMovieModel> services;

  static String normalizePosterUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty || u.startsWith('data:')) return '';
    if (u.startsWith('//')) u = 'https:$u';
    if (u.startsWith('http://')) {
      final lower = u.toLowerCase();
      if (lower.contains('tmdb.org') ||
          lower.contains('ekino.ws') ||
          lower.contains('obejrzyj.to') ||
          lower.contains('filman.cc') ||
          lower.contains('docchi.pl') ||
          lower.contains('bajeczki.org') ||
          lower.contains('myanimelist.net') ||
          lower.contains('anilist.co') ||
          lower.contains('fwcdn.pl')) {
        u = u.replaceFirst('http://', 'https://');
      }
    }
    if (u.contains('image.tmdb.org/t/p/original/')) {
      u = u.replaceFirst(
          'image.tmdb.org/t/p/original/', 'image.tmdb.org/t/p/w500/');
    }
    return u;
  }

  static Map<String, String> buildImageHeaders(
      SupportedService service, String url) {
    final headers = <String, String>{
      'User-Agent': WebViewService.cleanUserAgent,
    };
    final lower = url.toLowerCase();
    final needsServiceCookies =
        (service == SupportedService.filman && lower.contains('filman')) ||
            (service == SupportedService.ekino && lower.contains('ekino'));
    if (needsServiceCookies) {
      final cookies = getIt<Map<SupportedService, AuthRepository>>()[service]
          ?.getAccount()
          ?.cookies;
      if (cookies != null && cookies.isNotEmpty) {
        final cookieStr = cookies
            .where((c) => c.name.isNotEmpty && c.value.isNotEmpty)
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
        if (cookieStr.isNotEmpty) {
          headers['Cookie'] = cookieStr;
        }
      }
      if (service == SupportedService.ekino) {
        headers['Referer'] = 'https://ekino.ws/';
      } else if (service == SupportedService.filman) {
        headers['Referer'] = 'https://filman.cc/';
      }
    }
    return headers;
  }

  static int _posterServicePriority(ServiceMovieModel s) {
    final u = s.imageUrl.trim().toLowerCase();
    if (u.isEmpty || !u.startsWith('http')) return 99;
    if (u.contains('tmdb.org')) return 0;
    if (s.service == SupportedService.obejrzyjto) return 1;
    if (s.service == SupportedService.docchi) return 2;
    if (s.service == SupportedService.ekino) return 3;
    if (s.service == SupportedService.custom) return 4;
    if (s.service == SupportedService.bajeczki) return 5;
    if (s.service == SupportedService.filman) return 6;
    return 7;
  }

  List<ServiceMovieModel> get _rankedPosterServices {
    final list = List<ServiceMovieModel>.from(services);
    list.sort((a, b) =>
        _posterServicePriority(a).compareTo(_posterServicePriority(b)));
    return list;
  }

  ServiceMovieModel get _bestPosterService => _rankedPosterServices.first;

  String get title => services.first.title;

  String get imageUrl => normalizePosterUrl(_bestPosterService.imageUrl);

  Map<String, String> get imageHeaders {
    final best = _bestPosterService;
    return buildImageHeaders(best.service, normalizePosterUrl(best.imageUrl));
  }

  List<PosterCandidate> get fallbackPosterCandidates {
    final ranked = _rankedPosterServices;
    if (ranked.length <= 1) return const [];
    final primaryUrl = imageUrl;
    final out = <PosterCandidate>[];
    for (final s in ranked.skip(1)) {
      final norm = normalizePosterUrl(s.imageUrl);
      if (norm.isNotEmpty && norm != primaryUrl) {
        out.add(PosterCandidate(
          url: norm,
          headers: buildImageHeaders(s.service, norm),
        ));
      }
    }
    return out;
  }

  const MovieModel({
    required this.services,
  });
}

@HiveType(typeId: 1)
class EpisodeModel {
  @HiveField(0)
  final String url;

  @HiveField(1)
  final int number;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final List<HostLink>? videoUrls;

  @HiveField(4)
  final List<VideoSource>? directUrls;

  EpisodeModel(
      {required this.title,
      required this.number,
      required this.url,
      required this.videoUrls,
      this.directUrls});

  EpisodeModel copyWith({
    String? url,
    int? number,
    String? title,
    List<HostLink>? videoUrls,
    List<VideoSource>? directUrls,
  }) {
    return EpisodeModel(
        url: url ?? this.url,
        number: number ?? this.number,
        title: title ?? this.title,
        videoUrls: videoUrls ?? this.videoUrls,
        directUrls: directUrls ?? this.directUrls);
  }
}

@HiveType(typeId: 4)
class SeasonModel {
  @HiveField(0)
  final int number;

  @HiveField(1)
  final List<EpisodeModel> episodes;

  SeasonModel({required this.number, required this.episodes});
}

@HiveType(typeId: 7)
class ServiceMovieDetailsModel {
  @HiveField(0)
  final SupportedService service;

  @HiveField(1)
  final String url;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final String description;

  @HiveField(4)
  final String imageUrl;

  @HiveField(5)
  final List<HostLink>? videoUrls;

  @HiveField(10)
  final bool isSeries;

  @HiveField(11)
  final List<SeasonModel>? seasons;

  const ServiceMovieDetailsModel({
    required this.service,
    required this.url,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.isSeries,
    this.videoUrls,
    this.seasons,
  });

  ServiceMovieDetailsModel copyWith({
    SupportedService? service,
    String? url,
    String? title,
    String? description,
    String? imageUrl,
    List<HostLink>? videoUrls,
    String? year,
    List<String>? genres,
    List<String>? countries,
    bool? isSeries,
    List<SeasonModel>? seasons,
  }) {
    return ServiceMovieDetailsModel(
      service: service ?? this.service,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrls: videoUrls ?? this.videoUrls,
      isSeries: isSeries ?? this.isSeries,
      seasons: seasons ?? this.seasons,
    );
  }

  @override
  String toString() {
    return 'ServiceMovieDetailsModel(service: $service, url: $url, title: $title, description: $description, imageUrl: $imageUrl, videoUrls: $videoUrls, isSeries: $isSeries, seasons: $seasons)';
  }
}

@HiveType(typeId: 5)
class MovieDetailsModel {
  @HiveField(0)
  final List<ServiceMovieDetailsModel> services;

  @HiveField(1)
  final FilmwebPreviewModel? filmwebInfo;

  String get title => filmwebInfo?.title ?? services.first.title;

  String get description => filmwebInfo?.plot ?? services.first.description;

  String get imageUrl {
    if (filmwebInfo?.posterUrl != null &&
        filmwebInfo!.posterUrl!.trim().isNotEmpty) {
      return MovieModel.normalizePosterUrl(filmwebInfo!.posterUrl!);
    }
    for (final s in services) {
      if (s.imageUrl.contains('tmdb.org') && s.imageUrl.trim().isNotEmpty) {
        return MovieModel.normalizePosterUrl(s.imageUrl);
      }
    }
    for (final s in services) {
      if (s.imageUrl.trim().isNotEmpty) {
        return MovieModel.normalizePosterUrl(s.imageUrl);
      }
    }
    return '';
  }

  Map<String, String> get imageHeaders {
    final u = imageUrl;
    if (filmwebInfo?.posterUrl != null &&
        filmwebInfo!.posterUrl!.trim().isNotEmpty) {
      return {
        'User-Agent': WebViewService.cleanUserAgent,
      };
    }
    for (final s in services) {
      if (MovieModel.normalizePosterUrl(s.imageUrl) == u) {
        return MovieModel.buildImageHeaders(s.service, u);
      }
    }
    return MovieModel.buildImageHeaders(services.first.service, u);
  }

  List<PosterCandidate> get fallbackPosterCandidates {
    final primary = imageUrl;
    final out = <PosterCandidate>[];
    for (final s in services) {
      final norm = MovieModel.normalizePosterUrl(s.imageUrl);
      if (norm.isNotEmpty && norm != primary) {
        out.add(PosterCandidate(
          url: norm,
          headers: MovieModel.buildImageHeaders(s.service, norm),
        ));
      }
    }
    return out;
  }

  List<HostLink>? get videoUrls =>
      services.expand((e) => e.videoUrls ?? const <HostLink>[]).toList();

  final List<VideoSource>? directUrls;

  bool get isSeries => services.any((s) => s.isSeries);

  final List<SeasonModel>? seasons;

  static List<SeasonModel> _combineSeasons(
      List<ServiceMovieDetailsModel> services) {
    final Map<int, SeasonModel> combinedSeasons = {};

    for (final service in services) {
      if (service.seasons != null) {
        for (final season in service.seasons!) {
          if (combinedSeasons.containsKey(season.number)) {
            final existingSeason = combinedSeasons[season.number]!;
            final allEpisodes = <EpisodeModel>[
              ...existingSeason.episodes,
              ...season.episodes,
            ];

            final Map<int, EpisodeModel> uniqueEpisodes = {};
            for (final episode in allEpisodes) {
              uniqueEpisodes[episode.number] = episode;
            }

            combinedSeasons[season.number] = SeasonModel(
              number: season.number,
              episodes: uniqueEpisodes.values.toList()
                ..sort((a, b) => a.number.compareTo(b.number)),
            );
          } else {
            combinedSeasons[season.number] = SeasonModel(
              number: season.number,
              episodes: season.episodes,
            );
          }
        }
      }
    }

    return combinedSeasons.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  MovieDetailsModel({required this.services, this.filmwebInfo, this.directUrls})
      : seasons = _combineSeasons(services);

  MovieDetailsModel copyWith({
    List<ServiceMovieDetailsModel>? services,
    FilmwebPreviewModel? filmwebInfo,
    List<VideoSource>? directUrls,
  }) {
    return MovieDetailsModel(
      services: services ?? this.services,
      filmwebInfo: filmwebInfo ?? this.filmwebInfo,
      directUrls: directUrls ?? this.directUrls,
    );
  }

  @override
  String toString() {
    return 'MovieDetailsModel(services: $services, title: $title, description: $description, imageUrl: $imageUrl, videoUrls: $videoUrls, directUrls: $directUrls, isSeries: $isSeries, seasons: $seasons)';
  }
}
