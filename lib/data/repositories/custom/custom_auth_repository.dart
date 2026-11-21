import 'dart:async';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/account_model.dart';
import 'package:purevideo/data/models/auth_model.dart';
import 'package:purevideo/data/repositories/auth_repository.dart';

class CustomAuthRepository implements AuthRepository {
  final _authController = StreamController<AuthModel>.broadcast();
  final AccountModel _account = AccountModel(
    fields: const {'login': 'Gość'},
    cookies: const [],
    service: SupportedService.custom,
  );

  @override
  Stream<AuthModel> get authStream => _authController.stream;

  @override
  AccountModel? getAccount() => _account;

  @override
  Future<void> setAccount(AccountModel account) async {}

  @override
  Future<AuthModel> signIn(Map<String, String> fields) async {
    return AuthModel(
      service: SupportedService.custom,
      success: true,
      account: _account,
    );
  }

  @override
  Future<void> signOut() async {}

  void dispose() {
    _authController.close();
  }
}
