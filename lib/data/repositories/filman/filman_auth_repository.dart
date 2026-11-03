import 'package:purevideo/core/utils/safe_cookie.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/filman/filman_dio_factory.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/di/injection_container.dart';

class FilmanAuthRepository implements AuthRepository {
  late Dio _dio;
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();
  late StreamSubscription<AuthModel> _authSubscription;

  FilmanAuthRepository([AccountModel? account]) {
    _loadSavedAccount();
    _authSubscription = _authController.stream.listen(_onAuthChanged);
  }

  Future<void> _loadSavedAccount() async {
    try {
      final accountJson = await SecureStorageService.getServiceData(
        SupportedService.filman,
        'account',
      );
      if (accountJson != null) {
        _account = AccountModel.fromMap(jsonDecode(accountJson));
        _dio = FilmanDioFactory.getDio(_account);
        try {
final res = await _dio.get('/');
final body = res.data?.toString() ?? '';
final loc = res.headers.map['location']?.join(' ') ?? '';
if (res.statusCode == 302 || res.statusCode == 301 || loc.contains('logowanie') || (!body.contains('wyloguj') && !body.contains('Just a moment'))) {
  throw Exception('Sesja Filman wygasła lub była niepełna');
}
_authController.add(
  AuthModel(
    service: SupportedService.filman,
    success: true,
    account: _account,
  ),
);
        } catch (e) {
await SecureStorageService.deleteServiceData(
  SupportedService.filman,
  'account',
);
_account = null;
_dio = FilmanDioFactory.getDio(null);
        }
      } else {
        _dio = FilmanDioFactory.getDio(null);
      }
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Filman.cc: $e');
      _dio = FilmanDioFactory.getDio(null);
    }
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.filman) {
      _dio = FilmanDioFactory.getDio(auth.account);
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  String _getFilmanLoginScript(String login, String password) {
    final safeLogin = login.replaceAll("'", "\'");
    final safePass = password.replaceAll("'", "\'");
    return '''
      (function() {
        try {
const st = document.createElement('style');
st.innerHTML = '#outdated, .outdated-browser, .browser-Gate { display: none !important; }';
if (document.head) document.head.appendChild(st);
        } catch (_) {}

        if (!window.location.href.includes('/logowanie') &&
  (document.querySelector('a[href*="wyloguj"]') || document.querySelector('#item-list'))) {
window.flutter_inappwebview.callHandler('messageHandler', JSON.stringify({success: true, cookies: document.cookie}));
return;
        }

        function setupForm() {
const form = document.querySelector('#signin-form') || document.querySelector('form[action*="logowanie"]');
if (!form) {
  setTimeout(setupForm, 200);
  return;
}
const lInput = form.querySelector('input[name="login"]') || form.login;
const pInput = form.querySelector('input[name="password"]') || form.password;
if (lInput && !lInput.value) lInput.value = '$safeLogin';
if (pInput && !pInput.value) pInput.value = '$safePass';

if (!window._filmanCaptchaTimer) {
  window._filmanCaptchaTimer = setInterval(function() {
    const g = document.querySelector('[name="g-recaptcha-response"]');
    const c = document.querySelector('[name="cf-turnstile-response"]');
    const val = (g && g.value) || (c && c.value) || '';
    if (val && val.length > 20 && !window._filmanSubmittedOnce) {
      window._filmanSubmittedOnce = true;
      clearInterval(window._filmanCaptchaTimer);
      const btn = form.querySelector("button[name='submit']") || form.querySelector("button[type='submit']") || form.querySelector("input[type='submit']");
      if (btn) btn.click();
    }
  }, 400);
}
        }
        setupForm();
      })();
    ''';
  }

  @override
  Future<AuthModel> signIn(Map<String, String> fields) async {
    try {
      final webviewLogin = await getIt<WebViewService>().executeJavaScript(
        '${SupportedService.filman.baseUrl}/logowanie',
        _getFilmanLoginScript(fields['login'] ?? '', fields['password'] ?? ''),
      );
      final json = jsonDecode(webviewLogin!);
      if (json['success'] == true && json['cookies'] != null) {
        final cookieList = (json['cookies'] as String).split(';');
        final cookies = cookieList
  .map((h) => h.trim())
  .where((h) => h.contains('=') && !h.startsWith('='))
  .map((h) => RawCookie(h.substring(0, h.indexOf('=')).trim(), h.substring(h.indexOf('=') + 1).trim()))
  .toList();
        _account = AccountModel(
fields: fields,
cookies: cookies,
service: SupportedService.filman,
        );
        final authModel = AuthModel(
service: SupportedService.filman,
success: true,
account: _account,
        );
        _authController.add(authModel);
        return authModel;
      } else {
        final authModel = AuthModel(
service: SupportedService.filman,
success: false,
error: [json['error'] ?? 'Logowanie nie powiodło się'],
        );
        _authController.add(authModel);
        return authModel;
      }
    } catch (e) {
      final authModel = AuthModel(
        service: SupportedService.filman,
        success: false,
        error: ['Błąd logowania: $e'],
      );
      _authController.add(authModel);
      return authModel;
    }
  }

  @override
  AccountModel? getAccount() => _account;

  @override
  Future<void> setAccount(AccountModel account) async {
    _account = account;
    _dio = FilmanDioFactory.getDio(_account);
    await SecureStorageService.saveServiceData(
      SupportedService.filman,
      'account',
      jsonEncode(account.toMap()),
    );
    _authController.add(AuthModel(service: SupportedService.filman, success: true, account: _account));
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _dio = FilmanDioFactory.getDio(null);
    _authController.add(AuthModel(service: SupportedService.filman, success: false, account: null));
    await SecureStorageService.deleteServiceData(SupportedService.filman, 'account');
  }

  void dispose() {
    _authSubscription.cancel();
    _authController.close();
  }
}