import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';

class DocchiAuthRepository implements AuthRepository {
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();
  bool _userTouched = false;
  late final Future<void> _initFuture;

  DocchiAuthRepository([AccountModel? account]) {
    if (account != null) {
      _account = account;
    }
    _initFuture = _loadSavedAccount();
  }

  Future<void> ensureInitialized() => _initFuture;

  Future<void> _loadSavedAccount() async {
    try {
      final loggedOut = await SecureStorageService.getServiceData(
        SupportedService.docchi,
        'logged_out',
      );
      if (_userTouched) return;
      if (loggedOut == 'true') {
        _account = null;
        _authController.add(AuthModel(
          service: SupportedService.docchi,
          success: false,
          account: null,
        ));
        return;
      }

      final accountJson = await SecureStorageService.getServiceData(
        SupportedService.docchi,
        'account',
      );
      if (_userTouched) return;
      if (accountJson != null) {
        _account = AccountModel.fromMap(jsonDecode(accountJson));
      } else {
        _account = AccountModel(
          fields: const {'login': 'Dostęp publiczny'},
          cookies: const [],
          service: SupportedService.docchi,
        );
        await SecureStorageService.saveServiceData(
          SupportedService.docchi,
          'account',
          jsonEncode(_account!.toMap()),
        );
      }
      _authController.add(AuthModel(
        service: SupportedService.docchi,
        success: true,
        account: _account,
      ));
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Docchi.pl: $e');
      if (!_userTouched && _account == null) {
        _account = AccountModel(
          fields: const {'login': 'Dostęp publiczny'},
          cookies: const [],
          service: SupportedService.docchi,
        );
        _authController.add(AuthModel(
          service: SupportedService.docchi,
          success: true,
          account: _account,
        ));
      }
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  @override
  Future<AuthModel> signIn(Map<String, String> fields) async {
    _userTouched = true;
    await SecureStorageService.deleteServiceData(
      SupportedService.docchi,
      'logged_out',
    );
    _account = AccountModel(
      fields: const {'login': 'Dostęp publiczny'},
      cookies: const [],
      service: SupportedService.docchi,
    );
    await SecureStorageService.saveServiceData(
      SupportedService.docchi,
      'account',
      jsonEncode(_account!.toMap()),
    );
    final authModel = AuthModel(
      service: SupportedService.docchi,
      success: true,
      account: _account,
    );
    _authController.add(authModel);
    return authModel;
  }

  @override
  AccountModel? getAccount() => _account;

  @override
  Future<void> setAccount(AccountModel account) async {
    _userTouched = true;
    _account = account;
    await SecureStorageService.deleteServiceData(
      SupportedService.docchi,
      'logged_out',
    );
    await SecureStorageService.saveServiceData(
      SupportedService.docchi,
      'account',
      jsonEncode(account.toMap()),
    );
    _authController.add(AuthModel(
      service: SupportedService.docchi,
      success: true,
      account: _account,
    ));
  }

  @override
  Future<void> signOut() async {
    _userTouched = true;
    _account = null;
    await SecureStorageService.deleteServiceData(
      SupportedService.docchi,
      'account',
    );
    await SecureStorageService.saveServiceData(
      SupportedService.docchi,
      'logged_out',
      'true',
    );
    _authController.add(AuthModel(
      service: SupportedService.docchi,
      success: false,
      account: null,
    ));
  }

  void dispose() {
    _authController.close();
  }
}
