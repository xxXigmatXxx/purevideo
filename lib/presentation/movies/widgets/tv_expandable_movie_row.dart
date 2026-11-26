import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/tv_preview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/purevideo_logo.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';

class TvExpandableRowItem {
  final MovieModel movie;
  final int? topRank;
  final String? bottomBadge;
  final double? progress;
  final String? episodeLabel;
  final String? subtitleOverride;

  const TvExpandableRowItem({
    required this.movie,
    this.topRank,
    this.bottomBadge,
    this.progress,
    this.episodeLabel,
    this.subtitleOverride,
  });
}

/// High-FPS Netflix 2025/2026 TV horizontal row:
/// Uses RepaintBoundary per card & row, zero GPU blurs, and constant decodeWidth
/// so scrolling and expanding cards run smoothly at 60 FPS on Android TV.
class TvExpandableMovieRow extends StatefulWidget {
  final String title;
  final List<TvExpandableRowItem> items;
  final bool autofocusFirst;
  final ValueChanged<TvExpandableRowItem>? onItemLongPress;

  const TvExpandableMovieRow({
    super.key,
    required this.title,
    required this.items,
    this.autofocusFirst = false,
    this.onItemLongPress,
  });

  @override
  State<TvExpandableMovieRow> createState() => _TvExpandableMovieRowState();
}

class _TvExpandableMovieRowState extends State<TvExpandableMovieRow> {
  static const double _portraitWidth = 132.0;
  static const double _expandedWidth = 340.0;
  static const double _cardHeight = 192.0;
  static const double _itemSpacing = 12.0;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _rowKey = GlobalKey();
  final TvPreviewService _previewService = getIt<TvPreviewService>();
  int? _focusedIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  String _cleanCategory(String? raw, bool isSeries) {
    final t = (raw ?? '').trim();
    if (t.isEmpty || t.toUpperCase() == 'INNE') {
      return isSeries ? 'Serial' : 'Film';
    }
    final first = t.split('|').first.trim();
    if (first.isEmpty) return isSeries ? 'Serial' : 'Film';
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  void _onCardFocus(int index, bool hasFocus) {
    if (hasFocus) {
      final wasInactive = _focusedIndex == null;
      if (mounted && _focusedIndex != index) {
        setState(() => _focusedIndex = index);
      }
      final item = widget.items[index];
      _previewService.requestPreview(item.movie);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only vertically align row when first entering it (never on Left/Right inside same row)
        if (wasInactive) {
          final rowCtx = _rowKey.currentContext;
          if (rowCtx != null) {
            Scrollable.ensureVisible(
              rowCtx,
              alignment: 0.34,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
            );
          }
        }
        if (_scrollController.hasClients) {
          final targetOffset =
              (index * (_portraitWidth + _itemSpacing)) - 36.0;
          final maxScroll = _scrollController.position.maxScrollExtent;
          final clamped = targetOffset.clamp(0.0, maxScroll);
          if ((clamped - _scrollController.offset).abs() > 14.0) {
            _scrollController.animateTo(
              clamped,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        }
      });
    } else {
      Future.microtask(() {
        if (!mounted) return;
        final primaryFocus = FocusManager.instance.primaryFocus;
        final rowCtx = _rowKey.currentContext;
        if (primaryFocus?.context != null && rowCtx != null) {
          bool insideThisRow = false;
          primaryFocus!.context!.visitAncestorElements((el) {
            if (el == rowCtx) {
              insideThisRow = true;
              return false;
            }
            return true;
          });
          if (insideThisRow) return;
        }
        if (_focusedIndex == index && mounted) {
          setState(() => _focusedIndex = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final focusedItem = (_focusedIndex != null &&
            _focusedIndex! >= 0 &&
            _focusedIndex! < widget.items.length)
        ? widget.items[_focusedIndex!]
        : null;

    return RepaintBoundary(
      child: Container(
        key: _rowKey,
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            SizedBox(
              height: _cardHeight + 4,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                cacheExtent: 500,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: _itemSpacing),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final isFocused = _focusedIndex == index;
                  final isSeries = _isSeriesMovie(item.movie);

                  return TvFocusable(
                    autofocus: widget.autofocusFirst && index == 0,
                    ensureVisibleOnFocus: false,
                    focusScale: 1.0,
                    focusBorderColor: Colors.white,
                    focusBorderWidth: 2.5,
                    borderRadius: BorderRadius.circular(10),
                    onFocusChange: (f) => _onCardFocus(index, f),
                    onTap: () => context.pushNamed(
                      'movie_details_plain',
                      extra: item.movie,
                    ),
                    onLongPress: widget.onItemLongPress != null
                        ? () => widget.onItemLongPress!(item)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: isFocused ? _expandedWidth : _portraitWidth,
                      height: _cardHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PosterImage(
                              url: item.movie.imageUrl,
                              headers: item.movie.imageHeaders,
                              fallbacks: item.movie.fallbackPosterCandidates,
                              decodeWidth: 300,
                              alignment: isFocused
                                  ? const Alignment(0, -0.22)
                                  : Alignment.center,
                              title: item.movie.title,
                            ),
                            if (isFocused)
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: [0.35, 0.72, 1.0],
                                    colors: [
                                      Color(0x00000000),
                                      Color(0xAA000000),
                                      Color(0xEE000000),
                                    ],
                                  ),
                                ),
                              ),
                            const Positioned(
                              top: 8,
                              left: 8,
                              child: PureVideoPosterBadge(size: 13),
                            ),
                            if (item.topRank != null && item.topRank! <= 10)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: const BoxDecoration(
                                    color: kPureVideoRed,
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(8),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'TOP',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1.0,
                                        ),
                                      ),
                                      Text(
                                        '${item.topRank}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          height: 1.05,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (isFocused)
                              Positioned(
                                left: 14,
                                right: 14,
                                bottom: item.progress != null ? 14 : 12,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        const PureVideoMark(size: 12),
                                        const SizedBox(width: 6),
                                        Text(
                                          isSeries ? 'S E R I A L' : 'F I L M',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.8,
                                          ),
                                        ),
                                        if (item.episodeLabel != null &&
                                            item.episodeLabel!.isNotEmpty) ...[
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withAlpha(32),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.episodeLabel!,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.movie.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              if (item.episodeLabel != null &&
                                  item.episodeLabel!.isNotEmpty)
                                Positioned(
                                  left: 6,
                                  bottom: item.progress != null ? 8 : 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(195),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.episodeLabel!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              if (item.bottomBadge != null &&
                                  item.bottomBadge!.isNotEmpty &&
                                  item.progress == null)
                                Positioned(
                                  bottom: 0,
                                  left: 6,
                                  right: 6,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: const BoxDecoration(
                                        color: kPureVideoRed,
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(4),
                                          topRight: Radius.circular(4),
                                        ),
                                      ),
                                      child: Text(
                                        item.bottomBadge!,
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
                            if (item.progress != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: LinearProgressIndicator(
                                  value: item.progress!.clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          kPureVideoRed),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (focusedItem != null)
              ListenableBuilder(
                listenable: _previewService,
                builder: (context, _) {
                  final m = focusedItem.movie;
                  final isSeries = _isSeriesMovie(m);
                  final preview = _previewService.getCached(m);
                  final cat = _cleanCategory(
                      m.services.isNotEmpty
                          ? m.services.first.category
                          : null,
                      isSeries);
                  final sources = m.services
                      .map((s) => s.service.displayName)
                      .toSet()
                      .join(' • ');
                  final metaParts = <String>[
                    if (focusedItem.subtitleOverride != null &&
                        focusedItem.subtitleOverride!.isNotEmpty)
                      focusedItem.subtitleOverride!,
                    cat,
                    if (preview?.year != null) '${preview!.year}',
                    isSeries ? 'Serial' : 'Film',
                    if (sources.isNotEmpty) sources,
                  ];
                  final plotText = (preview != null &&
                          preview.plot.trim().isNotEmpty)
                      ? preview.plot.trim()
                      : 'Naciśnij OK na pilocie, aby zobaczyć źródła, odcinki i rozpocząć odtwarzanie.';

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(28, 10, 48, 2),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 740),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            metaParts.join('  •  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            plotText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.32,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
