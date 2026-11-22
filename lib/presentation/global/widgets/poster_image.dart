import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:purevideo/core/services/poster_cache_service.dart';

class PosterImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final List<PosterCandidate> fallbacks;
  final String? title;
  final BoxFit fit;
  final Alignment alignment;
  final int decodeWidth;

  const PosterImage({
    super.key,
    required this.url,
    this.headers,
    this.fallbacks = const [],
    this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.decodeWidth = 360,
  });

  static String normalizeUrl(String raw, {bool smallCard = true}) {
    var u = raw.trim();
    if (u.isEmpty || u.startsWith('data:')) return '';
    if (u.startsWith('//')) {
      u = 'https:$u';
    }
    if (u.startsWith('http://')) {
      final lower = u.toLowerCase();
      if (lower.contains('tmdb.org') ||
          lower.contains('ekino.ws') ||
          lower.contains('obejrzyj.to') ||
          lower.contains('filman.cc') ||
          lower.contains('docchi.pl') ||
          lower.contains('bajeczki.org') ||
          lower.contains('myanimelist.net') ||
          lower.contains('anilist.co') ||
          lower.contains('fwcdn.pl')) {
        u = u.replaceFirst('http://', 'https://');
      }
    }
    if (u.contains('image.tmdb.org/t/p/')) {
      if (smallCard) {
        u = u
            .replaceFirst('/t/p/original/', '/t/p/w342/')
            .replaceFirst('/t/p/w1280/', '/t/p/w342/')
            .replaceFirst('/t/p/w780/', '/t/p/w342/')
            .replaceFirst('/t/p/w500/', '/t/p/w342/');
      } else {
        u = u.replaceFirst('/t/p/original/', '/t/p/w500/');
      }
    }
    return u;
  }

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  Uint8List? _bytes;
  bool _failed = false;
  int _loadEpoch = 0;

  bool get _isSmallCard => widget.decodeWidth <= 420;

  List<PosterCandidate> _normalizedFallbacks() {
    return widget.fallbacks
        .map((c) => PosterCandidate(
              url: PosterImage.normalizeUrl(c.url, smallCard: _isSmallCard),
              headers: c.headers,
            ))
        .where((c) => c.url.isNotEmpty)
        .toList();
  }

  void _initLoad() {
    _loadEpoch++;
    final epoch = _loadEpoch;
    final cleanUrl =
        PosterImage.normalizeUrl(widget.url, smallCard: _isSmallCard);
    final fallbacks = _normalizedFallbacks();

    if (cleanUrl.isEmpty && fallbacks.isEmpty) {
      _bytes = null;
      _failed = true;
      return;
    }

    final memHit = PosterCacheService.instance
        .getCachedSync(cleanUrl, fallbacks: fallbacks);
    if (memHit != null) {
      _bytes = memHit;
      _failed = false;
      return;
    }

    _bytes = null;
    _failed = false;

    PosterCacheService.instance
        .loadPoster(
      cleanUrl,
      headers: widget.headers,
      fallbacks: fallbacks,
    )
        .then((data) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        if (data != null) {
          _bytes = data;
          _failed = false;
        } else {
          _failed = true;
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.decodeWidth != widget.decodeWidth ||
        oldWidget.fallbacks.length != widget.fallbacks.length) {
      _initLoad();
    }
  }

  Widget _buildFallback() {
    final t = (widget.title ?? '').trim();
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_creation_outlined,
            color: Color(0xFFE50914),
            size: 28,
          ),
          if (t.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              t,
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return _buildFallback();
    }
    final bytes = _bytes;
    if (bytes == null) {
      return Container(color: const Color(0xFF1A1A1A));
    }
    final provider = ResizeImage.resizeIfNeeded(
      widget.decodeWidth,
      null,
      MemoryImage(bytes),
    );
    return Image(
      image: provider,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _buildFallback(),
    );
  }
}
