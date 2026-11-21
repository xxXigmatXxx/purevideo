import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cast_framework/cast.dart';
import 'package:flutter_cast_framework/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/movies/bloc/movies_bloc.dart';
import 'package:purevideo/presentation/movies/bloc/movies_event.dart';
import 'package:purevideo/presentation/movies/bloc/movies_state.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

const Color _kNetflixRed = Color(0xFFE50914);

enum _HomeFilter { all, series, movies, myList }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class MovieListItem extends StatelessWidget {
  final MovieModel movie;
  final String? bottomBadge;
  final int? topRank;
  final bool autofocus;

  const MovieListItem({
    super.key,
    required this.movie,
    this.bottomBadge,
    this.topRank,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
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
              title: movie.title,
            ),
            // Top-left PureVideo 'P' watermark
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(155),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: _kNetflixRed,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            if (topRank != null && topRank! <= 10)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: const BoxDecoration(
                    color: _kNetflixRed,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'TOP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        '$topRank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (bottomBadge != null && bottomBadge!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 6,
                right: 6,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: _kNetflixRed,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: Radius.circular(3),
                      ),
                    ),
                    child: Text(
                      bottomBadge!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  late MoviesBloc _moviesBloc;
  final WatchedService _watchedService = getIt<WatchedService>();
  final SettingsService _settingsService = getIt<SettingsService>();
  _HomeFilter _selectedFilter = _HomeFilter.all;
  String? _selectedCategory;
  int _heroSeed = 0;

  static const Set<String> _genericCategories = {
    'polecane dla ciebie',
    'popularne filmy',
    'gorące filmy',
    'najnowsze filmy',
    'najpopularniejsze filmy',
    'popularne',
  };

  @override
  void initState() {
    super.initState();
    _moviesBloc = MoviesBloc();
  }

  String _movieDedupeKey(MovieModel m) {
    final norm = MergeService.normalizeTitle(m.title);
    final isSeries = _isSeriesMovie(m) ? 's' : 'm';
    return '$norm|$isSeries';
  }

  List<MovieModel> _dedupeMovies(List<MovieModel> input) {
    final seen = <String>{};
    final out = <MovieModel>[];
    for (final m in input) {
      final key = _movieDedupeKey(m);
      if (key.isEmpty || key.startsWith('|')) continue;
      if (seen.add(key)) {
        out.add(m);
      }
    }
    return out;
  }

  bool _isSeriesMovie(MovieModel m) {
    for (final s in m.services) {
      final cat = (s.category ?? '').toLowerCase();
      final url = s.url.toLowerCase();
      if (cat.contains('serial') ||
          url.contains('/s/') ||
          url.contains('/serie/') ||
          url.contains('serial')) {
        return true;
      }
    }
    return false;
  }

  String _cleanCategoryName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'INNE') {
      return 'Polecane dla Ciebie';
    }
    final lower = trimmed.toLowerCase();
    if (lower.contains('bajki') ||
        lower == 'animacja' ||
        lower == 'seriale animowane') {
      return 'Bajki dla dzieci';
    }
    if (lower.contains('familij')) {
      return 'Familijne';
    }
    if (lower == 'najpopularniejsze seriale' || lower == 'seriale') {
      return 'Popularne seriale';
    }
    if (lower == 'najpopularniejsze filmy' ||
        lower == 'gorące filmy' ||
        lower == 'najnowsze filmy') {
      return 'Popularne filmy';
    }
    return lower[0].toUpperCase() + lower.substring(1);
  }

  List<String> _extractMovieCategories(MovieModel movie) {
    final cats = <String>{};
    for (final s in movie.services) {
      final raw = s.category ?? '';
      for (final part in raw.split('|')) {
        if (part.trim().isNotEmpty) {
          cats.add(_cleanCategoryName(part));
        }
      }
    }
    if (cats.isEmpty) {
      cats.add(
          _isSeriesMovie(movie) ? 'Popularne seriale' : 'Popularne filmy');
    }
    return cats.toList();
  }

  String _pickPrimaryCategory(List<String> cats) {
    // Prefer specific genres/curated categories over generic catch-alls
    for (final c in const [
      'Bajki dla dzieci',
      'Anime',
      'Familijne',
      'Popularne seriale',
      'Akcja',
      'Komedia',
      'Horror',
      'Thriller',
      'Sci-Fi',
      'Dramat',
    ]) {
      if (cats.contains(c)) return c;
    }
    for (final c in cats) {
      if (!_genericCategories.contains(c.toLowerCase())) return c;
    }
    return cats.first;
  }

  List<MovieModel> _applyFilter(List<MovieModel> all) {
    var list = _dedupeMovies(all);
    if (_selectedFilter == _HomeFilter.series) {
      list = list.where(_isSeriesMovie).toList();
    } else if (_selectedFilter == _HomeFilter.movies) {
      list = list.where((m) => !_isSeriesMovie(m)).toList();
    } else if (_selectedFilter == _HomeFilter.myList) {
      return _dedupeMovies(_settingsService.getMyList());
    }
    if (_selectedCategory != null) {
      list = list
          .where((m) => _extractMovieCategories(m).contains(_selectedCategory))
          .toList();
    }
    return list;
  }

  List<String> _collectAllCategories(List<MovieModel> movies) {
    final set = <String>{};
    for (final m in movies) {
      set.addAll(_extractMovieCategories(m));
    }
    final ordered = <String>[];
    for (final priority in const [
      'Bajki dla dzieci',
      'Anime',
      'Familijne',
      'Popularne seriale',
      'Popularne filmy',
      'Akcja',
      'Komedia',
      'Horror',
      'Thriller',
      'Sci-Fi',
      'Dramat',
    ]) {
      if (set.remove(priority)) {
        ordered.add(priority);
      }
    }
    ordered.addAll(set);
    return ordered;
  }

  Map<String, List<MovieModel>> _groupByCategories(
    List<MovieModel> movies, {
    Set<String> excludeKeys = const {},
  }) {
    final rawMap = <String, List<MovieModel>>{};
    final usedKeys = <String>{...excludeKeys};

    for (final movie in movies) {
      final key = _movieDedupeKey(movie);
      final cats = _extractMovieCategories(movie);

      if (_selectedCategory != null) {
        if (!cats.contains(_selectedCategory)) continue;
        final bucket = rawMap.putIfAbsent(_selectedCategory!, () => []);
        if (!bucket.any((m) => _movieDedupeKey(m) == key)) {
          bucket.add(movie);
        }
      } else {
        // Assign every movie to AT MOST ONE category row on the Home feed -> ZERO duplicates!
        if (!usedKeys.add(key)) continue;
        final primaryCat = _pickPrimaryCategory(cats);
        final bucket = rawMap.putIfAbsent(primaryCat, () => []);
        bucket.add(movie);
      }
    }

    final ordered = <String, List<MovieModel>>{};
    for (final priority in const [
      'Bajki dla dzieci',
      'Anime',
      'Familijne',
      'Popularne seriale',
      'Akcja',
      'Komedia',
      'Horror',
      'Thriller',
      'Sci-Fi',
      'Dramat',
      'Popularne filmy',
    ]) {
      if (rawMap.containsKey(priority)) {
        ordered[priority] = rawMap.remove(priority)!;
      }
    }
    ordered.addAll(rawMap);
    return ordered;
  }

  void _showCategoryPicker(BuildContext context, List<String> categories) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wybierz kategorię',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(
                          'Wszystkie kategorie',
                          style: TextStyle(
                            color: _selectedCategory == null
                                ? _kNetflixRed
                                : Colors.white,
                            fontWeight: _selectedCategory == null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: _selectedCategory == null
                            ? const Icon(Icons.check, color: _kNetflixRed)
                            : null,
                        onTap: () {
                          setState(() => _selectedCategory = null);
                          Navigator.of(ctx).pop();
                        },
                      ),
                      for (final c in categories)
                        ListTile(
                          title: Text(
                            c,
                            style: TextStyle(
                              color: _selectedCategory == c
                                  ? _kNetflixRed
                                  : Colors.white70,
                              fontWeight: _selectedCategory == c
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: _selectedCategory == c
                              ? const Icon(Icons.check, color: _kNetflixRed)
                              : null,
                          onTap: () {
                            setState(() => _selectedCategory = c);
                            Navigator.of(ctx).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = DeviceUtils.isWideLayout(context);

    return BlocProvider(
      create: (_) => _moviesBloc..add(LoadMoviesRequested()),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocBuilder<MoviesBloc, MoviesState>(
          builder: (context, state) {
            if (state is MoviesLoading) {
              return const Center(
                child: CircularProgressIndicator(color: _kNetflixRed),
              );
            }

            if (state is MoviesError) {
              return ErrorView(
                message: state.message,
                onRetry: () {
                  context.read<MoviesBloc>().add(LoadMoviesRequested());
                },
              );
            }

            if (state is MoviesLoaded) {
              final allUnique = _dedupeMovies(state.movies);
              if (allUnique.isEmpty) {
                return const Center(
                  child: Text(
                    'Brak dostępnych filmów',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final allCategories = _collectAllCategories(allUnique);
              final filteredMovies = _applyFilter(allUnique);
              final pool =
                  filteredMovies.isNotEmpty ? filteredMovies : allUnique;
              final heroMovie = pool[_heroSeed % pool.length];

              final showTop10 =
                  _selectedCategory == null && pool.length >= 3;
              final top10Movies = showTop10 ? pool.take(10).toList() : <MovieModel>[];
              final excludeFromCategories = <String>{
                if (_selectedCategory == null) ...top10Movies.map(_movieDedupeKey),
              };
              final grouped = _groupByCategories(
                pool,
                excludeKeys: excludeFromCategories,
              );

              return SettingsListenable(
                builder: (context, box, _) {
                  if (!_settingsService.isNetflixStyle) {
                    final gridCols =
                        screenWidth > 960 ? 6 : (screenWidth > 620 ? 4 : 3);
                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('PureVideo'),
                        actions: [
                          if (!DeviceUtils.isTv)
                            CastButton(
                              castFramework: getIt<FlutterCastFramework>(),
                              activeColor: _kNetflixRed,
                              color: Colors.white,
                              disabledColor: Colors.white60,
                            ),
                          IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => context.go('/search'),
                          ),
                        ],
                      ),
                      body: RefreshIndicator(
                        onRefresh: () async {
                          context.read<MoviesBloc>().add(LoadMoviesRequested());
                        },
                        child: GridView.builder(
                          padding: const EdgeInsets.all(10),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: gridCols,
                            childAspectRatio: 0.67,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: allUnique.length,
                          itemBuilder: (context, index) => MovieListItem(
                            movie: allUnique[index],
                            autofocus: DeviceUtils.isTv && index == 0,
                          ),
                        ),
                      ),
                    );
                  }

                  final myList = _dedupeMovies(_settingsService.getMyList());
                  return Stack(
                    children: [
                      RefreshIndicator(
                        color: _kNetflixRed,
                        backgroundColor: const Color(0xFF1A1A1A),
                        onRefresh: () async {
                          setState(() => _heroSeed++);
                          context.read<MoviesBloc>().add(LoadMoviesRequested());
                        },
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: _buildTopHeaderAndPills(
                                context,
                                allCategories,
                                isWide: isWide,
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: isWide
                                  ? _buildTvHeroBanner(context, heroMovie)
                                  : _buildHeroBanner(context, heroMovie),
                            ),
                            // Continue Watching row ("Ostatnio oglądane")
                            SliverToBoxAdapter(
                              child: _buildContinueWatchingSection(context),
                            ),
                            // My List row ("Moja lista")
                            if (myList.isNotEmpty)
                              SliverToBoxAdapter(
                                child: _buildHorizontalRow(
                                  context,
                                  title: 'Moja lista',
                                  movies: myList,
                                  badgeText: null,
                                ),
                              ),
                            // Top 10 / Popularne
                            if (showTop10)
                              SliverToBoxAdapter(
                                child: _buildHorizontalRow(
                                  context,
                                  title: 'Top 10 dzisiaj w PureVideo',
                                  movies: top10Movies,
                                  showRank: true,
                                  badgeText: 'Nowy sezon',
                                ),
                              ),
                            // Category rows (100% deduplicated!)
                            for (final entry in grouped.entries)
                              if (entry.value.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _buildHorizontalRow(
                                    context,
                                    title: entry.key,
                                    movies: entry.value,
                                    badgeText: entry.key
                                            .toLowerCase()
                                            .contains('nowe')
                                        ? 'Ostatnio dodany'
                                        : null,
                                  ),
                                ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 90),
                            ),
                          ],
                        ),
                      ),
                      if (!isWide)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: TvFocusable(
                            borderRadius: BorderRadius.circular(28),
                            onTap: () {
                              final randomMovie = allUnique[
                                  DateTime.now().millisecondsSinceEpoch %
                                      allUnique.length];
                              context.pushNamed(
                                'movie_details_plain',
                                extra: randomMovie,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shuffle,
                                      color: _kNetflixRed, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Odtwórz losowo',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildTopHeaderAndPills(
      BuildContext context, List<String> allCategories,
      {bool isWide = false}) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 8, isWide ? 24 : 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'P',
                  style: TextStyle(
                    color: _kNetflixRed,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'PureVideo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!DeviceUtils.isTv)
                  CastButton(
                    castFramework: getIt<FlutterCastFramework>(),
                    activeColor: _kNetflixRed,
                    color: Colors.white,
                    disabledColor: Colors.white60,
                  ),
                IconButton(
                  icon:
                      const Icon(Icons.search, color: Colors.white, size: 26),
                  onPressed: () => context.go('/search'),
                ),
                const SizedBox(width: 4),
                TvFocusable(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => context.pushNamed('accounts'),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kNetflixRed, Color(0xFF8B0000)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedFilter != _HomeFilter.all ||
                      _selectedCategory != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TvFocusable(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() {
                          _selectedFilter = _HomeFilter.all;
                          _selectedCategory = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white54),
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  _buildFilterChip(
                    label: 'Seriale',
                    selected: _selectedFilter == _HomeFilter.series,
                    onTap: () => setState(() {
                      _selectedFilter = _selectedFilter == _HomeFilter.series
                          ? _HomeFilter.all
                          : _HomeFilter.series;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Filmy',
                    selected: _selectedFilter == _HomeFilter.movies,
                    onTap: () => setState(() {
                      _selectedFilter = _selectedFilter == _HomeFilter.movies
                          ? _HomeFilter.all
                          : _HomeFilter.movies;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Moja lista',
                    selected: _selectedFilter == _HomeFilter.myList,
                    onTap: () => setState(() {
                      _selectedFilter = _selectedFilter == _HomeFilter.myList
                          ? _HomeFilter.all
                          : _HomeFilter.myList;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: _selectedCategory ?? 'Kategorie',
                    selected: _selectedCategory != null,
                    hasDropdown: true,
                    onTap: () => _showCategoryPicker(context, allCategories),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    bool hasDropdown = false,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(20),
      focusScale: 1.02,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withAlpha(45) : Colors.black26,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white : Colors.white38,
            width: selected ? 1.3 : 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (hasDropdown) ...[
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white, size: 17),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTvHeroBanner(BuildContext context, MovieModel movie) {
    final isSeries = _isSeriesMovie(movie);
    final inMyList = _settingsService.isInMyList(movie);
    final rawCat = movie.services.first.category;
    final catTag = (rawCat != null && rawCat.trim().isNotEmpty)
        ? _cleanCategoryName(rawCat)
        : (isSeries ? 'Serial' : 'Film');
    final serviceTag =
        movie.services.map((s) => s.service.displayName).join(' • ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
      child: Container(
        height: 290,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 0.9),
          color: const Color(0xFF111111),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred ambient backdrop using the poster
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Opacity(
                  opacity: 0.38,
                  child: PosterImage(
                    url: movie.imageUrl,
                    headers: movie.imageHeaders,
                    title: movie.title,
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xF0000000),
                      Color(0xBB000000),
                      Color(0x44000000),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'P',
                                style: TextStyle(
                                  color: _kNetflixRed,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isSeries ? 'S E R I A L' : 'F I L M',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  letterSpacing: 2.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$catTag  •  Polecane  •  $serviceTag',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TvFocusable(
                                autofocus: DeviceUtils.isTv,
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => context.pushNamed(
                                  'movie_details_plain',
                                  extra: movie,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow,
                                          color: Colors.black, size: 24),
                                      SizedBox(width: 6),
                                      Text(
                                        'Odtwórz',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              TvFocusable(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _settingsService.toggleMyList(movie),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2B2B2B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        inMyList ? Icons.check : Icons.add,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Moja lista',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: TvFocusable(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => context.pushNamed(
                          'movie_details_plain',
                          extra: movie,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: PosterImage(
                            url: movie.imageUrl,
                            headers: movie.imageHeaders,
                            title: movie.title,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context, MovieModel movie) {
    final isSeries = _isSeriesMovie(movie);
    final inMyList = _settingsService.isInMyList(movie);
    final rawCat = movie.services.first.category;
    final catTag = (rawCat != null && rawCat.trim().isNotEmpty)
        ? _cleanCategoryName(rawCat)
        : (isSeries ? 'Serial' : 'Film');
    final serviceTag =
        movie.services.map((s) => s.service.displayName).join(' • ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(16),
        focusScale: 1.01,
        onTap: () => context.pushNamed(
          'movie_details_plain',
          extra: movie,
        ),
        child: Container(
          height: 450,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: _kNetflixRed.withAlpha(35),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterImage(
                  url: movie.imageUrl,
                  headers: movie.imageHeaders,
                  title: movie.title,
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.35, 0.65, 1.0],
                      colors: [
                        Color(0x88000000),
                        Color(0x00000000),
                        Color(0xAA000000),
                        Color(0xF2000000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                            isSeries ? 'S E R I A L' : 'F I L M',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        movie.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$catTag  •  Polecane  •  $serviceTag',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => context.pushNamed(
                                'movie_details_plain',
                                extra: movie,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow,
                                  color: Colors.black, size: 24),
                              label: const Text(
                                'Odtwórz',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _settingsService.toggleMyList(movie);
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF2B2B2B).withAlpha(210),
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              icon: Icon(
                                inMyList ? Icons.check : Icons.add,
                                color: Colors.white,
                                size: 22,
                              ),
                              label: const Text(
                                'Moja lista',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueWatchingSection(BuildContext context) {
    final isWide = DeviceUtils.isWideLayout(context);
    return StreamBuilder<List<WatchedMovieModel>>(
      stream: _watchedService.watchedStream,
      builder: (context, snapshot) {
        final watchedList = (snapshot.data ?? _watchedService.getAll())
            .toList()
          ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));

        if (watchedList.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 18, 16, 10),
              child: const Text(
                'Kontynuuj oglądanie',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              height: 196,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                scrollDirection: Axis.horizontal,
                itemCount: watchedList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = watchedList[index];
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

                  return SizedBox(
                    width: 120,
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.pushNamed(
                        'movie_details_plain',
                        extra: movie,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: const Color(0xFF181818),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    PosterImage(
                                      url: movie.imageUrl,
                                      headers: movie.imageHeaders,
                                      title: movie.title,
                                    ),
                                    Container(color: Colors.black26),
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
                                            padding: const EdgeInsets.all(3),
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
                                    Center(
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(170),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 1.6),
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 6,
                                      right: 6,
                                      bottom: 4,
                                      child: Text(
                                        item.movie.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black,
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 3.5,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    _kNetflixRed),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 5),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.info_outline,
                                      color: Colors.white70,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHorizontalRow(
    BuildContext context, {
    required String title,
    required List<MovieModel> movies,
    bool showRank = false,
    String? badgeText,
  }) {
    final isWide = DeviceUtils.isWideLayout(context);
    final double cardWidth = isWide ? 132 : 120;
    final double rowHeight = isWide ? 198 : 180;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 20, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
            scrollDirection: Axis.horizontal,
            itemCount: movies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final movie = movies[index];
              String? badge = badgeText;
              if (badge == null && index % 5 == 0) {
                badge = 'Ostatnio dodany';
              }
              return SizedBox(
                width: cardWidth,
                child: MovieListItem(
                  movie: movie,
                  topRank: showRank ? index + 1 : null,
                  bottomBadge: badge,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
