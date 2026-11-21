import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';

class BajeczkiAuthRepository implements AuthRepository {
  AccountModel? _account;
  final _authController = StreamController<AuthModel>.broadcast();

  BajeczkiAuthRepository([AccountModel? account]) {
    _account = account ??
        AccountModel(
          fields: const {'login': 'Gość'},
          cookies: const [],
          service: SupportedService.bajeczki,
        );
    _loadSavedAccount();
  }

  Future<void> _loadSavedAccount() async {
    try {
      final accountJson = await SecureStorageService.getServiceData(
        SupportedService.bajeczki,
        'account',
      );
      if (accountJson != null) {
        _account = AccountModel.fromMap(jsonDecode(accountJson));
        _authController.add(AuthModel(
          service: SupportedService.bajeczki,
          success: true,
          account: _account,
        ));
      } else {
        final loggedOut = await SecureStorageService.getServiceData(
          SupportedService.bajeczki,
          'logged_out',
        );
        if (loggedOut == 'true') {
          _account = null;
          _authController.add(AuthModel(
            service: SupportedService.bajeczki,
            success: false,
            account: null,
          ));
        } else {
          _account = AccountModel(
            fields: const {'login': 'Gość'},
            cookies: const [],
            service: SupportedService.bajeczki,
          );
          await SecureStorageService.saveServiceData(
            SupportedService.bajeczki,
            'account',
            jsonEncode(_account!.toMap()),
          );
          _authController.add(AuthModel(
            service: SupportedService.bajeczki,
            success: true,
            account: _account,
          ));
        }
      }
    } catch (e) {
      debugPrint('Błąd podczas ładowania konta Bajeczki.org: $e');
    }
  }

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  @override
  Future<AuthModel> signIn(Map<String, String> fields) async {
    await SecureStorageService.deleteServiceData(
      SupportedService.bajeczki,
      'logged_out',
    );
    _account = AccountModel(
      fields: const {'login': 'Gość'},
      cookies: const [],
      service: SupportedService.bajeczki,
    );
    await SecureStorageService.saveServiceData(
      SupportedService.bajeczki,
      'account',
      jsonEncode(_account!.toMap()),
    );
    final authModel = AuthModel(
      service: SupportedService.bajeczki,
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
    _account = account;
    await SecureStorageService.deleteServiceData(
      SupportedService.bajeczki,
      'logged_out',
    );
    await SecureStorageService.saveServiceData(
      SupportedService.bajeczki,
      'account',
      jsonEncode(account.toMap()),
    );
    _authController.add(AuthModel(
      service: SupportedService.bajeczki,
      success: true,
      account: _account,
    ));
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _authController.add(AuthModel(
      service: SupportedService.bajeczki,
      success: false,
      account: null,
    ));
    await SecureStorageService.deleteServiceData(
      SupportedService.bajeczki,
      'account',
    );
    await SecureStorageService.saveServiceData(
      SupportedService.bajeczki,
      'logged_out',
      'true',
    );
  }

  void dispose() {
    _authController.close();
  }
}
