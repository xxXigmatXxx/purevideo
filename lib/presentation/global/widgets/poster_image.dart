import 'package:fast_cached_network_image/fast_cached_network_image.dart';
import 'package:flutter/material.dart';

class PosterImage extends StatelessWidget {
  final String url;
  final Map<String, String>? headers;
  final String? title;
  final BoxFit fit;
  final Alignment alignment;

  const PosterImage({
    super.key,
    required this.url,
    this.headers,
    this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('//')) {
      u = 'https:$u';
    }
    if (u.startsWith('http://image.tmdb.org') ||
        u.startsWith('http://ekino.ws') ||
        u.startsWith('http://www.obejrzyj.to') ||
        u.startsWith('http://obejrzyj.to') ||
        u.startsWith('http://filman.cc')) {
      u = u.replaceFirst('http://', 'https://');
    }
    if (u.contains('image.tmdb.org/t/p/original/')) {
      u = u.replaceFirst('image.tmdb.org/t/p/original/', 'image.tmdb.org/t/p/w500/');
    }
    return u;
  }

  Widget _buildFallback() {
    final t = (title ?? '').trim();
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
    final cleanUrl = normalizeUrl(url);
    if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) {
      return _buildFallback();
    }

    final Map<String, String>? cleanHeaders =
        (headers != null && headers!.isNotEmpty) ? headers : null;

    return FastCachedImage(
      url: cleanUrl,
      headers: cleanHeaders,
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 160),
      loadingBuilder: (context, progress) => Container(
        color: const Color(0xFF1A1A1A),
      ),
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          cleanUrl,
          headers: cleanHeaders,
          fit: fit,
          alignment: alignment,
          errorBuilder: (_, __, ___) => _buildFallback(),
        );
      },
    );
  }
}
