import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class _ProxiedTarget {
  final String url;
  final Map<String, String> headers;
  final bool isPlaylist;

  const _ProxiedTarget({
    required this.url,
    required this.headers,
    required this.isPlaylist,
  });
}

class CastProxyService {
  HttpServer? _server;
  String? _lanIp;
  int _counter = 0;
  final Map<String, _ProxiedTarget> _targets = <String, _ProxiedTarget>{};
  final HttpClient _httpClient = HttpClient()
    ..badCertificateCallback = ((_, __, ___) => true)
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 20);

  Future<String?> _findLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      String? fallbackPrivate;
      String? fallbackAny;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isWifi = name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('eth') ||
            name.contains('ap') ||
            name.contains('en');
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          final isPrivate = ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              _is172Private(ip);
          if (isWifi && isPrivate) return ip;
          if (isPrivate) fallbackPrivate ??= ip;
          fallbackAny ??= ip;
        }
      }
      return fallbackPrivate ?? fallbackAny;
    } catch (e) {
      debugPrint('[CastProxy] Error discovering LAN IP: $e');
      return null;
    }
  }

  static bool _is172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  Future<void> _ensureStarted() async {
    _lanIp = await _findLanIp();
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    _server!.listen(_handleRequest, onError: (Object err) {
      debugPrint('[CastProxy] Server error: $err');
    });
    debugPrint('[CastProxy] Started on port ${_server!.port}, LAN IP=$_lanIp');
  }

  String _storeTarget(
    String url,
    Map<String, String> headers, {
    bool isPlaylist = false,
  }) {
    if (_targets.length > 4000) {
      final removeCount = _targets.length - 3000;
      final keysToRemove = _targets.keys.take(removeCount).toList();
      for (final k in keysToRemove) {
        _targets.remove(k);
      }
    }
    _counter++;
    final token = 't$_counter';
    _targets[token] = _ProxiedTarget(
      url: url,
      headers: Map<String, String>.from(headers),
      isPlaylist: isPlaylist,
    );
    return token;
  }

  String _baseProxyUrl() {
    final ip = _lanIp ?? '127.0.0.1';
    final port = _server!.port;
    return 'http://$ip:$port';
  }

  Future<String> registerStream({
    required String url,
    Map<String, String>? headers,
  }) async {
    try {
      await _ensureStarted();
      if (_lanIp == null || _server == null) {
        return url;
      }
      final cleanHeaders = <String, String>{};
      if (headers != null) {
        headers.forEach((k, v) {
          if (k.trim().isNotEmpty && v.trim().isNotEmpty) {
            cleanHeaders[k.trim()] = v.trim();
          }
        });
      }
      cleanHeaders.putIfAbsent(
        'User-Agent',
        () =>
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      );

      final isHls = _looksLikeM3u8(url);
      final token = _storeTarget(url, cleanHeaders, isPlaylist: isHls);
      final ext = isHls ? 'index.m3u8' : 'video.mp4';
      return '${_baseProxyUrl()}/p/$token/$ext';
    } catch (e) {
      debugPrint('[CastProxy] Failed to register stream: $e');
      return url;
    }
  }

  static bool _looksLikeM3u8(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return path.contains('.m3u8') || path.contains('/m3u8');
  }

  void _applyCorsHeaders(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', '*');
    res.headers.set('Access-Control-Allow-Private-Network', 'true');
    res.headers.set(
      'Access-Control-Expose-Headers',
      'Content-Length, Content-Range, Accept-Ranges, Content-Type',
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final res = request.response;
    _applyCorsHeaders(res);

    if (request.method.toUpperCase() == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    try {
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != 'p') {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }

      final token = segments[1];
      final target = _targets[token];
      if (target == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final method = request.method.toUpperCase() == 'HEAD' ? 'HEAD' : 'GET';

      final upstreamResult = await _openUpstream(
        target.url,
        method: method,
        headers: target.headers,
        rangeHeader: rangeHeader,
      );

      final upstreamRes = upstreamResult.response;
      final effectiveUri = upstreamResult.effectiveUri;

      final contentType =
          (upstreamRes.headers.value(HttpHeaders.contentTypeHeader) ?? '')
              .toLowerCase();
      final isM3u8 = target.isPlaylist ||
          contentType.contains('mpegurl') ||
          contentType.contains('x-mpegurl') ||
          _looksLikeM3u8(effectiveUri.toString());

      if (isM3u8 && method == 'GET' && upstreamRes.statusCode < 400) {
        final bytes = await upstreamRes.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        final text = utf8.decode(bytes, allowMalformed: true);
        if (text.trimLeft().startsWith('#EXTM3U')) {
          final rewritten = _rewriteM3u8(
            text,
            effectiveUri,
            target.headers,
          );
          final outBytes = utf8.encode(rewritten);
          res.statusCode = HttpStatus.ok;
          res.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/vnd.apple.mpegurl; charset=utf-8',
          );
          res.headers.set(HttpHeaders.contentLengthHeader, outBytes.length);
          res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
          res.add(outBytes);
          await res.close();
          return;
        }
        // Not actually text M3U8 -> send raw bytes
        res.statusCode = upstreamRes.statusCode;
        _copyUpstreamHeaders(upstreamRes, res, overrideLength: bytes.length);
        res.add(bytes);
        await res.close();
        return;
      }

      res.statusCode = upstreamRes.statusCode;
      _copyUpstreamHeaders(upstreamRes, res);
      if (method == 'HEAD') {
        await upstreamRes.drain<void>();
        await res.close();
        return;
      }

      res.bufferOutput = false;
      await res.addStream(upstreamRes);
      await res.close();
    } catch (e) {
      debugPrint('[CastProxy] Request error: $e');
      try {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
      } catch (_) {}
    }
  }

  void _copyUpstreamHeaders(
    HttpClientResponse upstreamRes,
    HttpResponse res, {
    int? overrideLength,
  }) {
    final ct = upstreamRes.headers.value(HttpHeaders.contentTypeHeader);
    if (ct != null && ct.isNotEmpty) {
      res.headers.set(HttpHeaders.contentTypeHeader, ct);
    }
    if (overrideLength != null) {
      res.headers.set(HttpHeaders.contentLengthHeader, overrideLength);
    } else if (upstreamRes.contentLength >= 0) {
      res.headers.set(
        HttpHeaders.contentLengthHeader,
        upstreamRes.contentLength,
      );
    }
    final cr = upstreamRes.headers.value(HttpHeaders.contentRangeHeader);
    if (cr != null && cr.isNotEmpty) {
      res.headers.set(HttpHeaders.contentRangeHeader, cr);
    }
    final ar = upstreamRes.headers.value(HttpHeaders.acceptRangesHeader);
    res.headers.set(
      HttpHeaders.acceptRangesHeader,
      (ar != null && ar.isNotEmpty) ? ar : 'bytes',
    );
  }

  Future<({HttpClientResponse response, Uri effectiveUri})> _openUpstream(
    String rawUrl, {
    required String method,
    required Map<String, String> headers,
    String? rangeHeader,
  }) async {
    var currentUri = Uri.parse(rawUrl);
    for (var hop = 0; hop < 6; hop++) {
      final req = await _httpClient.openUrl(method, currentUri);
      req.followRedirects = false;
      headers.forEach((k, v) {
        if (k.toLowerCase() == 'host') return;
        req.headers.set(k, v);
      });
      if (rangeHeader != null && rangeHeader.isNotEmpty) {
        req.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }

      final resp = await req.close();
      if (resp.isRedirect ||
          resp.statusCode == 301 ||
          resp.statusCode == 302 ||
          resp.statusCode == 303 ||
          resp.statusCode == 307 ||
          resp.statusCode == 308) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (loc != null && loc.isNotEmpty) {
          currentUri = currentUri.resolve(loc);
          continue;
        }
      }
      return (response: resp, effectiveUri: currentUri);
    }
    throw const HttpException('Too many redirects');
  }

  String _rewriteM3u8(
    String content,
    Uri baseUri,
    Map<String, String> headers,
  ) {
    final lines = const LineSplitter().convert(content);
    final out = StringBuffer();
    final baseProxy = _baseProxyUrl();
    bool nextLineIsPlaylist = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        out.writeln();
        continue;
      }

      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-STREAM-INF') ||
            line.startsWith('#EXT-X-I-FRAME-STREAM-INF')) {
          nextLineIsPlaylist = true;
        }
        final rewrittenTag = line.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (match) {
            final origUri = match.group(1)!;
            final resolved = baseUri.resolve(origUri).toString();
            final isSubPlaylist = _looksLikeM3u8(resolved) ||
                line.startsWith('#EXT-X-MEDIA') ||
                line.startsWith('#EXT-X-I-FRAME-STREAM-INF');
            final tok = _storeTarget(
              resolved,
              headers,
              isPlaylist: isSubPlaylist,
            );
            final ext = isSubPlaylist ? 'sub.m3u8' : 'key.bin';
            return 'URI="$baseProxy/p/$tok/$ext"';
          },
        );
        out.writeln(rewrittenTag);
        continue;
      }

      final resolved = baseUri.resolve(line).toString();
      final isSubPlaylist = nextLineIsPlaylist || _looksLikeM3u8(resolved);
      nextLineIsPlaylist = false;
      final tok = _storeTarget(
        resolved,
        headers,
        isPlaylist: isSubPlaylist,
      );
      final ext = isSubPlaylist
          ? 'sub.m3u8'
          : (resolved.toLowerCase().contains('.m4s') ? 'seg.m4s' : 'seg.ts');
      out.writeln('$baseProxy/p/$tok/$ext');
    }

    return out.toString();
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _targets.clear();
  }
}
