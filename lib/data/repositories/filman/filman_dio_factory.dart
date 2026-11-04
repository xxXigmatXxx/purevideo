import 'package:purevideo/core/utils/safe_cookie.dart';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:purevideo/core/error/exceptions.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/di/injection_container.dart';

class FilmanDioFactory {
  static Future<List<Cookie>?>? _cfInFlight;
  static DateTime _cfCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static Dio getDio([AccountModel? account]) {
    final dio = Dio(
      BaseOptions(
        baseUrl: SupportedService.filman.baseUrl,
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
          if (account != null)
            'Cookie': account.cookies
                .map((cookie) => '${cookie.name}=${cookie.value}')
                .join('; '),
        },
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Cloudflare clearance is bound to the User-Agent: always send the
          // same UA the WebView used to solve the challenge.
          options.headers['User-Agent'] = WebViewService.cleanUserAgent;
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.data.toString().contains('Just a moment...')) {
            // Never loop: one Cloudflare retry per request, and a cooldown
            // after a failed attempt so the UI does not hang or spam dialogs.
            if (response.requestOptions.extra['cf_retried'] == true ||
                DateTime.now().isBefore(_cfCooldownUntil)) {
              throw ServiceExeption(SupportedService.filman,
                  'Cloudflare blokuje dostep (sprobuj ponownie za chwile)');
            }
            final List<Cookie> initialCookies =
                (response.requestOptions.headers['Cookie'] as String?)
                        ?.split(';')
                        .map((h) => h.trim()).where((h) => h.contains('=') && !h.startsWith('=')).map((h) => RawCookie(h.substring(0, h.indexOf('=')).trim(), h.substring(h.indexOf('=') + 1).trim()))
                        .where((cookie) => cookie.name != 'cf_clearance')
                        .toList() ??
                    [];

            _cfInFlight ??= getIt<WebViewService>()
                .getCfCookies(
                  response.requestOptions.uri.toString(),
                  initialCookies: initialCookies,
                )
                .whenComplete(() => _cfInFlight = null);
            final cookies = await _cfInFlight;
            if (cookies == null ||
                !cookies.any((c) => c.name == 'cf_clearance')) {
              _cfCooldownUntil = DateTime.now().add(const Duration(seconds: 60));
              throw ServiceExeption(SupportedService.filman,
                  'Nie udalo sie przejsc weryfikacji Cloudflare');
            }
            final requestOptions = response.requestOptions;
            requestOptions.extra['cf_retried'] = true;
            requestOptions.headers['User-Agent'] = WebViewService.cleanUserAgent;
            requestOptions.headers['Cookie'] = cookies
                ?.map((cookie) => '${cookie.name}=${cookie.value}')
                .join('; ');
            final newResponse = await dio.fetch(requestOptions);
            newResponse.headers['set-cookie']?.addAll(
              cookies?.map((cookie) => cookie.toString()).toList() ?? [],
            );

            final cfClearance = cookies
                ?.firstWhereOrNull((cookie) => cookie.name == 'cf_clearance');
            if (cfClearance != null) {
              final authRepository =
                  getIt<Map<SupportedService, AuthRepository>>()[
                      SupportedService.filman];
              final account = authRepository?.getAccount();
              if (account != null) {
                final cookieMap = <String, Cookie>{
                  for (final c in account.cookies) c.name: c,
                  for (final c in (cookies ?? const <Cookie>[])) c.name: c,
                };
                final updatedCookies = cookieMap.values.toList();
                final mergedCookieHeader = updatedCookies
                    .map((cookie) => '${cookie.name}=${cookie.value}')
                    .join('; ');
                dio.options.headers['Cookie'] = mergedCookieHeader;
                requestOptions.headers['Cookie'] = mergedCookieHeader;

                authRepository?.setAccount(AccountModel(
                  service: SupportedService.filman,
                  fields: account.fields,
                  cookies: updatedCookies,
                ));
              }
            }
            return handler.next(newResponse);
          }
          if (response.headers.map['location']?.contains(
                'https://filman.cc/logowanie',
              ) ==
              true) {
            debugPrint(
                'Error while fetching: ${response.requestOptions.uri} with cookies: ${response.requestOptions.headers}');
            throw const UnauthorizedException();
          }
          return handler.next(response);
        },
      ),
    );
    return dio;
  }
}
