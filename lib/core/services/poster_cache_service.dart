import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:purevideo/core/services/webview_service.dart';

class PosterCandidate {
  final String url;
  final Map<String, String>? headers;

  const PosterCandidate({
    required this.url,
    this.headers,
  });
}

class _SlotRequest {
  final Completer<void> completer;
  _SlotRequest(this.completer);
}

class PosterCacheService {
  PosterCacheService._();
  static final PosterCacheService instance = PosterCacheService._();

  static const int _maxConcurrent = 6;
  static const int _maxMemoryEntries = 140;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 9),
    responseType: ResponseType.bytes,
    followRedirects: true,
    maxRedirects: 4,
    validateStatus: (status) => status != null && status >= 200 && status < 400,
  ));

  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Map<String, DateTime> _failedUntil = {};
  final List<_SlotRequest> _waitQueue = [];
  int _activeDownloads = 0;

  Directory? _cacheDir;
  Future<Directory?>? _cacheDirFuture;

  Future<Directory?> _getCacheDir() {
    if (_cacheDir != null) return Future.value(_cacheDir);
    return _cacheDirFuture ??= () async {
      try {
        final tmp = await getTemporaryDirectory();
        final dir = Directory('${tmp.path}/pv_posters_v2');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _cacheDir = dir;
        return dir;
      } catch (_) {
        return null;
      }
    }();
  }

  static String _hashUrl(String url) {
    final digest =
        SHA256Digest().process(Uint8List.fromList(utf8.encode(url)));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool isValidImageBytes(Uint8List bytes) {
    if (bytes.length < 48) return false;
    // Reject obvious HTML / Cloudflare challenge pages
    final head = String.fromCharCodes(
      bytes.take(32).where((b) => b >= 9 && b <= 126),
    ).trimLeft().toLowerCase();
    if (head.startsWith('<') ||
        head.startsWith('just a moment') ||
        head.startsWith('{')) {
      return false;
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // GIF: GIF8
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }
    // WebP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    // AVIF / HEIC ftyp box
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true;
    }
    return false;
  }

  void _putMemory(String key, Uint8List bytes) {
    _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    while (_memoryCache.length > _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  Uint8List? getCachedSync(
    String primaryUrl, {
    List<PosterCandidate> fallbacks = const [],
  }) {
    if (primaryUrl.isNotEmpty) {
      final hit = _memoryCache.remove(primaryUrl);
      if (hit != null) {
        _memoryCache[primaryUrl] = hit;
        return hit;
      }
    }
    for (final fb in fallbacks) {
      if (fb.url.isEmpty) continue;
      final hit = _memoryCache.remove(fb.url);
      if (hit != null) {
        _memoryCache[fb.url] = hit;
        return hit;
      }
    }
    return null;
  }

  Future<void> _acquireSlot() async {
    if (_activeDownloads < _maxConcurrent) {
      _activeDownloads++;
      return;
    }
    final req = _SlotRequest(Completer<void>());
    // LIFO insert so newly visible cards are prioritized over stale offscreen ones
    _waitQueue.add(req);
    await req.completer.future;
  }

  void _releaseSlot() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeLast();
      if (!next.completer.isCompleted) {
        next.completer.complete();
      }
    } else if (_activeDownloads > 0) {
      _activeDownloads--;
    }
  }

  Future<Uint8List?> _fetchSingleCandidate(PosterCandidate candidate) async {
    final url = candidate.url.trim();
    if (url.isEmpty || !url.startsWith('http')) return null;

    final mem = _memoryCache[url];
    if (mem != null) return mem;

    final failUntil = _failedUntil[url];
    if (failUntil != null && DateTime.now().isBefore(failUntil)) {
      return null;
    }

    final dir = await _getCacheDir();
    File? cacheFile;
    if (dir != null) {
      cacheFile = File('${dir.path}/${_hashUrl(url)}.bin');
      try {
        if (await cacheFile.exists()) {
          final diskBytes = await cacheFile.readAsBytes();
          if (isValidImageBytes(diskBytes)) {
            _putMemory(url, diskBytes);
            return diskBytes;
          } else {
            await cacheFile.delete().catchError((_) => cacheFile!);
          }
        }
      } catch (_) {}
    }

    await _acquireSlot();
    try {
      // Re-check memory cache after waiting in queue
      final memAfterWait = _memoryCache[url];
      if (memAfterWait != null) return memAfterWait;

      final reqHeaders = <String, String>{
        'User-Agent': WebViewService.cleanUserAgent,
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      };
      if (candidate.headers != null) {
        candidate.headers!.forEach((k, v) {
          if (v.trim().isNotEmpty) {
            if (k.toLowerCase() == 'user-agent') {
              reqHeaders['User-Agent'] = WebViewService.cleanUserAgent;
            } else {
              reqHeaders[k] = v;
            }
          }
        });
      }

      final resp = await _dio.get<List<int>>(
        url,
        options: Options(headers: reqHeaders),
      );
      final raw = resp.data;
      if (raw == null || raw.isEmpty) {
        _failedUntil[url] = DateTime.now().add(const Duration(seconds: 60));
        return null;
      }
      final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
      if (!isValidImageBytes(bytes)) {
        _failedUntil[url] = DateTime.now().add(const Duration(seconds: 90));
        return null;
      }

      _failedUntil.remove(url);
      _putMemory(url, bytes);
      if (cacheFile != null) {
        unawaited(cacheFile.writeAsBytes(bytes, flush: false).catchError((_) => cacheFile!));
      }
      return bytes;
    } catch (e) {
      debugPrint('Poster fetch failed ($url): $e');
      _failedUntil[url] = DateTime.now().add(const Duration(seconds: 60));
      return null;
    } finally {
      _releaseSlot();
    }
  }

  List<PosterCandidate> _expandCandidates(
    String primaryUrl,
    Map<String, String>? primaryHeaders,
    List<PosterCandidate> fallbacks,
  ) {
    final out = <PosterCandidate>[];
    final seen = <String>{};

    void addCandidate(String u, Map<String, String>? h) {
      final clean = u.trim();
      if (clean.isEmpty || !clean.startsWith('http')) return;
      if (seen.add(clean)) {
        out.add(PosterCandidate(url: clean, headers: h));
      }
      if (clean.contains('ekino.ws/static/normal/')) {
        final thumb = clean.replaceFirst('/static/normal/', '/static/thumb/');
        if (seen.add(thumb)) {
          out.add(PosterCandidate(url: thumb, headers: h));
        }
      }
    }

    addCandidate(primaryUrl, primaryHeaders);
    for (final fb in fallbacks) {
      addCandidate(fb.url, fb.headers);
    }
    return out;
  }

  Future<Uint8List?> loadPoster(
    String primaryUrl, {
    Map<String, String>? headers,
    List<PosterCandidate> fallbacks = const [],
  }) {
    final syncHit = getCachedSync(primaryUrl, fallbacks: fallbacks);
    if (syncHit != null) return Future.value(syncHit);

    final candidates = _expandCandidates(primaryUrl, headers, fallbacks);
    if (candidates.isEmpty) return Future.value(null);

    final key = candidates.first.url;
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = () async {
      try {
        for (final c in candidates) {
          final bytes = await _fetchSingleCandidate(c);
          if (bytes != null) {
            if (c.url != key) {
              _putMemory(key, bytes);
            }
            return bytes;
          }
        }
        return null;
      } finally {
        _inFlight.remove(key);
      }
    }();

    _inFlight[key] = future;
    return future;
  }
}
