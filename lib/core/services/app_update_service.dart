import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purevideo/core/services/extra_sources_service.dart';
import 'package:purevideo/core/services/secure_storage_service.dart';
import 'package:purevideo/di/injection_container.dart';

enum AppUpdateChannel { release, dev }

extension AppUpdateChannelExt on AppUpdateChannel {
  String get apiValue =>
      this == AppUpdateChannel.dev ? 'dev' : 'release';

  String get displayName => this == AppUpdateChannel.dev
      ? 'Deweloperska (tylko dostęp admina)'
      : 'Wydanie (dla wszystkich)';

  static AppUpdateChannel fromString(String? raw) {
    return (raw ?? '').toLowerCase().trim() == 'dev'
        ? AppUpdateChannel.dev
        : AppUpdateChannel.release;
  }
}

enum AppUpdateSourceType { artifact, releaseAsset }

extension AppUpdateSourceTypeExt on AppUpdateSourceType {
  String get apiValue =>
      this == AppUpdateSourceType.releaseAsset ? 'release_asset' : 'artifact';

  String get displayName => this == AppUpdateSourceType.releaseAsset
      ? 'GitHub Release'
      : 'GitHub Actions Artifact';

  static AppUpdateSourceType fromString(String? raw) {
    return (raw ?? '').toLowerCase().trim() == 'release_asset'
        ? AppUpdateSourceType.releaseAsset
        : AppUpdateSourceType.artifact;
  }
}

class AppUpdateInfo {
  final String id;
  final String name;
  final String version;
  final int buildNumber;
  final String description;
  final AppUpdateChannel channel;
  final AppUpdateSourceType sourceType;
  final String sourceLabel;
  final String downloadUrl;
  final bool isZip;
  final String publishedAt;

  const AppUpdateInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.buildNumber,
    required this.description,
    required this.channel,
    required this.sourceType,
    required this.sourceLabel,
    required this.downloadUrl,
    this.isZip = false,
    this.publishedAt = '',
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic> map) {
    return AppUpdateInfo(
      id: (map['id'] ?? '').toString().trim(),
      name: (map['name'] ?? '').toString().trim(),
      version: (map['version'] ?? '').toString().trim(),
      buildNumber: (map['buildNumber'] as num?)?.toInt() ?? 0,
      description: (map['description'] ?? '').toString().trim(),
      channel: AppUpdateChannelExt.fromString(map['channel']?.toString()),
      sourceType:
          AppUpdateSourceTypeExt.fromString(map['sourceType']?.toString()),
      sourceLabel: (map['sourceLabel'] ?? '').toString().trim(),
      downloadUrl: (map['downloadUrl'] ?? '').toString().trim(),
      isZip: map['isZip'] == true,
      publishedAt: (map['publishedAt'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'version': version,
        'buildNumber': buildNumber,
        'description': description,
        'channel': channel.apiValue,
        'sourceType': sourceType.apiValue,
        'sourceLabel': sourceLabel,
        'downloadUrl': downloadUrl,
        'isZip': isZip,
        'publishedAt': publishedAt,
      };
}

class GitHubWorkflowRunItem {
  final int id;
  final int runNumber;
  final String headBranch;
  final String commitMessage;
  final String createdAt;

  const GitHubWorkflowRunItem({
    required this.id,
    required this.runNumber,
    required this.headBranch,
    required this.commitMessage,
    required this.createdAt,
  });
}

class GitHubArtifactItem {
  final int id;
  final String name;
  final int sizeBytes;
  final String archiveDownloadUrl;

  const GitHubArtifactItem({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.archiveDownloadUrl,
  });
}

class GitHubReleaseAssetItem {
  final String name;
  final int sizeBytes;
  final String browserDownloadUrl;

  const GitHubReleaseAssetItem({
    required this.name,
    required this.sizeBytes,
    required this.browserDownloadUrl,
  });
}

class GitHubReleaseItem {
  final int id;
  final String tagName;
  final String name;
  final bool prerelease;
  final List<GitHubReleaseAssetItem> assets;

  const GitHubReleaseItem({
    required this.id,
    required this.tagName,
    required this.name,
    required this.prerelease,
    required this.assets,
  });
}

class AppUpdateService {
  static const String updatesManifestPath = 'app_updates.json';
  static const String rawUpdatesUrl =
      'https://raw.githubusercontent.com/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/${ExtraSourcesService.repoBranch}/$updatesManifestPath';

  static const MethodChannel _channel = MethodChannel('purevideo/updater');

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
    headers: const {
      'User-Agent': 'PureVideo-App/1.0',
    },
  ));

  final ValueNotifier<AppUpdateInfo?> availableUpdate = ValueNotifier(null);
  bool _hasCheckedOnce = false;

  Future<Map<String, AppUpdateInfo>> fetchPublishedUpdates() async {
    final result = <String, AppUpdateInfo>{};
    try {
      final resp = await _dio.get<String>(
        '$rawUpdatesUrl?t=${DateTime.now().millisecondsSinceEpoch}',
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
          for (final k in const ['release', 'dev']) {
            final item = decoded[k];
            if (item is Map) {
              final info = AppUpdateInfo.fromMap(
                Map<String, dynamic>.from(item),
              );
              if (info.downloadUrl.startsWith('http') &&
                  info.version.isNotEmpty) {
                result[k] = info;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching updates manifest: $e');
    }
    return result;
  }

  static int compareVersions(String a, String b) {
    List<int> parseParts(String v) {
      final clean = v.split('+').first.replaceAll(RegExp(r'^v'), '').trim();
      return clean
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final pa = parseParts(a);
    final pb = parseParts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  bool _isNewerThanInstalled(
    AppUpdateInfo candidate,
    String installedVersion,
    int installedBuild,
  ) {
    if (candidate.buildNumber > 0 && installedBuild > 0) {
      if (candidate.buildNumber != installedBuild) {
        return candidate.buildNumber > installedBuild;
      }
    }
    final cmp = compareVersions(candidate.version, installedVersion);
    if (cmp != 0) return cmp > 0;
    return false;
  }

  Future<AppUpdateInfo?> checkForUpdates({bool force = false}) async {
    if (_hasCheckedOnce && !force) return availableUpdate.value;
    _hasCheckedOnce = true;

    try {
      final pkg = await PackageInfo.fromPlatform();
      final installedVersion = pkg.version;
      final installedBuild = int.tryParse(pkg.buildNumber) ?? 0;

      final isAdmin =
          await getIt<ExtraSourcesService>().hasVerifiedOwnerCredentials();
      final updates = await fetchPublishedUpdates();

      AppUpdateInfo? chosen;
      final rel = updates['release'];
      final dev = isAdmin ? updates['dev'] : null;

      bool relNewer =
          rel != null && _isNewerThanInstalled(rel, installedVersion, installedBuild);
      bool devNewer =
          dev != null && _isNewerThanInstalled(dev, installedVersion, installedBuild);

      if (relNewer && devNewer) {
        if (dev.buildNumber != rel.buildNumber) {
          chosen = dev.buildNumber > rel.buildNumber ? dev : rel;
        } else {
          chosen =
              compareVersions(dev.version, rel.version) >= 0 ? dev : rel;
        }
      } else if (devNewer) {
        chosen = dev;
      } else if (relNewer) {
        chosen = rel;
      }

      availableUpdate.value = chosen;
      return chosen;
    } catch (e) {
      debugPrint('checkForUpdates error: $e');
      return null;
    }
  }

  Future<bool> canRequestPackageInstalls() async {
    try {
      final res =
          await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  /// Downloads the APK (or ZIP containing APK) and triggers the Android system
  /// package installer UI ("Aktualizuj"). Returns `'STARTED'`, `'NEED_PERMISSION'`,
  /// or throws on error.
  Future<(String status, String filePath)> downloadAndInstallUpdate(
    AppUpdateInfo update, {
    required void Function(double progress, String statusText) onProgress,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final ext = (update.isZip ||
            update.downloadUrl.toLowerCase().endsWith('.zip') ||
            update.downloadUrl.toLowerCase().contains('/zip'))
        ? 'zip'
        : 'apk';
    final targetPath = '${cacheDir.path}/purevideo_ota.$ext';
    final f = File(targetPath);
    if (await f.exists()) {
      await f.delete();
    }

    onProgress(0.0, 'Pobieranie aktualizacji...');
    await _dio.download(
      update.downloadUrl,
      targetPath,
      options: Options(followRedirects: true),
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          final mbDone = (received / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
          onProgress(p, 'Pobieranie: $mbDone / $mbTotal MB');
        } else {
          final mbDone = (received / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.0, 'Pobieranie: $mbDone MB...');
        }
      },
    );

    onProgress(1.0, 'Uruchamianie instalatora Android...');
    final result = await installDownloadedFile(targetPath);
    return (result, targetPath);
  }

  Future<String> installDownloadedFile(String filePath) async {
    final res = await _channel.invokeMethod<String>(
      'installApk',
      {'filePath': filePath},
    );
    return res ?? 'STARTED';
  }

  // --- Admin GitHub API helpers (uses verified owner PAT in Keystore) ---

  Future<String?> _getOwnerToken() async {
    return SecureStorageService.getData('pv_owner_github_token');
  }

  Map<String, String> _ghHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<List<GitHubWorkflowRunItem>> fetchRecentBuilds() async {
    final token = await _getOwnerToken();
    final resp = await _dio.get(
      'https://api.github.com/repos/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/actions/runs',
      queryParameters: {
        'status': 'completed',
        'per_page': 20,
      },
      options: Options(
        headers: token != null ? _ghHeaders(token) : null,
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('Nie udało się pobrać listy buildów (HTTP ${resp.statusCode})');
    }
    final runs = (resp.data['workflow_runs'] as List?) ?? const [];
    final out = <GitHubWorkflowRunItem>[];
    for (final r in runs.whereType<Map>()) {
      if (r['conclusion']?.toString() != 'success') continue;
      final commitMsg =
          (r['head_commit']?['message'] ?? r['display_title'] ?? 'Build')
              .toString()
              .split('\n')
              .first
              .trim();
      out.add(GitHubWorkflowRunItem(
        id: (r['id'] as num?)?.toInt() ?? 0,
        runNumber: (r['run_number'] as num?)?.toInt() ?? 0,
        headBranch: (r['head_branch'] ?? 'master').toString(),
        commitMessage: commitMsg,
        createdAt: (r['created_at'] ?? '').toString(),
      ));
    }
    return out;
  }

  Future<List<GitHubArtifactItem>> fetchArtifactsForRun(int runId) async {
    final token = await _getOwnerToken();
    final resp = await _dio.get(
      'https://api.github.com/repos/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/actions/runs/$runId/artifacts',
      options: Options(
        headers: token != null ? _ghHeaders(token) : null,
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('Błąd pobierania artifactów (HTTP ${resp.statusCode})');
    }
    final list = (resp.data['artifacts'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .where((a) => a['expired'] != true)
        .map((a) => GitHubArtifactItem(
              id: (a['id'] as num?)?.toInt() ?? 0,
              name: (a['name'] ?? 'Artifact').toString(),
              sizeBytes: (a['size_in_bytes'] as num?)?.toInt() ?? 0,
              archiveDownloadUrl: (a['archive_download_url'] ?? '').toString(),
            ))
        .where((a) => a.id > 0 && a.archiveDownloadUrl.isNotEmpty)
        .toList();
  }

  Future<List<GitHubReleaseItem>> fetchGitHubReleases() async {
    final token = await _getOwnerToken();
    final resp = await _dio.get(
      'https://api.github.com/repos/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/releases',
      queryParameters: {'per_page': 20},
      options: Options(
        headers: token != null ? _ghHeaders(token) : null,
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode != 200 || resp.data is! List) {
      throw Exception('Błąd pobierania listy Releases (HTTP ${resp.statusCode})');
    }
    final out = <GitHubReleaseItem>[];
    for (final rel in (resp.data as List).whereType<Map>()) {
      final rawAssets = (rel['assets'] as List?) ?? const [];
      final assets = rawAssets
          .whereType<Map>()
          .map((a) => GitHubReleaseAssetItem(
                name: (a['name'] ?? '').toString(),
                sizeBytes: (a['size'] as num?)?.toInt() ?? 0,
                browserDownloadUrl: (a['browser_download_url'] ?? '').toString(),
              ))
          .where((a) =>
              a.browserDownloadUrl.isNotEmpty &&
              (a.name.toLowerCase().endsWith('.apk') ||
                  a.name.toLowerCase().endsWith('.zip')))
          .toList();
      if (assets.isEmpty) continue;
      out.add(GitHubReleaseItem(
        id: (rel['id'] as num?)?.toInt() ?? 0,
        tagName: (rel['tag_name'] ?? '').toString(),
        name: (rel['name'] ?? rel['tag_name'] ?? 'Release').toString(),
        prerelease: rel['prerelease'] == true,
        assets: assets,
      ));
    }
    return out;
  }

  /// Mirrors a selected GitHub Actions Artifact APK to a public GitHub Release
  /// asset so EVERY user can download it directly without a GitHub token.
  Future<String> _mirrorArtifactApkToPublicRelease({
    required String token,
    required GitHubWorkflowRunItem run,
    required GitHubArtifactItem artifact,
    required String version,
    required int buildNumber,
    required String title,
    required String description,
    required AppUpdateChannel channel,
    required void Function(String status) onStatus,
  }) async {
    final headers = _ghHeaders(token);
    onStatus('Pobieranie redirectu artifactu #${run.runNumber}...');

    // Step 1: Resolve 302 Location manually so Authorization header isn't forwarded to Azure Blob!
    final redirResp = await _dio.get(
      artifact.archiveDownloadUrl,
      options: Options(
        headers: headers,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final signedBlobUrl = redirResp.headers.value('location');
    if (signedBlobUrl == null || signedBlobUrl.isEmpty) {
      throw Exception('GitHub nie zwrócił adresu pobrania artifactu');
    }

    onStatus('Pobieranie paczki artifactu (${(artifact.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB)...');
    final tmpDir = await getTemporaryDirectory();
    final zipPath = '${tmpDir.path}/admin_art_${artifact.id}.zip';
    await _dio.download(signedBlobUrl, zipPath);

    onStatus('Rozpakowywanie app-release.apk...');
    final extractedApkPath = await _channel.invokeMethod<String>(
      'extractApkFromZip',
      {'zipPath': zipPath},
    );
    if (extractedApkPath == null || extractedApkPath.isEmpty) {
      throw Exception('Nie udało się rozpakować APK z artifactu');
    }

    final apkFile = File(extractedApkPath);
    final apkBytes = await apkFile.readAsBytes();

    final tagName = 'ota-${channel.apiValue}-b$buildNumber';
    final releaseApiBase =
        'https://api.github.com/repos/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/releases';

    onStatus('Tworzenie publicznego wydania ($tagName)...');
    Map<String, dynamic>? relData;
    final byTagResp = await _dio.get(
      '$releaseApiBase/tags/$tagName',
      options: Options(headers: headers, validateStatus: (_) => true),
    );
    if (byTagResp.statusCode == 200 && byTagResp.data is Map) {
      relData = Map<String, dynamic>.from(byTagResp.data);
    } else {
      final createResp = await _dio.post(
        releaseApiBase,
        data: jsonEncode({
          'tag_name': tagName,
          'target_commitish': ExtraSourcesService.repoBranch,
          'name': '$title (v$version)',
          'body': description,
          'draft': false,
          'prerelease': channel == AppUpdateChannel.dev,
        }),
        options: Options(headers: headers, validateStatus: (_) => true),
      );
      if ((createResp.statusCode == 200 || createResp.statusCode == 201) &&
          createResp.data is Map) {
        relData = Map<String, dynamic>.from(createResp.data);
      } else {
        throw Exception(
            'Błąd tworzenia GitHub Release (HTTP ${createResp.statusCode})');
      }
    }

    final releaseId = (relData['id'] as num).toInt();
    final assetName = 'PureVideo-b$buildNumber-${channel.apiValue}.apk';

    // Remove pre-existing asset with same name if re-publishing
    final oldAssets = (relData['assets'] as List?) ?? const [];
    for (final a in oldAssets.whereType<Map>()) {
      if (a['name']?.toString() == assetName && a['id'] != null) {
        await _dio.delete(
          '$releaseApiBase/assets/${a['id']}',
          options: Options(headers: headers, validateStatus: (_) => true),
        );
      }
    }

    onStatus('Przesyłanie pliku APK do publicznego pobrania...');
    final uploadUrl =
        'https://uploads.github.com/repos/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/releases/$releaseId/assets?name=${Uri.encodeComponent(assetName)}';
    final upResp = await _dio.post(
      uploadUrl,
      data: Stream.fromIterable([apkBytes]),
      options: Options(
        headers: {
          ...headers,
          'Content-Type': 'application/vnd.android.package-archive',
          'Content-Length': apkBytes.length.toString(),
        },
        validateStatus: (_) => true,
      ),
    );
    if ((upResp.statusCode != 200 && upResp.statusCode != 201) ||
        upResp.data is! Map) {
      throw Exception('Błąd przesyłania APK (HTTP ${upResp.statusCode})');
    }
    final browserUrl = (upResp.data['browser_download_url'] ?? '').toString();
    if (!browserUrl.startsWith('http')) {
      throw Exception('Brak publicznego adresu browser_download_url');
    }

    try {
      await File(zipPath).delete();
      await apkFile.delete();
    } catch (_) {}

    return browserUrl;
  }

  /// Publishes an OTA update entry into app_updates.json on GitHub.
  Future<String?> publishUpdate({
    required String pin,
    required String name,
    required String version,
    required int buildNumber,
    required String description,
    required AppUpdateChannel channel,
    required AppUpdateSourceType sourceType,
    GitHubWorkflowRunItem? run,
    GitHubArtifactItem? artifact,
    GitHubReleaseItem? release,
    GitHubReleaseAssetItem? releaseAsset,
    required void Function(String status) onStatus,
  }) async {
    final extraService = getIt<ExtraSourcesService>();
    if (!await extraService.verifyPin(pin)) {
      return 'Nieprawidłowy kod PIN właściciela.';
    }
    final token = await _getOwnerToken();
    if (token == null || token.isEmpty) {
      return 'Brak zapisanego tokenu właściciela.';
    }

    try {
      String finalDownloadUrl;
      String sourceLabel;
      bool isZip = false;

      if (sourceType == AppUpdateSourceType.releaseAsset) {
        if (release == null || releaseAsset == null) {
          return 'Wybierz Release i plik APK.';
        }
        finalDownloadUrl = releaseAsset.browserDownloadUrl;
        isZip = releaseAsset.name.toLowerCase().endsWith('.zip');
        sourceLabel = '${release.tagName} • ${releaseAsset.name}';
      } else {
        if (run == null || artifact == null) {
          return 'Wybierz build (Workflow Run) oraz Artifact.';
        }
        finalDownloadUrl = await _mirrorArtifactApkToPublicRelease(
          token: token,
          run: run,
          artifact: artifact,
          version: version.trim(),
          buildNumber: buildNumber,
          title: name.trim(),
          description: description.trim(),
          channel: channel,
          onStatus: onStatus,
        );
        isZip = false;
        sourceLabel = 'Build #${run.runNumber} • ${artifact.name}';
      }

      onStatus('Publikowanie app_updates.json na GitHub...');
      final apiUrl =
          'https://api.github.com/repos/${ExtraSourcesService.repoOwner}/${ExtraSourcesService.repoName}/contents/$updatesManifestPath';
      final headers = _ghHeaders(token);

      String? fileSha;
      final rootMap = <String, dynamic>{
        'schemaVersion': 1,
      };

      final getResp = await _dio.get(
        '$apiUrl?ref=${ExtraSourcesService.repoBranch}',
        options: Options(headers: headers, validateStatus: (_) => true),
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
            rootMap.addAll(Map<String, dynamic>.from(parsed));
          }
        }
      } else if (getResp.statusCode != 404) {
        return 'Błąd odczytu $updatesManifestPath (HTTP ${getResp.statusCode}).';
      }

      final newEntry = AppUpdateInfo(
        id: '${channel.apiValue}_b${buildNumber}_${DateTime.now().millisecondsSinceEpoch}',
        name: name.trim(),
        version: version.trim(),
        buildNumber: buildNumber,
        description: description.trim(),
        channel: channel,
        sourceType: sourceType,
        sourceLabel: sourceLabel,
        downloadUrl: finalDownloadUrl,
        isZip: isZip,
        publishedAt: DateTime.now().toUtc().toIso8601String(),
      );

      rootMap[channel.apiValue] = newEntry.toMap();
      rootMap['updatedAt'] = DateTime.now().toUtc().toIso8601String();

      final newJson = const JsonEncoder.withIndent('  ').convert(rootMap);
      final putResp = await _dio.put(
        apiUrl,
        data: jsonEncode({
          'message':
              'Publish ${channel.apiValue} update: ${newEntry.name} (${newEntry.version})',
          'content': base64Encode(utf8.encode('$newJson\n')),
          'branch': ExtraSourcesService.repoBranch,
          if (fileSha != null) 'sha': fileSha,
        }),
        options: Options(headers: headers, validateStatus: (_) => true),
      );
      if (putResp.statusCode != 200 && putResp.statusCode != 201) {
        final msg = (putResp.data is Map)
            ? (putResp.data['message'] ?? '').toString()
            : '';
        return 'Błąd zapisu $updatesManifestPath (HTTP ${putResp.statusCode}): $msg';
      }

      await checkForUpdates(force: true);
      return null;
    } catch (e) {
      return 'Błąd publikacji aktualizacji: $e';
    }
  }
}
