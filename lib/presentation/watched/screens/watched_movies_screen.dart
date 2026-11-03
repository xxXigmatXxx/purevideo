import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';
import 'package:purevideo/di/injection_container.dart';
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
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
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
                        height: 170,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: myList.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final m = myList[index];
                            return SizedBox(
                              width: 114,
                              child: GestureDetector(
                                onTap: () => context.pushNamed(
                                  'movie_details',
                                  pathParameters: {'title': m.title},
                                  extra: m,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: FastCachedImage(
                                    url: m.imageUrl,
                                    headers: m.imageHeaders,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF1F1F1F),
                                      child: const Icon(Icons.movie,
                                          color: _kNetflixRed),
                                    ),
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
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.63,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
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
                                (watchedSec / denom).clamp(0.06, 0.96);

                            return GestureDetector(
                              onTap: () => context.pushNamed(
                                'movie_details',
                                pathParameters: {'title': movie.title},
                                extra: movie,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FastCachedImage(
                                      url: movie.imageUrl,
                                      headers: movie.imageHeaders,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFF1F1F1F),
                                        child: const Icon(Icons.movie,
                                            color: _kNetflixRed),
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
