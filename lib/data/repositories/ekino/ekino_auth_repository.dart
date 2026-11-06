import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/rendering.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/ekino/ekino_dio_factory.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/di/injection_container.dart';

class EkinoAuthRepository implements AuthRepository {
  late Dio _dio;
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();
  late StreamSubscription<AuthModel> _authSubscription;

  EkinoAuthRepository([AccountModel? account]) {
    _dio = EkinoDioFactory.getDio(account);
    _loadSavedAccount();
    _authSubscription = _authController.stream.listen(_onAuthChanged);
  }

  List<Cookie> _parseCookiesFromSetCookieHeaders(List<String>? headers) {
    if (headers == null || headers.isEmpty) return [];
    final cookies = <Cookie>[];
    for (final raw in headers) {
      final lower = raw.toLowerCase();
      if (lower.contains('max-age=0') || lower.contains('1970')) continue;
      final firstPart = raw.split(';').first.trim();
      final idx = firstPart.indexOf('=');
      if (idx <= 0) continue;
      final name = firstPart.substring(0, idx).trim();
      final value = firstPart.substring(idx + 1).trim();
      if (name.isEmpty || value.isEmpty || value == 'deleted') continue;
      cookies.add(RawCookie(name, value));
    }
    return cookies;
  }

  Future<void> _loadSavedAccount() async {
    try {
      final accountJson = await SecureStorageService.getServiceData(
        SupportedService.ekino,
        'account',
      );

      if (accountJson != null) {
        _account = AccountModel.fromMap(jsonDecode(accountJson));
        _dio = EkinoDioFactory.getDio(_account);
        _authController.add(
          AuthModel(
            service: SupportedService.ekino,
            success: true,
            account: _account,
          ),
        );
        return;
      }

      final loggedOut = await SecureStorageService.getServiceData(
        SupportedService.ekino,
        'logged_out',
      );
      if (loggedOut != 'true') {
        await signIn({'anonymous': 'true'});
      }
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Ekino: $e');
      _account = null;
      _dio = EkinoDioFactory.getDio(null);
    }
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.ekino) {
      _dio = EkinoDioFactory.getDio(auth.account);
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  String _getEkinoLoginScript(String login, String password) {
    return '''
      (function() {
        function waitForElement(selector, callback) {
          const element = document.querySelector(selector);
          if (element) {
            callback(element);
          } else {
            setTimeout(() => waitForElement(selector, callback), 100);
          }
        }
        waitForElement('.alert.alert-success', function(element) {
          window.flutter_inappwebview.callHandler('messageHandler', JSON.stringify({success: true, cookies: document.cookie}));
        });
        waitForElement('.alert.alert-danger', function(element) {
          window.flutter_inappwebview.callHandler('messageHandler', JSON.stringify({success: false, error: element.textContent.trim()}));
        });
        waitForElement('#login_fr', function(element) {
          document.forms['login_fr'].login.value = '$login';
          document.forms['login_fr'].password.value = '$password';
          document.forms['login_fr'].querySelector("input[type='submit']").click();
        });
      })();
    ''';
  }

  @override
  Future<AuthModel> signIn(
    Map<String, String> fields,
  ) async {
    try {
      await SecureStorageService.deleteServiceData(
        SupportedService.ekino,
        'logged_out',
      );
      if (fields.containsKey('anonymous')) {
        List<Cookie> cookies = [];
        try {
          final response = await _dio.get('/');
          cookies = _parseCookiesFromSetCookieHeaders(
              response.headers['set-cookie']);
        } catch (_) {}

        _account = AccountModel(
          fields: {
            'login': 'Gość',
          },
          cookies: cookies,
          service: SupportedService.ekino,
        );
        await setAccount(_account!);
        return AuthModel(
          service: SupportedService.ekino,
          success: true,
          account: _account,
        );
      }

      final webviewLogin = await getIt<WebViewService>().executeJavaScript(
          '${SupportedService.ekino.baseUrl}/login',
          _getEkinoLoginScript(fields['login']!, fields['password']!));

      try {
        final json = jsonDecode(webviewLogin!);
        if (json['success'] == true && json['cookies'] != null) {
          final cookieList = (json['cookies'] as String).split(';');

          final cookies = cookieList
              .map((h) => h.trim())
              .where((h) => h.contains('=') && !h.startsWith('='))
              .map((h) => RawCookie(
                    h.substring(0, h.indexOf('=')).trim(),
                    h.substring(h.indexOf('=') + 1).trim(),
                  ))
              .where((c) => c.value != 'deleted' && c.value.isNotEmpty)
              .toList();

          _account = AccountModel(
            fields: fields,
            cookies: cookies,
            service: SupportedService.ekino,
          );
          await setAccount(_account!);
          return AuthModel(
            service: SupportedService.ekino,
            success: true,
            account: _account,
          );
        } else {
          final authModel = AuthModel(
            service: SupportedService.ekino,
            success: false,
            error: [json['error'] ?? 'Nieznany błąd logowania $webviewLogin'],
          );
          _authController.add(authModel);
          return authModel;
        }
      } catch (e) {
        final authModel = AuthModel(
          service: SupportedService.ekino,
          success: false,
          error: ['Błąd parsowania odpowiedzi logowania: $e'],
        );
        _authController.add(authModel);
        return authModel;
      }
    } catch (e) {
      final authModel = AuthModel(
        service: SupportedService.ekino,
        success: false,
        error: ['Błąd logowania: $e'],
      );
      _authController.add(authModel);
      return authModel;
    }
  }

  @override
  AccountModel? getAccount() {
    return _account;
  }

  @override
  Future<void> setAccount(AccountModel account) async {
    _account = account;
    _dio = EkinoDioFactory.getDio(_account);

    await SecureStorageService.saveServiceData(
      SupportedService.ekino,
      'account',
      jsonEncode(account.toMap()),
    );

    _authController.add(
      AuthModel(
        service: SupportedService.ekino,
        success: true,
        account: _account,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _dio = EkinoDioFactory.getDio(null);
    await SecureStorageService.saveServiceData(
      SupportedService.ekino,
      'logged_out',
      'true',
    );
    await SecureStorageService.deleteServiceData(
      SupportedService.ekino,
      'account',
    );
    _authController.add(
      AuthModel(
        service: SupportedService.ekino,
        success: false,
        account: null,
      ),
    );
  }

  void dispose() {
    _authSubscription.cancel();
    _authController.close();
  }
}
