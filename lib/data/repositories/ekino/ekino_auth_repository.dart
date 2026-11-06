import 'package:purevideo/core/utils/safe_cookie.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:purevideo/core/services/captcha_service.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/core/services/webview_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';
import 'package:purevideo/data/repositories/ekino/ekino_dio_factory.dart';
import 'package:purevideo/di/injection_container.dart';

class EkinoAuthRepository implements AuthRepository {
  late Dio _dio;
  final CaptchaService _captchaService = getIt();
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();
  late StreamSubscription<AuthModel> _authSubscription;

  EkinoAuthRepository([AccountModel? account]) {
    _account = account ??
        AccountModel(
          fields: const {'login': 'Gość'},
          cookies: const [],
          service: SupportedService.ekino,
        );
    _dio = EkinoDioFactory.getDio(_account);
    _loadSavedAccount();
    _authSubscription = _authController.stream.listen(_onAuthChanged);
  }

  List<Cookie> _parseCookiesFromHeaders(List<String>? rawHeaders) {
    if (rawHeaders == null || rawHeaders.isEmpty) return [];
    final byName = <String, Cookie>{};
    for (final header in rawHeaders) {
      final lower = header.toLowerCase();
      final firstPart = header.split(';').first.trim();
      final eq = firstPart.indexOf('=');
      if (eq <= 0) continue;
      final name = firstPart.substring(0, eq).trim();
      final val = firstPart.substring(eq + 1).trim();
      if (val == 'deleted' ||
          lower.contains('max-age=0') ||
          lower.contains('1970')) {
        byName.remove(name);
        continue;
      }
      if (name.isNotEmpty && val.isNotEmpty) {
        final parsed = RawCookie.parse(firstPart);
        if (parsed != null) {
          byName[name] = parsed;
        }
      }
    }
    return byName.values.toList();
  }

  Future<void> _loadSavedAccount() async {
    try {
      await WebViewService.ensureCleanUserAgent();
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
      } else {
        final loggedOut = await SecureStorageService.getServiceData(
          SupportedService.ekino,
          'logged_out',
        );
        if (loggedOut == 'true') {
          _account = null;
          _dio = EkinoDioFactory.getDio(null);
          _authController.add(
            const AuthModel(
              service: SupportedService.ekino,
              success: false,
              account: null,
            ),
          );
        } else {
          _account = AccountModel(
            fields: const {'login': 'Gość'},
            cookies: const [],
            service: SupportedService.ekino,
          );
          _dio = EkinoDioFactory.getDio(_account);
          await SecureStorageService.saveServiceData(
            SupportedService.ekino,
            'account',
            jsonEncode(_account!.toMap()),
          );
          _authController.add(
            AuthModel(
              service: SupportedService.ekino,
              success: true,
              account: _account,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Ekino.ws: $e');
      _dio = EkinoDioFactory.getDio(_account);
    }
  }

  void _onAuthChanged(AuthModel auth) {
    if (auth.service == SupportedService.ekino) {
      _dio = EkinoDioFactory.getDio(auth.account);
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

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
        final response = await _dio.get('/');
        final cookies =
            _parseCookiesFromHeaders(response.headers['set-cookie']);

        _account = AccountModel(
          fields: {
            'login': 'Gość',
          },
          cookies: cookies,
          service: SupportedService.ekino,
        );

        final authModel = AuthModel(
          service: SupportedService.ekino,
          success: true,
          account: _account,
        );

        _authController.add(authModel);
        return authModel;
      }

      final captchaToken =
          await _captchaService.getCaptchaToken(SupportedService.ekino);

      final response = await _dio.post(
        '/icall/login',
        data: {
          ...fields,
          'g-recaptcha-response': captchaToken,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      if (response.statusCode != 302) {
        final document = html.parse(response.data);
        final errors = document
            .querySelectorAll('.alert-danger')
            .map((e) => e.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();

        if (errors.isNotEmpty) {
          final authModel = AuthModel(
            service: SupportedService.ekino,
            success: false,
            error: errors,
          );
          _authController.add(authModel);
          return authModel;
        }
      }

      final cookies = _parseCookiesFromHeaders(response.headers['set-cookie']);
      if (cookies.isNotEmpty) {
        _account = AccountModel(
          fields: fields,
          cookies: cookies,
          service: SupportedService.ekino,
        );

        final authModel = AuthModel(
          service: SupportedService.ekino,
          success: true,
          account: _account,
        );
        _authController.add(authModel);
        return authModel;
      }

      final authModel = AuthModel(
        service: SupportedService.ekino,
        success: false,
        error: ['Brak ciasteczek'],
      );
      _authController.add(authModel);
      return authModel;
    } catch (e) {
      debugPrint('Błąd logowania do Ekino: $e', wrapWidth: 1024);
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
    await SecureStorageService.deleteServiceData(
      SupportedService.ekino,
      'logged_out',
    );
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
    _authController.add(
      AuthModel(
        service: SupportedService.ekino,
        success: false,
        account: null,
      ),
    );
    await SecureStorageService.deleteServiceData(
      SupportedService.ekino,
      'account',
    );
    await SecureStorageService.saveServiceData(
      SupportedService.ekino,
      'logged_out',
      'true',
    );
  }

  void dispose() {
    _authSubscription.cancel();
    _authController.close();
  }
}
