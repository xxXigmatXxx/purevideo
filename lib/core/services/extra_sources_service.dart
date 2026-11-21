import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/core/services/settings_service.dart';
import 'package:purevideo/di/injection_container.dart';

enum ExtraSourceType { wordpress, ekinoMirror, htmlAuto }

extension ExtraSourceTypeExt on ExtraSourceType {
  String get apiValue => switch (this) {
        ExtraSourceType.wordpress => 'wordpress',
        ExtraSourceType.ekinoMirror => 'ekino_mirror',
        ExtraSourceType.htmlAuto => 'html_auto',
      };

  String get displayName => switch (this) {
        ExtraSourceType.wordpress => 'WordPress (wp-json)',
        ExtraSourceType.ekinoMirror => 'Ekino Mirror',
        ExtraSourceType.htmlAuto => 'Uniwersalny HTML',
      };

  static ExtraSourceType fromString(String? val) {
    switch ((val ?? '').toLowerCase().trim()) {
      case 'wordpress':
        return ExtraSourceType.wordpress;
      case 'ekino_mirror':
        return ExtraSourceType.ekinoMirror;
      default:
        return ExtraSourceType.htmlAuto;
    }
  }
}

class ExtraSourceConfig {
  final String id;
  final String name;
  final String baseUrl;
  final ExtraSourceType type;
  final String category;
  final String logoUrl;
  final bool enabled;
  final bool isRemote;

  const ExtraSourceConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.type,
    required this.category,
    this.logoUrl = '',
    this.enabled = true,
    this.isRemote = false,
  });

  factory ExtraSourceConfig.fromMap(Map<String, dynamic> map,
      {bool isRemote = false}) {
    var base = (map['baseUrl'] ?? '').toString().trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return ExtraSourceConfig(
      id: (map['id'] ?? '').toString().trim(),
      name: (map['name'] ?? '').toString().trim(),
      baseUrl: base,
      type: ExtraSourceTypeExt.fromString(map['type']?.toString()),
      category: (map['category'] ?? 'Popularne filmy').toString().trim(),
      logoUrl: (map['logoUrl'] ?? '').toString().trim(),
      enabled: map['enabled'] != false,
      isRemote: isRemote,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'type': type.apiValue,
        'category': category,
        'logoUrl': logoUrl,
        'enabled': enabled,
      };
}

class ExtraSourcesService {
  static const String repoOwner = 'xxXigmatXxx';
  static const String repoName = 'purevideo';
  static const String repoBranch = 'master';
  static const String manifestPath = 'remote_sources.json';
  static const String rawManifestUrl =
      'https://raw.githubusercontent.com/$repoOwner/$repoName/$repoBranch/$manifestPath';

  static const String _ownerTokenKey = 'pv_owner_github_token';
  static const String _ownerPinHashKey = 'pv_owner_pin_hash';
  static const String _ownerLoginKey = 'pv_owner_github_login';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 12),
    headers: const {
      'User-Agent': 'PureVideo-App/1.0',
      'Accept': 'application/vnd.github+json',
    },
  ));

  final SettingsService _settings = getIt<SettingsService>();
  final _changesController = StreamController<void>.broadcast();
  bool _hasSyncedOnce = false;

  Stream<void> get changesStream => _changesController.stream;

  void notifyChanged() {
    _settings.bumpExtraSourcesVersion();
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  static String _sha256Hex(String input) {
    final digest = SHA256Digest();
    final bytes = Uint8List.fromList(utf8.encode(input));
    final out = digest.process(bytes);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> hasVerifiedOwnerCredentials() async {
    final token = await SecureStorageService.getData(_ownerTokenKey);
    final pinHash = await SecureStorageService.getData(_ownerPinHashKey);
    return token != null &&
        token.trim().isNotEmpty &&
        pinHash != null &&
        pinHash.trim().isNotEmpty;
  }

  Future<String?> getVerifiedOwnerLogin() async {
    return SecureStorageService.getData(_ownerLoginKey);
  }

  Future<void> clearOwnerVerification() async {
    await SecureStorageService.deleteData(_ownerTokenKey);
    await SecureStorageService.deleteData(_ownerPinHashKey);
    await SecureStorageService.deleteData(_ownerLoginKey);
  }

  Future<bool> verifyPin(String pin) async {
    final savedHash = await SecureStorageService.getData(_ownerPinHashKey);
    if (savedHash == null || savedHash.isEmpty) return false;
    return _sha256Hex('pv:$pin') == savedHash;
  }

  /// Verifies that the supplied GitHub token actually belongs to [repoOwner]
  /// (or has push permissions to [repoOwner]/[repoName]) and saves it in
  /// Android Keystore protected by a local PIN hash.
  Future<String?> verifyAndSaveOwnerCredentials({
    required String githubToken,
    required String pin,
  }) async {
    final cleanToken = githubToken.trim();
    final cleanPin = pin.trim();
    if (cleanToken.length < 10) {
      return 'Wprowadź poprawny token GitHub (PAT).';
    }
    if (cleanPin.length < 4 || cleanPin.length > 8) {
      return 'PIN powinien mieć od 4 do 8 znaków.';
    }

    try {
      final authHeaders = {
        'Authorization': 'Bearer $cleanToken',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

      final userResp = await _dio.get(
        'https://api.github.com/user',
        options: Options(
          headers: authHeaders,
          validateStatus: (_) => true,
        ),
      );
      if (userResp.statusCode != 200 || userResp.data is! Map) {
        return 'Nieprawidłowy token GitHub (HTTP ${userResp.statusCode}).';
      }
      final login = (userResp.data['login'] ?? '').toString().trim();

      final repoResp = await _dio.get(
        'https://api.github.com/repos/$repoOwner/$repoName',
        options: Options(
          headers: authHeaders,
          validateStatus: (_) => true,
        ),
      );
      if (repoResp.statusCode != 200 || repoResp.data is! Map) {
        return 'Brak dostępu do repozytorium $repoOwner/$repoName.';
      }
      final perms = repoResp.data['permissions'];
      final canPush = perms is Map && perms['push'] == true;
      if (!canPush || login.toLowerCase() != repoOwner.toLowerCase()) {
        return 'Odmowa dostępu: konto "$login" nie jest właścicielem ($repoOwner) z prawem zapisu.';
      }

      await SecureStorageService.saveData(_ownerTokenKey, cleanToken);
      await SecureStorageService.saveData(
          _ownerPinHashKey, _sha256Hex('pv:$cleanPin'));
      await SecureStorageService.saveData(_ownerLoginKey, login);
      return null;
    } catch (e) {
      return 'Błąd weryfikacji GitHub: $e';
    }
  }

  List<ExtraSourceConfig> getRemoteSources() {
    return _settings
        .getRemoteSourcesMaps()
        .map((m) => ExtraSourceConfig.fromMap(m, isRemote: true))
        .where((s) => s.id.isNotEmpty && s.baseUrl.startsWith('http'))
        .toList();
  }

  List<ExtraSourceConfig> getLocalSources() {
    return _settings
        .getLocalSourcesMaps()
        .map((m) => ExtraSourceConfig.fromMap(m, isRemote: false))
        .where((s) => s.id.isNotEmpty && s.baseUrl.startsWith('http'))
        .toList();
  }

  List<ExtraSourceConfig> getAllActiveCustomSources() {
    if (!_settings.extraSourcesEnabled) return const [];
    final map = <String, ExtraSourceConfig>{};
    for (final s in getRemoteSources()) {
      if (s.enabled) map[s.id] = s;
    }
    for (final s in getLocalSources()) {
      if (s.enabled) map[s.id] = s;
    }
    return map.values.toList();
  }

  ExtraSourceConfig? findById(String id) {
    for (final s in getLocalSources()) {
      if (s.id == id) return s;
    }
    for (final s in getRemoteSources()) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<bool> syncRemoteSources({bool force = false}) async {
    if (_hasSyncedOnce && !force) return true;
    try {
      final resp = await _dio.get<String>(
        '$rawManifestUrl?t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode == 200 &&
          resp.data != null &&
          resp.data!.trim().isNotEmpty) {
        final decoded = jsonDecode(resp.data!);
        if (decoded is Map && decoded['sources'] is List) {
          final list = (decoded['sources'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _settings.setRemoteSourcesMaps(list);
          _hasSyncedOnce = true;
          if (force) notifyChanged();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Remote sources sync error: $e');
    }
    return false;
  }

  Future<void> addLocalSource(ExtraSourceConfig source) async {
    final current = getLocalSources().where((s) => s.id != source.id).toList();
    current.add(source);
    _settings.setLocalSourcesMaps(current.map((e) => e.toMap()).toList());
    notifyChanged();
  }

  Future<void> removeLocalSource(String id) async {
    final current = getLocalSources().where((s) => s.id != id).toList();
    _settings.setLocalSourcesMaps(current.map((e) => e.toMap()).toList());
    notifyChanged();
  }

  Future<String?> validateSourceUrl(String rawUrl) async {
    var url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'Adres musi zaczynać się od http:// lub https://';
    }
    try {
      final r = await _dio.get(
        url,
        options: Options(
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
          },
          validateStatus: (_) => true,
        ),
      );
      if (r.statusCode == null || r.statusCode! >= 500) {
        return 'Strona nie odpowiada poprawnie (HTTP ${r.statusCode}).';
      }
      return null;
    } catch (e) {
      return 'Nie udało się połączyć ze stroną: $e';
    }
  }

  /// Publishes a new global source (or removes one when [removeId] is set) to
  /// remote_sources.json on GitHub using the verified owner token stored locally.
  Future<String?> publishGlobalSourcesChange({
    ExtraSourceConfig? addSource,
    String? removeId,
    required String pin,
  }) async {
    if (!await verifyPin(pin)) {
      return 'Nieprawidłowy kod PIN właściciela.';
    }
    final token = await SecureStorageService.getData(_ownerTokenKey);
    if (token == null || token.isEmpty) {
      return 'Brak zapisanego tokenu właściciela.';
    }

    if (addSource != null) {
      final urlErr = await validateSourceUrl(addSource.baseUrl);
      if (urlErr != null) return urlErr;
    }

    try {
      final apiUrl =
          'https://api.github.com/repos/$repoOwner/$repoName/contents/$manifestPath';
      final authHeaders = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

      String? fileSha;
      int version = 1;
      final existingList = <Map<String, dynamic>>[];

      final getResp = await _dio.get(
        '$apiUrl?ref=$repoBranch',
        options: Options(headers: authHeaders, validateStatus: (_) => true),
      );

      if (getResp.statusCode == 200 && getResp.data is Map) {
        fileSha = getResp.data['sha']?.toString();
        final b64 = (getResp.data['content'] ?? '')
            .toString()
            .replaceAll('\n', '')
            .trim();
        if (b64.isNotEmpty) {
          final parsed = jsonDecode(utf8.decode(base64Decode(b64)));
          if (parsed is Map) {
            version = ((parsed['version'] as num?)?.toInt() ?? 0) + 1;
            if (parsed['sources'] is List) {
              for (final item in (parsed['sources'] as List).whereType<Map>()) {
                existingList.add(Map<String, dynamic>.from(item));
              }
            }
          }
        }
      } else if (getResp.statusCode != 404) {
        return 'Błąd odczytu manifestu z GitHub (HTTP ${getResp.statusCode}).';
      }

      if (removeId != null) {
        existingList.removeWhere((e) => e['id']?.toString() == removeId);
      }
      if (addSource != null) {
        existingList.removeWhere((e) =>
            e['id']?.toString() == addSource.id ||
            e['baseUrl']?.toString() == addSource.baseUrl);
        existingList.add(addSource.toMap());
      }

      final newJson = const JsonEncoder.withIndent('  ').convert({
        'version': version,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'sources': existingList,
      });

      final putResp = await _dio.put(
        apiUrl,
        data: jsonEncode({
          'message': addSource != null
              ? 'Update remote_sources.json: add ${addSource.name}'
              : 'Update remote_sources.json: remove $removeId',
          'content': base64Encode(utf8.encode('$newJson\n')),
          'branch': repoBranch,
          if (fileSha != null) 'sha': fileSha,
        }),
        options: Options(headers: authHeaders, validateStatus: (_) => true),
      );

      if (putResp.statusCode != 200 && putResp.statusCode != 201) {
        final msg = (putResp.data is Map)
            ? (putResp.data['message'] ?? '').toString()
            : '';
        return 'Błąd zapisu na GitHub (HTTP ${putResp.statusCode}): $msg';
      }

      _settings.setRemoteSourcesMaps(existingList);
      _hasSyncedOnce = true;
      notifyChanged();
      return null;
    } catch (e) {
      return 'Błąd publikacji globalnego źródła: $e';
    }
  }
}
