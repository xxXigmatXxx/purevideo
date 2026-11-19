import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

const Color _kNetflixRed = Color(0xFFE50914);

class WatchedMoviesScreen extends StatefulWidget {
  const WatchedMoviesScreen({super.key});

  @override
  State<WatchedMoviesScreen> createState() => _WatchedMoviesScreenState();
}

class _WatchedMoviesScreenState extends State<WatchedMoviesScreen> {
  final WatchedService _watchedService = getIt<WatchedService>();
  final SettingsService _settingsService = getIt<SettingsService>();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bool isWide = DeviceUtils.isWideLayout(context);
    final int crossAxisCount =
        width > 1100 ? 6 : (width > 760 ? 5 : (width > 560 ? 4 : 3));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Moje PureVideo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            focusColor: Colors.white24,
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            focusColor: Colors.white24,
            icon: const Icon(Icons.manage_accounts_outlined, color: Colors.white),
            onPressed: () => context.pushNamed('accounts'),
          ),
        ],
      ),
      body: SettingsListenable(
        builder: (context, box, _) {
          final myList = _settingsService.getMyList();
          return StreamBuilder<List<WatchedMovieModel>>(
            stream: _watchedService.watchedStream,
            builder: (context, snapshot) {
              final watchedMovies =
                  (snapshot.data ?? _watchedService.getAll()).toList()
                    ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));

              if (watchedMovies.isEmpty && myList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.movie_filter_outlined,
                        color: Colors.white38,
                        size: 64,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Brak zapisanych i oglądanych filmów',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Dodaj tytuły do „Mojej listy” lub rozpocznij oglądanie.',
                        style: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return CustomScrollView(
                slivers: [
                  if (myList.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Text(
                          'Moja lista',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: isWide ? 210 : 170,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: myList.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final m = myList[index];
                            return SizedBox(
                              width: isWide ? 140 : 114,
                              child: TvFocusable(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => context.pushNamed(
                                  'movie_details_plain',
                                  extra: m,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: PosterImage(
                                    url: m.imageUrl,
                                    headers: m.imageHeaders,
                                    title: m.title,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  if (watchedMovies.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
                        child: Text(
                          'Ostatnio oglądane',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.63,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = watchedMovies[index];
                            final movie = MovieModel(
                              services: item.movie.services
                                  .map((e) => ServiceMovieModel(
                                        service: e.service,
                                        url: e.url,
                                        title: e.title,
                                        imageUrl: e.imageUrl,
                                      ))
                                  .toList(),
                            );
                            final lastEp = item.lastWatchedEpisode;
                            final int watchedSec = lastEp != null
                                ? lastEp.watchedEpisode.watchedTime
                                : item.watchedTime;
                            final int denom =
                                item.movie.isSeries ? 2700 : 5700;
                            final double progress =
                                (watchedSec / denom).clamp(0.08, 0.96);
                            final String badge = lastEp != null
                                ? 'S${lastEp.season.number}:E${lastEp.watchedEpisode.episode.number}'
                                : '${(watchedSec ~/ 60) > 0 ? (watchedSec ~/ 60) : 1} min';

                            return TvFocusable(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => context.pushNamed(
                                'movie_details_plain',
                                extra: movie,
                              ),
                              onLongPress: DeviceUtils.isTv
                                  ? () =>
                                      _watchedService.removeMovie(item.movie)
                                  : null,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    PosterImage(
                                      url: movie.imageUrl,
                                      headers: movie.imageHeaders,
                                      title: movie.title,
                                    ),
                                    if (!DeviceUtils.isTv)
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () {
                                            _watchedService
                                                .removeMovie(item.movie);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black87,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white70,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            6, 16, 6, 4),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black87,
                                            ],
                                          ),
                                        ),
                                        child: Text(
                                          '${movie.title} ($badge)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 4,
                                        backgroundColor: Colors.black54,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                                _kNetflixRed),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: watchedMovies.length,
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
