import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cast_framework/cast.dart';
import 'package:flutter_cast_framework/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/tv_preview_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/core/utils/tv_nav_controller.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/purevideo_logo.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/movies/bloc/movies_bloc.dart';
import 'package:purevideo/presentation/movies/bloc/movies_event.dart';
import 'package:purevideo/presentation/movies/bloc/movies_state.dart';
import 'package:purevideo/presentation/movies/widgets/tv_expandable_movie_row.dart';
import 'package:purevideo/presentation/settings/widgets/settings_listenable.dart';

const Color _kNetflixRed = kPureVideoRed;

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
              fallbacks: movie.fallbackPosterCandidates,
              title: movie.title,
            ),
            const Positioned(
              top: 6,
              left: 6,
              child: PureVideoPosterBadge(size: 12),
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
  final TvPreviewService _previewService = getIt<TvPreviewService>();
  final TvNavController _tvNav = TvNavController.instance;
  final ScrollController _verticalScrollController = ScrollController();

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
    _tvNav.homeFilter.addListener(_onTvNavFilterChanged);
    _tvNav.scrollHomeToTop = () {
      if (_verticalScrollController.hasClients) {
        _verticalScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    };
  }

  @override
  void dispose() {
    _tvNav.homeFilter.removeListener(_onTvNavFilterChanged);
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _onTvNavFilterChanged() {
    if (!mounted) return;
    final tvFilter = _tvNav.homeFilter.value;
    setState(() {
      switch (tvFilter) {
        case HomeTabFilter.series:
          _selectedFilter = _HomeFilter.series;
          break;
        case HomeTabFilter.movies:
          _selectedFilter = _HomeFilter.movies;
          break;
        case HomeTabFilter.all:
          _selectedFilter = _HomeFilter.all;
          break;
      }
      _selectedCategory = null;
    });
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
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF141418),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Wybierz kategorię',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TvFocusable(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(10),
                    children: [
                      _CategoryDialogItem(
                        label: 'Wszystkie kategorie',
                        selected: _selectedCategory == null,
                        autofocus: _selectedCategory == null,
                        onTap: () {
                          setState(() => _selectedCategory = null);
                          Navigator.of(ctx).pop();
                        },
                      ),
                      for (final c in categories)
                        _CategoryDialogItem(
                          label: c,
                          selected: _selectedCategory == c,
                          autofocus: _selectedCategory == c,
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
        backgroundColor: const Color(0xFF0A0A0D),
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

              if (isWide) {
                _previewService.requestPreview(heroMovie);
              }

              final showTop10 =
                  _selectedCategory == null && pool.length >= 3;
              final top10Movies =
                  showTop10 ? pool.take(10).toList() : <MovieModel>[];
              final excludeFromCategories = <String>{
                if (_selectedCategory == null)
                  ...top10Movies.map(_movieDedupeKey),
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
                      backgroundColor: const Color(0xFF0A0A0D),
                      appBar: isWide
                          ? null
                          : AppBar(
                              title: const PureVideoWordmark(height: 24),
                              actions: [
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
                          context
                              .read<MoviesBloc>()
                              .add(LoadMoviesRequested());
                        },
                        child: GridView.builder(
                          padding: EdgeInsets.all(isWide ? 24 : 10),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: gridCols,
                            childAspectRatio: 0.67,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: pool.length,
                          itemBuilder: (context, index) => MovieListItem(
                            movie: pool[index],
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
                          context
                              .read<MoviesBloc>()
                              .add(LoadMoviesRequested());
                        },
                        child: CustomScrollView(
                          controller: _verticalScrollController,
                          slivers: [
                            if (!isWide)
                              SliverToBoxAdapter(
                                child: _buildTopHeaderAndPills(
                                  context,
                                  allCategories,
                                ),
                              )
                            else
                              SliverToBoxAdapter(
                                child: _buildTvHeroBanner(
                                  context,
                                  heroMovie,
                                  allCategories,
                                  pool,
                                ),
                              ),
                            if (!isWide)
                              SliverToBoxAdapter(
                                child: _buildHeroBanner(context, heroMovie),
                              ),
                            SliverToBoxAdapter(
                              child: _buildContinueWatchingSection(
                                context,
                                isWide: isWide,
                              ),
                            ),
                            if (myList.isNotEmpty)
                              SliverToBoxAdapter(
                                child: isWide
                                    ? TvExpandableMovieRow(
                                        title: 'Moja lista',
                                        items: myList
                                            .map((m) =>
                                                TvExpandableRowItem(movie: m))
                                            .toList(),
                                      )
                                    : _buildHorizontalRow(
                                        context,
                                        title: 'Moja lista',
                                        movies: myList,
                                        badgeText: null,
                                      ),
                              ),
                            if (showTop10)
                              SliverToBoxAdapter(
                                child: isWide
                                    ? TvExpandableMovieRow(
                                        title: 'Top 10 dzisiaj w PureVideo',
                                        items: [
                                          for (var i = 0;
                                              i < top10Movies.length;
                                              i++)
                                            TvExpandableRowItem(
                                              movie: top10Movies[i],
                                              topRank: i + 1,
                                              bottomBadge: 'Nowy sezon',
                                            ),
                                        ],
                                      )
                                    : _buildHorizontalRow(
                                        context,
                                        title: 'Top 10 dzisiaj w PureVideo',
                                        movies: top10Movies,
                                        showRank: true,
                                        badgeText: 'Nowy sezon',
                                      ),
                              ),
                            for (final entry in grouped.entries)
                              if (entry.value.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: isWide
                                      ? TvExpandableMovieRow(
                                          title: entry.key,
                                          items: [
                                            for (var i = 0;
                                                i < entry.value.length;
                                                i++)
                                              TvExpandableRowItem(
                                                movie: entry.value[i],
                                                bottomBadge: entry.key
                                                        .toLowerCase()
                                                        .contains('nowe')
                                                    ? 'Ostatnio dodany'
                                                    : (i % 5 == 0
                                                        ? 'Ostatnio dodany'
                                                        : null),
                                              ),
                                          ],
                                        )
                                      : _buildHorizontalRow(
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
                              child: SizedBox(height: 84),
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
                              final randomMovie = pool[
                                  DateTime.now().millisecondsSinceEpoch %
                                      pool.length];
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
      BuildContext context, List<String> allCategories) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PureVideoWordmark(height: 26),
                const Spacer(),
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

  /// New 2025/2026 Netflix TV Hero Card matching Image 2 (rounded wide showcase + pill actions + Filmweb synopsis)
  Widget _buildTvHeroBanner(
    BuildContext context,
    MovieModel movie,
    List<String> allCategories,
    List<MovieModel> pool,
  ) {
    final isSeries = _isSeriesMovie(movie);
    final inMyList = _settingsService.isInMyList(movie);
    final rawCat =
        movie.services.isNotEmpty ? movie.services.first.category : null;
    final catTag = (rawCat != null && rawCat.trim().isNotEmpty)
        ? _cleanCategoryName(rawCat)
        : (isSeries ? 'Serial' : 'Film');
    final serviceTag = movie.services
        .map((s) => s.service.displayName)
        .toSet()
        .join(' • ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 318,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(34), width: 1.0),
              color: const Color(0xFF111116),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(140),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Wide right-weighted visual backdrop
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.68,
                        heightFactor: 1.0,
                        child: PosterImage(
                          url: movie.imageUrl,
                          headers: movie.imageHeaders,
                          fallbacks: movie.fallbackPosterCandidates,
                          decodeWidth: 960,
                          alignment: const Alignment(0, -0.25),
                          title: movie.title,
                        ),
                      ),
                    ),
                  ),
                  // Subtle ambient blur left bleed so there's no hard seam
                  Positioned.fill(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                      child: Opacity(
                        opacity: 0.25,
                        child: PosterImage(
                          url: movie.imageUrl,
                          headers: movie.imageHeaders,
                          fallbacks: movie.fallbackPosterCandidates,
                          decodeWidth: 320,
                          title: movie.title,
                        ),
                      ),
                    ),
                  ),
                  // Deep cinematic left-to-right + bottom vignette
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: [0.0, 0.36, 0.64, 1.0],
                        colors: [
                          Color(0xFF0E0E13),
                          Color(0xEE0E0E13),
                          Color(0x880E0E13),
                          Color(0x180E0E13),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: [0.0, 0.4, 1.0],
                        colors: [
                          Color(0xAA0E0E13),
                          Color(0x000E0E13),
                          Color(0x000E0E13),
                        ],
                      ),
                    ),
                  ),
                  // Content left column + subtle right badge
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 24, 24),
                    child: ListenableBuilder(
                      listenable: _previewService,
                      builder: (context, _) {
                        final preview = _previewService.getCached(movie);
                        final metaParts = <String>[
                          isSeries ? 'Serial' : 'Film',
                          catTag,
                          if (preview?.year != null) '${preview!.year}',
                          if (serviceTag.isNotEmpty) serviceTag,
                        ];
                        final synopsis = (preview != null &&
                                preview.plot.trim().isNotEmpty)
                            ? preview.plot.trim()
                            : 'Wybrany tytuł polecany na dziś. Wybierz źródło i oglądaj w wysokiej jakości na ekranie telewizora.';

                        return Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: 0.56,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      const PureVideoMark(size: 16),
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
                                      fontSize: 31,
                                      fontWeight: FontWeight.w900,
                                      height: 1.08,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    metaParts.join('  •  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    synopsis,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13.5,
                                      height: 1.38,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      TvFocusable(
                                        autofocus: DeviceUtils.isTv,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        focusScale: 1.04,
                                        onTap: () => context.pushNamed(
                                          'movie_details_plain',
                                          extra: movie,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 22, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.play_arrow_rounded,
                                                  color: Colors.black,
                                                  size: 22),
                                              SizedBox(width: 6),
                                              Text(
                                                'Odtwórz',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      TvFocusable(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        focusScale: 1.04,
                                        onTap: () => context.pushNamed(
                                          'movie_details_plain',
                                          extra: movie,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(36),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.info_outline_rounded,
                                                  color: Colors.white,
                                                  size: 20),
                                              SizedBox(width: 6),
                                              Text(
                                                'Więcej informacji',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      TvFocusable(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        focusScale: 1.04,
                                        onTap: () =>
                                            _settingsService.toggleMyList(movie),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(30),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                inMyList
                                                    ? Icons.check_rounded
                                                    : Icons.add_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                inMyList
                                                    ? 'Na liście'
                                                    : 'Moja lista',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
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
                            // Bottom-right sleek badge like "Season 2 Coming Soon" in Image 2
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(165),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(30),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department_rounded,
                                      color: _kNetflixRed,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Polecane • $catTag',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Minimal TV sub-controls row: Category Filter + Shuffle Hero
          Row(
            children: [
              _buildFilterChip(
                label: _selectedCategory != null
                    ? 'Kategoria: $_selectedCategory'
                    : 'Wszystkie kategorie',
                selected: _selectedCategory != null,
                hasDropdown: true,
                onTap: () => _showCategoryPicker(context, allCategories),
              ),
              if (_selectedCategory != null) ...[
                const SizedBox(width: 8),
                TvFocusable(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() => _selectedCategory = null),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(24),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, color: Colors.white, size: 15),
                        SizedBox(width: 4),
                        Text(
                          'Wyczyść filtr',
                          style: TextStyle(color: Colors.white, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              TvFocusable(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  if (pool.isNotEmpty) {
                    setState(() => _heroSeed = (_heroSeed + 1) % pool.length);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle_rounded,
                          color: _kNetflixRed, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Inny polecany',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildHeroBanner(BuildContext context, MovieModel movie) {
    final isSeries = _isSeriesMovie(movie);
    final inMyList = _settingsService.isInMyList(movie);
    final rawCat =
        movie.services.isNotEmpty ? movie.services.first.category : null;
    final catTag = (rawCat != null && rawCat.trim().isNotEmpty)
        ? _cleanCategoryName(rawCat)
        : (isSeries ? 'Serial' : 'Film');
    final serviceTag =
        movie.services.map((s) => s.service.displayName).join(' • ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
              GestureDetector(
                onTap: () => context.pushNamed(
                  'movie_details_plain',
                  extra: movie,
                ),
                child: PosterImage(
                  url: movie.imageUrl,
                  headers: movie.imageHeaders,
                  fallbacks: movie.fallbackPosterCandidates,
                  decodeWidth: 640,
                  title: movie.title,
                ),
              ),
              IgnorePointer(
                child: Container(
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
                        const PureVideoMark(size: 16),
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
    );
  }

  Widget _buildContinueWatchingSection(
    BuildContext context, {
    required bool isWide,
  }) {
    return StreamBuilder<List<WatchedMovieModel>>(
      stream: _watchedService.watchedStream,
      builder: (context, snapshot) {
        final watchedList = (snapshot.data ?? _watchedService.getAll())
            .toList()
          ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
        if (watchedList.isEmpty) {
          return const SizedBox.shrink();
        }

        if (isWide) {
          final items = watchedList.map((item) {
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
            final double progress = (watchedSec / denom).clamp(0.06, 0.96);
            final String subtitle = lastEp != null
                ? 'S${lastEp.season.number}:E${lastEp.watchedEpisode.episode.number}'
                : '${(watchedSec ~/ 60) > 0 ? (watchedSec ~/ 60) : 1} min';
            return TvExpandableRowItem(
              movie: movie,
              progress: progress,
              episodeLabel: subtitle,
              subtitleOverride: lastEp != null
                  ? 'Kontynuuj odtwarzanie ($subtitle)'
                  : 'Obejrzano: $subtitle',
            );
          }).toList();

          return TvExpandableMovieRow(
            title: 'Kontynuuj oglądanie',
            items: items,
            onItemLongPress: (rowItem) {
              final found = watchedList.firstWhere(
                (w) =>
                    MergeService.normalizeTitle(w.movie.title) ==
                    MergeService.normalizeTitle(rowItem.movie.title),
                orElse: () => watchedList.first,
              );
              _watchedService.removeMovie(found.movie);
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text(
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                      fallbacks: movie.fallbackPosterCandidates,
                                      title: movie.title,
                                    ),
                                    Container(color: Colors.black26),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
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
          height: 180,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                width: 120,
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

class _CategoryDialogItem extends StatelessWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _CategoryDialogItem({
    required this.label,
    required this.selected,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(10),
        focusScale: 1.02,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? _kNetflixRed.withAlpha(42)
                : Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: _kNetflixRed, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
