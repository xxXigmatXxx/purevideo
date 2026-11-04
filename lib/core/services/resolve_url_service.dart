import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/cupertino.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';

class ResolveUrlService {
  final Dio _dio;
  late final Dio _extDio;
  String serverUrl = 'http://localhost:8080';

  ResolveUrlService(this._dio) {
    _extDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 9),
      followRedirects: true,
      maxRedirects: 6,
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7',
      },
    ));
    (_extDio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }

  String _cleanEmbedUrl(String rawUrl) {
    var u = rawUrl.trim();
    if (u.startsWith('//')) u = 'https:$u';
    if (u.contains('tmp-url.pro/?u=')) {
      try {
        final uri = Uri.parse(u);
        final uParam = uri.queryParameters['u'];
        if (uParam != null && uParam.isNotEmpty) {
          final b64 = uParam.replaceAll('-', '+').replaceAll('_', '/');
          final pad = (4 - b64.length % 4) % 4;
          final raw = base64Decode(b64 + ('=' * pad));
          const key = 'x7k9m2p4q8w1e3r5t6y0u';
          final keyBytes = utf8.encode(key);
          final out = List<int>.generate(
            raw.length,
            (i) => raw[i] ^ keyBytes[i % keyBytes.length],
          );
          final dec = utf8.decode(out, allowMalformed: true).trim();
          if (dec.startsWith('http')) u = dec;
        }
      } catch (_) {}
    }
    return u;
  }

  Future<String> _unwrapUrl(String url) async {
    var u = _cleanEmbedUrl(url);
    if (u.contains('streamlyplayero.') || u.contains('streamlyplayer.')) {
      try {
        final r = await _extDio.get<String>(
          u,
          options: Options(headers: {'Referer': 'https://obejrzyj.to/'}),
        );
        final body = r.data ?? '';
        final m = RegExp(
          r'''<iframe[^>]+src=["']([^"']+)["']''',
          caseSensitive: false,
        ).firstMatch(body);
        if (m != null) {
          var ifr = (m.group(1) ?? '').trim();
          if (ifr.startsWith('//')) ifr = 'https:$ifr';
          if (ifr.startsWith('http')) return ifr;
        }
      } catch (_) {}
    }
    return u;
  }

  String _rot13(String s) {
    final codes = s.codeUnits.map((c) {
      if (c >= 65 && c <= 90) return ((c - 65 + 13) % 26) + 65;
      if (c >= 97 && c <= 122) return ((c - 97 + 13) % 26) + 97;
      return c;
    });
    return String.fromCharCodes(codes);
  }

  Map<String, dynamic>? _voeDecode(String ct) {
    try {
      var txt = _rot13(ct);
      for (final pat in [r'@$', '^^', '~@', '%?', '*~', '!!', '#&']) {
        txt = txt.replaceAll(pat, '_');
      }
      txt = txt.split('_').join('');
      var b64 = txt.replaceAll('-', '+').replaceAll('_', '/');
      var pad = (4 - b64.length % 4) % 4;
      var step3 =
          utf8.decode(base64Decode(b64 + ('=' * pad)), allowMalformed: true);
      var step4 = String.fromCharCodes(step3.codeUnits.map((c) => c - 3));
      var step5 = step4.split('').reversed.join('');
      var b64_2 = step5.replaceAll('-', '+').replaceAll('_', '/');
      var pad2 = (4 - b64_2.length % 4) % 4;
      var finalJson = utf8.decode(base64Decode(b64_2 + ('=' * pad2)),
          allowMalformed: true);
      final parsed = jsonDecode(finalJson);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return null;
  }

  Future<VideoSource?> _resolveDirectInDart(
      HostLink link, String cleanedUrl) async {
    try {
      var currentUrl = cleanedUrl;
      var html = '';
      for (int hop = 0; hop < 4; hop++) {
        final resp = await _extDio.get<String>(
          currentUrl,
          options: Options(headers: {'Referer': currentUrl}),
        );
        html = resp.data ?? '';
        final realUri = resp.realUri.toString();
        if (realUri.isNotEmpty && realUri.startsWith('http')) {
          currentUrl = realUri;
        }
        final jsRedirect = RegExp(
          r'''window\.location\.href\s*=\s*["'](https?://[^"']+)["']''',
          caseSensitive: false,
        ).firstMatch(html);
        if (jsRedirect != null) {
          currentUrl = jsRedirect.group(1)!;
          continue;
        }
        break;
      }

      if (html.isEmpty) return null;
      final parsedUri = Uri.tryParse(currentUrl);
      final origin = parsedUri != null
          ? '${parsedUri.scheme}://${parsedUri.host}'
          : 'https://voe.sx';
      final hdrs = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Referer': '$origin/',
        'Origin': origin,
      };

      // 0. Vidneo.cc: Next.js payload with "/hls/.../master.m3u8"
      if (currentUrl.contains('vidneo.') || html.contains('VIDNEO')) {
        final vnMatch = RegExp(
          r'''\\?"src\\?"\s*:\s*\\?"(/hls/[^"\\]+\.m3u8[^"\\]*)\\?"''',
        ).firstMatch(html);
        if (vnMatch != null) {
          final hlsPath = vnMatch.group(1)!;
          final fullUrl =
              hlsPath.startsWith('http') ? hlsPath : '$origin$hlsPath';
          return VideoSource(
            url: fullUrl,
            lang: link.lang,
            quality: link.quality,
            host: 'Vidneo',
            headers: {
              ...hdrs,
              'Referer': currentUrl,
            },
          );
        }
      }

      // 1. VOE: application/json script block
      final jsonScriptMatches = RegExp(
        r'''<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>''',
        caseSensitive: false,
      ).allMatches(html);
      for (final m in jsonScriptMatches) {
        final body = (m.group(1) ?? '').trim();
        if (body.startsWith('[') && body.endsWith(']')) {
          try {
            final arr = jsonDecode(body);
            if (arr is List && arr.isNotEmpty && arr[0] is String) {
              final decoded = _voeDecode(arr[0] as String);
              if (decoded != null) {
                final src = decoded['source']?.toString();
                if (src != null && src.startsWith('http')) {
                  return VideoSource(
                    url: src,
                    lang: link.lang,
                    quality: link.quality,
                    host: 'VOE',
                    headers: hdrs,
                  );
                }
                final dc = decoded['direct_access_url']?.toString();
                if (dc != null && dc.startsWith('http')) {
                  return VideoSource(
                    url: dc,
                    lang: link.lang,
                    quality: link.quality,
                    host: 'VOE',
                    headers: hdrs,
                  );
                }
              }
            }
          } catch (_) {}
        }
      }

      // 2. VOE: hls / mp4 in HTML
      final hlsMatch = RegExp(
        r'''["'](?:hls|mp4)["']\s*:\s*["']([^"']+)["']''',
      ).firstMatch(html);
      if (hlsMatch != null) {
        var sUrl = hlsMatch.group(1)!;
        if (!sUrl.startsWith('http')) {
          try {
            sUrl = utf8.decode(base64Decode(sUrl), allowMalformed: true);
          } catch (_) {}
        }
        if (sUrl.startsWith('http')) {
          return VideoSource(
            url: sUrl,
            lang: link.lang,
            quality: link.quality,
            host: 'VOE',
            headers: hdrs,
          );
        }
      }

      // 3. Vidoza / generic <source src="https://...mp4/m3u8">
      final sourceTagMatch = RegExp(
        r'''<source[^>]+src=["'](https?://[^"']+\.(?:mp4|m3u8)[^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (sourceTagMatch != null) {
        final vUrl = sourceTagMatch.group(1)!;
        final hName = parsedUri?.host
                .replaceFirst('www.', '')
                .split('.')
                .first
                .toUpperCase() ??
            'DIRECT';
        return VideoSource(
          url: vUrl,
          lang: link.lang,
          quality: link.quality,
          host: hName,
          headers: hdrs,
        );
      }

      // 4. Streamtape: get_video?id=...
      if (currentUrl.contains('streamtape') || html.contains('robotlink')) {
        final stMatch = RegExp(
          r'''getElementById\(["']robotlink["']\)\.innerHTML\s*=\s*["']([^"']+)["']\s*\+\s*\(["']([^"']+)["']\)\.substring\((\d+)\)''',
        ).firstMatch(html);
        if (stMatch != null) {
          final p1 = stMatch.group(1)!;
          final p2 = stMatch.group(2)!;
          final offset = int.tryParse(stMatch.group(3)!) ?? 0;
          var stUrl = '$p1${p2.substring(offset)}';
          if (stUrl.startsWith('//')) {
            stUrl = 'https:$stUrl';
          } else if (stUrl.startsWith('/')) {
            stUrl = 'https://streamtape.com$stUrl';
          }
          if (stUrl.startsWith('http')) {
            return VideoSource(
              url: stUrl,
              lang: link.lang,
              quality: link.quality,
              host: 'Streamtape',
              headers: hdrs,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  VideoSource _buildFallbackSource(HostLink u) {
    final cleaned = _cleanEmbedUrl(u.url);
    String hostName = 'Odtwarzacz (Web)';
    try {
      final uri = Uri.parse(cleaned);
      if (uri.host.isNotEmpty) {
        hostName =
            '${uri.host.replaceFirst('www.', '').split('.').first.toUpperCase()} (Web)';
      }
    } catch (_) {}
    return VideoSource(
      url: cleaned,
      lang: u.lang,
      quality: u.quality,
      host: hostName,
      headers: const {'Referer': 'https://filman.cc/'},
    );
  }

  Future<List<VideoSource>> resolve(List<HostLink> urls) async {
    debugPrint('Resolving URLs: $urls');
    final unwrappedResults = await Future.wait(urls.map((u) async {
      if (u.url.trim().isEmpty || u.url.contains('upzone.cc')) return null;
      final unwrapped = await _unwrapUrl(u.url);
      if (unwrapped.isNotEmpty &&
          !unwrapped.contains('upzone.cc') &&
          !unwrapped.contains('ekino.link')) {
        return u.copyWith(url: unwrapped);
      }
      return null;
    }));
    final unwrappedList = unwrappedResults.whereType<HostLink>().toList();
    if (unwrappedList.isEmpty) return [];

    final fallbackSources = unwrappedList.map(_buildFallbackSource).toList();

    // 1. Fast pure-Dart direct extraction in parallel (instant for VOE, Vidoza, Streamtape)
    final dartFutures =
        unwrappedList.map((u) => _resolveDirectInDart(u, u.url)).toList();
    final dartResults = await Future.wait(dartFutures);

    final nativeSources = <VideoSource>[];
    final remainingUrls = <HostLink>[];
    for (int i = 0; i < unwrappedList.length; i++) {
      if (dartResults[i] != null) {
        nativeSources.add(dartResults[i]!);
      } else {
        remainingUrls.add(unwrappedList[i]);
      }
    }

    // 2. Local Python ResolveURL server for remaining hosts (e.g. Byse/mfw09, Doodstream, Filemoon, Luluvdo)
    if (remainingUrls.isNotEmpty) {
      try {
        final isUp = await _waitForServer();
        if (isUp) {
          final response = await _dio.post(
            '$serverUrl/resolve',
            data: jsonEncode(remainingUrls
                .map((link) => {
                      'url': link.url,
                      'language': link.lang,
                      'quality': link.quality,
                    })
                .toList()),
            options: Options(
              headers: {'Content-Type': 'application/json'},
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 22),
              sendTimeout: const Duration(seconds: 5),
              validateStatus: (status) => status != null && status < 500,
            ),
          );
          if (response.data is List && (response.data as List).isNotEmpty) {
            final resolved = (response.data as List)
                .map((item) => VideoSource(
                      url: item['url'] ?? '',
                      lang: item['language'] ?? '',
                      quality: item['quality'] ?? '',
                      host: item['host'] ?? 'Wideo',
                      headers: item['headers'] != null
                          ? Map<String, String>.from(item['headers'])
                          : null,
                    ))
                .where((s) => s.url.isNotEmpty)
                .toList();
            final pyNative =
                resolved.where((s) => !s.host.contains('(Web)')).toList();
            nativeSources.addAll(pyNative);
          }
        }
      } catch (e) {
        debugPrint('Error resolving URLs in Python: $e');
      }
    }

    return nativeSources.where((s) => !s.host.contains('(Web)')).toList();
  }

  Future<bool> _waitForServer() async {
    for (var i = 0; i < 30; i++) {
      try {
        final r = await _dio.get(
          '$serverUrl/health',
          options: Options(
            connectTimeout: const Duration(milliseconds: 400),
            receiveTimeout: const Duration(milliseconds: 400),
            sendTimeout: const Duration(milliseconds: 400),
            validateStatus: (_) => true,
          ),
        );
        if (r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }
}
