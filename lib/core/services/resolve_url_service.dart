import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/cupertino.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';

class ResolveUrlService {
  final Dio _dio;
  late final Dio _extDio;
  String serverUrl = 'http://localhost:8080';

  static final Uint8List _aesSbox = _buildAesSbox();

  static Uint8List _buildAesSbox() {
    final sbox = Uint8List(256);
    final p = Uint8List(256);
    final q = Uint8List(256);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      p[i] = x;
      q[x] = i;
      x ^= ((x << 1) ^ ((x & 0x80) != 0 ? 0x11b : 0)) & 0xff;
    }
    sbox[0] = 0x63;
    for (int i = 1; i < 256; i++) {
      final y = p[255 - q[i]];
      int s = y;
      for (int r = 1; r <= 4; r++) {
        s ^= ((y << r) | (y >>> (8 - r))) & 0xff;
      }
      sbox[i] = (s ^ 0x63) & 0xff;
    }
    return sbox;
  }

  static int _xtime(int a) =>
      (((a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0)) & 0xff);

  static Uint8List _aes256ExpandKey(Uint8List key) {
    final w = Uint8List(240);
    w.setRange(0, 32, key);
    int rcon = 1;
    for (int i = 8; i < 60; i++) {
      int t0 = w[(i - 1) * 4];
      int t1 = w[(i - 1) * 4 + 1];
      int t2 = w[(i - 1) * 4 + 2];
      int t3 = w[(i - 1) * 4 + 3];
      if (i % 8 == 0) {
        final tmp = t0;
        t0 = _aesSbox[t1] ^ rcon;
        t1 = _aesSbox[t2];
        t2 = _aesSbox[t3];
        t3 = _aesSbox[tmp];
        rcon = _xtime(rcon);
      } else if (i % 8 == 4) {
        t0 = _aesSbox[t0];
        t1 = _aesSbox[t1];
        t2 = _aesSbox[t2];
        t3 = _aesSbox[t3];
      }
      w[i * 4] = w[(i - 8) * 4] ^ t0;
      w[i * 4 + 1] = w[(i - 8) * 4 + 1] ^ t1;
      w[i * 4 + 2] = w[(i - 8) * 4 + 2] ^ t2;
      w[i * 4 + 3] = w[(i - 8) * 4 + 3] ^ t3;
    }
    return w;
  }

  static Uint8List _aes256EncryptBlock(Uint8List block, Uint8List w) {
    final s = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      s[i] = block[i] ^ w[i];
    }
    final t = Uint8List(16);
    for (int round = 1; round <= 14; round++) {
      t[0] = _aesSbox[s[0]];
      t[1] = _aesSbox[s[5]];
      t[2] = _aesSbox[s[10]];
      t[3] = _aesSbox[s[15]];
      t[4] = _aesSbox[s[4]];
      t[5] = _aesSbox[s[9]];
      t[6] = _aesSbox[s[14]];
      t[7] = _aesSbox[s[3]];
      t[8] = _aesSbox[s[8]];
      t[9] = _aesSbox[s[13]];
      t[10] = _aesSbox[s[2]];
      t[11] = _aesSbox[s[7]];
      t[12] = _aesSbox[s[12]];
      t[13] = _aesSbox[s[1]];
      t[14] = _aesSbox[s[6]];
      t[15] = _aesSbox[s[11]];
      if (round < 14) {
        for (int c = 0; c < 4; c++) {
          final idx = c * 4;
          final a0 = t[idx];
          final a1 = t[idx + 1];
          final a2 = t[idx + 2];
          final a3 = t[idx + 3];
          final xorAll = a0 ^ a1 ^ a2 ^ a3;
          t[idx] ^= xorAll ^ _xtime(a0 ^ a1);
          t[idx + 1] ^= xorAll ^ _xtime(a1 ^ a2);
          t[idx + 2] ^= xorAll ^ _xtime(a2 ^ a3);
          t[idx + 3] ^= xorAll ^ _xtime(a3 ^ a0);
        }
      }
      final ro = round * 16;
      for (int i = 0; i < 16; i++) {
        s[i] = t[i] ^ w[ro + i];
      }
    }
    return s;
  }

  static Uint8List _aes256GcmDecryptPayload(
      Uint8List key32, Uint8List iv12, Uint8List rawPayloadWithTag) {
    if (rawPayloadWithTag.length <= 16) return Uint8List(0);
    final ctLen = rawPayloadWithTag.length - 16;
    final w = _aes256ExpandKey(key32);
    final out = Uint8List(ctLen);
    final counterBlock = Uint8List(16);
    counterBlock.setRange(0, 12, iv12);
    for (int offset = 0, blockIdx = 0;
        offset < ctLen;
        offset += 16, blockIdx++) {
      final ctr = 2 + blockIdx;
      counterBlock[12] = (ctr >>> 24) & 0xff;
      counterBlock[13] = (ctr >>> 16) & 0xff;
      counterBlock[14] = (ctr >>> 8) & 0xff;
      counterBlock[15] = ctr & 0xff;
      final ks = _aes256EncryptBlock(counterBlock, w);
      final chunk = min(16, ctLen - offset);
      for (int i = 0; i < chunk; i++) {
        out[offset + i] = rawPayloadWithTag[offset + i] ^ ks[i];
      }
    }
    return out;
  }

  static Uint8List _b64UrlDecode(String s) {
    var norm = s.trim().replaceAll('-', '+').replaceAll('_', '/');
    final pad = (4 - norm.length % 4) % 4;
    norm += '=' * pad;
    return Uint8List.fromList(base64Decode(norm));
  }

  static int _u32(int x) => x & 0xFFFFFFFF;
  static int _rotl32(int x, int k) =>
      (((x & 0xFFFFFFFF) << k) | ((x & 0xFFFFFFFF) >>> (32 - k))) & 0xFFFFFFFF;
  static int _imul32(int a, int b) =>
      ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF;

  static void _byseYe(List<int> t) {
    t[0] = _u32(t[0] + t[1]);
    t[3] = _rotl32(t[3] ^ t[0], 16);
    t[2] = _u32(t[2] + t[3]);
    t[1] = _rotl32(t[1] ^ t[2], 12);
    t[0] = _u32(t[0] + t[1]);
    t[3] = _rotl32(t[3] ^ t[0], 8);
    t[2] = _u32(t[2] + t[3]);
    t[1] = _rotl32(t[1] ^ t[2], 7);
  }

  static List<int> _byseGr(List<int> bytes) {
    final e = <int>[1779033703, 3144134277, 1013904242, 2773480762];
    for (int i = 0; i < bytes.length; i++) {
      e[0] = _u32(e[0] + (bytes[i] & 0xff));
      e[0] = _rotl32(e[0], 7);
      _byseYe(e);
    }
    for (int i = 0; i < 8; i++) {
      _byseYe(e);
    }
    final r = List<int>.filled(512, 0);
    for (int i = 0; i < 512; i++) {
      _byseYe(e);
      r[i] = _u32(e[0] ^ e[2]);
    }
    for (int i = 0; i < 2; i++) {
      for (int s = 0; s < 512; s++) {
        final a = r[s] & 511;
        int c = _u32(r[s] + r[a]);
        c = _rotl32(c, 13);
        c = _u32(c ^ _imul32(r[(s + 1) & 511], 2654435761));
        r[s] = c;
        e[0] = _u32(e[0] ^ c);
        _byseYe(e);
      }
    }
    final n = List<int>.filled(8, 0);
    for (int i = 0; i < 8; i++) {
      _byseYe(e);
      int s = e[0];
      final a = i * 64;
      for (int c = 0; c < 64; c++) {
        final d = r[a + c];
        s = _u32(s + d);
        s = _rotl32(s, 5);
        s = _u32(s ^ _imul32(d, 2246822519));
      }
      n[i] = _u32(s ^ e[2]);
    }
    return n;
  }

  static int _byseLeadingZeros(List<int> n) {
    int e = 0;
    for (int r = 0; r < n.length; r++) {
      final v = n[r] & 0xFFFFFFFF;
      if (v == 0) {
        e += 32;
      } else {
        return e + (32 - v.bitLength);
      }
    }
    return e;
  }

  static String _solveBysePow(String nonce, int difficulty) {
    if (difficulty <= 0) return '0';
    final prefix = '$nonce:';
    for (int s = 0; s < 500000; s++) {
      final candidate = '$prefix$s';
      final d = _byseGr(candidate.codeUnits);
      if (_byseLeadingZeros(d) >= difficulty) {
        return s.toString();
      }
    }
    return '0';
  }

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

  String? _unpackJsPacker(String html) {
    try {
      final m = RegExp(
        r"""eval\(function\(p,a,c,k,e,[dr]\)\{[\s\S]*?\}\(\s*'((?:\\'|[^'])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:\\'|[^'])*)'\.split\('\|'\)""",
      ).firstMatch(html);
      if (m == null) return null;
      var payload = m.group(1)!.replaceAll(r"\'", "'");
      final radix = int.tryParse(m.group(2)!) ?? 36;
      final count = int.tryParse(m.group(3)!) ?? 0;
      final symtab = m.group(4)!.split('|');
      if (count <= 0 || symtab.isEmpty) return null;

      String encodeBase(int val, int base) {
        const chars =
            '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        if (val < base) {
          return val < 36
              ? chars[val]
              : String.fromCharCode(val + 29);
        }
        return encodeBase(val ~/ base, base) + encodeBase(val % base, base);
      }

      final dict = <String, String>{};
      for (int i = count - 1; i >= 0; i--) {
        final key = encodeBase(i, radix);
        final replacement = (i < symtab.length && symtab[i].isNotEmpty)
            ? symtab[i]
            : key;
        dict[key] = replacement;
      }

      return payload.replaceAllMapped(
        RegExp(r'\b\w+\b'),
        (match) => dict[match.group(0)!] ?? match.group(0)!,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<VideoSource>> _resolveByseInDart(
    HostLink link,
    String currentUrl,
    String origin,
    Map<String, String> baseHeaders,
  ) async {
    try {
      final codeMatch =
          RegExp(r'/(?:e|d)/([a-zA-Z0-9_-]+)').firstMatch(currentUrl);
      if (codeMatch == null) return const [];
      final code = codeMatch.group(1)!;
      final apiHeaders = <String, String>{
        ...baseHeaders,
        'Referer': currentUrl,
        'Content-Type': 'application/json',
        'X-Embed-Origin': 'play.ekino.link',
        'X-Embed-Referer': 'https://play.ekino.link/',
        'X-Embed-Parent': 'https://play.ekino.link/',
      };

      String? captchaToken;
      try {
        final capResp = await _extDio.post<String>(
          '$origin/api/videos/$code/embed/captcha',
          data: '{}',
          options: Options(headers: apiHeaders),
        );
        if (capResp.data != null && capResp.data!.isNotEmpty) {
          final capJson = jsonDecode(capResp.data!) as Map<String, dynamic>;
          final nonce = (capJson['pow_nonce'] ?? '').toString();
          final diff = (capJson['pow_difficulty'] as num?)?.toInt() ?? 12;
          final powToken = (capJson['pow_token'] ?? '').toString();
          if (nonce.isNotEmpty && powToken.isNotEmpty) {
            final solution = _solveBysePow(nonce, diff);
            final verResp = await _extDio.post<String>(
              '$origin/api/videos/$code/embed/captcha/verify',
              data: jsonEncode({
                'pow_token': powToken,
                'solution': solution,
              }),
              options: Options(headers: apiHeaders),
            );
            if (verResp.data != null && verResp.data!.isNotEmpty) {
              final verJson =
                  jsonDecode(verResp.data!) as Map<String, dynamic>;
              captchaToken = verJson['token']?.toString();
            }
          }
        }
      } catch (_) {}

      final pbHeaders = <String, String>{
        ...apiHeaders,
        if (captchaToken != null && captchaToken.isNotEmpty)
          'X-Captcha-Token': captchaToken,
      };
      final pbResp = await _extDio.post<String>(
        '$origin/api/videos/$code/embed/playback',
        data: jsonEncode({
          'fingerprint': {
            'token': 'a',
            'viewer_id': 'b',
            'device_id': 'c',
            'confidence': 1,
          }
        }),
        options: Options(headers: pbHeaders),
      );
      if (pbResp.data == null || pbResp.data!.isEmpty) return const [];
      final pbRoot = jsonDecode(pbResp.data!) as Map<String, dynamic>;
      final pb = pbRoot['playback'];
      if (pb is! Map<String, dynamic>) return const [];

      final version = int.tryParse((pb['version'] ?? '1').toString()) ?? 1;
      final keyParts = pb['key_parts'];
      if (keyParts is! List || keyParts.length < 30) return const [];
      final p1 = _b64UrlDecode(keyParts[version - 1].toString());
      final p2 = _b64UrlDecode(keyParts[31 - version - 1].toString());
      final key32 = Uint8List(p1.length + p2.length);
      key32.setRange(0, p1.length, p1);
      key32.setRange(p1.length, key32.length, p2);
      if (key32.length != 32) return const [];

      final iv12 = _b64UrlDecode((pb['iv'] ?? '').toString());
      final rawPayload = _b64UrlDecode((pb['payload'] ?? '').toString());
      final decryptedBytes = _aes256GcmDecryptPayload(key32, iv12, rawPayload);
      if (decryptedBytes.isEmpty) return const [];

      final decryptedJson = jsonDecode(
        utf8.decode(decryptedBytes, allowMalformed: true),
      ) as Map<String, dynamic>;
      final sources = decryptedJson['sources'];
      if (sources is! List || sources.isEmpty) return const [];

      final out = <VideoSource>[];
      for (final s in sources) {
        if (s is Map) {
          final sUrl = (s['url'] ?? '').toString().trim();
          if (sUrl.startsWith('http')) {
            final label = (s['label'] ?? link.quality).toString().trim();
            out.add(VideoSource(
              url: sUrl,
              lang: link.lang,
              quality: label.isEmpty ? 'HD' : label,
              host: label.isEmpty ? 'Byse' : 'Byse ($label)',
              headers: {
                'User-Agent': baseHeaders['User-Agent']!,
                'Referer': '$origin/',
                'Origin': origin,
              },
            ));
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('Byse decrypt error: $e');
      return const [];
    }
  }

  Future<List<VideoSource>> _resolveDirectInDart(
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

      if (html.isEmpty) return const [];
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
          final vnHeaders = <String, String>{
            ...hdrs,
            'Referer': currentUrl,
          };
          try {
            final masterResp = await _extDio.get<String>(
              fullUrl,
              options: Options(headers: vnHeaders),
            );
            final masterBody = masterResp.data ?? '';
            if (masterBody.contains('#EXT-X-STREAM-INF')) {
              var plAudio = 'a1';
              final lines = masterBody.split(RegExp(r'\r?\n'));
              for (final line in lines) {
                if (line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO') &&
                    (line.toLowerCase().contains('language="pl"') ||
                        line.toLowerCase().contains('name="polski"'))) {
                  final am = RegExp(r'index-(a\d+)\.m3u8').firstMatch(line);
                  if (am != null) {
                    plAudio = am.group(1)!;
                    break;
                  }
                }
              }
              final variants = <MapEntry<int, VideoSource>>[];
              for (int i = 0; i < lines.length; i++) {
                final line = lines[i].trim();
                if (line.startsWith('#EXT-X-STREAM-INF')) {
                  final resMatch =
                      RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
                  final width = resMatch != null
                      ? (int.tryParse(resMatch.group(1)!) ?? 0)
                      : 0;
                  final height = resMatch != null
                      ? (int.tryParse(resMatch.group(2)!) ?? 0)
                      : 0;
                  final qual = (width >= 1900 || height >= 1000)
                      ? '1080p'
                      : ((width >= 1200 || height >= 700)
                          ? '720p'
                          : (link.quality.isNotEmpty ? link.quality : 'HD'));
                  if (i + 1 < lines.length) {
                    var subPath = lines[i + 1].trim();
                    if (subPath.isNotEmpty && !subPath.startsWith('#')) {
                      subPath = subPath.replaceAllMapped(
                        RegExp(r'index-v(\d+)-a\d+\.m3u8'),
                        (m) => 'index-v${m.group(1)}-$plAudio.m3u8',
                      );
                      final subUrl = subPath.startsWith('http')
                          ? subPath
                          : '$origin$subPath';
                      variants.add(MapEntry(
                        width,
                        VideoSource(
                          url: subUrl,
                          lang: link.lang,
                          quality: qual,
                          host: 'Vidneo ($qual)',
                          headers: vnHeaders,
                        ),
                      ));
                    }
                  }
                }
              }
              if (variants.isNotEmpty) {
                variants.sort((a, b) => a.key.compareTo(b.key));
                return variants.map((e) => e.value).toList();
              }
            }
          } catch (_) {}
          return [
            VideoSource(
              url: fullUrl,
              lang: link.lang,
              quality: link.quality,
              host: 'Vidneo',
              headers: vnHeaders,
            ),
          ];
        }
      }

      // 0b. Byse Frontend (mfw09.org, bysekoze.com, byse*, filemoon Byse)
      if (html.contains('Byse Frontend') ||
          html.contains('video-embed-mode') ||
          currentUrl.contains('mfw09.') ||
          currentUrl.contains('byse')) {
        final byseSources =
            await _resolveByseInDart(link, currentUrl, origin, hdrs);
        if (byseSources.isNotEmpty) {
          return byseSources;
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
                  return [
                    VideoSource(
                      url: src,
                      lang: link.lang,
                      quality: link.quality,
                      host: 'VOE',
                      headers: hdrs,
                    )
                  ];
                }
                final dc = decoded['direct_access_url']?.toString();
                if (dc != null && dc.startsWith('http')) {
                  return [
                    VideoSource(
                      url: dc,
                      lang: link.lang,
                      quality: link.quality,
                      host: 'VOE',
                      headers: hdrs,
                    )
                  ];
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
          return [
            VideoSource(
              url: sUrl,
              lang: link.lang,
              quality: link.quality,
              host: 'VOE',
              headers: hdrs,
            )
          ];
        }
      }

      // 3. JS Packer (shvid, vmoly, file1, mixdrop, luluvdo, vtube)
      if (html.contains('eval(function(p,a,c,k,e,')) {
        final unpacked = _unpackJsPacker(html);
        if (unpacked != null && unpacked.isNotEmpty) {
          // MixDrop: MDCore.wurl = "//..."
          final mdMatch = RegExp(
            r'''wurl\s*=\s*["']([^"']+)["']''',
          ).firstMatch(unpacked);
          if (mdMatch != null) {
            var mdUrl = mdMatch.group(1)!.trim();
            if (mdUrl.startsWith('//')) mdUrl = 'https:$mdUrl';
            if (mdUrl.startsWith('http')) {
              return [
                VideoSource(
                  url: mdUrl,
                  lang: link.lang,
                  quality: link.quality,
                  host: 'MixDrop',
                  headers: hdrs,
                )
              ];
            }
          }
          // Generic HLS/MP4 in unpacked JS
          final fileMatch = RegExp(
            r'''(?:file|src)\s*:\s*["'](https?://[^"']+\.(?:m3u8|mp4)[^"']*)["']''',
            caseSensitive: false,
          ).firstMatch(unpacked);
          if (fileMatch != null) {
            final fUrl = fileMatch.group(1)!;
            final hName = parsedUri?.host
                    .replaceFirst('www.', '')
                    .split('.')
                    .first
                    .toUpperCase() ??
                'STREAM';
            return [
              VideoSource(
                url: fUrl,
                lang: link.lang,
                quality: link.quality,
                host: hName,
                headers: hdrs,
              )
            ];
          }
        }
      }

      // 4. DoodStream (dood, d000d, myvidplay)
      if (html.contains('/pass_md5/')) {
        final passMatch =
            RegExp(r'''['"](/pass_md5/[^'"]+)['"]''').firstMatch(html);
        if (passMatch != null) {
          final passPath = passMatch.group(1)!;
          final token = passPath.split('/').last;
          final passResp = await _extDio.get<String>(
            '$origin$passPath',
            options: Options(headers: {...hdrs, 'Referer': currentUrl}),
          );
          final baseData = (passResp.data ?? '').trim();
          if (baseData.startsWith('http')) {
            const chars =
                'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
            final rnd = Random();
            final randStr =
                List.generate(10, (_) => chars[rnd.nextInt(chars.length)])
                    .join();
            final expiry = DateTime.now().millisecondsSinceEpoch;
            final doodUrl = '$baseData$randStr?token=$token&expiry=$expiry';
            return [
              VideoSource(
                url: doodUrl,
                lang: link.lang,
                quality: link.quality,
                host: 'DoodStream',
                headers: {...hdrs, 'Referer': currentUrl},
              )
            ];
          }
        }
      }

      // 5. Vidoza / Wrzucaj / generic <source src="https://...mp4/m3u8">
      final sourceTagMatch = RegExp(
        r'''(?:<source[^>]+src|file|src)\s*[:=]\s*["'](https?://[^"']+\.(?:mp4|m3u8)[^"']*)["']''',
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
        return [
          VideoSource(
            url: vUrl,
            lang: link.lang,
            quality: link.quality,
            host: hName,
            headers: hdrs,
          )
        ];
      }

      // 6. Streamtape: get_video?id=...
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
            return [
              VideoSource(
                url: stUrl,
                lang: link.lang,
                quality: link.quality,
                host: 'Streamtape',
                headers: hdrs,
              )
            ];
          }
        }
      }
    } catch (_) {}
    return const [];
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

    // 1. Fast pure-Dart direct extraction in parallel (Vidneo, Byse/mfw09, VOE, Shvid, MixDrop, DoodStream, Vidoza, Streamtape)
    final dartFutures =
        unwrappedList.map((u) => _resolveDirectInDart(u, u.url)).toList();
    final dartResults = await Future.wait(dartFutures);

    final nativeSources = <VideoSource>[];
    final remainingUrls = <HostLink>[];
    for (int i = 0; i < unwrappedList.length; i++) {
      if (dartResults[i].isNotEmpty) {
        nativeSources.addAll(dartResults[i]);
      } else {
        remainingUrls.add(unwrappedList[i]);
      }
    }

    // 2. Local Python ResolveURL server for any remaining hosts
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
                .where((s) =>
                    s.url.isNotEmpty &&
                    !s.host.contains('(Web)') &&
                    s.url != remainingUrls.firstWhere(
                      (r) => r.url == s.url,
                      orElse: () => HostLink(url: '', lang: '', quality: ''),
                    ).url)
                .toList();
            nativeSources.addAll(resolved);
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
