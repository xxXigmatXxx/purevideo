import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purevideo/core/utils/tv_nav_controller.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/merg_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/core/utils/device_utils.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/purevideo_logo.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';
import 'package:purevideo/presentation/search/bloc/search_block.dart';
import 'package:purevideo/presentation/search/bloc/search_event.dart';
import 'package:purevideo/presentation/search/bloc/search_state.dart';

const Color _kNetflixRed = kPureVideoRed;

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = DeviceUtils.isWideLayout(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0D),
      appBar: isWide
          ? null
          : AppBar(title: const Text('Szukaj'), centerTitle: true),
      body: BlocProvider(
        create: (context) => SearchBloc(),
        child: const SearchScreenContent(),
      ),
    );
  }
}

class SearchMovieTile extends StatelessWidget {
  final MovieModel movie;

  const SearchMovieTile({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
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
            const Positioned(
              top: 6,
              left: 6,
              child: PureVideoPosterBadge(size: 12),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Text(
                  movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
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

class SearchScreenContent extends StatefulWidget {
  const SearchScreenContent({super.key});

  @override
  State<SearchScreenContent> createState() => _SearchScreenContentState();
}

class _SearchScreenContentState extends State<SearchScreenContent> {
  final TextEditingController _searchController = TextEditingController();
  final TvNavController _tvNav = TvNavController.instance;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tvNav.searchInputNode.onKeyEvent = _onSearchInputKey;
  }

  KeyEventResult _onSearchInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!DeviceUtils.isWideLayout(context)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _tvNav.focusActiveTopNav(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final sel = _searchController.selection;
      if (_searchController.text.isEmpty ||
          (sel.isValid && sel.extentOffset >= _searchController.text.length)) {
        if (_tvNav.searchButtonNode.canRequestFocus) {
          _tvNav.searchButtonNode.requestFocus();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _tvNav.searchInputNode.onKeyEvent = null;
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      context.read<SearchBloc>().add(SearchRequested(query));
    }
  }

  void _onSearchChanged(String query) {
    setState(() {});
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      context.read<SearchBloc>().add(const SearchCleared());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && query.trim().length >= 2) {
        context.read<SearchBloc>().add(SearchRequested(query.trim()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggested = getIt<MergeService>().getMovies.isNotEmpty
        ? getIt<MergeService>().getMovies
        : getIt<SettingsService>().getCachedHomeMovies();
    final isWide = DeviceUtils.isWideLayout(context);
    final width = MediaQuery.sizeOf(context).width;
    final int crossAxisCount =
        width > 1100 ? 6 : (width > 760 ? 5 : (width > 560 ? 4 : 3));

    return ListView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 28 : 16,
        isWide ? 14 : 16,
        isWide ? 28 : 16,
        28,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: TextField(
                  focusNode: _tvNav.searchInputNode,
                  controller: _searchController,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _submitSearch(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Szukaj filmów i seriali...',
                    hintStyle:
                        const TextStyle(color: Colors.white54, fontSize: 14),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.white70,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            TvFocusable(
              focusNode: _tvNav.searchButtonNode,
              borderRadius: BorderRadius.circular(12),
              focusScale: 1.04,
              onTap: _submitSearch,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _kNetflixRed,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Szukaj',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        BlocBuilder<SearchBloc, SearchState>(
          builder: (context, state) {
            if (state is SearchInitial) {
              if (suggested.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Wpisz tytuł, aby wyszukać filmy i seriale z dostępnymi linkami',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Polecane i popularne w PureVideo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 0.67,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: suggested.take(24).length,
                    itemBuilder: (context, index) {
                      return SearchMovieTile(movie: suggested[index]);
                    },
                  ),
                ],
              );
            } else if (state is SearchLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(38),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _kNetflixRed),
                      SizedBox(height: 14),
                      Text(
                        'Wyszukiwanie tytułów z aktywnymi linkami...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            } else if (state is SearchLoaded) {
              if (state.results.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Brak tytułów z aktywnymi linkami dla podanej frazy',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.67,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: state.results.length,
                itemBuilder: (context, index) {
                  return SearchMovieTile(movie: state.results[index]);
                },
              );
            } else if (state is SearchError) {
              return ErrorView(
                message: state.message,
                onRetry: _submitSearch,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
