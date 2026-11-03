import 'dart:async';
import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/data/models/watched_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
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

  const MovieListItem({
    super.key,
    required this.movie,
    this.bottomBadge,
    this.topRank,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.pushNamed(
        'movie_details_plain',
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
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFF1F1F1F),
                child: const Icon(
                  Icons.movie_creation_outlined,
                  color: _kNetflixRed,
                  size: 36,
                ),
              ),
            ),
            // Top-left PureVideo 'P' watermark
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
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

  @override
  void initState() {
    super.initState();
    _moviesBloc = MoviesBloc();
  }

  bool _isSeriesMovie(MovieModel m) {
    for (final s in m.services) {
      final cat = (s.category ?? '').toLowerCase();
      final url = s.url.toLowerCase();
      if (cat.contains('serial') ||
          url.contains('/s/') ||
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
    return lower[0].toUpperCase() + lower.substring(1);
  }

  List<MovieModel> _applyFilter(List<MovieModel> all) {
    var list = all;
    if (_selectedFilter == _HomeFilter.series) {
      list = list.where(_isSeriesMovie).toList();
    } else if (_selectedFilter == _HomeFilter.movies) {
      list = list.where((m) => !_isSeriesMovie(m)).toList();
    } else if (_selectedFilter == _HomeFilter.myList) {
      return _settingsService.getMyList();
    }
    if (_selectedCategory != null) {
      list = list
          .where((m) => m.services.any(
              (s) => _cleanCategoryName(s.category ?? '') == _selectedCategory))
          .toList();
    }
    return list;
  }

  Map<String, List<MovieModel>> _groupByCategories(List<MovieModel> movies) {
    final map = <String, List<MovieModel>>{};
    for (final movie in movies) {
      String? cat;
      for (final s in movie.services) {
        if (s.category != null && s.category!.trim().isNotEmpty) {
          cat = _cleanCategoryName(s.category!);
          break;
        }
      }
      cat ??= _isSeriesMovie(movie) ? 'Popularne seriale' : 'Popularne filmy';
      final bucket = map.putIfAbsent(cat, () => []);
      if (!bucket.any((m) => m.title == movie.title)) {
        bucket.add(movie);
      }
    }
    return map;
  }

  void _showCategoryPicker(BuildContext context, List<String> categories) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
              if (state.movies.isEmpty) {
                return const Center(
                  child: Text(
                    'Brak dostępnych filmów',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final allCategories =
                  _groupByCategories(state.movies).keys.toList();
              final filteredMovies = _applyFilter(state.movies);
              final grouped = _groupByCategories(
                  filteredMovies.isEmpty ? state.movies : filteredMovies);
              final heroPool =
                  filteredMovies.isNotEmpty ? filteredMovies : state.movies;
              final heroMovie = heroPool[_heroSeed % heroPool.length];

              return SettingsListenable(
                builder: (context, box, _) {
                  if (!_settingsService.isNetflixStyle) {
                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('PureVideo'),
                        actions: [
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
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: state.movies.length,
                          itemBuilder: (context, index) => MovieListItem(
                            movie: state.movies[index],
                          ),
                        ),
                      ),
                    );
                  }
                  final myList = _settingsService.getMyList();
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
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: _buildHeroBanner(context, heroMovie),
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
                            if (heroPool.length >= 3)
                              SliverToBoxAdapter(
                                child: _buildHorizontalRow(
                                  context,
                                  title: 'Top 10 dzisiaj w PureVideo',
                                  movies: heroPool.take(10).toList(),
                                  showRank: true,
                                  badgeText: 'Nowy sezon',
                                ),
                              ),
                            // Category rows
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
                      // Floating "Odtwórz losowo" pill button like on the Netflix screenshot
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: Material(
                          color: Colors.white,
                          elevation: 6,
                          borderRadius: BorderRadius.circular(28),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(28),
                            onTap: () {
                              final randomMovie = state.movies[
                                  DateTime.now().millisecondsSinceEpoch %
                                      state.movies.length];
                              context.pushNamed(
                                'movie_details_plain',
                                extra: randomMovie,
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: Row(
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
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white, size: 26),
                  onPressed: () => context.go('/search'),
                ),
                GestureDetector(
                  onTap: () => context.pushNamed('accounts'),
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(left: 4),
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
                      child: InkWell(
                        onTap: () => setState(() {
                          _selectedFilter = _HomeFilter.all;
                          _selectedCategory = null;
                        }),
                        borderRadius: BorderRadius.circular(20),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
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

  Widget _buildHeroBanner(BuildContext context, MovieModel movie) {
    final isSeries = _isSeriesMovie(movie);
    final inMyList = _settingsService.isInMyList(movie);
    final rawCat = movie.services.first.category;
    final catTag = (rawCat != null && rawCat.trim().isNotEmpty)
        ? _cleanCategoryName(rawCat)
        : (isSeries ? 'Serial' : 'Film');
    final serviceTag = movie.services.map((s) => s.service.displayName).join(' • ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: GestureDetector(
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
                FastCachedImage(
                  url: movie.imageUrl,
                  headers: movie.imageHeaders,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF1A1A1A),
                    child: const Icon(Icons.movie,
                        color: Colors.white24, size: 72),
                  ),
                ),
                // Top and bottom gradient vignette like Netflix mobile card
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Text(
                'Ostatnio oglądane',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              height: 195,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: watchedList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = watchedList[index];
                  final movieModel = MovieModel(
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
                  final int denom = item.movie.isSeries ? 2700 : 5700;
                  final double progress =
                      (watchedSec / denom).clamp(0.08, 0.96);

                  final String subtitle = lastEp != null
                      ? 'S${lastEp.season.number}:E${lastEp.watchedEpisode.episode.number}'
                      : '${(watchedSec ~/ 60) > 0 ? (watchedSec ~/ 60) : 1} min';

                  return SizedBox(
                    width: 126,
                    child: GestureDetector(
                      onTap: () => context.pushNamed(
                        'movie_details_plain',
                        extra: movieModel,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          color: const Color(0xFF181818),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FastCachedImage(
                                      url: item.movie.imageUrl,
                                      headers: item.movie.imageHeaders,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFF222222),
                                        padding: const EdgeInsets.all(8),
                                        alignment: Alignment.center,
                                        child: Text(
                                          item.movie.title,
                                          maxLines: 3,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
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
          height: 170,
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
                width: 114,
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
