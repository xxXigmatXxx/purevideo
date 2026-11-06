import 'package:dio/dio.dart';
import 'package:purevideo/core/error/exceptions.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:html/parser.dart' as html;

class EkinoDioFactory {
  static Dio getDio([AccountModel? account]) {
    final cookieHeader = account != null
        ? account.cookies
            .where((c) =>
                c.name.trim().isNotEmpty &&
                c.value.trim().isNotEmpty &&
                !c.value.startsWith('deleted'))
            .map((cookie) =>
                '${cookie.name.trim()}=${cookie.value.split(';').first.trim()}')
            .join('; ')
        : '';

    return Dio(
      BaseOptions(
        baseUrl: SupportedService.ekino.baseUrl,
        followRedirects: true,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (_) => true,
        headers: {
          'User-Agent': WebViewService.cleanUserAgent,
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        },
      ),
    )..interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            if (response.data.toString().contains('cf-wrapper')) {
              final error =
                  html.parse(response.data).querySelector('.code-label')?.text;
              if (error != null) {
                throw ServiceExeption(
                    SupportedService.ekino, 'Cloudflare error: $error');
              }
            }
            return handler.next(response);
          },
        ),
      );
  }
}
