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

class ExtraMediaLink {
  final String url;
  final String lang;
  final String quality;

  const ExtraMediaLink({
    required this.url,
    this.lang = 'Lektor PL',
    this.quality = 'HD',
  });

  String get hostBadge {
    final lower = url.toLowerCase();
    if (lower.contains('vider.info') || lower.contains('vider.pl')) {
      return 'Vider.info';
    }
    if (lower.contains('cda.pl')) {
      return 'CDA';
    }
    return Uri.tryParse(url)?.host ?? 'Link';
  }

  factory ExtraMediaLink.fromMap(Map<String, dynamic> map) {
    return ExtraMediaLink(
      url: (map['url'] ?? '').toString().trim(),
      lang: (map['lang'] ?? 'PL').toString().trim(),
      quality: (map['quality'] ?? 'HD').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'lang': lang,
        'quality': quality,
      };
}

class ExtraEpisodeEntry {
  final int number;
  final String title;
  final List<ExtraMediaLink> links;

  const ExtraEpisodeEntry({
    required this.number,
    this.title = '',
    required this.links,
  });

  factory ExtraEpisodeEntry.fromMap(Map<String, dynamic> map) {
    final rawLinks = (map['links'] as List?) ?? const [];
    return ExtraEpisodeEntry(
      number: (map['number'] as num?)?.toInt() ?? 1,
      title: (map['title'] ?? '').toString().trim(),
      links: rawLinks
          .whereType<Map>()
          .map((e) => ExtraMediaLink.fromMap(Map<String, dynamic>.from(e)))
          .where((l) => l.url.startsWith('http'))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'number': number,
        'title': title,
        'links': links.map((l) => l.toMap()).toList(),
      };
}

class ExtraSeasonEntry {
  final int number;
  final List<ExtraEpisodeEntry> episodes;

  const ExtraSeasonEntry({
    required this.number,
    required this.episodes,
  });

  factory ExtraSeasonEntry.fromMap(Map<String, dynamic> map) {
    final rawEps = (map['episodes'] as List?) ?? const [];
    final eps = rawEps
        .whereType<Map>()
        .map((e) => ExtraEpisodeEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return ExtraSeasonEntry(
      number: (map['number'] as num?)?.toInt() ?? 1,
      episodes: eps,
    );
  }

  Map<String, dynamic> toMap() => {
        'number': number,
        'episodes': episodes.map((e) => e.toMap()).toList(),
      };
}

class ExtraMediaEntry {
  final String id;
  final String title;
  final String posterUrl;
  final String description;
  final String category;
  final bool isSeries;
  final List<ExtraMediaLink> links;
  final List<ExtraSeasonEntry> seasons;
  final bool isRemote;

  const ExtraMediaEntry({
    required this.id,
    required this.title,
    this.posterUrl = '',
    this.description = '',
    this.category = '',
    required this.isSeries,
    this.links = const [],
    this.seasons = const [],
    this.isRemote = false,
  });

  factory ExtraMediaEntry.fromMap(Map<String, dynamic> map,
      {bool isRemote = false}) {
    final isSeries = map['isSeries'] == true;
    final rawLinks = (map['links'] as List?) ?? const [];
    final rawSeasons = (map['seasons'] as List?) ?? const [];
    final seasons = rawSeasons
        .whereType<Map>()
        .map((e) => ExtraSeasonEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return ExtraMediaEntry(
      id: (map['id'] ?? '').toString().trim(),
      title: (map['title'] ?? '').toString().trim(),
      posterUrl: (map['posterUrl'] ?? '').toString().trim(),
      description: (map['description'] ?? '').toString().trim(),
      category: (map['category'] ?? '').toString().trim(),
      isSeries: isSeries,
      links: rawLinks
          .whereType<Map>()
          .map((e) => ExtraMediaLink.fromMap(Map<String, dynamic>.from(e)))
          .where((l) => l.url.startsWith('http'))
          .toList(),
      seasons: seasons,
      isRemote: isRemote,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'description': description,
        'category': category,
        'isSeries': isSeries,
        if (!isSeries) 'links': links.map((l) => l.toMap()).toList(),
        if (isSeries) 'seasons': seasons.map((s) => s.toMap()).toList(),
      };

  ExtraMediaEntry mergeSeriesEpisode({
    required int seasonNumber,
    required int episodeNumber,
    required String episodeTitle,
    required List<ExtraMediaLink> newLinks,
  }) {
    final seasonMap = <int, List<ExtraEpisodeEntry>>{};
    for (final s in seasons) {
      seasonMap[s.number] = List<ExtraEpisodeEntry>.from(s.episodes);
    }
    final epList = seasonMap[seasonNumber] ?? <ExtraEpisodeEntry>[];
    final existingIdx = epList.indexWhere((e) => e.number == episodeNumber);
    if (existingIdx >= 0) {
      final existing = epList[existingIdx];
      final combined = <ExtraMediaLink>[...existing.links];
      for (final nl in newLinks) {
        if (!combined.any((c) => c.url == nl.url)) {
          combined.add(nl);
        }
      }
      epList[existingIdx] = ExtraEpisodeEntry(
        number: episodeNumber,
        title: episodeTitle.trim().isNotEmpty ? episodeTitle.trim() : existing.title,
        links: combined,
      );
    } else {
      epList.add(ExtraEpisodeEntry(
        number: episodeNumber,
        title: episodeTitle.trim().isNotEmpty
            ? episodeTitle.trim()
            : 'Odcinek $episodeNumber',
        links: newLinks,
      ));
    }
    epList.sort((a, b) => a.number.compareTo(b.number));
    seasonMap[seasonNumber] = epList;
    final sortedSeasons = seasonMap.entries
        .map((e) => ExtraSeasonEntry(number: e.key, episodes: e.value))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return ExtraMediaEntry(
      id: id,
      title: title,
      posterUrl: posterUrl,
      description: description,
      category: category,
      isSeries: true,
      seasons: sortedSeasons,
      isRemote: isRemote,
    );
  }
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
    _changesController.add(null);
  }

  static String _sha256Hex(String input) {
    final digest = SHA256Digest().process(Uint8List.fromList(utf8.encode(input)));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> hasVerifiedOwnerCredentials() async {
    final tok = await SecureStorageService.getData(_ownerTokenKey);
    final pin = await SecureStorageService.getData(_ownerPinHashKey);
    return tok != null && tok.isNotEmpty && pin != null && pin.isNotEmpty;
  }

  Future<String?> getVerifiedOwnerLogin() async {
    return SecureStorageService.getData(_ownerLoginKey);
  }

  Future<bool> verifyPin(String pin) async {
    final savedHash = await SecureStorageService.getData(_ownerPinHashKey);
    if (savedHash == null || savedHash.isEmpty) return false;
    return savedHash == _sha256Hex('pv:${pin.trim()}');
  }

  Future<void> clearOwnerVerification() async {
    await SecureStorageService.deleteData(_ownerTokenKey);
    await SecureStorageService.deleteData(_ownerPinHashKey);
    await SecureStorageService.deleteData(_ownerLoginKey);
  }

  Future<String?> verifyAndSaveOwnerCredentials({
    required String githubToken,
    required String pin,
  }) async {
    final cleanToken = githubToken.trim();
    final cleanPin = pin.trim();
    if (cleanToken.isEmpty) return 'Wprowadź token GitHub (PAT).';
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
        options: Options(headers: authHeaders, validateStatus: (_) => true),
      );
      if (userResp.statusCode != 200 || userResp.data is! Map) {
        return 'Nieprawidłowy token GitHub (HTTP ${userResp.statusCode}).';
      }
      final login = (userResp.data['login'] ?? '').toString().trim();
      final repoResp = await _dio.get(
        'https://api.github.com/repos/$repoOwner/$repoName',
        options: Options(headers: authHeaders, validateStatus: (_) => true),
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

  // --- Website adapters ---

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

  // --- Curated Movies & Series (CDA / Vider.info) ---

  List<ExtraMediaEntry> getRemoteMedia() {
    return _settings
        .getRemoteMediaMaps()
        .map((m) => ExtraMediaEntry.fromMap(m, isRemote: true))
        .where((m) => m.id.isNotEmpty && m.title.isNotEmpty)
        .toList();
  }

  List<ExtraMediaEntry> getLocalMedia() {
    return _settings
        .getLocalMediaMaps()
        .map((m) => ExtraMediaEntry.fromMap(m, isRemote: false))
        .where((m) => m.id.isNotEmpty && m.title.isNotEmpty)
        .toList();
  }

  List<ExtraMediaEntry> getAllActiveCustomMedia() {
    if (!_settings.extraSourcesEnabled) return const [];
    final map = <String, ExtraMediaEntry>{};
    for (final m in getRemoteMedia()) {
      map[m.id] = m;
    }
    for (final m in getLocalMedia()) {
      if (map.containsKey(m.id) && m.isSeries && map[m.id]!.isSeries) {
        var combined = map[m.id]!;
        for (final s in m.seasons) {
          for (final ep in s.episodes) {
            combined = combined.mergeSeriesEpisode(
              seasonNumber: s.number,
              episodeNumber: ep.number,
              episodeTitle: ep.title,
              newLinks: ep.links,
            );
          }
        }
        map[m.id] = combined;
      } else {
        map[m.id] = m;
      }
    }
    return map.values.toList();
  }

  ExtraMediaEntry? findMediaById(String id) {
    for (final m in getAllActiveCustomMedia()) {
      if (m.id == id) return m;
    }
    for (final m in getLocalMedia()) {
      if (m.id == id) return m;
    }
    for (final m in getRemoteMedia()) {
      if (m.id == id) return m;
    }
    return null;
  }

  static String? validateVideoLinkUrl(String rawUrl) {
    final u = rawUrl.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      return 'Link musi zaczynać się od http:// lub https://';
    }
    final lower = u.toLowerCase();
    final isCda = lower.contains('cda.pl');
    final isVider = lower.contains('vider.info') || lower.contains('vider.pl');
    if (!isCda && !isVider) {
      return 'Obsługiwane są obecnie linki z cda.pl oraz vider.info.';
    }
    return null;
  }

  Future<void> addOrUpdateLocalMedia(ExtraMediaEntry entry) async {
    final current = getLocalMedia().where((m) => m.id != entry.id).toList();
    current.add(entry);
    _settings.setLocalMediaMaps(current.map((e) => e.toMap()).toList());
    notifyChanged();
  }

  Future<void> removeLocalMedia(String id) async {
    final current = getLocalMedia().where((m) => m.id != id).toList();
    _settings.setLocalMediaMaps(current.map((e) => e.toMap()).toList());
    notifyChanged();
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
        if (decoded is Map) {
          final sourcesList = (decoded['sources'] is List)
              ? (decoded['sources'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];
          final mediaList = (decoded['media'] is List)
              ? (decoded['media'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];
          _settings.setRemoteSourcesMaps(sourcesList);
          _settings.setRemoteMediaMaps(mediaList);
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
    final url = rawUrl.trim();
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

  Future<String?> _updateManifestOnGitHub({
    required String pin,
    required String commitMessage,
    required void Function(
      List<Map<String, dynamic>> sources,
      List<Map<String, dynamic>> media,
    ) mutate,
  }) async {
    if (!await verifyPin(pin)) {
      return 'Nieprawidłowy kod PIN właściciela.';
    }
    final token = await SecureStorageService.getData(_ownerTokenKey);
    if (token == null || token.isEmpty) {
      return 'Brak zapisanego tokenu właściciela.';
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
      final sourcesList = <Map<String, dynamic>>[];
      final mediaList = <Map<String, dynamic>>[];

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
                sourcesList.add(Map<String, dynamic>.from(item));
              }
            }
            if (parsed['media'] is List) {
              for (final item in (parsed['media'] as List).whereType<Map>()) {
                mediaList.add(Map<String, dynamic>.from(item));
              }
            }
          }
        }
      } else if (getResp.statusCode != 404) {
        return 'Błąd odczytu manifestu z GitHub (HTTP ${getResp.statusCode}).';
      }

      mutate(sourcesList, mediaList);

      final newJson = const JsonEncoder.withIndent('  ').convert({
        'version': version,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'sources': sourcesList,
        'media': mediaList,
      });

      final putResp = await _dio.put(
        apiUrl,
        data: jsonEncode({
          'message': commitMessage,
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

      _settings.setRemoteSourcesMaps(sourcesList);
      _settings.setRemoteMediaMaps(mediaList);
      _hasSyncedOnce = true;
      notifyChanged();
      return null;
    } catch (e) {
      return 'Błąd publikacji na GitHub: $e';
    }
  }

  Future<String?> publishGlobalSourcesChange({
    ExtraSourceConfig? addSource,
    String? removeId,
    required String pin,
  }) async {
    if (addSource != null) {
      final urlErr = await validateSourceUrl(addSource.baseUrl);
      if (urlErr != null) return urlErr;
    }
    return _updateManifestOnGitHub(
      pin: pin,
      commitMessage: addSource != null
          ? 'Update remote_sources.json: add source ${addSource.name}'
          : 'Update remote_sources.json: remove source $removeId',
      mutate: (sourcesList, _) {
        if (removeId != null) {
          sourcesList.removeWhere((e) => e['id']?.toString() == removeId);
        }
        if (addSource != null) {
          sourcesList.removeWhere((e) =>
              e['id']?.toString() == addSource.id ||
              e['baseUrl']?.toString() == addSource.baseUrl);
          sourcesList.add(addSource.toMap());
        }
      },
    );
  }

  Future<String?> publishGlobalMediaChange({
    ExtraMediaEntry? upsertMedia,
    String? removeMediaId,
    required String pin,
  }) async {
    return _updateManifestOnGitHub(
      pin: pin,
      commitMessage: upsertMedia != null
          ? 'Update remote_sources.json: ${upsertMedia.isSeries ? "series" : "movie"} ${upsertMedia.title}'
          : 'Update remote_sources.json: remove media $removeMediaId',
      mutate: (_, mediaList) {
        if (removeMediaId != null) {
          mediaList.removeWhere((e) => e['id']?.toString() == removeMediaId);
        }
        if (upsertMedia != null) {
          final existingIdx = mediaList.indexWhere((e) =>
              e['id']?.toString() == upsertMedia.id ||
              (upsertMedia.isSeries &&
                  e['isSeries'] == true &&
                  (e['title'] ?? '').toString().toLowerCase().trim() ==
                      upsertMedia.title.toLowerCase().trim()));
          if (existingIdx >= 0 && upsertMedia.isSeries) {
            var base = ExtraMediaEntry.fromMap(mediaList[existingIdx], isRemote: true);
            for (final s in upsertMedia.seasons) {
              for (final ep in s.episodes) {
                base = base.mergeSeriesEpisode(
                  seasonNumber: s.number,
                  episodeNumber: ep.number,
                  episodeTitle: ep.title,
                  newLinks: ep.links,
                );
              }
            }
            mediaList[existingIdx] = base.toMap();
          } else {
            if (existingIdx >= 0) {
              mediaList.removeAt(existingIdx);
            }
            mediaList.add(upsertMedia.toMap());
          }
        }
      },
    );
  }
}
