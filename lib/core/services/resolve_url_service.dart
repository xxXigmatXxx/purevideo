import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/data/models/link_model.dart';
import 'package:purevideo/data/repositories/video_source_repository.dart';
import 'package:purevideo/di/injection_container.dart';

class ResolveUrlService {
  final Dio _dio;
  String serverUrl = 'http://localhost:8080';

  ResolveUrlService(this._dio);

  Future<List<VideoSource>> resolve(List<HostLink> urls) async {
    debugPrint('Resolving URLs: $urls');

    urls = await Future.wait(urls
        .map((link) async => link.url.contains('play.ekino.link')
            ? link.copyWith(
                url: (await getIt<WebViewService>()
                        .waitForDomElement(link.url, 'iframe'))
                    ?.attributes['src'])
            : link)
        .toList());

    try {
      await _waitForServer();
      final response = await _dio.post(
        '$serverUrl/resolve',
        data: jsonEncode(urls
            .map((link) => {
                  'url': link.url,
                  'language': link.lang,
                  'quality': link.quality,
                })
            .toList()),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      debugPrint(
          'Response from resolver: ${response.statusCode} - ${response.data}');

      return (response.data as List).map((item) {
        return VideoSource(
          url: item['url'] ?? '',
          lang: item['language'] ?? '',
          quality: item['quality'] ?? '',
          host: item['host'] ?? '',
          headers: item['headers'] != null
              ? Map<String, String>.from(item['headers'])
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error resolving URLs: $e');
      return [];
    }
  }

  /// Python resolver is started asynchronously at app launch, so on first use
  /// it may not be listening yet. Poll /health for up to ~20 seconds.
  Future<void> _waitForServer() async {
    for (var i = 0; i < 40; i++) {
      try {
        final r = await _dio.get(
          '$serverUrl/health',
          options: Options(
            receiveTimeout: const Duration(seconds: 2),
            sendTimeout: const Duration(seconds: 2),
            validateStatus: (_) => true,
          ),
        );
        if (r.statusCode == 200) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('Resolver server did not respond on /health');
  }
}
