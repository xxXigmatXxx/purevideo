import 'dart:async';
import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/filmweb_model.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/repositories/movie_repository.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/movie_details/bloc/movie_details_bloc.dart';
import 'package:purevideo/presentation/movie_details/bloc/movie_details_event.dart';
import 'package:purevideo/presentation/movie_details/bloc/movie_details_state.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

const Color _kNetflixRed = Color(0xFFE50914);

class MovieDetailsScreen extends StatelessWidget {
  final MovieModel? movie;
  final FilmwebPreviewModel? filmwebData;

  const MovieDetailsScreen({
    super.key,
    this.movie,
    this.filmwebData,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MovieDetailsBloc()
        ..add(
          movie != null
              ? LoadMovieDetails(movie: movie!)
              : LoadFilmwebMovieDetails(movie: filmwebData!),
        ),
      child: const MovieDetailsView(),
    );
  }
}

class MovieDetailsView extends StatefulWidget {
  const MovieDetailsView({super.key});

  @override
  State<MovieDetailsView> createState() => _MovieDetailsViewState();
}

class _MovieDetailsViewState extends State<MovieDetailsView> {
  final WatchedService _watchedService = getIt<WatchedService>();
  final SettingsService _settingsService = getIt<SettingsService>();
  StreamSubscription? _watchedSubscription;

  @override
  void initState() {
    super.initState();
    _setupWatchedListener();
  }

  @override
  void dispose() {
    _watchedSubscription?.cancel();
    super.dispose();
  }

  void _setupWatchedListener() {
    _watchedSubscription = _watchedService.watchedStream.listen((watchedList) {
      if (mounted) {
        final bloc = context.read<MovieDetailsBloc>();
        if (bloc.state.movie != null) {
          final watched = _watchedService.getByMovie(bloc.state.movie!);
          bloc.add(UpdateWatchedStatus(watched: watched));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MovieDetailsBloc, MovieDetailsState>(
      builder: (context, state) {
        if (state.movie != null) {
          return _buildMovieDetails(context, state);
        } else if (state.errorMessage != null) {
          return _buildErrorView(
              context, state.errorMessage ?? 'Nieznany błąd');
        } else {
          return _buildLoadingView(context);
        }
      },
    );
  }

  Widget _buildLoadingView(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _kNetflixRed),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text('Anuluj'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, String errorMessage) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: BackButton(
          color: Colors.white,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ErrorView(
        message: 'Wystąpił błąd: $errorMessage',
        onRetry: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  MovieModel _asMovieModel(MovieDetailsModel details) {
    return MovieModel(
      services: details.services
          .map((s) => ServiceMovieModel(
                service: s.service,
                url: s.url,
                title: s.title,
                imageUrl: s.imageUrl,
              ))
          .toList(),
    );
  }

  void _openPlayer(
    BuildContext context,
    MovieDetailsState state, {
    int? sourceIndex,
  }) {
    final movie = state.movie!;
    if (!state.isLoaded) return;
    if (movie.isSeries) {
      int epIdx = 0;
      final lastWatchedEpNum =
          state.watched?.lastWatchedEpisode?.watchedEpisode.episode.number;
      if (lastWatchedEpNum != null &&
          state.episodes.isNotEmpty) {
        final found =
            state.episodes.indexWhere((e) => e.number == lastWatchedEpNum);
        if (found >= 0) epIdx = found;
      }
      final qp = <String, String>{
        'season': state.selectedSeasonIndex.toString(),
        'episode': epIdx.toString(),
      };
      if (sourceIndex != null) {
        qp['source'] = sourceIndex.toString();
      }
      context.pushNamed(
        'player',
        extra: movie,
        queryParameters: qp,
      );
    } else {
      final qp = <String, String>{};
      if (sourceIndex != null) {
        qp['source'] = sourceIndex.toString();
      }
      context.pushNamed(
        'player',
        extra: movie,
        queryParameters: qp,
      );
    }
  }

  Widget _buildSourceBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _showMovieLinksBottomSheet(
      BuildContext context, MovieDetailsState state) {
    final sources = state.movie?.directUrls ?? const <VideoSource>[];
    if (sources.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_rounded,
                          color: _kNetflixRed, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wybierz link wideo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Dostępne źródła: ${sources.length}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final s = sources[idx];
                      final isWeb = s.host.contains('(Web)');
                      final cleanHost =
                          s.host.replaceAll('(Web)', '').trim();
                      final lang = s.lang.trim().isEmpty ? 'PL' : s.lang.trim();
                      final qual =
                          s.quality.trim().isEmpty ? 'HD' : s.quality.trim();

                      return Material(
                        color: const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openPlayer(context, state, sourceIndex: idx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: idx == 0
                                    ? _kNetflixRed.withAlpha(160)
                                    : Colors.white12,
                                width: idx == 0 ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isWeb
                                        ? const Color(0xFF1E3A5F)
                                        : _kNetflixRed.withAlpha(40),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    isWeb
                                        ? Icons.language_rounded
                                        : Icons.bolt_rounded,
                                    color: isWeb
                                        ? const Color(0xFF64B5F6)
                                        : _kNetflixRed,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              'Link #${idx + 1} • $cleanHost',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (idx == 0) ...[
                                            const SizedBox(width: 8),
                                            _buildSourceBadge(
                                              'Polecany',
                                              _kNetflixRed,
                                              Colors.white,
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _buildSourceBadge(
                                            lang,
                                            Colors.white12,
                                            Colors.white,
                                          ),
                                          _buildSourceBadge(
                                            qual,
                                            const Color(0xFF263238),
                                            const Color(0xFF81C784),
                                          ),
                                          _buildSourceBadge(
                                            isWeb
                                                ? 'Odtwarzacz Web'
                                                : 'Odtwarzacz natywny',
                                            isWeb
                                                ? const Color(0xFF1A2736)
                                                : const Color(0xFF1B3320),
                                            isWeb
                                                ? const Color(0xFF90CAF9)
                                                : const Color(0xFF69F0AE),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEpisodeLinksBottomSheet(
    BuildContext context,
    MovieDetailsState state,
    int episodeIndex,
  ) async {
    final movie = state.movie!;
    final seasonIdx = state.selectedSeasonIndex;
    final episode = state.episodes[episodeIndex];
    final movieRepositories = getIt<Map<SupportedService, MovieRepository>>();
    final videoSourceRepository = getIt<VideoSourceRepository>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<VideoSource>>(
          future: () async {
            final eps = <EpisodeModel>[];
            for (final service in movie.services) {
              final repo = movieRepositories[service.service];
              if (repo == null) continue;
              if (service.seasons == null ||
                  seasonIdx >= service.seasons!.length) {
                continue;
              }
              final season = service.seasons![seasonIdx];
              if (episodeIndex >= season.episodes.length) continue;
              final ep = season.episodes[episodeIndex];
              try {
                final withHosts = await repo.getEpisodeHosts(ep);
                eps.add(withHosts);
              } catch (_) {}
            }
            final tempModel = MovieDetailsModel(
              services: [
                ServiceMovieDetailsModel(
                  service: SupportedService.values.first,
                  url: '',
                  title: '',
                  description: '',
                  imageUrl: '',
                  isSeries: true,
                  videoUrls:
                      eps.expand((e) => e.videoUrls ?? const []).toList(),
                ),
              ],
            );
            final resolved =
                await videoSourceRepository.scrapeVideoUrls(tempModel);
            return resolved.directUrls ?? const <VideoSource>[];
          }(),
          builder: (ctx, snapshot) {
            final sources = snapshot.data ?? const <VideoSource>[];
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.72,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                      child: Row(
                        children: [
                          const Icon(Icons.dns_rounded,
                              color: _kNetflixRed, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Odcinek ${episode.number}: ${episode.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  snapshot.connectionState ==
                                          ConnectionState.waiting
                                      ? 'Pobieranie dostępnych linków...'
                                      : 'Dostępne źródła: ${sources.length}',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(
                          child: CircularProgressIndicator(color: _kNetflixRed),
                        ),
                      )
                    else if (sources.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Brak dostępnych linków dla tego odcinka',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: sources.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, idx) {
                            final s = sources[idx];
                            final isWeb = s.host.contains('(Web)');
                            final cleanHost =
                                s.host.replaceAll('(Web)', '').trim();
                            final lang =
                                s.lang.trim().isEmpty ? 'PL' : s.lang.trim();
                            final qual = s.quality.trim().isEmpty
                                ? 'HD'
                                : s.quality.trim();

                            return Material(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  context.pushNamed(
                                    'player',
                                    extra: movie,
                                    queryParameters: {
                                      'season': seasonIdx.toString(),
                                      'episode': episodeIndex.toString(),
                                      'source': idx.toString(),
                                    },
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: idx == 0
                                          ? _kNetflixRed.withAlpha(160)
                                          : Colors.white12,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isWeb
                                              ? const Color(0xFF1E3A5F)
                                              : _kNetflixRed.withAlpha(40),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          isWeb
                                              ? Icons.language_rounded
                                              : Icons.bolt_rounded,
                                          color: isWeb
                                              ? const Color(0xFF64B5F6)
                                              : _kNetflixRed,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Link #${idx + 1} • $cleanHost',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                _buildSourceBadge(
                                                  lang,
                                                  Colors.white12,
                                                  Colors.white,
                                                ),
                                                _buildSourceBadge(
                                                  qual,
                                                  const Color(0xFF263238),
                                                  const Color(0xFF81C784),
                                                ),
                                                _buildSourceBadge(
                                                  isWeb
                                                      ? 'Web'
                                                      : 'Natywny',
                                                  isWeb
                                                      ? const Color(0xFF1A2736)
                                                      : const Color(0xFF1B3320),
                                                  isWeb
                                                      ? const Color(0xFF90CAF9)
                                                      : const Color(0xFF69F0AE),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMovieDetails(BuildContext context, MovieDetailsState state) {
    final movie = state.movie!;
    final movieModel = _asMovieModel(movie);
    final watched = state.watched;
    final lastEp = watched?.lastWatchedEpisode;
    final int watchedSec = lastEp != null
        ? lastEp.watchedEpisode.watchedTime
        : (watched?.watchedTime ?? 0);
    final int denom = movie.isSeries ? 2700 : 5700;
    final double progress =
        watchedSec > 0 ? (watchedSec / denom).clamp(0.05, 0.96) : 0.0;

    final allMerged = getIt<MergeService>().getMovies;
    final similar = allMerged
        .where((m) => m.title != movie.title)
        .take(9)
        .toList();

    final directSources = movie.directUrls ?? const <VideoSource>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SettingsListenable(
        builder: (context, box, _) {
          final inMyList = _settingsService.isInMyList(movieModel);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    SizedBox(
                      height: 290,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FastCachedImage(
                            url: movie.imageUrl,
                            headers: movie.imageHeaders,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF1A1A1A),
                              child: const Icon(Icons.broken_image,
                                  size: 56, color: Colors.white24),
                            ),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x99000000),
                                  Color(0x22000000),
                                  Color(0xEB000000),
                                  Colors.black,
                                ],
                              ),
                            ),
                          ),
                          Center(
                            child: GestureDetector(
                              onTap: () => _openPlayer(context, state),
                              child: Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(150),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: _kNetflixRed, width: 2.2),
                                ),
                                child: Icon(
                                  state.isLoaded
                                      ? Icons.play_arrow
                                      : Icons.hourglass_top,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.white),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                            CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.search,
                                    color: Colors.white),
                                onPressed: () => context.go('/search'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3.5,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(_kNetflixRed),
                        ),
                      ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'P',
                            style: TextStyle(
                              color: _kNetflixRed,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            movie.isSeries ? 'S E R I A L' : 'F I L M',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        movie.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            '98% trafności',
                            style: TextStyle(
                              color: Color(0xFF46D369),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'HD',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              movie.services
                                  .map((s) => s.service.displayName)
                                  .join(' • '),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildPlayButton(context, state),
                      if (!movie.isSeries &&
                          state.isLoaded &&
                          directSources.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _showMovieLinksBottomSheet(context, state),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1E1E),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(
                                vertical: 11, horizontal: 14),
                            minimumSize: const Size(double.infinity, 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: const Icon(Icons.dns_rounded,
                              color: _kNetflixRed, size: 20),
                          label: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Wybierz link / serwer (${directSources.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white70, size: 20),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        movie.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildActionIcon(
                            icon: inMyList ? Icons.check : Icons.add,
                            label: 'Moja lista',
                            onTap: () =>
                                _settingsService.toggleMyList(movieModel),
                          ),
                          if (!movie.isSeries && directSources.isNotEmpty)
                            _buildActionIcon(
                              icon: Icons.dns_rounded,
                              label: 'Linki (${directSources.length})',
                              onTap: () =>
                                  _showMovieLinksBottomSheet(context, state),
                            )
                          else
                            _buildActionIcon(
                              icon: Icons.thumb_up_alt_outlined,
                              label: 'Oceń',
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Dzięki za ocenę!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          if (similar.isNotEmpty)
                            _buildActionIcon(
                              icon: Icons.shuffle,
                              label: 'Inny tytuł',
                              onTap: () {
                                final next = similar[
                                    DateTime.now().millisecondsSinceEpoch %
                                        similar.length];
                                context.pushReplacementNamed(
                                  'movie_details_plain',
                                  extra: next,
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white12, height: 1),
                    ],
                  ),
                ),
              ),
              if (state.isSeries && state.seasons.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: _buildSeriesSection(context, state),
                  ),
                ),
              if (similar.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                    child: Text(
                      'Podobne tytuły',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.67,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final sim = similar[index];
                        return GestureDetector(
                          onTap: () => context.pushReplacementNamed(
                            'movie_details_plain',
                            extra: sim,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: FastCachedImage(
                              url: sim.imageUrl,
                              headers: sim.imageHeaders,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFF1F1F1F),
                                child: const Icon(Icons.movie,
                                    color: Colors.white38),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: similar.length,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton(BuildContext context, MovieDetailsState state) {
    return ElevatedButton.icon(
      onPressed: () => _openPlayer(context, state),
      icon: state.isLoaded
          ? const Icon(Icons.play_arrow, color: Colors.black, size: 26)
          : const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.black,
              ),
            ),
      label: Text(
        state.isLoaded ? watchedText(state) : 'Wczytywanie źródeł...',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          fontSize: 15.5,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 12),
        minimumSize: const Size(double.infinity, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  String watchedText(MovieDetailsState state) {
    if (state.watched != null) {
      if (state.movie!.isSeries) {
        final lastEp = state.watched!.lastWatchedEpisode;
        final sNum =
            lastEp?.season.number ?? (state.selectedSeasonIndex + 1);
        final eNum = lastEp?.watchedEpisode.episode.number ?? 1;
        return 'Kontynuuj S$sNum:E$eNum';
      } else {
        return 'Wznów odtwarzanie';
      }
    } else {
      if (state.movie!.isSeries) {
        return 'Odtwórz sezon ${state.selectedSeasonIndex + 1}';
      } else {
        return 'Odtwórz';
      }
    }
  }

  Widget _buildSeriesSection(BuildContext context, MovieDetailsState state) {
    final bloc = context.read<MovieDetailsBloc>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Odcinki',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (state.seasons.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: state.selectedSeasonIndex,
                    isDense: true,
                    dropdownColor: const Color(0xFF262626),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    items: state.seasons.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text('Sezon ${entry.value.number}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        bloc.add(SelectSeason(seasonIndex: value));
                      }
                    },
                  ),
                ),
              )
            else if (state.seasons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Text(
                  'Sezon ${state.seasons.first.number}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.episodes.length,
          separatorBuilder: (_, __) => const Divider(
            height: 1,
            color: Colors.white12,
          ),
          itemBuilder: (context, index) {
            final episode = state.episodes[index];
            final watchedEp =
                _watchedService.getByEpisode(state.movie!, episode);
            final bool isWatched = watchedEp != null && watchedEp.watchedTime > 0;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 0,
              ),
              leading: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isWatched
                      ? _kNetflixRed.withAlpha(50)
                      : const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(6),
                  border: isWatched
                      ? Border.all(color: _kNetflixRed, width: 1.2)
                      : null,
                ),
                child: Text(
                  episode.number.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                episode.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: isWatched
                  ? Text(
                      'Oglądano • ${(watchedEp.watchedTime ~/ 60)} min',
                      style: const TextStyle(
                        color: _kNetflixRed,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Wybierz link / serwer',
                    icon: const Icon(
                      Icons.dns_rounded,
                      color: Colors.white70,
                      size: 21,
                    ),
                    onPressed: () =>
                        _showEpisodeLinksBottomSheet(context, state, index),
                  ),
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
              onTap: () {
                context.pushNamed(
                  'player',
                  extra: state.movie!,
                  queryParameters: {
                    'season': state.selectedSeasonIndex.toString(),
                    'episode': index.toString(),
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}
