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

  void _openPlayer(BuildContext context, MovieDetailsState state) {
    final movie = state.movie!;
    if (!state.isLoaded) return;
    if (movie.isSeries) {
      context.pushNamed(
        'player',
        extra: movie,
        queryParameters: {
          'season': state.selectedSeasonIndex.toString(),
          'episode': ((state.watched?.lastWatchedEpisode?.watchedEpisode
                          .episode.number ??
                      1) -
                  1)
              .toString(),
        },
      );
    } else {
      context.pushNamed(
        'player',
        extra: movie,
      );
    }
  }

  Widget _buildMovieDetails(BuildContext context, MovieDetailsState state) {
    final movie = state.movie!;
    final movieModel = _asMovieModel(movie);
    final watched = state.watched;
    final lastEp = watched?.lastWatchedEpisode;
    final int watchedSec =
        lastEp != null ? lastEp.watchedEpisode.watchedTime : (watched?.watchedTime ?? 0);
    final int denom = movie.isSeries ? 2700 : 5700;
    final double progress =
        watchedSec > 0 ? (watchedSec / denom).clamp(0.05, 0.96) : 0.0;

    final allMerged = getIt<MergeService>().getMovies;
    final similar = allMerged
        .where((m) => m.title != movie.title)
        .take(9)
        .toList();

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
                                  'movie_details',
                                  pathParameters: {'title': next.title},
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
                            'movie_details',
                            pathParameters: {'title': sim.title},
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
        return 'Kontynuuj S${state.selectedSeasonIndex + 1}:E${state.watched!.lastWatchedEpisode?.watchedEpisode.episode.number ?? 1}';
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
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(6),
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
              trailing: const Icon(
                Icons.play_circle_outline,
                color: Colors.white70,
                size: 26,
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
