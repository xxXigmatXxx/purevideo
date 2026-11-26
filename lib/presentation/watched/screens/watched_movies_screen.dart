import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/core/utils/tv_nav_controller.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/purevideo_logo.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/movies/widgets/tv_expandable_movie_row.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

const Color _kNetflixRed = kPureVideoRed;

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
      backgroundColor: const Color(0xFF0A0A0D),
      appBar: isWide
          ? null
          : AppBar(
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
                  icon: const Icon(Icons.manage_accounts_outlined,
                      color: Colors.white),
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

              if (isWide) {
                final watchedItems = watchedMovies.map((w) {
                  final m = MovieModel(
                    services: w.movie.services
                        .map((s) => ServiceMovieModel(
                              service: s.service,
                              url: s.url,
                              title: s.title,
                              imageUrl: s.imageUrl,
                            ))
                        .toList(),
                  );
                  final lastEp = w.lastWatchedEpisode;
                  final int watchedSec = lastEp != null
                      ? lastEp.watchedEpisode.watchedTime
                      : w.watchedTime;
                  final int denom = w.movie.isSeries ? 2700 : 5700;
                  final double progress =
                      (watchedSec / denom).clamp(0.06, 0.96);
                  final String subtitle = lastEp != null
                      ? 'S${lastEp.season.number}:E${lastEp.watchedEpisode.episode.number}'
                      : '${(watchedSec ~/ 60) > 0 ? (watchedSec ~/ 60) : 1} min';
                  return TvExpandableRowItem(
                    movie: m,
                    progress: progress,
                    episodeLabel: subtitle,
                    subtitleOverride: lastEp != null
                        ? 'Kontynuuj odtwarzanie ($subtitle)'
                        : 'Obejrzano: $subtitle',
                  );
                }).toList();

                return CustomScrollView(
                  slivers: [
                    if (myList.isNotEmpty)
                      SliverToBoxAdapter(
                        child: TvExpandableMovieRow(
                          title: 'Moja lista',
                          firstItemFocusNode:
                              TvNavController.instance.myListFirstNode,
                          autofocusFirst: true,
                          items: myList
                              .map((m) => TvExpandableRowItem(movie: m))
                              .toList(),
                          onItemLongPress: (item) =>
                              _settingsService.toggleMyList(item.movie),
                        ),
                      ),
                    if (watchedItems.isNotEmpty)
                      SliverToBoxAdapter(
                        child: TvExpandableMovieRow(
                          title: 'Kontynuuj oglądanie',
                          firstItemFocusNode: myList.isEmpty
                              ? TvNavController.instance.myListFirstNode
                              : null,
                          autofocusFirst: myList.isEmpty,
                          items: watchedItems,
                          onItemLongPress: (rowItem) {
                            final found = watchedMovies.firstWhere(
                              (w) =>
                                  MergeService.normalizeTitle(w.movie.title) ==
                                  MergeService.normalizeTitle(
                                      rowItem.movie.title),
                              orElse: () => watchedMovies.first,
                            );
                            _watchedService.removeMovie(found.movie);
                          },
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 60)),
                  ],
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
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final m = myList[index];
                            return SizedBox(
                              width: 114,
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
                                    fallbacks: m.fallbackPosterCandidates,
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
                          'Kontynuuj oglądanie',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.67,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = watchedMovies[index];
                            final movie = MovieModel(
                              services: item.movie.services
                                  .map((s) => ServiceMovieModel(
                                        service: s.service,
                                        url: s.url,
                                        title: s.title,
                                        imageUrl: s.imageUrl,
                                      ))
                                  .toList(),
                            );
                            final lastEp = item.lastWatchedEpisode;
                            final int watchedSec = lastEp != null
                                ? lastEp.watchedEpisode.watchedTime
                                : item.watchedTime;
                            final int denom = item.movie.isSeries ? 2700 : 5700;
                            final double progress =
                                (watchedSec / denom).clamp(0.06, 0.96);
                            final String subtitle = lastEp != null
                                ? 'S${lastEp.season.number}:E${lastEp.watchedEpisode.episode.number}'
                                : '${(watchedSec ~/ 60) > 0 ? (watchedSec ~/ 60) : 1} min';
                            return TvFocusable(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => context.pushNamed(
                                'movie_details_plain',
                                extra: movie,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    PosterImage(
                                      url: movie.imageUrl,
                                      headers: movie.imageHeaders,
                                      fallbacks: movie.fallbackPosterCandidates,
                                      title: movie.title,
                                    ),
                                    Container(color: Colors.black26),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _watchedService
                                            .removeMovie(item.movie),
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
                                      left: 6,
                                      bottom: 10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          subtitle,
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
