import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';

class ResolveUrlService {
  final Dio _dio;
  late final Dio _extDio;
  final String serverUrl = 'http://localhost:8080';

  // --- Pure-Dart AES-256-CTR (for AES-256-GCM payload decryption in Byse/mfw09) ---
  static const List<int> _aesSbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];

  static const List<int> _aesRcon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
  ];

  static int _xtime(int x) => ((x << 1) ^ (((x >> 7) & 1) * 0x1b)) & 0xff;

  static Uint8List _aes256ExpandKey(Uint8List key) {
    final w = Uint8List(240);
    w.setRange(0, 32, key);
    final temp = Uint8List(4);
    for (int i = 8; i < 60; i++) {
      final prev = (i - 1) * 4;
      temp[0] = w[prev];
      temp[1] = w[prev + 1];
      temp[2] = w[prev + 2];
      temp[3] = w[prev + 3];
      if (i % 8 == 0) {
        final t = temp[0];
        temp[0] = _aesSbox[temp[1]] ^ _aesRcon[i ~/ 8];
        temp[1] = _aesSbox[temp[2]];
        temp[2] = _aesSbox[temp[3]];
        temp[3] = _aesSbox[t];
      } else if (i % 8 == 4) {
        temp[0] = _aesSbox[temp[0]];
        temp[1] = _aesSbox[temp[1]];
        temp[2] = _aesSbox[temp[2]];
        temp[3] = _aesSbox[temp[3]];
      }
      final cur = i * 4;
      final old = (i - 8) * 4;
      w[cur] = w[old] ^ temp[0];
      w[cur + 1] = w[old + 1] ^ temp[1];
      w[cur + 2] = w[old + 2] ^ temp[2];
      w[cur + 3] = w[old + 3] ^ temp[3];
    }
    return w;
  }

  static Uint8List _aes256EncryptBlock(Uint8List input, Uint8List w) {
    final s = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      s[i] = input[i] ^ w[i];
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



  // Register-inlined zero-allocation PoW worker executed inside a background Isolate!
  static String _solveBysePowInIsolate(String nonce, int difficulty) {
    if (difficulty <= 0) return '0';
    final prefixUnits = '$nonce:'.codeUnits;
    int init0 = 1779033703;
    int init1 = 3144134277;
    int init2 = 1013904242;
    int init3 = 2773480762;

    for (int i = 0; i < prefixUnits.length; i++) {
      init0 = (init0 + (prefixUnits[i] & 0xff)) & 0xFFFFFFFF;
      init0 = (((init0 << 7) | (init0 >>> 25))) & 0xFFFFFFFF;
      init0 = (init0 + init1) & 0xFFFFFFFF;
      init3 = (((init3 ^ init0) << 16) | ((init3 ^ init0) >>> 16)) & 0xFFFFFFFF;
      init2 = (init2 + init3) & 0xFFFFFFFF;
      init1 = (((init1 ^ init2) << 12) | ((init1 ^ init2) >>> 20)) & 0xFFFFFFFF;
      init0 = (init0 + init1) & 0xFFFFFFFF;
      init3 = (((init3 ^ init0) << 8) | ((init3 ^ init0) >>> 24)) & 0xFFFFFFFF;
      init2 = (init2 + init3) & 0xFFFFFFFF;
      init1 = (((init1 ^ init2) << 7) | ((init1 ^ init2) >>> 25)) & 0xFFFFFFFF;
    }

    final r = Uint32List(512);
    final digits = Uint8List(12);

    for (int s = 0; s < 220000; s++) {
      int dLen = 0;
      if (s == 0) {
        digits[0] = 48;
        dLen = 1;
      } else {
        int tmp = s;
        while (tmp > 0) {
          digits[dLen++] = 48 + (tmp % 10);
          tmp ~/= 10;
        }
      }

      int e0 = init0;
      int e1 = init1;
      int e2 = init2;
      int e3 = init3;

      for (int i = dLen - 1; i >= 0; i--) {
        e0 = (e0 + digits[i]) & 0xFFFFFFFF;
        e0 = ((e0 << 7) | (e0 >>> 25)) & 0xFFFFFFFF;
        e0 = (e0 + e1) & 0xFFFFFFFF;
        e3 = (((e3 ^ e0) << 16) | ((e3 ^ e0) >>> 16)) & 0xFFFFFFFF;
        e2 = (e2 + e3) & 0xFFFFFFFF;
        e1 = (((e1 ^ e2) << 12) | ((e1 ^ e2) >>> 20)) & 0xFFFFFFFF;
        e0 = (e0 + e1) & 0xFFFFFFFF;
        e3 = (((e3 ^ e0) << 8) | ((e3 ^ e0) >>> 24)) & 0xFFFFFFFF;
        e2 = (e2 + e3) & 0xFFFFFFFF;
        e1 = (((e1 ^ e2) << 7) | ((e1 ^ e2) >>> 25)) & 0xFFFFFFFF;
      }

      for (int i = 0; i < 8; i++) {
        e0 = (e0 + e1) & 0xFFFFFFFF;
        e3 = (((e3 ^ e0) << 16) | ((e3 ^ e0) >>> 16)) & 0xFFFFFFFF;
        e2 = (e2 + e3) & 0xFFFFFFFF;
        e1 = (((e1 ^ e2) << 12) | ((e1 ^ e2) >>> 20)) & 0xFFFFFFFF;
        e0 = (e0 + e1) & 0xFFFFFFFF;
        e3 = (((e3 ^ e0) << 8) | ((e3 ^ e0) >>> 24)) & 0xFFFFFFFF;
        e2 = (e2 + e3) & 0xFFFFFFFF;
        e1 = (((e1 ^ e2) << 7) | ((e1 ^ e2) >>> 25)) & 0xFFFFFFFF;
      }

      for (int i = 0; i < 512; i++) {
        e0 = (e0 + e1) & 0xFFFFFFFF;
        e3 = (((e3 ^ e0) << 16) | ((e3 ^ e0) >>> 16)) & 0xFFFFFFFF;
        e2 = (e2 + e3) & 0xFFFFFFFF;
        e1 = (((e1 ^ e2) << 12) | ((e1 ^ e2) >>> 20)) & 0xFFFFFFFF;
        e0 = (e0 + e1) & 0xFFFFFFFF;
        e3 = (((e3 ^ e0) << 8) | ((e3 ^ e0) >>> 24)) & 0xFFFFFFFF;
        e2 = (e2 + e3) & 0xFFFFFFFF;
        e1 = (((e1 ^ e2) << 7) | ((e1 ^ e2) >>> 25)) & 0xFFFFFFFF;
        r[i] = (e0 ^ e2) & 0xFFFFFFFF;
      }

      for (int pass = 0; pass < 2; pass++) {
        for (int idx = 0; idx < 512; idx++) {
          final a = r[idx] & 511;
          int c = (r[idx] + r[a]) & 0xFFFFFFFF;
          c = ((c << 13) | (c >>> 19)) & 0xFFFFFFFF;
          c = (c ^ ((r[(idx + 1) & 511] * 2654435761) & 0xFFFFFFFF)) & 0xFFFFFFFF;
          r[idx] = c;
          e0 = (e0 ^ c) & 0xFFFFFFFF;
          e0 = (e0 + e1) & 0xFFFFFFFF;
          e3 = (((e3 ^ e0) << 16) | ((e3 ^ e0) >>> 16)) & 0xFFFFFFFF;
          e2 = (e2 + e3) & 0xFFFFFFFF;
          e1 = (((e1 ^ e2) << 12) | ((e1 ^ e2) >>> 20)) & 0xFFFFFFFF;
          e0 = (e0 + e1) & 0xFFFFFFFF;
          e3 = (((e3 ^ e0) << 8) | ((e3 ^ e0) >>> 24)) & 0xFFFFFFFF;
          e2 = (e2 + e3) & 0xFFFFFFFF;
          e1 = (((e1 ^ e2) << 7) | ((e1 ^ e2) >>> 25)) & 0xFFFFFFFF;
        }
      }

      e0 = (e0 + e1) & 0xFFFFFFFF;
      e3 = (((e3 ^ e0) << 16) | ((e3 ^ e0) >>> 16)) & 0xFFFFFFFF;
      e2 = (e2 + e3) & 0xFFFFFFFF;
      e1 = (((e1 ^ e2) << 12) | ((e1 ^ e2) >>> 20)) & 0xFFFFFFFF;
      e0 = (e0 + e1) & 0xFFFFFFFF;
      e3 = (((e3 ^ e0) << 8) | ((e3 ^ e0) >>> 24)) & 0xFFFFFFFF;
      e2 = (e2 + e3) & 0xFFFFFFFF;
      e1 = (((e1 ^ e2) << 7) | ((e1 ^ e2) >>> 25)) & 0xFFFFFFFF;

      int st = e0;
      for (int c = 0; c < 64; c++) {
        final d = r[c];
        st = (st + d) & 0xFFFFFFFF;
        st = ((st << 5) | (st >>> 27)) & 0xFFFFFFFF;
        st = (st ^ ((d * 2246822519) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      }
      final w0 = (st ^ e2) & 0xFFFFFFFF;
      final leadingZeros = w0 == 0 ? 32 : (32 - w0.bitLength);
      if (leadingZeros >= difficulty) {
        return s.toString();
      }
    }
    return '0';
  }

  ResolveUrlService(this._dio) {
    _extDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 7),
      followRedirects: true,
      maxRedirects: 5,
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

  // Safe O(N) linear unpacker with zero regex backtracking
  String? _unpackJsPacker(String html) {
    try {
      final startIdx = html.indexOf('eval(function(p,a,c,k,e,');
      if (startIdx == -1) return null;
      final splitMarker = ".split('|')";
      final splitIdx = html.indexOf(splitMarker, startIdx);
      if (splitIdx == -1 || splitIdx - startIdx > 250000) return null;

      final bodyEnd = html.indexOf("}('", startIdx);
      if (bodyEnd == -1 || bodyEnd >= splitIdx) return null;

      // Scan first single-quoted string starting at bodyEnd + 3
      final pStart = bodyEnd + 3;
      final pBuf = StringBuffer();
      int i = pStart;
      while (i < splitIdx) {
        final ch = html.codeUnitAt(i);
        if (ch == 92 && i + 1 < splitIdx) {
          // backslash
          final next = html.codeUnitAt(i + 1);
          if (next == 39 || next == 92) {
            pBuf.writeCharCode(next);
            i += 2;
            continue;
          }
        } else if (ch == 39) {
          // closing single quote
          i++;
          break;
        }
        pBuf.writeCharCode(ch);
        i++;
      }

      final tail = html.substring(i, splitIdx);
      final tailMatch = RegExp(
        r"""^\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'([^']*)$""",
      ).firstMatch(tail);
      if (tailMatch == null) return null;

      final payload = pBuf.toString();
      final radix = int.tryParse(tailMatch.group(1)!) ?? 36;
      final count = int.tryParse(tailMatch.group(2)!) ?? 0;
      final symtab = tailMatch.group(3)!.split('|');
      if (radix < 2 || count <= 0 || count > 10000 || symtab.isEmpty) {
        return null;
      }

      String encodeBase(int val, int base) {
        const chars =
            '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        if (val < base) {
          return val < 36 ? chars[val] : String.fromCharCode(val + 29);
        }
        return encodeBase(val ~/ base, base) + encodeBase(val % base, base);
      }

      final dict = <String, String>{};
      for (int idx = count - 1; idx >= 0; idx--) {
        final key = encodeBase(idx, radix);
        final replacement =
            (idx < symtab.length && symtab[idx].isNotEmpty) ? symtab[idx] : key;
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
            // Solve PoW on a background isolate so the main UI thread never freezes!
            final solution = await Isolate.run(
              () => _solveBysePowInIsolate(nonce, diff),
            ).timeout(const Duration(seconds: 4), onTimeout: () => '0');

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
      final decryptedBytes = await Isolate.run(
        () => _aes256GcmDecryptPayload(key32, iv12, rawPayload),
      );
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
      HostLink link, String cleanedUrl,
      {bool allowByse = true}) async {
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
      if (allowByse &&
          (html.contains('Byse Frontend') ||
              html.contains('video-embed-mode') ||
              currentUrl.contains('mfw09.') ||
              currentUrl.contains('byse'))) {
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
    final seenUrls = <String>{};
    final unwrappedResults = await Future.wait(urls.map((u) async {
      final raw = u.url.trim();
      if (raw.isEmpty || raw.contains('upzone.cc') || !seenUrls.add(raw)) {
        return null;
      }
      final unwrapped = await _unwrapUrl(raw);
      if (unwrapped.isNotEmpty &&
          !unwrapped.contains('upzone.cc') &&
          !unwrapped.contains('ekino.link') &&
          !unwrapped.contains('play.ekino')) {
        return u.copyWith(url: unwrapped);
      }
      return null;
    }));
    final unwrappedList = unwrappedResults.whereType<HostLink>().toList();
    if (unwrappedList.isEmpty) return [];

    // Limit Byse PoW to at most 1 link per movie so we never spawn multiple PoW workers
    int byseCount = 0;
    final dartFutures = unwrappedList.map((u) {
      final lower = u.url.toLowerCase();
      final isByse = lower.contains('mfw09.') || lower.contains('byse');
      final allowByse = !isByse || (++byseCount <= 1);
      return _resolveDirectInDart(u, u.url, allowByse: allowByse);
    }).toList();

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

    // Only call fallback Python server if pure-Dart resolvers found 0 sources
    if (nativeSources.isEmpty && remainingUrls.isNotEmpty) {
      try {
        final isUp = await _waitForServer();
        if (isUp) {
          final response = await _dio.post(
            '$serverUrl/resolve',
            data: jsonEncode(remainingUrls
                .take(4)
                .map((link) => {
                      'url': link.url,
                      'language': link.lang,
                      'quality': link.quality,
                    })
                .toList()),
            options: Options(
              headers: {'Content-Type': 'application/json'},
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 3),
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
                    s.url !=
                        remainingUrls
                            .firstWhere(
                              (r) => r.url == s.url,
                              orElse: () =>
                                  HostLink(url: '', lang: '', quality: ''),
                            )
                            .url)
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
    for (var i = 0; i < 8; i++) {
      try {
        final r = await _dio.get(
          '$serverUrl/health',
          options: Options(
            connectTimeout: const Duration(milliseconds: 300),
            receiveTimeout: const Duration(milliseconds: 300),
            sendTimeout: const Duration(milliseconds: 300),
            validateStatus: (_) => true,
          ),
        );
        if (r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }
}
